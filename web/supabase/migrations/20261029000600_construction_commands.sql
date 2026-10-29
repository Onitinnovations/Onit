begin;
alter table private.construction_milestones add column inspection_evidence_id uuid references private.execution_evidence(id) on delete restrict;
alter table private.construction_variations add column customer_decided_at timestamptz,add column commercial_approved_at timestamptz,
 add column implemented_commercial_version_id uuid references private.order_commercial_versions(id) on delete restrict;
create function app_private.construction_ready(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.construction_projects where operation_id=p_operation)
 and exists(select 1 from private.construction_milestones where operation_id=p_operation)
 and not exists(select 1 from private.construction_milestones milestone join private.work_tasks task on task.id=milestone.task_id
 where milestone.operation_id=p_operation and (milestone.customer_approved_by is null or task.status not in ('qa_approved','closed') or not app_private.operation_evidence(p_operation,milestone.inspection_evidence_id)))
 and not exists(select 1 from private.construction_variations where operation_id=p_operation and status not in ('implemented','rejected','withdrawn'))
 and not exists(select 1 from private.construction_material_requirements requirement where requirement.operation_id=p_operation and requirement.status='draft')
 and not exists(select 1 from private.construction_material_requirements requirement where requirement.operation_id=p_operation and (select coalesce(sum(case when kind='received' then quantity else -quantity end),0) from private.construction_material_events where requirement_id=requirement.id)<>0)
$$;
create function app_private.construction_action(p_operation uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;project private.construction_projects;milestone private.construction_milestones;requirement private.construction_material_requirements;
 variation private.construction_variations;task private.work_tasks;commercial private.order_commercial_versions;quote public.quotation_versions;
 result uuid;amount numeric;available numeric;staff boolean;begin
 select * into operation from private.service_operations where id=p_operation;
 if operation.kind<>'construction' then raise exception 'construction operation required' using errcode='23514';end if;
 staff=app_private.operation_staff(operation.id);
 if p_action not in ('milestone.accept','variation.customer') and not staff then raise exception 'central construction authority required' using errcode='42501';end if;
 case p_action
 when 'project.create' then
 if operation.status<>'planning' or jsonb_typeof(p_data->'specification') is distinct from 'object' or length(coalesce(p_data->>'access',''))>2000 then raise exception 'bounded technical project plan required' using errcode='23514';end if;
 if not exists(select 1 from private.service_orders where id=operation.primary_order_id and service_location_id=(p_data->>'site_id')::uuid) then raise exception 'original approved service site required' using errcode='23514';end if;
 insert into private.construction_projects(operation_id,site_location_id,customer_account_id,technical_specification,access_instructions,created_by)
 values(operation.id,(p_data->>'site_id')::uuid,operation.customer_account_id,p_data->'specification',coalesce(p_data->>'access',''),auth.uid()) returning id into result;
 when 'milestone.create' then
 select * into project from private.construction_projects where operation_id=operation.id;
 select task_row.* into task from private.operation_tasks link join private.work_tasks task_row on task_row.id=link.task_id where link.operation_id=operation.id and link.purpose='construction_milestone' and task_row.id=(p_data->>'task_id')::uuid;
 if project.id is null or task.id is null or operation.status<>'planning' or jsonb_typeof(p_data->'scope') is distinct from 'object' or jsonb_typeof(p_data->'measurements') is distinct from 'object' then raise exception 'linked planned trade task and immutable technical measurements required' using errcode='23514';end if;
 insert into private.construction_milestones(operation_id,project_id,task_id,code,trade,scope_snapshot,measurements,created_by)
 values(operation.id,project.id,task.id,p_data->>'code',p_data->>'trade',p_data->'scope',p_data->'measurements',auth.uid()) returning id into result;
 when 'milestone.inspect' then
 select * into milestone from private.construction_milestones where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if milestone.id is null or milestone.inspection_evidence_id is not null or not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.operation_independent(operation.id,auth.uid()) or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid)
 or not exists(select 1 from private.work_tasks where id=milestone.task_id and status='qa_approved') then raise exception 'independent shared QA and accepted site inspection required' using errcode='42501';end if;
 insert into private.operation_documents(operation_id,customer_account_id,document_id,task_id,classification,created_by)
 select operation.id,operation.customer_account_id,document_id,milestone.task_id,'measurement',auth.uid() from private.execution_evidence where id=(p_data->>'evidence_id')::uuid;
 update private.construction_milestones set inspection_evidence_id=(p_data->>'evidence_id')::uuid where id=milestone.id;result=milestone.id;
 when 'milestone.accept' then
 select * into milestone from private.construction_milestones where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if milestone.id is null or milestone.customer_approved_by is not null or milestone.inspection_evidence_id is null or not app_private.order_customer(operation.primary_order_id,'approve') or not app_private.operation_evidence(operation.id,milestone.inspection_evidence_id) then raise exception 'current customer and independently inspected milestone required' using errcode='42501';end if;
 update private.construction_milestones set customer_approved_by=auth.uid(),customer_approved_at=clock_timestamp() where id=milestone.id;result=milestone.id;
 when 'material.prepare' then
 if length(coalesce(p_data->>'code','')) not between 1 and 100 or length(coalesce(p_data->>'description','')) not between 1 and 2000 or length(coalesce(p_data->>'unit','')) not between 1 and 30 or p_data->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' then raise exception 'explicit decimal material specification required' using errcode='23514';end if;
 insert into private.construction_material_requirements(operation_id,code,version,description,unit,quantity,created_by)
 select operation.id,p_data->>'code',coalesce(max(version),0)+1,p_data->>'description',p_data->>'unit',(p_data->>'quantity')::numeric,auth.uid() from private.construction_material_requirements where operation_id=operation.id and code=p_data->>'code' returning id into result;
 when 'material.approve' then
 select * into requirement from private.construction_material_requirements where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if requirement.id is null or requirement.status<>'draft' or requirement.created_by=auth.uid() or not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.operation_independent(operation.id,auth.uid()) then raise exception 'independent material requirement approval required' using errcode='42501';end if;
 if exists(select 1 from private.construction_material_requirements where operation_id=operation.id and code=requirement.code and status='approved') then raise exception 'retire previous approved material requirement first' using errcode='23514';end if;
 update private.construction_material_requirements set status='approved',approved_by=auth.uid() where id=requirement.id;result=requirement.id;
 when 'material.retire' then
 select * into requirement from private.construction_material_requirements where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if requirement.id is null or requirement.status<>'approved' or requirement.created_by=auth.uid() or not app_private.operation_staff(operation.id,'specialized.approve') then raise exception 'independent material retirement required' using errcode='42501';end if;
 if (select coalesce(sum(case when kind='received' then quantity else -quantity end),0) from private.construction_material_events where requirement_id=requirement.id)<>0 then raise exception 'reconcile remaining site materials before retirement' using errcode='23514';end if;
 update private.construction_material_requirements set status='retired' where id=requirement.id;result=requirement.id;
 when 'material.record' then
 select * into requirement from private.construction_material_requirements where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 select task_row.* into task from private.operation_tasks link join private.work_tasks task_row on task_row.id=link.task_id where link.operation_id=operation.id and task_row.id=(p_data->>'task_id')::uuid;
 if requirement.id is null or requirement.status<>'approved' or task.id is null or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) or p_data->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or p_data->>'kind' not in ('received','consumed','returned','waste') then raise exception 'approved material, linked task and accepted evidence required' using errcode='23514';end if;
 amount=(p_data->>'quantity')::numeric;perform app_private.operation_validate_resource(operation.id,task.resource_id);
 select coalesce(sum(case when kind='received' then quantity else -quantity end),0) into available from private.construction_material_events where requirement_id=requirement.id;
 if amount<=0 or (p_data->>'kind'<>'received' and amount>available) or(p_data->>'kind'='received' and amount+coalesce((select sum(quantity) from private.construction_material_events where requirement_id=requirement.id and kind='received'),0)>requirement.quantity) then raise exception 'material quantity exceeds approved demand or held balance' using errcode='23514';end if;
 insert into private.construction_material_events(operation_id,requirement_id,task_id,kind,quantity,evidence_id,created_by) values(operation.id,requirement.id,task.id,p_data->>'kind',amount,(p_data->>'evidence_id')::uuid,auth.uid()) returning id into result;
 when 'variation.propose' then
 select * into commercial from private.order_commercial_versions where order_id=operation.primary_order_id order by version desc limit 1;
 if jsonb_typeof(p_data->'scope') is distinct from 'object' or p_data->>'cost_impact' !~ '^-?[0-9]{1,15}(\.[0-9]{1,4})?$' or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) then raise exception 'evidenced exact scope variation required' using errcode='23514';end if;
 amount=(p_data->>'cost_impact')::numeric;
 if amount<>round(amount,commercial.minor_units) then raise exception 'variation must respect commercial currency precision' using errcode='23514';end if;
 if amount<>0 and p_data->>'quote_id' is null then raise exception 'commercial scope impact requires an accepted revised quotation' using errcode='23514';end if;
 if p_data->>'quote_id' is not null then
 select * into quote from public.quotation_versions where id=(p_data->>'quote_id')::uuid;
 if quote.id is null or quote.status<>'accepted' or quote.currency_id<>commercial.currency_id or quote.total-commercial.total<>amount or not exists(select 1 from public.quotations successor join public.service_requests request on request.id=successor.request_id join private.service_orders parent on parent.id=operation.primary_order_id where successor.id=quote.quotation_id and request.customer_account_id=parent.customer_account_id and request.branch_id is not distinct from parent.branch_id and request.department_id is not distinct from parent.department_id and request.service_version_id=parent.service_version_id and (select row(address_snapshot,country_id,state_id,city_id,latitude,longitude) from public.service_locations where id=request.service_location_id) is not distinct from (select row(address_snapshot,country_id,state_id,city_id,latitude,longitude) from public.service_locations where id=parent.service_location_id)) then raise exception 'accepted same-tenant/site revised quote and exact difference required' using errcode='23514';end if;end if;
 insert into private.construction_variations(operation_id,version,original_commercial_version_id,proposed_quote_version_id,reason,scope_snapshot,time_impact_seconds,currency_id,cost_impact,created_by)
 select operation.id,coalesce(max(version),0)+1,commercial.id,(p_data->>'quote_id')::uuid,p_data->>'reason',p_data->'scope'||jsonb_build_object('evidence_id',p_data->>'evidence_id'),(p_data->>'time_impact_seconds')::integer,commercial.currency_id,amount,auth.uid() from private.construction_variations where operation_id=operation.id returning id into result;
 when 'variation.customer' then
 select * into variation from private.construction_variations where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if variation.id is null or variation.status<>'proposed' or not app_private.order_customer(operation.primary_order_id,'approve') or jsonb_typeof(p_data->'accept') is distinct from 'boolean' then raise exception 'current scoped customer variation decision required' using errcode='42501';end if;
 update private.construction_variations set status=case when(p_data->>'accept')::boolean then 'customer_accepted' else 'rejected' end,customer_decided_by=auth.uid(),customer_decided_at=clock_timestamp() where id=variation.id;result=variation.id;
 when 'variation.authorize' then
 select * into variation from private.construction_variations where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if variation.id is null or variation.status<>'customer_accepted' or variation.created_by=auth.uid() or variation.customer_decided_by=auth.uid() or not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.has_permission('quotes.approve',(select organisation_id from private.service_orders where id=operation.primary_order_id)) or not app_private.operation_independent(operation.id,auth.uid()) then raise exception 'independent OnIt commercial variation authority required' using errcode='42501';end if;
 update private.construction_variations set status='approved',commercial_approved_by=auth.uid(),commercial_approved_at=clock_timestamp() where id=variation.id;result=variation.id;
 when 'variation.withdraw' then
 select * into variation from private.construction_variations where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if variation.id is null or variation.status not in ('proposed','customer_accepted') then raise exception 'undecided variation required' using errcode='23514';end if;
 update private.construction_variations set status='withdrawn' where id=variation.id;result=variation.id;
 when 'variation.implement' then
 select * into variation from private.construction_variations where id=(p_data->>'id')::uuid and operation_id=operation.id;
 select * into commercial from private.order_commercial_versions where order_id=operation.primary_order_id order by version desc limit 1;
 select task_row.* into task from private.operation_tasks link join private.work_tasks task_row on task_row.id=link.task_id where link.operation_id=operation.id and task_row.id=(p_data->>'task_id')::uuid;
 if variation.id is null or variation.status<>'approved' or task.id is null or task.status<>'awaiting_mobilisation' or(variation.proposed_quote_version_id is not null and commercial.quotation_version_id<>variation.proposed_quote_version_id) or not app_private.order_gate(operation.primary_order_id) then raise exception 'approved variation, current accepted order commercial version and unstarted task required' using errcode='23514';end if;
 perform app_private.operation_validate_resource(operation.id,task.resource_id,false);
 update private.construction_variations set status='implemented',implemented_task_id=task.id,implemented_commercial_version_id=commercial.id where id=variation.id;result=variation.id;
 else raise exception 'unknown construction command' using errcode='23514';end case;return result;
end$$;
create function app_private.guard_construction_record() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'construction history retained' using errcode='55000';end if;
 if tg_table_name='construction_projects' then raise exception 'technical site snapshot immutable' using errcode='55000';
 elsif tg_table_name='construction_milestones' then
 if old.customer_approved_by is not null or (to_jsonb(new)-array['inspection_evidence_id','customer_approved_by','customer_approved_at','updated_at'])<>(to_jsonb(old)-array['inspection_evidence_id','customer_approved_by','customer_approved_at','updated_at']) or(old.inspection_evidence_id is not null and new.inspection_evidence_id is distinct from old.inspection_evidence_id) then raise exception 'milestone scope and decided inspection immutable' using errcode='55000';end if;
 elsif tg_table_name='construction_material_requirements' then
 if old.status<>'draft' and not(old.status='approved' and new.status='retired' and(to_jsonb(new)-array['status','updated_at'])=(to_jsonb(old)-array['status','updated_at'])) then raise exception 'approved material terms immutable' using errcode='55000';end if;
 elsif tg_table_name='construction_variations' then
 if old.status in ('implemented','rejected','withdrawn') or(to_jsonb(new)-array['status','customer_decided_by','customer_decided_at','commercial_approved_by','commercial_approved_at','implemented_task_id','implemented_commercial_version_id','updated_at'])<>(to_jsonb(old)-array['status','customer_decided_by','customer_decided_at','commercial_approved_by','commercial_approved_at','implemented_task_id','implemented_commercial_version_id','updated_at']) then raise exception 'variation terms and final decision immutable' using errcode='55000';end if;
 end if;return new;end$$;
do $$declare name text;begin foreach name in array array['construction_projects','construction_milestones','construction_material_requirements','construction_variations'] loop execute format('create trigger construction_guard before update or delete on private.%I for each row execute function app_private.guard_construction_record()',name);end loop;end$$;
revoke all on function app_private.construction_ready(uuid),app_private.construction_action(uuid,text,jsonb) from public,anon,authenticated;
-- Rebind the one authorised operation command, retaining its locks, receipt and revision checks.
do $$declare source text;old_fragment text;begin
 source=pg_get_functiondef('app_private.service_operation_command(uuid,text,jsonb,text)'::regprocedure);
 old_fragment=$fragment$if operation.kind<>'laundry' or operation.status<>'active' or not app_private.laundry_ready(operation.id) then$fragment$;
 if position(old_fragment in source)=0 then raise exception 'review specialised closure integration';end if;
 source=replace(source,old_fragment,$fragment$if operation.status<>'active' or not(case operation.kind when 'laundry' then app_private.laundry_ready(operation.id) when 'construction' then app_private.construction_ready(operation.id) else false end) then$fragment$);
 old_fragment=$fragment$if operation.kind<>'laundry' or (operation.status<>'active' and p_action not in ('bag.create','item.create','bag.acknowledge')) then raise exception 'active specialised workflow required' using errcode='23514';end if;
 result=app_private.laundry_action(operation.id,p_action,p_data);$fragment$;
 if position(old_fragment in source)=0 then raise exception 'review specialised command integration';end if;
 source=replace(source,old_fragment,$fragment$if operation.status not in ('planning','active') then raise exception 'active specialised workflow required' using errcode='23514';end if;
 if operation.kind='laundry' then
 if operation.status<>'active' and p_action not in ('bag.create','item.create','bag.acknowledge') then raise exception 'active Laundry workflow required' using errcode='23514';end if;
 result=app_private.laundry_action(operation.id,p_action,p_data);
 elsif operation.kind='construction' then result=app_private.construction_action(operation.id,p_action,p_data);
 else raise exception 'unsupported specialised command' using errcode='23514';end if;$fragment$);execute source;
end$$;
-- Customer-safe technical projection; financial variation terms are restricted to staff/customer approvers.
alter function app_private.read_service_operation(uuid,uuid,integer) rename to read_operation_laundry_projection;
revoke all on function app_private.read_operation_laundry_projection(uuid,uuid,integer) from public,anon,authenticated;
create function app_private.read_service_operation(p_operation uuid,p_after uuid default null,p_limit integer default 25) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare operation private.service_operations;result jsonb;staff boolean;customer boolean;begin
 result=app_private.read_operation_laundry_projection(p_operation,p_after,p_limit);
 select * into operation from private.service_operations where id=p_operation;
 if operation.kind<>'construction' then return result;end if;
 staff=app_private.operation_staff(operation.id,'specialized.read') or app_private.operation_staff(operation.id);customer=app_private.operation_customer(operation.id,true);
 result=result||jsonb_build_object('project',(select jsonb_build_object('id',id,'site_id',site_location_id,'specification',technical_specification,'access',access_instructions) from private.construction_projects where operation_id=operation.id),
 'milestones',(select coalesce(jsonb_agg(to_jsonb(page)),'[]') from(select milestone.id,milestone.task_id,milestone.code,milestone.trade,milestone.scope_snapshot,milestone.measurements,milestone.inspection_evidence_id,milestone.customer_approved_at from private.construction_milestones milestone where milestone.operation_id=operation.id and(staff or customer or app_private.execution_worker(milestone.task_id)) and(p_after is null or milestone.id>p_after) order by milestone.id limit p_limit) page));
 if staff or customer then result=result||jsonb_build_object('variations',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'version',version,'status',status,'scope',scope_snapshot,'cost_impact',cost_impact::text,'time_impact_seconds',time_impact_seconds,'original_commercial_version_id',original_commercial_version_id,'proposed_quote_version_id',proposed_quote_version_id,'implemented_commercial_version_id',implemented_commercial_version_id)),'[]') from(select * from private.construction_variations where operation_id=operation.id and(p_after is null or id>p_after) order by id limit p_limit) page));end if;
 if staff then result=result||jsonb_build_object('materials',(select coalesce(jsonb_agg(jsonb_build_object('id',requirement.id,'code',requirement.code,'version',requirement.version,'status',requirement.status,'quantity',requirement.quantity::text,'unit',requirement.unit,'held',(select coalesce(sum(case when kind='received' then quantity else -quantity end),0)::text from private.construction_material_events where requirement_id=requirement.id))),'[]') from private.construction_material_requirements requirement where requirement.operation_id=operation.id));end if;return result;end$$;
grant execute on function app_private.read_service_operation(uuid,uuid,integer) to authenticated;
create or replace function public.read_service_operation(p_operation uuid,p_after uuid default null,p_limit integer default 25) returns jsonb language sql stable set search_path='' as $$select app_private.read_service_operation(p_operation,p_after,p_limit)$$;
commit;
