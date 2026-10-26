begin;
alter table public.service_requests add constraint request_account_version_key unique(id,customer_account_id,service_version_id);
create table private.site_assessments (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.service_requests(id) on delete restrict,
 customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
 request_revision integer not null, service_version_id uuid not null references public.service_versions(id) on delete restrict,
 revision integer not null check(revision>0), mode text not null check(mode in ('remote','physical')),
 status text not null default 'requested' check(status in ('requested','scheduled','completed','approved','rejected')),
 assessor_id uuid references public.profiles(id) on delete restrict, scheduled_start timestamptz,scheduled_end timestamptz,
 checklist_answers jsonb not null default '{}' check(jsonb_typeof(checklist_answers)='object'),
 measurements jsonb not null default '{}' check(jsonb_typeof(measurements)='object' and octet_length(measurements::text)<=65536),
 findings text not null default '' check(length(findings)<=8000),
 completed_by uuid references public.profiles(id) on delete restrict,completed_at timestamptz,
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 created_by uuid not null references public.profiles(id) on delete restrict,
 check((scheduled_start is null and scheduled_end is null) or (scheduled_start is not null and scheduled_end is not null and scheduled_end>scheduled_start)),
 check(approved_by is null or (approved_by<>completed_by and approved_by<>created_by)),
 check(status='requested' or (assessor_id is not null and scheduled_start is not null and scheduled_end is not null)),
 check(status not in ('completed','approved','rejected') or (completed_by is not null and completed_at is not null)),
 check(status not in ('approved','rejected') or (approved_by is not null and approved_at is not null)),
 foreign key(request_id,customer_account_id,service_version_id) references public.service_requests(id,customer_account_id,service_version_id) on delete restrict,
 unique(request_id,revision),unique(id,request_id),unique(id,customer_account_id)
);
create table private.assessment_evidence (
 id uuid primary key default gen_random_uuid(),assessment_id uuid not null references private.site_assessments(id) on delete restrict,
 document_object_id uuid not null references private.document_objects(id) on delete restrict,
 customer_account_id uuid not null,
 created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id) on delete restrict,
 foreign key(assessment_id,customer_account_id) references private.site_assessments(id,customer_account_id) on delete restrict,
 foreign key(document_object_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
 unique(assessment_id,document_object_id)
);
create function app_private.assessment_command(p_request uuid,p_action text,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; a private.site_assessments; v_id uuid; v_rev integer; item record; v_check jsonb;prior private.transaction_commands;payload jsonb;
begin
 select * into r from public.service_requests where id=p_request for update;
 if not found or auth.uid() is null then raise exception 'assessment access denied' using errcode='42501'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>131072 then raise exception 'assessment object required' using errcode='23514'; end if;
 if p_action='create' then
  if not app_private.has_permission('assessments.manage',r.organisation_id) then raise exception 'assessment manager required' using errcode='42501'; end if;
  if p_data->>'idempotency_key' is null or length(p_data->>'idempotency_key') not between 8 and 128 then raise exception 'assessment idempotency key required' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':assessment:'||(p_data->>'idempotency_key'),0));
  payload=jsonb_build_object('request',p_request,'data',p_data);
  select * into prior from private.transaction_commands where actor_id=auth.uid() and command='create_assessment' and idempotency_key=p_data->>'idempotency_key';
  if found then
   if prior.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505'; end if;return prior.result_id;
  end if;
  if r.status not in ('submitted','reviewed') then raise exception 'submitted request required' using errcode='23514'; end if;
  if exists(select 1 from public.quotations q join public.quotation_versions v on v.quotation_id=q.id where q.request_id=r.id and v.status='accepted') then raise exception 'accepted scope requires an order change workflow' using errcode='23514'; end if;
  select coalesce(max(revision),0)+1 into v_rev from private.site_assessments where request_id=r.id;
  insert into private.site_assessments(request_id,customer_account_id,request_revision,service_version_id,revision,mode,created_by)
   values(r.id,r.customer_account_id,r.revision,r.service_version_id,v_rev,p_data->>'mode',auth.uid()) returning id into v_id;
  insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'create_assessment',p_data->>'idempotency_key',payload,v_id);
  return v_id;
 end if;
 select * into a from private.site_assessments where id=(p_data->>'id')::uuid and request_id=r.id for update;
 if not found then raise exception 'assessment access denied' using errcode='42501'; end if;
 if a.revision<>(select max(revision) from private.site_assessments where request_id=r.id) or a.request_revision<>r.revision then raise exception 'stale assessment revision' using errcode='40001'; end if;
 if p_action='schedule' then
  if not app_private.has_permission('assessments.manage',r.organisation_id) then raise exception 'assessment manager required' using errcode='42501'; end if;
  if a.status not in ('requested','scheduled') then raise exception 'assessment cannot be scheduled' using errcode='23514'; end if;
  if not exists(select 1 from private.employee_profiles e join public.organisations o on o.id=e.organisation_id
   join public.profiles p on p.id=e.profile_id where e.profile_id=(p_data->>'assessor_id')::uuid and e.status='active' and o.organisation_type='onit' and o.status='active' and p.status='active') then raise exception 'active internal assessor required' using errcode='23514'; end if;
  if (p_data->>'start')::timestamptz<=now() or p_data->>'start' is null or p_data->>'end' is null then raise exception 'future assessment window required' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended('assessor:'||(p_data->>'assessor_id'),0));
  if exists(select 1 from private.site_assessments x where x.id<>a.id and x.assessor_id=(p_data->>'assessor_id')::uuid and x.status='scheduled'
    and tstzrange(x.scheduled_start,x.scheduled_end,'[)') && tstzrange((p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,'[)')) then raise exception 'assessor schedule conflict' using errcode='23514'; end if;
  update private.site_assessments set status='scheduled',assessor_id=(p_data->>'assessor_id')::uuid,scheduled_start=(p_data->>'start')::timestamptz,scheduled_end=(p_data->>'end')::timestamptz where id=a.id;
 elsif p_action='evidence' then
  if a.assessor_id is distinct from auth.uid() or not app_private.has_permission('assessments.perform',r.organisation_id) then raise exception 'assigned assessor required' using errcode='42501'; end if;
  if a.status<>'scheduled' then raise exception 'scheduled assessment required' using errcode='23514'; end if;
  if not exists(select 1 from private.document_objects d where d.id=(p_data->>'document_id')::uuid and d.customer_account_id=r.customer_account_id
   and d.classification in ('customer','work') and d.scan_status='clean' and d.archived_at is null) then raise exception 'clean account evidence required' using errcode='23514'; end if;
  insert into private.assessment_evidence(assessment_id,customer_account_id,document_object_id,created_by) values(a.id,r.customer_account_id,(p_data->>'document_id')::uuid,auth.uid()) on conflict(assessment_id,document_object_id) do nothing;
 elsif p_action='complete' then
  if a.assessor_id is distinct from auth.uid() or not app_private.has_permission('assessments.perform',r.organisation_id) then raise exception 'assigned assessor required' using errcode='42501'; end if;
  if a.status<>'scheduled' then raise exception 'scheduled assessment required' using errcode='23514'; end if;
  if jsonb_typeof(p_data->'measurements') is distinct from 'object' or jsonb_typeof(p_data->'checklist_answers') is distinct from 'object' or length(trim(coalesce(p_data->>'findings','')))=0 then raise exception 'assessment findings and answers required' using errcode='23514'; end if;
  for item in select key,value from jsonb_each(p_data->'measurements') loop
   if jsonb_typeof(item.value)<>'string' or (item.value#>>'{}') !~ '^\d{1,10}(\.\d{1,4})?$' or (item.value#>>'{}')::numeric<=0 then raise exception 'positive decimal measurement required' using errcode='23514'; end if;
  end loop;
  for item in select i.id,i.required from public.service_checklist_items i join public.service_checklists c on c.id=i.checklist_id where c.service_version_id=r.service_version_id and c.checklist_type='assessment' loop
   v_check=p_data->'checklist_answers'->item.id::text;
   if (item.required and v_check is null) or (v_check is not null and jsonb_typeof(v_check)<>'boolean') then raise exception 'invalid assessment checklist response' using errcode='23514'; end if;
  end loop;
  if exists(select 1 from jsonb_object_keys(p_data->'checklist_answers') k where not exists(select 1 from public.service_checklist_items i join public.service_checklists c on c.id=i.checklist_id where i.id::text=k and c.service_version_id=r.service_version_id and c.checklist_type='assessment')) then raise exception 'unknown assessment checklist item' using errcode='23514'; end if;
  update private.site_assessments set status='completed',findings=p_data->>'findings',measurements=p_data->'measurements',checklist_answers=p_data->'checklist_answers',completed_by=auth.uid(),completed_at=now() where id=a.id;
 elsif p_action in ('approve','reject') then
  if not app_private.has_permission('assessments.approve',r.organisation_id) or auth.uid() in (a.created_by,a.completed_by) then raise exception 'independent assessment approver required' using errcode='42501'; end if;
  if a.status<>'completed' then raise exception 'completed assessment required' using errcode='23514'; end if;
  if exists(select 1 from private.assessment_evidence e join private.document_objects d on d.id=e.document_object_id where e.assessment_id=a.id and (d.scan_status<>'clean' or d.archived_at is not null)) then raise exception 'assessment evidence unavailable' using errcode='23514'; end if;
  update private.site_assessments set status=case p_action when 'approve' then 'approved' else 'rejected' end,approved_by=auth.uid(),approved_at=now() where id=a.id;
 else raise exception 'invalid assessment action' using errcode='23514'; end if;
 return a.id;
end $$;
create function app_private.guard_assessment() returns trigger language plpgsql set search_path='' as $$
begin
 if old.status in ('approved','rejected') or (old.status='completed' and
 (to_jsonb(new)-array['status','approved_by','approved_at','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','approved_at','updated_at'])) then raise exception 'create a new assessment revision' using errcode='55000'; end if;
 return new;
end $$;
create trigger onit_assessment_guard before update on private.site_assessments for each row execute function app_private.guard_assessment();
create trigger onit_updated_at before update on private.site_assessments for each row execute function app_private.touch_updated_at();
create function public.assessment_command(p_request uuid,p_action text,p_data jsonb) returns uuid language sql set search_path='' as $$ select app_private.assessment_command(p_request,p_action,p_data); $$;
grant execute on function public.assessment_command(uuid,text,jsonb),app_private.assessment_command(uuid,text,jsonb) to authenticated;
create function app_private.read_assessment(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a private.site_assessments; v_org uuid;
begin
 select * into a from private.site_assessments where id=p_id;
 select organisation_id into v_org from public.service_requests where id=a.request_id;
 if a.id is null or not (app_private.has_permission('assessments.manage',v_org) or app_private.has_permission('assessments.approve',v_org)
 or (a.assessor_id=auth.uid() and app_private.has_permission('assessments.perform',v_org))) then raise exception 'assessment access denied' using errcode='42501'; end if;
 return to_jsonb(a)||jsonb_build_object('checklist',(select jsonb_agg(jsonb_build_object('id',i.id,'label',i.label,'required',i.required) order by c.code,i.position)
  from public.service_checklist_items i join public.service_checklists c on c.id=i.checklist_id where c.service_version_id=a.service_version_id and c.checklist_type='assessment'),
  'evidence',(select jsonb_agg(jsonb_build_object('document_id',d.id,'bucket',d.bucket_id,'object_name',d.object_name,'scan_status',d.scan_status))
   from private.assessment_evidence e join private.document_objects d on d.id=e.document_object_id where e.assessment_id=a.id));
end $$;
create function public.read_assessment(p_id uuid) returns jsonb language sql stable set search_path='' as $$ select app_private.read_assessment(p_id); $$;
grant execute on function public.read_assessment(uuid),app_private.read_assessment(uuid) to authenticated;
do $$ declare t text; begin
 foreach t in array array['site_assessments','assessment_evidence'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  execute format('grant all on private.%I to service_role',t);
  execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
  execute format('create trigger onit_no_delete before delete on private.%I for each row execute function app_private.reject_mutation()',t);
  execute format('create trigger onit_no_truncate before truncate on private.%I for each statement execute function app_private.reject_mutation()',t);
 end loop;
end $$;
create trigger onit_immutable before update on private.assessment_evidence for each row execute function app_private.reject_mutation();
create index assessment_assessor_schedule on private.site_assessments(assessor_id,scheduled_start) where status='scheduled';
create index assessment_evidence_document on private.assessment_evidence(document_object_id);
-- Extend the existing Storage predicate only through typed assessment links.
-- Employee/identity/contract files cannot be exposed through a generic staff role.
create or replace function app_private.can_read_object(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.document_objects d where d.bucket_id=p_bucket and d.object_name=p_name
 and d.scan_status='clean' and d.archived_at is null and (
  (d.classification='public' and d.bucket_id='marketing-assets')
  or (d.classification='identity' and d.owner_profile_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active'))
  or (d.classification='customer' and (app_private.can_access_customer(d.customer_account_id) or app_private.can_staff_read_customer(d.customer_account_id,'documents.read')
   or exists(select 1 from public.request_attachments x join public.service_requests r on r.id=x.request_id where x.document_object_id=d.id and r.branch_id is not null and app_private.can_access_branch(r.branch_id,'read',r.department_id))))
  or (d.classification in ('customer','work') and exists(select 1 from private.assessment_evidence e join private.site_assessments a on a.id=e.assessment_id
   join public.service_requests r on r.id=a.request_id where e.document_object_id=d.id
   and (app_private.has_permission('assessments.manage',r.organisation_id) or app_private.has_permission('assessments.approve',r.organisation_id)
    or (a.assessor_id=auth.uid() and app_private.has_permission('assessments.perform',r.organisation_id)))))));
$$;
commit;
