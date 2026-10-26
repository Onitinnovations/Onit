begin;
-- A quotation is a commercial proposal, never proof of payment or an order.
create table private.quotation_tax_rules (
 id uuid primary key default gen_random_uuid(), code text not null, version integer not null check(version>0),
 country_id uuid not null references public.countries(id) on delete restrict,
 rate numeric(9,6) not null check(rate between 0 and 100), valid_from timestamptz not null, valid_until timestamptz,
 status text not null default 'draft' check(status in ('draft','active','retired')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references public.profiles(id) on delete restrict,
 check(valid_until is null or valid_until>valid_from), unique(code,version)
);
create table public.quotations (
 id uuid primary key default gen_random_uuid(), request_id uuid not null unique references public.service_requests(id) on delete restrict,
 reference text not null unique default ('QUO-'||upper(replace(gen_random_uuid()::text,'-',''))),
 created_at timestamptz not null default now(), created_by uuid not null references public.profiles(id) on delete restrict
);
create table public.quotation_versions (
 id uuid primary key default gen_random_uuid(), quotation_id uuid not null references public.quotations(id) on delete restrict,
 version integer not null check(version>0), request_revision integer not null,
 currency_id uuid not null references public.currencies(id) on delete restrict,
 pricing_mode text not null check(pricing_mode in ('fixed_price','starting_price','quantity_based','assessment_based','custom_quotation')),
 status text not null default 'draft' check(status in ('draft','offered','accepted','rejected','expired','superseded')),
 valid_until timestamptz not null, terms text not null check(length(terms) between 1 and 8000),
 subtotal numeric(20,2) not null check(subtotal>=0), discount_total numeric(20,2) not null check(discount_total>=0),
 tax_total numeric(20,2) not null check(tax_total>=0), total numeric(20,2) not null check(total>=0),
 approved_by uuid references public.profiles(id) on delete restrict, approved_at timestamptz,
 decided_by uuid references public.profiles(id) on delete restrict, decided_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid not null references public.profiles(id) on delete restrict,
 check(total=subtotal-discount_total+tax_total), check(discount_total<=subtotal),
 check(approved_by is null or approved_by<>created_by), check((approved_by is null)=(approved_at is null)),
 unique(quotation_id,version)
);
create unique index quotation_live_version on public.quotation_versions(quotation_id) where status in ('draft','offered','accepted');
create index quotation_version_expiry on public.quotation_versions(valid_until) where status='offered';
create table public.quotation_line_items (
 id uuid primary key default gen_random_uuid(), quotation_version_id uuid not null references public.quotation_versions(id) on delete restrict,
 position integer not null check(position>=0), description text not null check(length(description) between 1 and 1000),
 kind text not null check(kind in ('service','labour','materials','logistics','other')),
 quantity numeric(14,4) not null check(quantity>0), unit_price numeric(16,4) not null check(unit_price>=0),
 discount numeric(20,2) not null check(discount>=0), tax_rule_id uuid references private.quotation_tax_rules(id) on delete restrict,
 tax_label text, tax_rate numeric(9,6) not null check(tax_rate between 0 and 100),
 gross numeric(20,2) not null, tax numeric(20,2) not null, total numeric(20,2) not null,
 created_at timestamptz not null default now(), created_by uuid not null references public.profiles(id) on delete restrict,
 check(gross=round(quantity*unit_price,2)), check(discount<=gross),
 check(tax=round((gross-discount)*tax_rate/100,2)), check(total=gross-discount+tax),
 check((tax_rule_id is null and tax_label is null and tax_rate=0) or (tax_rule_id is not null and tax_label is not null)),
 unique(quotation_version_id,position)
);
create index quotation_line_tax on public.quotation_line_items(tax_rule_id);
create table private.quotation_decisions (
 id uuid primary key default gen_random_uuid(), quotation_version_id uuid not null references public.quotation_versions(id) on delete restrict,
 decision text not null check(decision in ('approved','accepted','rejected','expired','superseded')),
 created_at timestamptz not null default now(), created_by uuid not null references public.profiles(id) on delete restrict,
 unique(quotation_version_id,decision)
);
create function app_private.quote_access(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.quotation_versions v join public.quotations q on q.id=v.quotation_id
 join public.service_requests r on r.id=q.request_id where v.id=p_id and (
 app_private.has_permission('quotes.manage',r.organisation_id) or app_private.has_permission('quotes.approve',r.organisation_id)
 or (v.status not in ('draft','superseded') and app_private.request_access(r.id))));
$$;
create function app_private.prepare_quotation(p_request uuid,p_currency uuid,p_valid_until timestamptz,p_terms text,p_lines jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; q uuid; v uuid; revision integer; line jsonb; qty numeric; price numeric; disc numeric;
 gross numeric; tax numeric; rate numeric; label text; tax_id uuid; country uuid; previous private.transaction_commands; payload jsonb; pos integer=0;
begin
 select * into r from public.service_requests where id=p_request for update;
 if not found or not app_private.has_permission('quotes.manage',r.organisation_id) then raise exception 'quotation permission required' using errcode='42501'; end if;
 if p_key is null or length(p_key) not between 8 and 128 then raise exception 'invalid idempotency key' using errcode='23514'; end if;
 payload=jsonb_build_object('request',p_request,'currency',p_currency,'until',p_valid_until,'terms',p_terms,'lines',p_lines);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':quote:'||p_key,0));
 select * into previous from private.transaction_commands where actor_id=auth.uid() and command='prepare_quote' and idempotency_key=p_key;
 if found then
  if previous.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505'; end if;
  return previous.result_id;
 end if;
 if r.status<>'reviewed' then raise exception 'reviewed request required' using errcode='23514'; end if;
 if p_valid_until is null or p_valid_until<=now() or p_valid_until>now()+interval '1 year'
  or p_lines is null or jsonb_typeof(p_lines)<>'array' or octet_length(p_lines::text)>131072 then raise exception 'invalid quote input' using errcode='23514'; end if;
 if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'invalid quote line count' using errcode='23514'; end if;
 if not exists(select 1 from public.customer_profiles c where c.id=r.customer_account_id and c.currency_id=p_currency) then raise exception 'account currency mismatch' using errcode='23514'; end if;
 if not exists(select 1 from public.currencies where id=p_currency and minor_units=2) then raise exception 'currency rounding configuration unsupported by this increment' using errcode='23514'; end if;
 select country_id into country from public.service_locations where id=r.service_location_id;
 insert into public.quotations(request_id,created_by) values(p_request,auth.uid()) on conflict(request_id) do nothing;
 select id into q from public.quotations where request_id=p_request for update;
 if exists(select 1 from public.quotation_versions where quotation_id=q and status='accepted') then raise exception 'accepted quotation is immutable' using errcode='55000'; end if;
 -- A new immutable revision supersedes prior unaccepted proposals atomically.
 insert into private.quotation_decisions(quotation_version_id,decision,created_by)
 select id,'superseded',auth.uid() from public.quotation_versions where quotation_id=q and status in ('draft','offered');
 update public.quotation_versions set status='superseded' where quotation_id=q and status in ('draft','offered');
 select coalesce(max(version),0)+1 into revision from public.quotation_versions where quotation_id=q;
 insert into public.quotation_versions(quotation_id,version,request_revision,currency_id,pricing_mode,valid_until,terms,subtotal,discount_total,tax_total,total,created_by)
 select q,revision,r.revision,p_currency,s.pricing_mode,p_valid_until,p_terms,0,0,0,0,auth.uid() from public.service_versions s where s.id=r.service_version_id returning id into v;
 for line in select value from jsonb_array_elements(p_lines) loop
  if jsonb_typeof(line)<>'object' or exists(select 1 from jsonb_object_keys(line) k where k not in ('description','kind','quantity','unit_price','discount','tax_rule_id')) then raise exception 'invalid quote line keys' using errcode='23514'; end if;
  -- Decimal strings prevent loss of precision before reaching PostgreSQL.
  if jsonb_typeof(line->'quantity') is distinct from 'string' or jsonb_typeof(line->'unit_price') is distinct from 'string'
   or (line->>'quantity') !~ '^\d{1,10}(\.\d{1,4})?$' or (line->>'unit_price') !~ '^\d{1,12}(\.\d{1,4})?$'
   or (line ? 'discount' and (jsonb_typeof(line->'discount') is distinct from 'string' or (line->>'discount') !~ '^\d{1,16}(\.\d{1,2})?$')) then raise exception 'invalid exact decimal' using errcode='23514'; end if;
  qty=(line->>'quantity')::numeric;price=(line->>'unit_price')::numeric;disc=coalesce((line->>'discount')::numeric,0);
  gross=round(qty*price,2);rate=0;label=null;tax_id=null;
  if line->>'tax_rule_id' is not null then
   select id,code,quotation_tax_rules.rate into tax_id,label,rate from private.quotation_tax_rules where id::text=line->>'tax_rule_id' and country_id=country
    and status='active' and valid_from<=now() and (valid_until is null or valid_until>now()) for share;
   if not found then raise exception 'tax configuration unavailable' using errcode='23514'; end if;
  end if;
  tax=round((gross-disc)*rate/100,2);
  insert into public.quotation_line_items(quotation_version_id,position,description,kind,quantity,unit_price,discount,tax_rule_id,tax_label,tax_rate,gross,tax,total,created_by)
  values(v,pos,line->>'description',line->>'kind',qty,price,disc,tax_id,label,rate,gross,tax,gross-disc+tax,auth.uid());pos=pos+1;
 end loop;
 update public.quotation_versions set subtotal=t.subtotal,discount_total=t.discount,tax_total=t.tax,total=t.total
 from (select sum(li.gross) subtotal,sum(li.discount) discount,sum(li.tax) tax,sum(li.total) total from public.quotation_line_items li where li.quotation_version_id=v) t where id=v;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'prepare_quote',p_key,payload,v);
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id) values(auth.uid(),'quote_prepared','public','quotation_versions',v);
 return v;
end $$;
create function app_private.decide_quotation(p_id uuid,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.quotation_versions; r public.service_requests; v_request uuid;
begin
 -- Request first: the same lock order as quotation preparation prevents deadlocks.
 select q.request_id into v_request from public.quotation_versions x join public.quotations q on q.id=x.quotation_id where x.id=p_id;
 select * into r from public.service_requests where id=v_request for update;
 select * into v from public.quotation_versions where id=p_id for update;
 if not found or auth.uid() is null then raise exception 'quotation access denied' using errcode='42501'; end if;
 if p_action='approve' then
  if not app_private.has_permission('quotes.approve',r.organisation_id) or auth.uid()=v.created_by then raise exception 'independent approver required' using errcode='42501'; end if;
  if v.status='offered' and v.approved_by=auth.uid() then return v.id; end if;
  if v.status<>'draft' or v.valid_until<=now() or r.status<>'reviewed' or r.revision<>v.request_revision then raise exception 'quotation cannot be approved' using errcode='23514'; end if;
  update public.quotation_versions set status='offered',approved_by=auth.uid(),approved_at=now() where id=v.id;
 elsif p_action='expire' then
  if not app_private.has_permission('quotes.manage',r.organisation_id) then raise exception 'quotation permission required' using errcode='42501'; end if;
  if v.status='expired' then return v.id; end if;
  if v.status<>'offered' or v.valid_until>now() then raise exception 'quotation has not expired' using errcode='23514'; end if;
  update public.quotation_versions set status='expired',decided_by=auth.uid(),decided_at=now() where id=v.id;
 elsif p_action in ('accept','reject') then
  if not app_private.request_access(r.id,'approve') then raise exception 'customer approver required' using errcode='42501'; end if;
  if v.status=(case p_action when 'accept' then 'accepted' else 'rejected' end) and v.decided_by=auth.uid() then return v.id; end if;
  if v.status<>'offered' or v.valid_until<=now() or r.status<>'reviewed' or r.revision<>v.request_revision then raise exception 'quotation not currently acceptable' using errcode='23514'; end if;
  update public.quotation_versions set status=case p_action when 'accept' then 'accepted' else 'rejected' end,decided_by=auth.uid(),decided_at=now() where id=v.id;
 else raise exception 'invalid quotation decision' using errcode='23514'; end if;
 insert into private.quotation_decisions(quotation_version_id,decision,created_by) values(v.id,case p_action when 'approve' then 'approved' when 'accept' then 'accepted' when 'expire' then 'expired' else 'rejected' end,auth.uid());
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id) values(auth.uid(),'quote_'||p_action,'public','quotation_versions',v.id);
 return v.id;
end $$;
create function app_private.guard_quote_version() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.status in ('accepted','rejected','expired','superseded') then raise exception 'final quotation is immutable' using errcode='55000'; end if;
 if (to_jsonb(new)-array['status','approved_by','approved_at','decided_by','decided_at','updated_at','subtotal','discount_total','tax_total','total'])
  is distinct from (to_jsonb(old)-array['status','approved_by','approved_at','decided_by','decided_at','updated_at','subtotal','discount_total','tax_total','total'])
  or (old.status<>'draft' and (new.subtotal,new.discount_total,new.tax_total,new.total) is distinct from (old.subtotal,old.discount_total,old.tax_total,old.total)) then
  raise exception 'create a quotation revision instead' using errcode='55000'; end if;
 return new;
end $$;
create trigger onit_quote_guard before update on public.quotation_versions for each row execute function app_private.guard_quote_version();
create function app_private.guard_accepted_request() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.status='cancelled' and exists(select 1 from public.quotations q join public.quotation_versions v on v.quotation_id=q.id where q.request_id=old.id and v.status='accepted') then
  raise exception 'accepted commercial scope requires the future order change workflow' using errcode='23514'; end if;
 return new;
end $$;
create trigger onit_accepted_request_guard before update on public.service_requests for each row execute function app_private.guard_accepted_request();
create trigger onit_updated_at before update on public.quotation_versions for each row execute function app_private.touch_updated_at();
create function public.prepare_quotation(p_request uuid,p_currency uuid,p_valid_until timestamptz,p_terms text,p_lines jsonb,p_key text) returns uuid
language sql set search_path='' as $$ select app_private.prepare_quotation(p_request,p_currency,p_valid_until,p_terms,p_lines,p_key); $$;
create function public.decide_quotation(p_id uuid,p_action text) returns uuid
language sql set search_path='' as $$ select app_private.decide_quotation(p_id,p_action); $$;
-- Monetary RPC output uses decimal strings so JavaScript cannot silently round it.
create function app_private.read_quotation(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not app_private.quote_access(p_id) then raise exception 'quotation access denied' using errcode='42501'; end if;
 select jsonb_build_object('id',v.id,'quotation_id',v.quotation_id,'version',v.version,'currency',c.code,
  'pricing_mode',v.pricing_mode,'status',v.status,'valid_until',v.valid_until,'terms',v.terms,
  'subtotal',v.subtotal::text,'discount_total',v.discount_total::text,'tax_total',v.tax_total::text,'total',v.total::text,
  'lines',(select jsonb_agg(jsonb_build_object('position',li.position,'description',li.description,'kind',li.kind,
   'quantity',li.quantity::text,'unit_price',li.unit_price::text,'discount',li.discount::text,'tax_label',li.tax_label,
   'tax_rate',li.tax_rate::text,'gross',li.gross::text,'tax',li.tax::text,'total',li.total::text) order by li.position)
   from public.quotation_line_items li where li.quotation_version_id=v.id)) into result
 from public.quotation_versions v join public.currencies c on c.id=v.currency_id where v.id=p_id;
 return result;
end $$;
create function public.read_quotation(p_id uuid) returns jsonb
language sql stable set search_path='' as $$ select app_private.read_quotation(p_id); $$;
grant execute on function app_private.read_quotation(uuid),public.read_quotation(uuid) to authenticated;
grant execute on function app_private.quote_access(uuid),app_private.prepare_quotation(uuid,uuid,timestamptz,text,jsonb,text),public.prepare_quotation(uuid,uuid,timestamptz,text,jsonb,text),app_private.decide_quotation(uuid,text),public.decide_quotation(uuid,text) to authenticated;
do $$ declare t text; begin
 foreach t in array array['quotations','quotation_versions','quotation_line_items'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create trigger onit_no_truncate before truncate on public.%I for each statement execute function app_private.reject_mutation()',t);
 end loop;
 foreach t in array array['quotation_tax_rules','quotation_decisions'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('grant all on private.%I to service_role',t);
 end loop;
 foreach t in array array['public.quotation_line_items','private.quotation_decisions','private.quotation_tax_rules'] loop
  execute format('create trigger onit_immutable before update or delete on %s for each row execute function app_private.reject_mutation()',t);
  execute format('create trigger onit_history_no_truncate before truncate on %s for each statement execute function app_private.reject_mutation()',t);
 end loop;
end $$;
create trigger onit_no_delete before delete on public.quotation_versions for each row execute function app_private.reject_mutation();
create trigger onit_identity_immutable before update or delete on public.quotations for each row execute function app_private.reject_mutation();
create policy quotation_identity_read on public.quotations for select to authenticated using(exists(select 1 from public.quotation_versions v where v.quotation_id=quotations.id and app_private.quote_access(v.id)));
create policy quotation_version_read on public.quotation_versions for select to authenticated using(app_private.quote_access(id));
create policy quotation_line_read on public.quotation_line_items for select to authenticated using(app_private.quote_access(quotation_version_id));
-- FK indexes only for the ten tables owned by this candidate; no unrelated DDL.
do $$ declare fk record; cols text; begin
 for fk in select con.conrelid,con.conkey,con.conname,n.nspname,c.relname from pg_constraint con
 join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
 where con.contype='f' and (n.nspname||'.'||c.relname)=any(array[
 'public.service_requests','public.request_history','public.request_attachments','private.request_revisions','private.transaction_commands',
 'public.quotations','public.quotation_versions','public.quotation_line_items','private.quotation_tax_rules','private.quotation_decisions'])
 and not exists(select 1 from pg_index i where i.indrelid=c.oid and i.indisvalid and i.indpred is null
 and array(select k from unnest(i.indkey::smallint[]) with ordinality x(k,pos) where pos<=cardinality(con.conkey) order by pos)=con.conkey)
 loop
 select string_agg(quote_ident(a.attname),',' order by u.pos) into cols from unnest(fk.conkey) with ordinality u(num,pos)
 join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=u.num;
 execute format('create index %I on %I.%I(%s)','onit_p2_fk_'||substr(md5(fk.nspname||fk.relname||fk.conname),1,24),fk.nspname,fk.relname,cols);
 end loop;
end $$;
commit;
