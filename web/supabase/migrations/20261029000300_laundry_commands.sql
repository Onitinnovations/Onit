begin;
alter table private.laundry_bags add column sorted_by uuid references public.profiles(id) on delete restrict,add column sorted_at timestamptz;
alter table private.laundry_processing_batches add column capacity_units numeric(20,4) not null check(capacity_units>0);
alter table private.laundry_batch_items add column inspection_task_id uuid,add foreign key(inspection_task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict;
alter table private.laundry_batch_items add unique(id,operation_id);
create unique index laundry_one_item_inspection on private.laundry_batch_items(operation_id,inspection_task_id) where inspection_task_id is not null;
create table private.laundry_allocation_changes (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,allocation_id uuid not null,delta integer not null check(delta<>0),
 case_id uuid references private.service_cases(id) on delete restrict,status text not null default 'pending' check(status in ('pending','approved','rejected')),
 approved_by uuid references public.profiles(id) on delete restrict,created_by uuid not null references public.profiles(id) on delete restrict,
 reason text not null check(length(reason) between 1 and 2000),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(allocation_id,operation_id) references private.laundry_batch_items(id,operation_id) on delete restrict,
 check(approved_by is null or approved_by<>created_by),check((status='pending')=(approved_by is null))
);
alter table private.laundry_allocation_changes enable row level security;
revoke all on private.laundry_allocation_changes from public,anon,authenticated;
grant all on private.laundry_allocation_changes to service_role;
create trigger laundry_allocation_audit after insert or update or delete on private.laundry_allocation_changes for each row execute function app_private.audit_access_change();
create trigger laundry_allocation_updated before update on private.laundry_allocation_changes for each row execute function app_private.touch_updated_at();
create function app_private.laundry_allocation_units(p_allocation uuid) returns integer language sql stable security definer set search_path='' as $$
 select allocation.units+coalesce((select sum(delta)::integer from private.laundry_allocation_changes where allocation_id=allocation.id and status='approved'),0) from private.laundry_batch_items allocation where allocation.id=p_allocation
$$;

create function app_private.operation_event(p_operation uuid,p_action text,p_subject uuid,p_reason text,p_details jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;event_id uuid;outbox uuid;correlation uuid=gen_random_uuid();begin
 select * into operation from private.service_operations where id=p_operation;
 insert into private.execution_history(order_id,action,subject_id,revision,reason,actor_id,permission_code,correlation_id,details)
 values(operation.primary_order_id,'specialized.'||p_action,p_subject,operation.revision,p_reason,auth.uid(),'specialized.command',correlation,p_details||jsonb_build_object('operation_id',operation.id,'operation_snapshot',to_jsonb(operation))) returning id into event_id;
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(operation.primary_order_id,'specialized.'||p_action,p_subject,correlation) returning id into outbox;
 insert into private.operational_event_deliveries(event_id,created_by) values(outbox,auth.uid());return event_id;
end$$;
create function app_private.operation_balance(p_operation uuid,p_item uuid,p_resource uuid,p_customer boolean,p_case uuid default null) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 insert into private.laundry_custody_balances(operation_id,item_id,resource_id,customer_holder,exception_case_id,units,created_by)
 values(p_operation,p_item,p_resource,p_customer,p_case,0,auth.uid()) on conflict(item_id,resource_id,customer_holder,exception_case_id) do update set units=laundry_custody_balances.units returning id into result;return result;
end$$;
create function app_private.laundry_action(p_operation uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;policy private.specialized_service_policies;bag private.laundry_bags;batch private.laundry_processing_batches;transfer private.laundry_custody_transfers;
 balance private.laundry_custody_balances;line record;item private.laundry_items;task private.work_tasks;resource private.assignment_resources;
 change private.laundry_allocation_changes;adjusted_row private.laundry_batch_items;
 result uuid;target uuid;missing_balance uuid;available integer;quantity integer;actual integer;missing integer;case_id uuid;staff boolean;begin
 select * into operation from private.service_operations where id=p_operation;select * into policy from private.specialized_service_policies where id=operation.policy_id;
 if operation.kind<>'laundry' then raise exception 'laundry operation required' using errcode='23514';end if;
 staff=app_private.operation_staff(operation.id);
 case p_action
 when 'bag.create' then
 if not staff or operation.status<>'planning' then raise exception 'laundry intake planning authority required' using errcode='42501';end if;
 insert into private.laundry_bags(operation_id,code,seal_reference,instructions,declared_condition,created_by) values(operation.id,p_data->>'code',p_data->>'seal',coalesce(p_data->>'instructions',''),coalesce(p_data->'condition','{}'),auth.uid()) returning id into result;
 when 'item.create' then
 select * into bag from private.laundry_bags where id=(p_data->>'bag_id')::uuid and operation_id=operation.id;
 if not staff or operation.status<>'planning' or bag.id is null or bag.customer_acknowledged_by is not null then raise exception 'unacknowledged intake and authority required' using errcode='42501';end if;
 if not(policy.configuration->'garment_categories' @> jsonb_build_array(p_data->>'category')) or not(policy.configuration->'treatments' @> jsonb_build_array(p_data->>'treatment')) then raise exception 'configured garment category and treatment required' using errcode='23514';end if;
 insert into private.laundry_items(operation_id,bag_id,reference,garment_category,units,tag,treatment,condition_snapshot,created_by)
 values(operation.id,bag.id,p_data->>'reference',p_data->>'category',(p_data->>'units')::integer,p_data->>'tag',p_data->>'treatment',p_data->'condition',auth.uid()) returning id into result;
 target=app_private.operation_balance(operation.id,result,null,true);update private.laundry_custody_balances set units=(p_data->>'units')::integer where id=target;
 when 'bag.acknowledge' then
 select * into bag from private.laundry_bags where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if bag.id is null or bag.customer_acknowledged_by is not null or not app_private.order_customer(operation.primary_order_id,'approve') then raise exception 'current customer intake acknowledgement required' using errcode='42501';end if;
 if not exists(select 1 from private.laundry_items where bag_id=bag.id) then raise exception 'counted items required before acknowledgement' using errcode='23514';end if;
 update private.laundry_bags set customer_acknowledged_by=auth.uid(),customer_acknowledged_at=clock_timestamp() where id=bag.id;result=bag.id;
 when 'bag.sort' then
 select * into bag from private.laundry_bags where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if not staff or bag.id is null or bag.customer_acknowledged_by is null or bag.sorted_at is not null then raise exception 'acknowledged unsorted bag and sorting authority required' using errcode='42501';end if;
 if exists(select 1 from private.laundry_custody_balances b join private.laundry_items i on i.id=b.item_id where i.bag_id=bag.id and b.customer_holder and b.units>0) then raise exception 'customer pickup must be received before sorting' using errcode='23514';end if;
 update private.laundry_bags set sorted_by=auth.uid(),sorted_at=clock_timestamp() where id=bag.id;result=bag.id;
 when 'batch.create' then
 if not staff or operation.status<>'active' then raise exception 'active processing coordination required' using errcode='42501';end if;
 select t.* into task from private.operation_tasks link join private.work_tasks t on t.id=link.task_id where link.operation_id=operation.id and link.purpose='processing' and t.id=(p_data->>'task_id')::uuid;
 if task.id is null then raise exception 'linked processing task required' using errcode='23514';end if;
 perform app_private.operation_validate_resource(operation.id,task.resource_id,false);
 select * into resource from private.assignment_resources where id=task.resource_id;
 if not exists(select 1 from private.provider_profiles where id=resource.provider_id and provider_type in ('processing_partner','service_business')) then raise exception 'approved processing business required' using errcode='23514';end if;
 if (p_data->>'capacity_units')::numeric<=0 or (p_data->>'capacity_units')::numeric+coalesce((select sum(b.capacity_units) from private.laundry_processing_batches b join private.work_tasks other on other.id=b.processing_task_id where b.operation_id=operation.id and other.resource_id=resource.id and b.status<>'returned'),0)>(select units from private.provider_capacity_reservations where id=resource.reservation_id) then raise exception 'processing batch exceeds assigned capacity' using errcode='23514';end if;
 insert into private.laundry_processing_batches(operation_id,processing_task_id,code,capacity_units,created_by) values(operation.id,task.id,p_data->>'code',(p_data->>'capacity_units')::numeric,auth.uid()) returning id into result;
 when 'batch.allocate' then
 select * into batch from private.laundry_processing_batches where id=(p_data->>'batch_id')::uuid and operation_id=operation.id;
 select * into item from private.laundry_items where id=(p_data->>'item_id')::uuid and operation_id=operation.id;
 quantity=(p_data->>'units')::integer;
 if not staff or batch.status<>'allocated' or batch.id is null or item.id is null then raise exception 'allocated batch and item required' using errcode='42501';end if;
 if not exists(select 1 from private.laundry_bags where id=item.bag_id and sorted_at is not null) or quantity<=0 or quantity+coalesce((select sum(app_private.laundry_allocation_units(id)) from private.laundry_batch_items where item_id=item.id),0)>item.units then raise exception 'sorted intake quantity would be overallocated' using errcode='23514';end if;
 if policy.configuration->>'qa_granularity'='item' and(item.units<>1 or quantity<>1 or(p_data->>'inspection_task_id')::uuid is distinct from batch.processing_task_id or exists(select 1 from private.laundry_batch_items where batch_id=batch.id)) then raise exception 'item quality requires one tagged garment and one dedicated shared processing/inspection task per batch' using errcode='23514';end if;
 insert into private.laundry_batch_items(operation_id,batch_id,item_id,units,inspection_task_id,created_by) values(operation.id,batch.id,item.id,quantity,(p_data->>'inspection_task_id')::uuid,auth.uid()) returning id into result;
 when 'allocation.adjust' then
 select * into adjusted_row from private.laundry_batch_items where id=(p_data->>'allocation_id')::uuid and operation_id=operation.id;
 if not staff or adjusted_row.id is null or not exists(select 1 from private.laundry_processing_batches where id=adjusted_row.batch_id and status in ('allocated','received')) then raise exception 'unprocessed allocation correction authority required' using errcode='42501';end if;
 if p_data->>'case_id' is not null and not exists(select 1 from private.service_cases where id=(p_data->>'case_id')::uuid and order_id=operation.primary_order_id) then raise exception 'same-order correction case required' using errcode='23514';end if;
 insert into private.laundry_allocation_changes(operation_id,allocation_id,delta,case_id,reason,created_by) values(operation.id,adjusted_row.id,(p_data->>'delta')::integer,(p_data->>'case_id')::uuid,p_data->>'reason',auth.uid()) returning id into result;
 when 'allocation.decide' then
 select * into change from private.laundry_allocation_changes where id=(p_data->>'id')::uuid and operation_id=operation.id;
 select * into adjusted_row from private.laundry_batch_items where id=change.allocation_id;
 if not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.operation_independent(operation.id,auth.uid()) or change.id is null or change.created_by=auth.uid() or change.status<>'pending' or jsonb_typeof(p_data->'approve') is distinct from 'boolean' then raise exception 'independent allocation decision required' using errcode='42501';end if;
 if not exists(select 1 from private.laundry_processing_batches where id=adjusted_row.batch_id and status in ('allocated','received')) then raise exception 'processing allocation terms frozen' using errcode='55000';end if;
 if (p_data->>'approve')::boolean and (app_private.laundry_allocation_units(adjusted_row.id)+change.delta<0 or (select coalesce(sum(app_private.laundry_allocation_units(id)),0) from private.laundry_batch_items where item_id=adjusted_row.item_id)+change.delta>(select units from private.laundry_items where id=adjusted_row.item_id)) then raise exception 'allocation correction violates intake quantity' using errcode='23514';end if;
 update private.laundry_allocation_changes set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,approved_by=auth.uid() where id=change.id;result=change.id;
 when 'batch.receive','batch.start','batch.complete','batch.package','batch.return' then
 select * into batch from private.laundry_processing_batches where id=(p_data->>'id')::uuid and operation_id=operation.id;
 select * into task from private.work_tasks where id=batch.processing_task_id;
 if batch.id is null or not(staff or app_private.execution_worker(task.id)) then raise exception 'assigned processing party required' using errcode='42501';end if;
 if p_action in ('batch.receive','batch.start') then perform app_private.operation_validate_resource(operation.id,task.resource_id);end if;
 if p_action='batch.receive' then
 if batch.status<>'allocated' or not exists(select 1 from private.laundry_batch_items where batch_id=batch.id) or exists(select 1 from private.laundry_batch_items row_allocation where row_allocation.batch_id=batch.id and app_private.laundry_allocation_units(row_allocation.id)>coalesce((select sum(units) from private.laundry_custody_balances where item_id=row_allocation.item_id and resource_id=task.resource_id),0)) then raise exception 'receiver-confirmed allocated custody required' using errcode='23514';end if;
 update private.laundry_processing_batches set status='received' where id=batch.id;
 elsif p_action='batch.start' then
 if batch.status<>'received' or task.status not in ('started','in_progress') then raise exception 'shared execution must have started' using errcode='23514';end if;
 update private.laundry_processing_batches set status='processing' where id=batch.id;
 elsif p_action='batch.complete' then
 if batch.status<>'processing' or task.status not in ('work_completed','awaiting_qa','qa_approved','closed') then raise exception 'shared completion required' using errcode='23514';end if;
 update private.laundry_processing_batches set status='quality_review' where id=batch.id;
 elsif p_action='batch.package' then
 if batch.status<>'quality_review' or task.status not in ('qa_approved','closed') or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) then raise exception 'shared independent quality and packaging evidence required' using errcode='23514';end if;
 if policy.configuration->>'qa_granularity'='item' and exists(select 1 from private.laundry_batch_items allocation left join private.work_tasks inspection on inspection.id=allocation.inspection_task_id where allocation.batch_id=batch.id and (inspection.id is null or inspection.status not in ('qa_approved','closed'))) then raise exception 'each item needs approved shared inspection' using errcode='23514';end if;
 update private.laundry_processing_batches set status='packaged' where id=batch.id;
 else
 if batch.status<>'packaged' or exists(select 1 from private.laundry_batch_items allocation join private.laundry_custody_balances b on b.item_id=allocation.item_id where allocation.batch_id=batch.id and b.resource_id=task.resource_id and b.units>0) then raise exception 'packaged batch must be acknowledged out of processing custody' using errcode='23514';end if;
 update private.laundry_processing_batches set status='returned' where id=batch.id;end if;result=batch.id;
 when 'custody.propose' then
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) then raise exception 'bounded custody lines and reviewed clean evidence required' using errcode='23514';end if;
 if not coalesce((p_data->>'to_customer')::boolean,false) and not app_private.operation_resource(operation.id,(p_data->>'resource_id')::uuid,false) then raise exception 'destination must be currently assigned to this operation' using errcode='23514';end if;
 insert into private.laundry_custody_transfers(operation_id,destination_resource_id,destination_customer,evidence_id,created_by) values(operation.id,(p_data->>'resource_id')::uuid,coalesce((p_data->>'to_customer')::boolean,false),(p_data->>'evidence_id')::uuid,auth.uid()) returning id into result;
 for line in select value data from jsonb_array_elements(p_data->'lines') loop
 select * into balance from private.laundry_custody_balances where id=(line.data->>'balance_id')::uuid and operation_id=operation.id;
 if balance.id is null or not(staff or (balance.customer_holder and app_private.order_customer(operation.primary_order_id,'approve')) or app_private.operation_resource(operation.id,balance.resource_id)) then raise exception 'custody source not authorised' using errcode='42501';end if;
 available=balance.units-coalesce((select sum(l.sent_units) from private.laundry_transfer_items l join private.laundry_custody_transfers h on h.id=l.transfer_id where l.source_balance_id=balance.id and h.status in ('proposed','sent')),0);
 quantity=(line.data->>'units')::integer;if quantity is null or quantity<=0 or quantity>available then raise exception 'insufficient unreserved custody quantity' using errcode='23514';end if;
 if balance.resource_id is not distinct from (p_data->>'resource_id')::uuid and balance.customer_holder=coalesce((p_data->>'to_customer')::boolean,false) then raise exception 'custody origin and destination must differ' using errcode='23514';end if;
 insert into private.laundry_transfer_items(operation_id,transfer_id,source_balance_id,sent_units,created_by) values(operation.id,result,balance.id,quantity,auth.uid());end loop;
 when 'custody.send','custody.reject','custody.receive','custody.resolve_loss' then
 select * into transfer from private.laundry_custody_transfers where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if transfer.id is null then raise exception 'custody transfer unavailable' using errcode='42501';end if;
 if p_action='custody.send' then
 if transfer.status<>'proposed' then raise exception 'proposed custody required' using errcode='55000';end if;
 if transfer.destination_customer and exists(select 1 from private.laundry_processing_batches where operation_id=operation.id and status not in ('packaged','returned')) then raise exception 'all processing quality and packaging must finish before customer delivery' using errcode='23514';end if;
 for line in select l.*,b.item_id,b.resource_id,b.customer_holder,b.exception_case_id from private.laundry_transfer_items l join private.laundry_custody_balances b on b.id=l.source_balance_id where l.transfer_id=transfer.id loop
 if not((line.customer_holder and app_private.order_customer(operation.primary_order_id,'approve') and exists(select 1 from private.laundry_items i join private.laundry_bags intake_bag on intake_bag.id=i.bag_id where i.id=line.item_id and intake_bag.customer_acknowledged_by is not null)) or app_private.operation_resource(operation.id,line.resource_id)) then raise exception 'actual source acknowledgement required' using errcode='42501';end if;
 if line.resource_id is not null then perform app_private.operation_validate_resource(operation.id,line.resource_id);end if;
 if transfer.destination_customer and not exists(select 1 from private.operation_tasks link join private.work_tasks t on t.id=link.task_id where link.operation_id=operation.id and link.purpose='laundry_delivery' and t.resource_id=line.resource_id and t.status in ('qa_approved','closed')) then raise exception 'delivery QA and assigned delivery personnel required' using errcode='23514';end if;
 insert into private.laundry_custody_events(operation_id,transfer_id,item_id,action,units,source_balance_id,created_by) values(operation.id,transfer.id,line.item_id,'sent',line.sent_units,line.source_balance_id,auth.uid());end loop;
 update private.laundry_custody_transfers set status='sent',sent_by=auth.uid(),sent_at=clock_timestamp() where id=transfer.id;
 elsif p_action='custody.resolve_loss' then
 if transfer.status<>'discrepant' or not coalesce((policy.configuration->>'allow_count_adjustment')::boolean,false) or not app_private.order_customer(operation.primary_order_id,'approve') then raise exception 'configured customer loss acknowledgement required' using errcode='42501';end if;
 if exists(select 1 from private.laundry_transfer_items l left join private.service_cases c on c.id=l.discrepancy_case_id where l.transfer_id=transfer.id and l.received_units<l.sent_units and(c.id is null or c.order_id<>operation.primary_order_id or c.status not in ('resolved','closed'))) then raise exception 'independently resolved discrepancy cases required' using errcode='23514';end if;
 for line in select l.*,b.item_id from private.laundry_transfer_items l join private.laundry_custody_balances b on b.id=l.source_balance_id where l.transfer_id=transfer.id and l.received_units<l.sent_units loop
 insert into private.laundry_custody_events(operation_id,transfer_id,item_id,action,units,source_balance_id,created_by) values(operation.id,transfer.id,line.item_id,'resolved',line.sent_units-line.received_units,line.source_balance_id,auth.uid());end loop;
 update private.laundry_custody_transfers set status='resolved' where id=transfer.id;
 else
 if transfer.status<>'sent' or transfer.sent_by=auth.uid() or not((transfer.destination_customer and app_private.order_customer(operation.primary_order_id,'approve')) or app_private.operation_resource(operation.id,transfer.destination_resource_id)) then raise exception 'different actual receiver acknowledgement required' using errcode='42501';end if;
 if transfer.destination_resource_id is not null then perform app_private.operation_validate_resource(operation.id,transfer.destination_resource_id);end if;
 if p_action='custody.reject' then
 update private.laundry_custody_transfers set status='rejected',received_by=auth.uid(),received_at=clock_timestamp() where id=transfer.id;
 for line in select l.*,b.item_id from private.laundry_transfer_items l join private.laundry_custody_balances b on b.id=l.source_balance_id where l.transfer_id=transfer.id loop insert into private.laundry_custody_events(operation_id,transfer_id,item_id,action,units,source_balance_id,created_by) values(operation.id,transfer.id,line.item_id,'rejected',line.sent_units,line.source_balance_id,auth.uid());end loop;
 else
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')<>(select count(*) from private.laundry_transfer_items where transfer_id=transfer.id) then raise exception 'explicit count for every transfer line required' using errcode='23514';end if;
 missing=0;
 for line in select l.*,b.item_id from private.laundry_transfer_items l join private.laundry_custody_balances b on b.id=l.source_balance_id where l.transfer_id=transfer.id loop
 if (select count(*) from jsonb_array_elements(p_data->'lines') value where value->>'id'=line.id::text)<>1 then raise exception 'one receipt per line required' using errcode='23514';end if;
 select (value->>'units')::integer,(value->>'case_id')::uuid into actual,case_id from jsonb_array_elements(p_data->'lines') value where value->>'id'=line.id::text;
 if actual is null or actual<0 or actual>line.sent_units then raise exception 'received count outside dispatched quantity' using errcode='23514';end if;
 if (actual<line.sent_units or case_id is not null) and not exists(select 1 from private.service_cases where id=case_id and order_id=operation.primary_order_id and customer_account_id=operation.customer_account_id) then raise exception 'typed same-order discrepancy case required' using errcode='23514';end if;
 update private.laundry_custody_balances set units=units-line.sent_units where id=line.source_balance_id;
 target=app_private.operation_balance(operation.id,line.item_id,transfer.destination_resource_id,transfer.destination_customer);update private.laundry_custody_balances set units=units+actual where id=target;
 update private.laundry_transfer_items set received_units=actual,discrepancy_case_id=case_id where id=line.id;
 insert into private.laundry_custody_events(operation_id,transfer_id,item_id,action,units,source_balance_id,destination_balance_id,created_by) values(operation.id,transfer.id,line.item_id,'received',actual,line.source_balance_id,target,auth.uid());
 if actual<line.sent_units then
 missing_balance=app_private.operation_balance(operation.id,line.item_id,null,false,case_id);update private.laundry_custody_balances set units=units+line.sent_units-actual where id=missing_balance;
 insert into private.laundry_custody_events(operation_id,transfer_id,item_id,action,units,source_balance_id,destination_balance_id,created_by) values(operation.id,transfer.id,line.item_id,'discrepancy',line.sent_units-actual,line.source_balance_id,missing_balance,auth.uid());missing=missing+1;end if;
 end loop;
 update private.laundry_custody_transfers set status=case when missing>0 then 'discrepant' else 'received' end,received_by=auth.uid(),received_at=clock_timestamp() where id=transfer.id;end if;end if;result=transfer.id;
 else raise exception 'unknown laundry action' using errcode='23514';end case;
 if exists(select 1 from private.laundry_items i where i.operation_id=operation.id and i.units<>(select coalesce(sum(units),0) from private.laundry_custody_balances where item_id=i.id)) then raise exception 'laundry custody conservation failure' using errcode='23514';end if;
 return result;
end$$;
commit;
