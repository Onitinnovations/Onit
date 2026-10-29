begin;
alter table private.construction_variations add unique(id,operation_id);
alter table private.construction_milestones add column source_variation_id uuid,
 add foreign key(source_variation_id,operation_id) references private.construction_variations(id,operation_id) on delete restrict;
create table private.construction_milestone_successors(
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 variation_id uuid not null,original_milestone_id uuid not null unique,successor_milestone_id uuid not null,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),
 foreign key(variation_id,operation_id) references private.construction_variations(id,operation_id) on delete restrict,
 foreign key(original_milestone_id,operation_id) references private.construction_milestones(id,operation_id) on delete restrict,
 foreign key(successor_milestone_id,operation_id) references private.construction_milestones(id,operation_id) on delete restrict,
 check(original_milestone_id<>successor_milestone_id)
);
alter table private.construction_milestone_successors enable row level security;
revoke all on private.construction_milestone_successors from public,anon,authenticated;
grant all on private.construction_milestone_successors to service_role;
create trigger construction_successor_immutable before update or delete on private.construction_milestone_successors for each row execute function app_private.reject_mutation();
create trigger construction_successor_audit after insert on private.construction_milestone_successors for each row execute function app_private.audit_access_change();
do $$declare source text;old_fragment text;begin
 source=pg_get_functiondef('app_private.construction_ready(uuid)'::regprocedure);
 source=replace(source,'where milestone.operation_id=p_operation and (','where milestone.operation_id=p_operation and not exists(select 1 from private.construction_milestone_successors successor where successor.original_milestone_id=milestone.id) and (');execute source;
 source=pg_get_functiondef('app_private.construction_action(uuid,text,jsonb)'::regprocedure);
 old_fragment=$fragment$if project.id is null or task.id is null or operation.status<>'planning' or$fragment$;
 if position(old_fragment in source)=0 then raise exception 'review construction milestone integration';end if;
 source=replace(source,old_fragment,$fragment$select * into variation from private.construction_variations where id=(p_data->>'variation_id')::uuid and operation_id=operation.id;
 if p_data->>'variation_id' is not null and(variation.id is null or variation.status<>'approved' or p_data->'scope' is distinct from(variation.scope_snapshot-'evidence_id')) then raise exception 'approved immutable variation scope required' using errcode='23514';end if;
 if project.id is null or task.id is null or(operation.status<>'planning' and variation.id is null) or$fragment$);
 source=replace(source,'scope_snapshot,measurements,created_by)','scope_snapshot,measurements,source_variation_id,created_by)');
 source=replace(source,$fragment$p_data->'scope',p_data->'measurements',auth.uid())$fragment$,$fragment$p_data->'scope',p_data->'measurements',variation.id,auth.uid())$fragment$);
 old_fragment=$fragment$when 'variation.withdraw' then$fragment$;
 source=replace(source,old_fragment,$fragment$when 'variation.reject' then
 select * into variation from private.construction_variations where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if variation.id is null or variation.status not in ('proposed','customer_accepted') or variation.created_by=auth.uid() or not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.operation_independent(operation.id,auth.uid()) then raise exception 'independent commercial rejection required' using errcode='42501';end if;
 update private.construction_variations set status='rejected',commercial_approved_by=auth.uid(),commercial_approved_at=clock_timestamp() where id=variation.id;result=variation.id;
 when 'variation.withdraw' then$fragment$);
 old_fragment=$fragment$perform app_private.operation_validate_resource(operation.id,task.resource_id,false);
 update private.construction_variations set status='implemented'$fragment$;
 if position(old_fragment in source)=0 then raise exception 'review construction commercial implementation boundary';end if;
 source=replace(source,old_fragment,$fragment$perform app_private.operation_validate_resource(operation.id,task.resource_id,false);
 if variation.proposed_quote_version_id is not null then
 select * into milestone from private.construction_milestones where operation_id=operation.id and task_id=task.id and source_variation_id=variation.id;
 if milestone.id is null or jsonb_typeof(coalesce(p_data->'predecessors','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_data->'predecessors','[]'::jsonb))>100 then raise exception 'explicit approved replacement milestone and bounded predecessor mapping required' using errcode='23514';end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'predecessors','[]'::jsonb)) predecessor where not exists(select 1 from private.construction_milestones old_milestone join private.work_tasks old_task on old_task.id=old_milestone.task_id where old_milestone.id=predecessor::uuid and old_milestone.operation_id=operation.id and old_task.status='cancelled')) then raise exception 'same-operation retired milestone predecessors required' using errcode='23514';end if;
 insert into private.construction_milestone_successors(operation_id,variation_id,original_milestone_id,successor_milestone_id,created_by) select operation.id,variation.id,predecessor::uuid,milestone.id,auth.uid() from jsonb_array_elements_text(coalesce(p_data->'predecessors','[]'::jsonb)) predecessor;
 end if;
 update private.construction_variations set status='implemented'$fragment$);execute source;
 source=pg_get_functiondef('app_private.service_operation_command(uuid,text,jsonb,text)'::regprocedure);
 old_fragment=$fragment$if operation.status<>'planning' or task.id is null or task.is_container$fragment$;
 source=replace(source,old_fragment,$fragment$if(operation.status<>'planning' and not(operation.kind='construction' and operation.status='active' and exists(select 1 from private.construction_variations variation join private.order_commercial_versions commercial on commercial.quotation_version_id=variation.proposed_quote_version_id and commercial.order_id=operation.primary_order_id where variation.operation_id=operation.id and variation.status='approved' and commercial.version=(select max(version) from private.order_commercial_versions where order_id=operation.primary_order_id)))) or task.id is null or task.is_container$fragment$);execute source;
 source=pg_get_functiondef('app_private.fulfilment_command(uuid,text,jsonb,text)'::regprocedure);
 old_fragment=$fragment$operation.status not in ('ready','closed','cancelled')) then$fragment$;
 if position(old_fragment in source)=0 then raise exception 'review shared retirement guard before commercial changes';end if;
 source=replace(source,old_fragment,$fragment$operation.status not in ('ready','closed','cancelled') and not(p_action='retire_for_reschedule' and operation.kind='construction' and exists(select 1 from private.construction_variations variation where variation.operation_id=operation.id and variation.status='approved' and variation.proposed_quote_version_id is not null))) then$fragment$);
 source=replace(source,$fragment$if p_action in ('progress','supervisor_verify','substitute','task_reassign') then$fragment$,$fragment$if p_action='progress' and exists(select 1 from private.construction_milestones milestone join private.construction_variations variation on variation.id=milestone.source_variation_id where milestone.task_id=(p_data->>'task_id')::uuid and variation.status<>'implemented') then raise exception 'commercial variation implementation required before field progress' using errcode='23514';end if;
 if p_action in ('progress','supervisor_verify','substitute','task_reassign') then$fragment$);execute source;
end$$;
commit;
