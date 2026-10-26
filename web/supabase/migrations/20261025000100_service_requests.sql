begin;
-- Phase 2A. No direct client writes: transactional commands enforce tenant,
-- version, document, concurrency and lifecycle rules together.
insert into private.permissions(code,description) values
 ('requests.read','Read requests within assigned organisation scope'),
 ('requests.review','Review submitted requests within assigned organisation scope'),
 ('quotes.manage','Prepare quotations within assigned organisation scope'),
 ('quotes.approve','Independently approve quotations within assigned organisation scope')
on conflict(code) do nothing;
-- Deliberately grant no existing role new authority automatically.
create table public.service_requests (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique default ('REQ-'||upper(replace(gen_random_uuid()::text,'-',''))),
 customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
 organisation_id uuid references public.organisations(id) on delete restrict,
 branch_id uuid, department_id uuid,
 service_id uuid not null, service_version_id uuid not null, booking_schema_id uuid not null,
 service_location_id uuid not null,
 status text not null default 'draft' check(status in ('draft','submitted','reviewed','cancelled')),
 revision integer not null default 1 check(revision>0),
 preferred_start timestamptz, preferred_end timestamptz,
 instructions text not null default '' check(length(instructions)<=4000),
 answers jsonb not null default '{}' check(jsonb_typeof(answers)='object' and octet_length(answers::text)<=131072),
 submitted_at timestamptz, reviewed_at timestamptz, cancelled_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid not null references public.profiles(id) on delete restrict,
 foreign key(service_version_id,service_id) references public.service_versions(id,service_id) on delete restrict,
 foreign key(booking_schema_id,service_version_id) references public.service_booking_schemas(id,service_version_id) on delete restrict,
 foreign key(service_location_id,customer_account_id) references public.service_locations(id,customer_account_id) on delete restrict,
 foreign key(branch_id,customer_account_id,organisation_id) references public.corporate_account_branches(id,customer_account_id,organisation_id) on delete restrict,
 foreign key(department_id,organisation_id) references private.departments(id,organisation_id) on delete restrict,
 check((preferred_start is null and preferred_end is null) or (preferred_start is not null and preferred_end is not null and preferred_end>preferred_start)),
 check(branch_id is null or organisation_id is not null), check(department_id is null or organisation_id is not null),
 unique(id,customer_account_id)
);
create index service_requests_account_time on public.service_requests(customer_account_id,created_at desc,id);
create index service_requests_branch on public.service_requests(branch_id,created_at desc);
create index service_requests_queue on public.service_requests(status,created_at,id);
create index service_requests_version on public.service_requests(service_version_id);
create index service_requests_schema on public.service_requests(booking_schema_id);
create index service_requests_location on public.service_requests(service_location_id);
create table public.request_history (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.service_requests(id) on delete restrict,
 revision integer not null, action text not null check(action in ('created','amended','submitted','reviewed','cancelled')),
 actor_id uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), unique(request_id,revision)
);
-- Historical answer/location snapshots stay private; history exposes no payload.
create table private.request_revisions (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.service_requests(id) on delete restrict,
 revision integer not null, snapshot jsonb not null, created_at timestamptz not null default now(),
 created_by uuid not null references public.profiles(id) on delete restrict, unique(request_id,revision)
);
create table private.transaction_commands (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id) on delete restrict,
 command text not null, idempotency_key text not null check(length(idempotency_key) between 8 and 128),
 payload jsonb not null, result_id uuid not null, created_at timestamptz not null default now(),
 unique(actor_id,command,idempotency_key)
);
create table public.request_attachments (
 id uuid primary key default gen_random_uuid(), request_id uuid not null, customer_account_id uuid not null,
 document_object_id uuid not null, created_at timestamptz not null default now(),
 created_by uuid not null references public.profiles(id) on delete restrict,
 foreign key(request_id,customer_account_id) references public.service_requests(id,customer_account_id) on delete restrict,
 foreign key(document_object_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
 unique(request_id,document_object_id)
);
create index request_attachments_document on public.request_attachments(document_object_id);

create function app_private.request_access(p_id uuid,p_action text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select p_action in ('read','request','approve') and exists(select 1 from public.service_requests r
 where r.id=p_id and (
  (r.branch_id is not null and app_private.can_access_branch(r.branch_id,p_action,r.department_id))
  or (r.branch_id is null and app_private.can_access_customer(r.customer_account_id,p_action='request',r.department_id)
    and (p_action<>'approve' or exists(select 1 from public.customer_profiles c where c.id=r.customer_account_id and c.individual_profile_id=auth.uid())
      or exists(select 1 from private.corporate_account_users u where u.customer_account_id=r.customer_account_id and u.profile_id=auth.uid() and u.can_approve)))
  or (p_action='read' and app_private.has_permission('requests.read',r.organisation_id))));
$$;

-- Pure bounded condition evaluation. JSON values never become executable SQL.
create function app_private.answer_condition(p_value jsonb,p_operator text,p_compare jsonb) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(case p_operator
 when 'is_present' then p_value is not null and p_value<>'null'::jsonb
 when 'equals' then p_value=p_compare
 when 'not_equals' then p_value<>p_compare
 when 'contains' then p_value @> jsonb_build_array(p_compare)
 when 'greater_than' then case when jsonb_typeof(p_value)='number' then (p_value#>>'{}')::numeric>(p_compare#>>'{}')::numeric else false end
 when 'less_than' then case when jsonb_typeof(p_value)='number' then (p_value#>>'{}')::numeric<(p_compare#>>'{}')::numeric else false end
 else false end,false);
$$;
create function app_private.validate_request_answers(p_schema uuid,p_account uuid,p_answers jsonb) returns void
language plpgsql set search_path='' as $$
declare g record; f record; rule record; item jsonb; value jsonb; visible boolean; idx integer; total integer; key text; n numeric; document_bytes bigint;
begin
 if p_answers is null or jsonb_typeof(p_answers)<>'object' or octet_length(p_answers::text)>131072 then
  raise exception 'invalid answer envelope' using errcode='23514'; end if;
 if exists(select 1 from jsonb_object_keys(p_answers) k where not exists(select 1 from public.service_booking_field_groups x where x.schema_id=p_schema and x.group_key=k)) then
  raise exception 'unknown answer group' using errcode='23514'; end if;
 for g in select * from public.service_booking_field_groups where schema_id=p_schema order by position loop
  if p_answers ? g.group_key and jsonb_typeof(p_answers->g.group_key)<>'array' then raise exception 'group must be an array' using errcode='23514'; end if;
  total=coalesce(jsonb_array_length(p_answers->g.group_key),0);
  if total<g.minimum_occurrences or total>g.maximum_occurrences then raise exception 'invalid group occurrence count' using errcode='23514'; end if;
  for idx in 0..total-1 loop
   item=p_answers->g.group_key->idx;
   if jsonb_typeof(item)<>'object' then raise exception 'group occurrence must be an object' using errcode='23514'; end if;
   for key in select jsonb_object_keys(item) loop
    if not exists(select 1 from public.service_booking_fields x where x.group_id=g.id and x.field_key=key and x.visibility<>'hidden') then
     raise exception 'unknown or hidden answer field' using errcode='23514'; end if;
   end loop;
   for f in select * from public.service_booking_fields where group_id=g.id and visibility<>'hidden' loop
    visible=f.visibility='visible';
    if f.visibility='conditional' then
     -- Cross-group dependencies can target only a single-occurrence source.
     if exists(select 1 from public.service_booking_field_dependencies dep join public.service_booking_fields src on src.id=dep.depends_on_field_id
      join public.service_booking_field_groups sg on sg.id=src.group_id where dep.field_id=f.id and sg.id<>g.id and sg.repeatable) then
      raise exception 'ambiguous repeated cross-group dependency' using errcode='23514'; end if;
     select coalesce(bool_or(matched),false) into visible from (
      select bool_and(app_private.answer_condition(
       p_answers->sg.group_key->(case when sg.id=g.id then idx else 0 end)->src.field_key,dep.operator,dep.comparison_value)) matched
      from public.service_booking_field_dependencies dep join public.service_booking_fields src on src.id=dep.depends_on_field_id
      join public.service_booking_field_groups sg on sg.id=src.group_id where dep.field_id=f.id group by dep.condition_group) conditions;
    end if;
    value=item->f.field_key;
    if not visible then
     if item ? f.field_key then raise exception 'answer to invisible field' using errcode='23514'; end if;
     continue;
    end if;
    if value is null or value='null'::jsonb then
     if f.required then raise exception 'required answer missing' using errcode='23514'; end if;
     continue;
    end if;
    if (f.field_type in ('text','date','single_choice','document') and jsonb_typeof(value)<>'string')
     or (f.field_type='number' and jsonb_typeof(value)<>'number')
     or (f.field_type='boolean' and jsonb_typeof(value)<>'boolean')
     or (f.field_type='multiple_choice' and jsonb_typeof(value)<>'array') then raise exception 'answer type mismatch' using errcode='23514'; end if;
    if f.field_type='text' and f.required and length(trim(value#>>'{}'))=0 then raise exception 'empty required answer' using errcode='23514'; end if;
    if f.field_type='date' then
     if (value#>>'{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid date' using errcode='23514'; end if;
     begin perform (value#>>'{}')::date; exception when others then raise exception 'invalid date' using errcode='23514'; end;
    end if;
    if f.field_type='single_choice' and not exists(select 1 from public.service_booking_field_options o where o.field_id=f.id and o.code=value#>>'{}') then
     raise exception 'unknown choice' using errcode='23514'; end if;
    if f.field_type='multiple_choice' then
     if jsonb_array_length(value)>100 or (f.required and jsonb_array_length(value)=0)
      or exists(select 1 from jsonb_array_elements(value) a where jsonb_typeof(a)<>'string' or not exists(select 1 from public.service_booking_field_options o where o.field_id=f.id and o.code=a#>>'{}'))
      or (select count(*)<>count(distinct a) from jsonb_array_elements(value) a) then raise exception 'invalid multiple choices' using errcode='23514'; end if;
    end if;
    if f.field_type='document' then
     select doc.byte_size into document_bytes from private.document_objects doc where doc.id::text=value#>>'{}' and doc.customer_account_id=p_account
      and doc.scan_status='clean' and doc.archived_at is null and doc.classification='customer';
     if not found then raise exception 'document unavailable' using errcode='23514'; end if;
    end if;
    for rule in select * from public.service_booking_field_validation_rules where field_id=f.id loop
     n=case when rule.rule_type in ('min_length','max_length') then length(value#>>'{}')
      when rule.rule_type in ('minimum','maximum') then (value#>>'{}')::numeric
      when rule.rule_type in ('min_choices','max_choices') then jsonb_array_length(value)
      when rule.rule_type='max_bytes' then document_bytes end;
     if (rule.rule_type in ('min_length','minimum','min_choices') and n<rule.rule_value)
      or (rule.rule_type in ('max_length','maximum','max_choices','max_bytes') and n>rule.rule_value) then
      raise exception 'answer violates validation rule' using errcode='23514'; end if;
    end loop;
   end loop;
  end loop;
 end loop;
end $$;

create function app_private.record_request_event(p_id uuid,p_action text) returns void
language plpgsql set search_path='' as $$
begin
 insert into public.request_history(request_id,revision,action,actor_id) select id,revision,p_action,auth.uid() from public.service_requests where id=p_id;
 insert into private.request_revisions(request_id,revision,snapshot,created_by) select id,revision,to_jsonb(r),auth.uid() from public.service_requests r where id=p_id;
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id) values(auth.uid(),p_action,'public','service_requests',p_id);
end $$;
create function app_private.create_service_request(p_account uuid,p_version uuid,p_address uuid,p_answers jsonb,p_key text,p_branch uuid default null,p_department uuid default null,p_start timestamptz default null,p_end timestamptz default null,p_instructions text default '') returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.customer_profiles; a public.customer_addresses; s public.service_booking_schemas; v_service uuid; v_location uuid; v_id uuid; previous private.transaction_commands; payload jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 if p_key is null or length(p_key) not between 8 and 128 then raise exception 'invalid idempotency key' using errcode='23514'; end if;
 select * into c from public.customer_profiles where id=p_account;
 if not found then raise exception 'account access denied' using errcode='42501'; end if;
 if p_branch is not null then
  if not exists(select 1 from public.corporate_account_branches b where b.id=p_branch and b.customer_account_id=p_account)
   or not app_private.can_access_branch(p_branch,'request',p_department) then raise exception 'branch access denied' using errcode='42501'; end if;
 elsif not app_private.can_access_customer(p_account,true,p_department) then raise exception 'account access denied' using errcode='42501'; end if;
 payload=jsonb_build_object('account',p_account,'version',p_version,'address',p_address,'answers',p_answers,'branch',p_branch,'department',p_department,'start',p_start,'end',p_end,'instructions',p_instructions);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':create_request:'||p_key,0));
 select * into previous from private.transaction_commands where actor_id=auth.uid() and command='create_request' and idempotency_key=p_key;
 if found then
  if previous.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505'; end if;
  return previous.result_id;
 end if;
 if not app_private.is_version_published(p_version) then raise exception 'service version unavailable' using errcode='23514'; end if;
 select * into s from public.service_booking_schemas where service_version_id=p_version and app_private.is_booking_schema_published(id);
 if not found then raise exception 'published booking schema required' using errcode='23514'; end if;
 select service_id into v_service from public.service_versions where id=p_version;
 select * into a from public.customer_addresses where id=p_address and customer_account_id=p_account and archived_at is null for share;
 if not found or not exists(select 1 from public.countries co join public.states st on st.country_id=co.id where co.id=a.country_id and st.id=a.state_id and co.status='active' and st.status='active')
  or (a.city_id is not null and not exists(select 1 from public.cities ci where ci.id=a.city_id and ci.status='active')) then raise exception 'active account address required' using errcode='23514'; end if;
 -- Drafts may be incomplete; shape and size still constrained by table checks.
 insert into public.service_locations(customer_account_id,source_address_id,address_snapshot,country_id,state_id,city_id,latitude,longitude,created_by)
 values(p_account,a.id,concat_ws(', ',a.address_line_1,a.address_line_2),a.country_id,a.state_id,a.city_id,a.latitude,a.longitude,auth.uid()) returning id into v_location;
 insert into public.service_requests(customer_account_id,organisation_id,branch_id,department_id,service_id,service_version_id,booking_schema_id,service_location_id,answers,preferred_start,preferred_end,instructions,created_by)
 values(p_account,c.organisation_id,p_branch,p_department,v_service,p_version,s.id,v_location,p_answers,p_start,p_end,p_instructions,auth.uid()) returning id into v_id;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'create_request',p_key,payload,v_id);
 perform app_private.record_request_event(v_id,'created');
 return v_id;
end $$;
create function app_private.change_service_request(p_id uuid,p_revision integer,p_action text,p_answers jsonb default null,p_start timestamptz default null,p_end timestamptz default null,p_instructions text default null) returns integer
language plpgsql security definer set search_path='' as $$
declare r public.service_requests;
begin
 select * into r from public.service_requests where id=p_id for update;
 if not found or not app_private.request_access(p_id,'request') then raise exception 'request access denied' using errcode='42501'; end if;
 if r.revision<>p_revision then raise exception 'stale request revision' using errcode='40001'; end if;
 if p_action='amend' and r.status='draft' then
  update public.service_requests set answers=coalesce(p_answers,answers),preferred_start=p_start,preferred_end=p_end,instructions=coalesce(p_instructions,instructions),revision=revision+1 where id=p_id;
 elsif p_action='submit' and r.status='draft' then
  if not app_private.is_version_published(r.service_version_id) or not app_private.is_booking_schema_published(r.booking_schema_id) then
   raise exception 'request configuration no longer available' using errcode='23514'; end if;
  if exists(select 1 from public.request_attachments a join private.document_objects d on d.id=a.document_object_id
   where a.request_id=r.id and (d.scan_status<>'clean' or d.archived_at is not null)) then raise exception 'request attachment unavailable' using errcode='23514'; end if;
  perform app_private.validate_request_answers(r.booking_schema_id,r.customer_account_id,r.answers);
  if r.preferred_start is not null and r.preferred_start<=now() then raise exception 'schedule is in the past' using errcode='23514'; end if;
  update public.service_requests set status='submitted',submitted_at=now(),revision=revision+1 where id=p_id;
 elsif p_action='cancel' and r.status in ('draft','submitted','reviewed') then
  update public.service_requests set status='cancelled',cancelled_at=now(),revision=revision+1 where id=p_id;
 else raise exception 'invalid request transition' using errcode='23514'; end if;
 perform app_private.record_request_event(p_id,case p_action when 'amend' then 'amended' when 'submit' then 'submitted' else 'cancelled' end);
 return r.revision+1;
end $$;
create function app_private.review_service_request(p_id uuid,p_revision integer) returns integer
language plpgsql security definer set search_path='' as $$
declare r public.service_requests;
begin
 select * into r from public.service_requests where id=p_id for update;
 if not found or not app_private.has_permission('requests.review',r.organisation_id) then raise exception 'review permission required' using errcode='42501'; end if;
 if r.revision<>p_revision then raise exception 'stale request revision' using errcode='40001'; end if;
 if r.status<>'submitted' then raise exception 'only submitted requests can be reviewed' using errcode='23514'; end if;
 update public.service_requests set status='reviewed',reviewed_at=now(),revision=revision+1 where id=p_id;
 perform app_private.record_request_event(p_id,'reviewed'); return r.revision+1;
end $$;
create function app_private.attach_request_document(p_id uuid,p_document uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; v_id uuid;
begin
 select * into r from public.service_requests where id=p_id for update;
 if not found or not app_private.request_access(p_id,'request') then raise exception 'request access denied' using errcode='42501'; end if;
 if r.status<>'draft' then raise exception 'attachments require draft' using errcode='23514'; end if;
 if not exists(select 1 from private.document_objects where id=p_document and customer_account_id=r.customer_account_id and classification='customer' and scan_status='clean' and archived_at is null) then raise exception 'document unavailable' using errcode='23514'; end if;
 insert into public.request_attachments(request_id,customer_account_id,document_object_id,created_by) values(r.id,r.customer_account_id,p_document,auth.uid())
 on conflict(request_id,document_object_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.request_attachments where request_id=r.id and document_object_id=p_document; end if;
 return v_id;
end $$;

create function public.create_service_request(p_account uuid,p_version uuid,p_address uuid,p_answers jsonb,p_key text,p_branch uuid default null,p_department uuid default null,p_start timestamptz default null,p_end timestamptz default null,p_instructions text default '') returns uuid
language sql set search_path='' as $$ select app_private.create_service_request(p_account,p_version,p_address,p_answers,p_key,p_branch,p_department,p_start,p_end,p_instructions); $$;
create function public.change_service_request(p_id uuid,p_revision integer,p_action text,p_answers jsonb default null,p_start timestamptz default null,p_end timestamptz default null,p_instructions text default null) returns integer
language sql set search_path='' as $$ select app_private.change_service_request(p_id,p_revision,p_action,p_answers,p_start,p_end,p_instructions); $$;
create function public.review_service_request(p_id uuid,p_revision integer) returns integer
language sql set search_path='' as $$ select app_private.review_service_request(p_id,p_revision); $$;
create function public.attach_request_document(p_id uuid,p_document uuid) returns uuid
language sql set search_path='' as $$ select app_private.attach_request_document(p_id,p_document); $$;
grant execute on function app_private.request_access(uuid,text),app_private.create_service_request(uuid,uuid,uuid,jsonb,text,uuid,uuid,timestamptz,timestamptz,text),public.create_service_request(uuid,uuid,uuid,jsonb,text,uuid,uuid,timestamptz,timestamptz,text),
 app_private.change_service_request(uuid,integer,text,jsonb,timestamptz,timestamptz,text),public.change_service_request(uuid,integer,text,jsonb,timestamptz,timestamptz,text),
 app_private.review_service_request(uuid,integer),public.review_service_request(uuid,integer),app_private.attach_request_document(uuid,uuid),public.attach_request_document(uuid,uuid) to authenticated;
alter table public.service_requests enable row level security;
alter table public.request_history enable row level security;
alter table public.request_attachments enable row level security;
alter table private.request_revisions enable row level security;
alter table private.transaction_commands enable row level security;
revoke all on public.service_requests,public.request_history,public.request_attachments from public,anon,authenticated;
grant select on public.service_requests,public.request_history,public.request_attachments to authenticated;
grant all on public.service_requests,public.request_history,public.request_attachments,private.request_revisions,private.transaction_commands to service_role;
create policy request_read on public.service_requests for select to authenticated using(app_private.request_access(id));
create policy request_history_read on public.request_history for select to authenticated using(app_private.request_access(request_id));
create policy request_attachment_read on public.request_attachments for select to authenticated using(app_private.request_access(request_id));
-- Branch members may download a linked clean document without gaining access
-- to every document owned by the corporate account. Staff still need docs.read.
create or replace function app_private.can_read_object(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.document_objects d where d.bucket_id=p_bucket and d.object_name=p_name
  and d.scan_status='clean' and d.archived_at is null and (
   (d.classification='public' and d.bucket_id='marketing-assets')
   or (d.classification='identity' and d.owner_profile_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active'))
   or (d.classification='customer' and (
    app_private.can_access_customer(d.customer_account_id) or app_private.can_staff_read_customer(d.customer_account_id,'documents.read')
    or exists(select 1 from public.request_attachments a join public.service_requests r on r.id=a.request_id
     where a.document_object_id=d.id and r.branch_id is not null and app_private.can_access_branch(r.branch_id,'read',r.department_id))))));
$$;
create trigger onit_updated_at before update on public.service_requests for each row execute function app_private.touch_updated_at();
create trigger onit_no_delete before delete on public.service_requests for each row execute function app_private.reject_mutation();
create trigger onit_no_truncate before truncate on public.service_requests for each statement execute function app_private.reject_mutation();
do $$ declare t text; begin
 foreach t in array array['public.request_history','public.request_attachments','private.request_revisions','private.transaction_commands'] loop
  execute format('create trigger onit_immutable before update or delete on %s for each row execute function app_private.reject_mutation()',t);
  execute format('create trigger onit_no_truncate before truncate on %s for each statement execute function app_private.reject_mutation()',t);
 end loop;
end $$;
commit;
