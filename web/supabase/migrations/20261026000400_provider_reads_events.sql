begin;
create function public.apply_provider(p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.provider_command(null,'apply',p_data,p_key)$$;
grant execute on function public.apply_provider(jsonb,text) to authenticated;
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
    or (a.assessor_id=auth.uid() and app_private.has_permission('assessments.perform',r.organisation_id)))))
  or (d.customer_account_id is null and d.classification in ('identity','contract','work') and exists(select 1 from private.provider_profiles p
   where app_private.provider_document(p.id,d.id) and (
    exists(select 1 from private.provider_qualifications q where q.provider_id=p.id and q.document_id=d.id
     and (app_private.has_permission('providers.documents.read',p.organisation_id) or (d.classification<>'identity' and app_private.provider_self(p.id) and (q.subject_profile_id=auth.uid() or app_private.provider_self(p.id,true)))))
    or exists(select 1 from private.provider_engagements e where e.provider_id=p.id and e.document_id=d.id
     and (app_private.has_permission('providers.documents.read',p.organisation_id) or (d.classification<>'identity' and app_private.provider_self(p.id,true)))))))));
$$;
create function app_private.list_providers(p_status text,p_after uuid,p_limit integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or (p_status is not null and p_status not in ('applicant','approved','active','suspended','offboarded')) then raise exception 'bounded provider filter required' using errcode='23514';end if;
 return (select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') from (
 select p.id,p.provider_type,p.status,p.revision from private.provider_profiles p
 where (p_status is null or p.status=p_status) and (p_after is null or p.id>p_after)
 and (app_private.provider_self(p.id) or app_private.has_permission('providers.read',p.organisation_id)) order by p.id limit p_limit) q);
end $$;
create function public.list_providers(p_status text default null,p_after uuid default null,p_limit integer default 25) returns jsonb
language sql stable set search_path='' as $$select app_private.list_providers(p_status,p_after,p_limit)$$;
create function app_private.read_provider_configuration(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not (app_private.has_permission('providers.policy.manage') or app_private.has_permission('providers.policy.approve')) then raise exception 'provider configuration reader required' using errcode='42501';end if;
 case p_kind
 when 'requirements' then return (select to_jsonb(x)-array['created_by','approved_by'] from private.provider_requirement_sets x where id=p_id);
 when 'course' then return (select to_jsonb(x)-array['created_by','approved_by'] from private.provider_training_courses x where id=p_id);
 when 'session' then return (select to_jsonb(x)-'created_by' from private.provider_training_sessions x where id=p_id);
 when 'campaign' then return (select to_jsonb(x)-'created_by' from private.provider_recruitment_campaigns x where id=p_id);
 else raise exception 'configuration kind unsupported' using errcode='23514';end case;
end $$;
create function public.read_provider_configuration(p_kind text,p_id uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_provider_configuration(p_kind,p_id)$$;
create function app_private.provider_document_reference(p_provider uuid,p_document uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d private.document_objects;p private.provider_profiles;
begin
 select * into p from private.provider_profiles where id=p_provider;
 select * into d from private.document_objects where id=p_document;
 if p.id is null or d.id is null or not app_private.provider_document(p.id,d.id)
  or not (app_private.has_permission('providers.read',p.organisation_id) or app_private.provider_self(p.id))
  or not (exists(select 1 from private.provider_qualifications q where q.provider_id=p.id and q.document_id=d.id) or exists(select 1 from private.provider_engagements e where e.provider_id=p.id and e.document_id=d.id))
  or not app_private.can_read_object(d.bucket_id,d.object_name) then raise exception 'provider document access denied' using errcode='42501';end if;
 return jsonb_build_object('id',d.id,'bucket',d.bucket_id,'object_name',d.object_name,'content_type',d.content_type,'byte_size',d.byte_size::text);
end$$;
create function public.provider_document_reference(p_provider uuid,p_document uuid) returns jsonb language sql stable set search_path='' as $$select app_private.provider_document_reference(p_provider,p_document)$$;
revoke all on function public.provider_document_reference(uuid,uuid) from public,anon;
grant execute on function public.provider_document_reference(uuid,uuid),app_private.provider_document_reference(uuid,uuid) to authenticated;
grant execute on function public.list_providers(text,uuid,integer),app_private.list_providers(text,uuid,integer),public.read_provider_configuration(text,uuid),app_private.read_provider_configuration(text,uuid) to authenticated;
create function app_private.provider_activity(p_provider uuid,p_before timestamptz,p_before_id uuid,p_limit integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from private.provider_profiles p where p.id=p_provider and app_private.has_permission('providers.read',p.organisation_id)) then raise exception 'scoped provider reader required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or (p_before is null)<>(p_before_id is null) then raise exception 'bounded paired timeline cursor required' using errcode='23514';end if;
 return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]') from (select id,action,subject_id,previous_state,new_state,reason,correlation_id,permission_code,actor_id,created_at from private.provider_history where provider_id=p_provider and (p_before is null or (created_at,id)<(p_before,p_before_id)) order by created_at desc,id desc limit p_limit) q);
end $$;
create function public.provider_activity(p_provider uuid,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 25) returns jsonb language sql stable set search_path='' as $$select app_private.provider_activity(p_provider,p_before,p_before_id,p_limit)$$;
grant execute on function public.provider_activity(uuid,timestamptz,uuid,integer),app_private.provider_activity(uuid,timestamptz,uuid,integer) to authenticated;
-- Durable leasing/acknowledgement only. Processing is not notification delivery.
alter table private.operational_event_deliveries add column last_failure_code text check(last_failure_code ~ '^[A-Z0-9_]{1,80}$');
alter table private.operational_event_deliveries add column last_receipt_token uuid,add column last_receipt_action text check(last_receipt_action in ('ack','retry')),add column last_receipt_hash text;
create function app_private.operational_event_worker(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb='[]';v private.operational_event_deliveries;seconds integer;max_attempts integer;row_item record;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'server worker only' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096 then raise exception 'bounded worker command required' using errcode='23514';end if;
 if p_action='claim' then
  seconds=(p_data->>'lease_seconds')::integer;max_attempts=(p_data->>'max_attempts')::integer;
  if seconds is null or seconds not between 1 and 3600 or max_attempts is null or max_attempts not between 1 and 100 or (p_data->>'limit')::integer not between 1 and 100 or p_data->>'limit' is null then raise exception 'explicit bounded worker configuration required' using errcode='23514';end if;
  -- Expired leases are eligible for redelivery; use consumer idempotency by event UUID.
  for row_item in select id from private.operational_event_deliveries where (status='pending' and available_at<=now()) or (status='leased' and lease_until<=now()) order by available_at,id limit (p_data->>'limit')::integer for update skip locked loop
   update private.operational_event_deliveries set status=case when attempts>=max_attempts then 'dead' else 'leased' end,
    attempts=case when attempts>=max_attempts then attempts else attempts+1 end,
    lease_token=case when attempts>=max_attempts then null else gen_random_uuid() end,
    lease_until=case when attempts>=max_attempts then null else now()+make_interval(secs=>seconds) end where id=row_item.id returning * into v;
   insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id,details)
   values(null,'outbox.claim','private','operational_event_deliveries',v.id,jsonb_build_object('actor_type','system_worker','authorization','service_role','state',v.status));
   if v.status='leased' then
    result=result||jsonb_build_array((select jsonb_build_object('id',v.id,'event_id',e.id,'token',v.lease_token,'lease_until',v.lease_until,'event_code',e.event_code,'subject_id',e.subject_id,'provider_id',e.provider_id,'correlation_id',e.correlation_id) from private.operational_events e where e.id=v.event_id));
   end if;
  end loop;
  return result;
 elsif p_action in ('ack','retry') then
  select * into v from private.operational_event_deliveries where id=(p_data->>'id')::uuid for update;
  if found and v.last_receipt_token=(p_data->>'token')::uuid and v.last_receipt_action=p_action then
   if v.last_receipt_hash is distinct from md5(p_data::text) then raise exception 'worker retry payload conflict' using errcode='23505';end if;
   return jsonb_build_object('id',v.id,'processed',p_action='ack');
  end if;
  if not found or v.status<>'leased' or v.lease_until<=now() or v.lease_token is distinct from (p_data->>'token')::uuid then raise exception 'lease unavailable' using errcode='40001';end if;
  if p_action='ack' then update private.operational_event_deliveries set status='processed',processed_at=now(),lease_token=null,lease_until=null where id=v.id;
  else
   seconds=(p_data->>'retry_seconds')::integer;
   if seconds is null or seconds not between 0 and 86400 or p_data->>'failure_code' is null then raise exception 'explicit retry delay and safe failure code required' using errcode='23514';end if;
   update private.operational_event_deliveries set status='pending',available_at=now()+make_interval(secs=>seconds),lease_token=null,lease_until=null,last_failure_code=p_data->>'failure_code' where id=v.id;
  end if;
  update private.operational_event_deliveries set last_receipt_token=(p_data->>'token')::uuid,last_receipt_action=p_action,last_receipt_hash=md5(p_data::text) where id=v.id;
  insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id,details)
  values(null,'outbox.'||p_action,'private','operational_event_deliveries',v.id,jsonb_build_object('actor_type','system_worker','authorization','service_role'));
  return jsonb_build_object('id',v.id,'processed',p_action='ack');
 else raise exception 'unsupported worker action' using errcode='23514';end if;
end $$;
create function public.operational_event_worker(p_action text,p_data jsonb) returns jsonb language sql set search_path='' as $$select app_private.operational_event_worker(p_action,p_data)$$;
-- Do not rely on a managed project's pre-existing default function ACLs.
revoke all on function public.apply_provider(jsonb,text),public.provider_command(uuid,text,jsonb,text),public.provider_configuration(text,jsonb,text),
 public.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),public.provider_reservation(uuid,text,jsonb,text),public.read_provider(uuid),
 public.list_providers(text,uuid,integer),public.read_provider_configuration(text,uuid),public.provider_activity(uuid,timestamptz,uuid,integer) from public,anon;
revoke all on function public.operational_event_worker(text,jsonb),app_private.operational_event_worker(text,jsonb) from public,anon,authenticated;
grant execute on function app_private.operational_event_worker(text,jsonb),public.operational_event_worker(text,jsonb) to service_role;
commit;
