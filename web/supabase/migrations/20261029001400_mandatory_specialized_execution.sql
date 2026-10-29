begin;
create function app_private.operation_task_member(p_operation uuid,p_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 with recursive ancestors(id) as(select p_task union select rework.original_task_id from private.rework_requests rework join ancestors on ancestors.id=rework.rework_task_id)
 select exists(select 1 from private.operation_tasks link join ancestors on ancestors.id=link.task_id join private.work_tasks task on task.id=p_task and task.order_id=link.order_id and task.customer_account_id=link.customer_account_id where link.operation_id=p_operation)
$$;
create or replace function app_private.operation_evidence(p_operation uuid,p_evidence uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.execution_evidence evidence join private.work_tasks task on task.id=evidence.task_id and task.execution_round=evidence.execution_round
 join private.service_operations operation on operation.id=p_operation and operation.customer_account_id=task.customer_account_id
 join private.document_objects document on document.id=evidence.document_id and document.customer_account_id=operation.customer_account_id and document.scan_status='clean' and document.archived_at is null
 where evidence.id=p_evidence and evidence.status='approved' and app_private.operation_task_member(p_operation,task.id))
$$;
revoke all on function app_private.operation_task_member(uuid,uuid),app_private.operation_evidence(uuid,uuid) from public,anon,authenticated;
create function app_private.require_specialized_execution(p_work uuid,p_action text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare work private.work_orders;parent private.service_orders;policy private.specialized_service_policies;operation private.service_operations;link private.operation_tasks;task private.work_tasks;begin
 if p_work is null then return;end if;
 if not app_private.execution_read_access(p_work) then raise exception 'current work authority required' using errcode='42501';end if;
 select * into work from private.work_orders where id=p_work;select * into parent from private.service_orders where id=work.order_id for update;
 if p_action not in ('progress','supervisor_verify','close_work','substitute','task_reassign') then return;end if;
 for policy in select policy_row.* from private.specialized_service_policies policy_row where policy_row.service_version_id=parent.service_version_id and((policy_row.status='approved' and policy_row.valid_from<=now() and(policy_row.valid_until is null or policy_row.valid_until>=work.ends_at)) or exists(select 1 from private.service_operations operation_row join private.operation_orders member on member.operation_id=operation_row.id where member.order_id=parent.id and operation_row.policy_id=policy_row.id and operation_row.status not in ('cancelled'))) loop
 select operation_row.* into operation from private.service_operations operation_row join private.operation_orders member on member.operation_id=operation_row.id where member.order_id=parent.id and operation_row.kind=policy.kind;
 if operation.id is null or(p_action='close_work' and operation.status not in ('ready','closed')) or(p_action<>'close_work' and operation.status<>'active') then raise exception 'mandatory specialised operation and controlled lifecycle required' using errcode='23514';end if;
 if p_action='close_work' then continue;end if;
 select * into task from private.work_tasks where id=(p_data->>'task_id')::uuid and work_order_id=work.id;
 if task.id is null then raise exception 'same-work specialised task required' using errcode='23514';end if;
 with recursive ancestors(id) as(select task.id union select rework.original_task_id from private.rework_requests rework join ancestors on ancestors.id=rework.rework_task_id)
 select operation_link.* into link from private.operation_tasks operation_link join ancestors on ancestors.id=operation_link.task_id where operation_link.operation_id=operation.id order by(operation_link.task_id=task.id) desc limit 1;
 if link.id is null then raise exception 'typed specialised task or actual shared corrective ancestry required' using errcode='23514';end if;
 if p_action in ('substitute','task_reassign') and operation.kind='laundry' and exists(select 1 from private.laundry_custody_balances where operation_id=operation.id and resource_id=task.resource_id and units>0) then raise exception 'actual acknowledged goods handover required before changing their responsible resource' using errcode='23514';end if;
 if p_action='progress' and operation.kind='construction' and link.purpose='construction_milestone' and not exists(select 1 from private.construction_milestones milestone left join private.construction_variations variation on variation.id=milestone.source_variation_id where milestone.operation_id=operation.id and milestone.task_id=link.task_id and(milestone.source_variation_id is null or variation.status='implemented')) then raise exception 'approved technical milestone and implemented variation required' using errcode='23514';end if;
 if operation.kind='field_campaign' then
 if not exists(select 1 from private.field_campaigns campaign join private.field_campaign_locations location on location.campaign_id=campaign.id where campaign.operation_id=operation.id and campaign.customer_approved_by is not null and location.task_id=task.id) then raise exception 'client-approved campaign and exact location task required' using errcode='23514';end if;
 if p_action='supervisor_verify' and not exists(select 1 from private.field_campaign_submissions submission join private.field_campaign_locations location on location.id=submission.location_id join private.execution_submissions response on response.id=submission.execution_submission_id where location.task_id=task.id and submission.execution_round=task.execution_round and submission.status='submitted' and submission.reviewed_by is not null and response.status='approved') then raise exception 'current reviewed location submission required before field QA' using errcode='23514';end if;
 end if;
 if p_action='supervisor_verify' and operation.kind='procurement' then
 if link.purpose='procurement_receiving' and(not exists(select 1 from private.procurement_receipts where receiving_task_id=task.id and status in ('accepted','rejected')) or exists(select 1 from private.procurement_receipts where receiving_task_id=task.id and status in ('declared','inspected'))) then raise exception 'actual inspected receipts required before receiving QA' using errcode='23514';end if;
 if link.purpose='procurement_handover' and(not exists(select 1 from private.purchase_orders where operation_id=operation.id and status='closed') or exists(select 1 from private.purchase_orders where operation_id=operation.id and status not in ('closed','cancelled'))) then raise exception 'reconciled purchasing required before customer handover QA' using errcode='23514';end if;
 end if;
 end loop;
end$$;
revoke all on function app_private.require_specialized_execution(uuid,text,jsonb) from public,anon,authenticated;
alter function app_private.fulfilment_command(uuid,text,jsonb,text) rename to before_specialized_execution_guards;
revoke all on function app_private.before_specialized_execution_guards(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform app_private.require_specialized_execution(p_work,p_action,p_data);
 return app_private.before_specialized_execution_guards(p_work,p_action,p_data,p_key);end$$;
grant execute on function app_private.fulfilment_command(uuid,text,jsonb,text) to authenticated;
create or replace function public.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(p_work,p_action,p_data,p_key)$$;
create or replace function public.create_work_order(p_order uuid,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(null,'create_work',p_data||jsonb_build_object('order_id',p_order),p_key)$$;

alter table private.service_orders add unique(id,customer_account_id,zone_id,service_location_id);
alter table private.work_tasks add unique(id,order_id,customer_account_id);
alter table private.field_campaign_locations add column order_id uuid not null,add column customer_account_id uuid not null,add column zone_id uuid not null,add column service_location_id uuid not null,
 add foreign key(operation_id,order_id,customer_account_id) references private.operation_orders(operation_id,order_id,customer_account_id) on delete restrict,
 add foreign key(task_id,order_id,customer_account_id) references private.work_tasks(id,order_id,customer_account_id) on delete restrict,
 add foreign key(order_id,customer_account_id,zone_id,service_location_id) references private.service_orders(id,customer_account_id,zone_id,service_location_id) on delete restrict;
create function app_private.field_location_scope() returns trigger language plpgsql security definer set search_path='' as $$begin
 select task.order_id,task.customer_account_id,parent.zone_id,parent.service_location_id into new.order_id,new.customer_account_id,new.zone_id,new.service_location_id from private.work_tasks task join private.service_orders parent on parent.id=task.order_id where task.id=new.task_id;return new;end$$;
create trigger field_location_scope before insert on private.field_campaign_locations for each row execute function app_private.field_location_scope();
revoke all on function app_private.field_location_scope() from public,anon,authenticated;
create index field_location_order_scope on private.field_campaign_locations(order_id,customer_account_id,zone_id,service_location_id);
create index field_location_task_scope on private.field_campaign_locations(task_id,order_id,customer_account_id);
commit;
