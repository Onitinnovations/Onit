begin;
-- Internal kernels preserve the existing eligibility implementation. Existing
-- user entry points remain authorised wrappers; kernels are never API executable.
do $$declare source text;guard text;begin
 source=pg_get_functiondef('app_private.provider_party_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid)'::regprocedure);
 guard=$guard$if p.id is null or not (app_private.provider_self(p.id) or app_private.has_permission('providers.read',p.organisation_id) or app_private.has_permission('providers.capacity.manage',p.organisation_id)) then raise exception 'provider eligibility access denied' using errcode='42501';end if;$guard$;
 if position(guard in source)=0 then raise exception 'review changed eligibility authority before migration';end if;
 source=replace(source,'FUNCTION app_private.provider_party_eligibility(','FUNCTION app_private.provider_party_eligibility_kernel(');
 source=replace(source,guard,$guard$if p.id is null then raise exception 'provider unavailable' using errcode='42501';end if;$guard$);execute source;
 source=pg_get_functiondef('app_private.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid)'::regprocedure);
 guard=$guard$if not (worker=auth.uid() or app_private.provider_self(p.id,true) or app_private.has_permission('providers.read',p.organisation_id) or app_private.has_permission('providers.capacity.manage',p.organisation_id)) then raise exception 'worker resource access denied' using errcode='42501';end if;$guard$;
 if position(guard in source)=0 then raise exception 'review changed personnel authority before migration';end if;
 source=replace(source,'FUNCTION app_private.provider_eligibility(','FUNCTION app_private.provider_eligibility_kernel(');
 source=replace(source,'app_private.provider_party_eligibility(','app_private.provider_party_eligibility_kernel(');
 source=replace(source,guard,'');execute source;
end$$;
revoke all on function app_private.provider_party_eligibility_kernel(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),app_private.provider_eligibility_kernel(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid) from public,anon,authenticated;

create function app_private.operation_staff(p_operation uuid,p_permission text default 'specialized.manage') returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_operations operation join private.service_orders o on o.id=operation.primary_order_id where operation.id=p_operation and app_private.has_permission(p_permission,o.organisation_id))
$$;
create function app_private.operation_customer(p_operation uuid,p_approve boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.operation_orders member where member.operation_id=p_operation and app_private.order_customer(member.order_id,case when p_approve then 'approve' else 'read' end))
$$;
create function app_private.operation_resource(p_operation uuid,p_resource uuid,p_actor boolean default true) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.operation_tasks link join private.work_tasks t on t.id=link.task_id join private.work_orders w on w.id=t.work_order_id
 join private.assignment_resources resource on resource.id=t.resource_id join private.provider_capacity_reservations capacity on capacity.id=resource.reservation_id and capacity.status='assigned'
 join private.dispatch_proposals proposal on proposal.id=w.proposal_id and proposal.status='confirmed'
 join private.assignment_offers offer on offer.id=resource.offer_id and offer.proposal_id=proposal.id
 join private.provider_profiles party on party.id=resource.provider_id and party.status='active'
 join public.profiles worker on worker.id=resource.worker_id and worker.status='active'
 where link.operation_id=p_operation and resource.id=p_resource and w.status not in ('closed','cancelled','suspended') and t.status not in ('closed','cancelled','awaiting_capacity')
 and (not p_actor or app_private.execution_worker(t.id)))
$$;
create function app_private.operation_independent(p_operation uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.operation_tasks link where link.operation_id=p_operation and not app_private.execution_target_independent(link.work_order_id,p_actor))
$$;
create function app_private.operation_validate_resource(p_operation uuid,p_resource uuid,p_physical boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare o private.service_orders;capacity private.provider_capacity_reservations;decision jsonb;begin
 if not app_private.operation_resource(p_operation,p_resource,false) then raise exception 'current confirmed execution resource required' using errcode='23514';end if;
 select service_order.* into o from private.operation_tasks link join private.work_tasks task on task.id=link.task_id join private.service_orders service_order on service_order.id=link.order_id where link.operation_id=p_operation and task.resource_id=p_resource limit 1;
 perform app_private.dispatch_locks(o.id);
 if p_physical and not exists(select 1 from private.operation_tasks link join private.work_tasks task on task.id=link.task_id where link.operation_id=p_operation and task.resource_id=p_resource and task.accepted_at is not null and task.starts_at<=clock_timestamp() and task.ends_at>clock_timestamp() and task.status in ('arrived','started','in_progress','work_completed','awaiting_qa','qa_approved')) then raise exception 'accepted attended work in the execution window required' using errcode='23514';end if;
 select r.* into capacity from private.assignment_resources a join private.provider_capacity_reservations r on r.id=a.reservation_id where a.id=p_resource for update of r;
 if (p_physical and (clock_timestamp()<capacity.starts_at or clock_timestamp()>=capacity.ends_at)) or not app_private.order_gate(o.id) then raise exception 'execution window or commercial gate unavailable' using errcode='23514';end if;
 update private.provider_capacity_reservations set status='released' where id=capacity.id;
 decision=app_private.provider_eligibility_kernel(capacity.provider_id,o.service_version_id,o.zone_id,capacity.starts_at,capacity.ends_at,capacity.units::text,capacity.worker_profile_id);
 if (decision->>'eligible')::boolean is distinct from true then raise exception 'execution eligibility changed' using errcode='23514';end if;
 update private.provider_capacity_reservations set status='assigned' where id=capacity.id;
end$$;
create function app_private.operation_evidence(p_operation uuid,p_evidence uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.execution_evidence evidence join private.operation_tasks link on link.task_id=evidence.task_id and link.operation_id=p_operation
 join private.work_tasks task on task.id=link.task_id and task.execution_round=evidence.execution_round
 join private.document_objects document on document.id=evidence.document_id and document.customer_account_id=link.customer_account_id and document.scan_status='clean' and document.archived_at is null
 where evidence.id=p_evidence and evidence.status='approved')
$$;

create function app_private.operation_policy_command(p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare policy private.specialized_service_policies;receipt private.transaction_commands;result uuid;payload jsonb=jsonb_build_object('action',p_action,'data',p_data);begin
 if auth.uid() is null or not app_private.has_permission(case when p_action='prepare' then 'specialized.policy.manage' else 'specialized.policy.approve' end) then raise exception 'global specialised policy authority required' using errcode='42501';end if;
 if length(coalesce(p_key,'')) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 then raise exception 'bounded policy command required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('operation-policy-command:'||auth.uid()::text||p_key,0));
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='operation_policy' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'policy idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action='prepare' then
 if jsonb_typeof(p_data->'configuration'->'required_purposes') is distinct from 'array' or jsonb_array_length(p_data->'configuration'->'required_purposes') not between 1 and 10 then raise exception 'explicit required task purposes needed' using errcode='23514';end if;
 if p_data->>'kind'='laundry' and (not(p_data->'configuration'->'required_purposes' @> '["pickup","processing","laundry_delivery"]'::jsonb) or coalesce(p_data->'configuration'->>'qa_granularity','') not in ('item','batch') or jsonb_typeof(p_data->'configuration'->'allow_count_adjustment') is distinct from 'boolean' or jsonb_typeof(p_data->'configuration'->'garment_categories') is distinct from 'array' or jsonb_typeof(p_data->'configuration'->'treatments') is distinct from 'array') then raise exception 'explicit Laundry custody, quality and classification policy required' using errcode='23514';end if;
 if not exists(select 1 from public.service_versions version join public.services service on service.id=version.service_id join public.service_families family on family.id=service.service_family_id join public.service_areas area on area.id=family.service_area_id where version.id=(p_data->>'service_version_id')::uuid and area.code=case p_data->>'kind' when 'laundry' then 'home-utilities' when 'construction' then 'construction' when 'procurement' then 'procurement' when 'field_campaign' then 'business-field-services' end) then raise exception 'specialised policy must match the approved service category' using errcode='23514';end if;
 if exists(select 1 from jsonb_array_elements_text(p_data->'configuration'->'required_purposes') purpose where not(case p_data->>'kind' when 'laundry' then purpose in ('pickup','intake','processing','laundry_delivery') when 'construction' then purpose in ('site_inspection','construction_milestone') when 'procurement' then purpose in ('procurement_receiving','procurement_handover') when 'field_campaign' then purpose='field_visit' else false end)) then raise exception 'typed task purposes required' using errcode='23514';end if;
 if p_data->>'kind'='laundry' and (jsonb_array_length(p_data->'configuration'->'garment_categories') not between 1 and 100 or jsonb_array_length(p_data->'configuration'->'treatments') not between 1 and 100 or exists(select 1 from jsonb_array_elements((p_data->'configuration'->'garment_categories')||(p_data->'configuration'->'treatments')) entry where jsonb_typeof(entry)<>'string' or length(entry#>>'{}') not between 1 and 100)) then raise exception 'bounded nonempty garment classifications required' using errcode='23514';end if;
 if not app_private.is_version_published((p_data->>'service_version_id')::uuid) then raise exception 'published service version required' using errcode='23514';end if;
 insert into private.specialized_service_policies(service_version_id,kind,version,valid_from,valid_until,configuration,created_by) values((p_data->>'service_version_id')::uuid,p_data->>'kind',(p_data->>'version')::integer,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,p_data->'configuration',auth.uid()) returning id into result;
 elsif p_action in ('approve','retire') then
 select * into policy from private.specialized_service_policies where id=(p_data->>'id')::uuid;
 if policy.id is null then raise exception 'policy unavailable' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('operation-policy:'||policy.service_version_id::text||policy.kind,0));select * into policy from private.specialized_service_policies where id=policy.id for update;
 if policy.created_by=auth.uid() or (p_action='approve' and policy.status<>'draft') or (p_action='retire' and policy.status<>'approved') then raise exception 'independent policy decision required' using errcode='42501';end if;
 if p_action='approve' and exists(select 1 from private.specialized_service_policies other where other.id<>policy.id and other.service_version_id=policy.service_version_id and other.kind=policy.kind and other.status='approved' and tstzrange(other.valid_from,other.valid_until,'[)')&&tstzrange(policy.valid_from,policy.valid_until,'[)')) then raise exception 'overlapping specialised policy' using errcode='23514';end if;
 update private.specialized_service_policies set status=case p_action when 'approve' then 'approved' else 'retired' end,approved_by=case p_action when 'approve' then auth.uid() else approved_by end,approved_at=case p_action when 'approve' then now() else approved_at end where id=policy.id;result=policy.id;
 else raise exception 'unknown policy action' using errcode='23514';end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'operation_policy',p_key,payload,result);return result;
end$$;
create function public.operation_policy_command(p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.operation_policy_command(p_action,p_data,p_key)$$;
revoke all on function public.operation_policy_command(text,jsonb,text) from public,anon;
grant execute on function public.operation_policy_command(text,jsonb,text),app_private.operation_policy_command(text,jsonb,text) to authenticated;
create function app_private.read_operation_policy(p_policy uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not(app_private.has_permission('specialized.policy.manage') or app_private.has_permission('specialized.policy.approve')) then raise exception 'global specialised policy authority required' using errcode='42501';end if;
 select to_jsonb(policy) into result from private.specialized_service_policies policy where id=p_policy;
 if result is null then raise exception 'specialised policy unavailable' using errcode='42501';end if;return result;
end$$;
create function public.read_operation_policy(p_policy uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_operation_policy(p_policy)$$;
revoke all on function public.read_operation_policy(uuid) from public,anon;
grant execute on function public.read_operation_policy(uuid),app_private.read_operation_policy(uuid) to authenticated;
commit;
