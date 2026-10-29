begin;
create function app_private.laundry_ready(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.laundry_items where operation_id=p_operation)
 and not exists(select 1 from private.laundry_bags where operation_id=p_operation and (customer_acknowledged_by is null or sorted_at is null))
 and not exists(select 1 from private.laundry_custody_transfers where operation_id=p_operation and status in ('proposed','sent','discrepant'))
 and not exists(select 1 from private.laundry_processing_batches where operation_id=p_operation and status<>'returned')
 and not exists(select 1 from private.laundry_items item where item.operation_id=p_operation and
 (item.units<>coalesce((select sum(units) from private.laundry_custody_balances b where b.item_id=item.id and (b.customer_holder or(b.exception_case_id is not null and exists(select 1 from private.laundry_transfer_items l join private.laundry_custody_transfers h on h.id=l.transfer_id where l.discrepancy_case_id=b.exception_case_id and h.status='resolved')))),0)
 or item.units<>coalesce((select sum(app_private.laundry_allocation_units(id)) from private.laundry_batch_items where item_id=item.id),0)+coalesce((select sum(units) from private.laundry_custody_balances b where b.item_id=item.id and b.exception_case_id is not null and exists(select 1 from private.laundry_transfer_items l join private.laundry_custody_transfers h on h.id=l.transfer_id where l.discrepancy_case_id=b.exception_case_id and h.status='resolved')),0)))
$$;
create function app_private.operation_access(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.operation_staff(p_operation,'specialized.read') or app_private.operation_staff(p_operation) or app_private.operation_customer(p_operation)
 or exists(select 1 from private.operation_tasks link where link.operation_id=p_operation and app_private.execution_worker(link.task_id))
$$;
create function app_private.operation_item_access(p_operation uuid,p_item uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.operation_staff(p_operation,'specialized.read') or app_private.operation_staff(p_operation) or app_private.operation_customer(p_operation)
 or exists(select 1 from private.laundry_batch_items allocation join private.laundry_processing_batches batch on batch.id=allocation.batch_id where allocation.item_id=p_item and allocation.operation_id=p_operation and app_private.execution_worker(batch.processing_task_id))
 or exists(select 1 from private.laundry_custody_balances balance where balance.item_id=p_item and balance.operation_id=p_operation and balance.units>0 and app_private.operation_resource(p_operation,balance.resource_id))
 or exists(select 1 from private.laundry_transfer_items line join private.laundry_custody_balances balance on balance.id=line.source_balance_id join private.laundry_custody_transfers transfer on transfer.id=line.transfer_id where balance.item_id=p_item and transfer.operation_id=p_operation and (app_private.operation_resource(p_operation,transfer.destination_resource_id) or app_private.operation_resource(p_operation,balance.resource_id)))
$$;
create function app_private.service_operation_command(p_operation uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;policy private.specialized_service_policies;o private.service_orders;task private.work_tasks;receipt private.transaction_commands;
 result uuid;event_id uuid;lock_order record;purpose text;payload jsonb=jsonb_build_object('operation',p_operation,'action',p_action,'data',p_data);reason text=p_data->>'reason';staff boolean;begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if length(coalesce(p_key,'')) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 or length(coalesce(reason,'')) not between 1 and 2000 then raise exception 'bounded specialised command required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('specialized-command:'||auth.uid()::text||p_key,0));
 if p_action='create' then
 select * into o from private.service_orders where id=(p_data->>'order_id')::uuid for update;
 if o.id is null or not app_private.has_permission('specialized.manage',o.organisation_id) then raise exception 'order-scoped specialised authority required' using errcode='42501';end if;
 else
 for lock_order in select ord.id from private.service_orders ord where ord.id in(select order_id from private.operation_orders where operation_id=p_operation) or(p_action='link_order' and ord.id=(p_data->>'order_id')::uuid) order by ord.id loop perform 1 from private.service_orders where id=lock_order.id for update;end loop;
 select * into operation from private.service_operations where id=p_operation for update;
 if operation.id is null or not app_private.operation_access(operation.id) then raise exception 'specialised operation unavailable' using errcode='42501';end if;
 select * into o from private.service_orders where id=operation.primary_order_id;
 end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='service_operation' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'specialised idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action<>'create' and ((p_data->>'expected_revision')::integer is distinct from operation.revision or operation.status in ('closed','cancelled')) then raise exception 'stale or terminal specialised operation' using errcode='40001';end if;
 staff=case when operation.id is null then true else app_private.operation_staff(operation.id) end;
 if p_action in ('create','link_order','link_task','activate','document','ready','close','cancel') and not staff then raise exception 'central operations authority required' using errcode='42501';end if;
 case p_action
 when 'create' then
 select * into policy from private.specialized_service_policies where service_version_id=o.service_version_id and kind=p_data->>'kind' and status='approved' and valid_from<=now() and(valid_until is null or valid_until>=o.ends_at);
 if policy.id is null or not app_private.order_gate(o.id) or not exists(select 1 from private.work_orders w join private.dispatch_proposals proposal on proposal.id=w.proposal_id and proposal.status='confirmed' and proposal.order_revision=o.revision where w.order_id=o.id and w.status not in ('closed','cancelled')) then raise exception 'approved policy, commercially released order and confirmed work required' using errcode='23514';end if;
 insert into private.service_operations(primary_order_id,customer_account_id,service_version_id,kind,policy_id,scope_snapshot,created_by)
 values(o.id,o.customer_account_id,o.service_version_id,policy.kind,policy.id,jsonb_build_object('commercial_version_id',(select id from private.order_commercial_versions where order_id=o.id order by version desc limit 1)),auth.uid()) returning * into operation;
 insert into private.operation_orders(operation_id,order_id,customer_account_id,created_by) values(operation.id,o.id,o.customer_account_id,auth.uid());result=operation.id;
 when 'link_order' then
 select * into o from private.service_orders where id=(p_data->>'order_id')::uuid;
 if operation.kind<>'field_campaign' or operation.status<>'planning' or o.customer_account_id<>operation.customer_account_id or o.service_version_id<>operation.service_version_id or not app_private.has_permission('specialized.manage',o.organisation_id) or not app_private.order_gate(o.id) then raise exception 'same-client approved campaign order required' using errcode='23514';end if;
 insert into private.operation_orders(operation_id,order_id,customer_account_id,created_by) values(operation.id,o.id,o.customer_account_id,auth.uid()) returning id into result;
 when 'link_task' then
 select * into task from private.work_tasks where id=(p_data->>'task_id')::uuid for update;
 purpose=p_data->>'purpose';
 if operation.status<>'planning' or task.id is null or task.is_container or task.status in ('closed','cancelled') or not exists(select 1 from private.operation_orders where operation_id=operation.id and order_id=task.order_id) then raise exception 'active same-operation execution task required' using errcode='23514';end if;
 if not ((operation.kind='laundry' and purpose in ('pickup','intake','processing','laundry_delivery')) or(operation.kind='construction' and purpose in ('site_inspection','construction_milestone')) or(operation.kind='procurement' and purpose in ('procurement_receiving','procurement_handover')) or(operation.kind='field_campaign' and purpose='field_visit')) then raise exception 'typed specialised task purpose required' using errcode='23514';end if;
 if not app_private.execution_staff(task.order_id,'specialized.manage') then raise exception 'task scope denied' using errcode='42501';end if;
 insert into private.operation_tasks(operation_id,order_id,customer_account_id,work_order_id,task_id,purpose,created_by) values(operation.id,task.order_id,task.customer_account_id,task.work_order_id,task.id,purpose,auth.uid()) returning id into result;
 perform app_private.operation_validate_resource(operation.id,task.resource_id,false);
 when 'activate' then
 select * into policy from private.specialized_service_policies where id=operation.policy_id;
 if operation.status<>'planning' or policy.status<>'approved' or exists(select 1 from jsonb_array_elements_text(policy.configuration->'required_purposes') requirement where not exists(select 1 from private.operation_tasks link where link.operation_id=operation.id and link.purpose=requirement)) then raise exception 'all approved specialised execution purposes required' using errcode='23514';end if;
 update private.service_operations set status='active' where id=operation.id;result=operation.id;
 when 'document' then
 if not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and customer_account_id=operation.customer_account_id and scan_status='clean' and archived_at is null and classification in ('work','field','customer')) then raise exception 'clean same-account operational document required' using errcode='23514';end if;
 insert into private.operation_documents(operation_id,customer_account_id,document_id,task_id,classification,created_by) values(operation.id,operation.customer_account_id,(p_data->>'document_id')::uuid,(p_data->>'task_id')::uuid,p_data->>'classification',auth.uid()) returning id into result;
 when 'ready' then
 if operation.kind<>'laundry' or operation.status<>'active' or not app_private.laundry_ready(operation.id) then raise exception 'specialised delivery requirements incomplete' using errcode='23514';end if;
 update private.service_operations set status='ready' where id=operation.id;result=operation.id;
 when 'close' then
 if operation.status<>'ready' or exists(select 1 from private.operation_orders member join private.service_orders ord on ord.id=member.order_id where member.operation_id=operation.id and ord.status not in ('closed','cancelled')) then raise exception 'shared order closure required' using errcode='23514';end if;
 update private.service_operations set status='closed',revision=revision+1 where id=operation.id;result=operation.id;
 when 'cancel' then
 if not app_private.operation_staff(operation.id,'specialized.approve') or operation.created_by=auth.uid() or not app_private.operation_independent(operation.id,auth.uid()) or exists(select 1 from private.laundry_custody_transfers where operation_id=operation.id and status not in ('proposed','rejected')) then raise exception 'independent pre-execution cancellation required' using errcode='42501';end if;
 update private.service_operations set status='cancelled',revision=revision+1 where id=operation.id;result=operation.id;
 else
 if operation.kind<>'laundry' or (operation.status<>'active' and p_action not in ('bag.create','item.create','bag.acknowledge')) then raise exception 'active specialised workflow required' using errcode='23514';end if;
 result=app_private.laundry_action(operation.id,p_action,p_data);
 end case;
 if p_action not in ('create','close','cancel') then update private.service_operations set revision=revision+1 where id=operation.id;end if;
 event_id=app_private.operation_event(operation.id,p_action,result,reason,jsonb_build_object('subject_id',result,'request',p_data));
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'service_operation',p_key,payload,result);return result;
end$$;
create function public.service_operation_command(p_operation uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.service_operation_command(p_operation,p_action,p_data,p_key)$$;
revoke all on function public.service_operation_command(uuid,text,jsonb,text) from public,anon;
grant execute on function public.service_operation_command(uuid,text,jsonb,text),app_private.service_operation_command(uuid,text,jsonb,text) to authenticated;

create function app_private.read_service_operation(p_operation uuid,p_after uuid default null,p_limit integer default 25) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare operation private.service_operations;staff boolean;result jsonb;begin
 if p_limit is null or p_limit not between 1 and 100 or not app_private.operation_access(p_operation) then raise exception 'bounded authorised specialised read required' using errcode='42501';end if;
 select * into operation from private.service_operations where id=p_operation;staff=app_private.operation_staff(operation.id,'specialized.read') or app_private.operation_staff(operation.id);
 result=jsonb_build_object('id',operation.id,'reference',operation.reference,'kind',operation.kind,'status',operation.status,'revision',operation.revision);
 if operation.kind='laundry' then result=result||jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(item) order by item.id),'[]') from (select id,bag_id,reference,garment_category,units,tag,treatment,condition_snapshot from private.laundry_items where operation_id=operation.id and app_private.operation_item_access(operation.id,id) and(p_after is null or id>p_after) order by id limit p_limit) item),
 'bags',(select coalesce(jsonb_agg(jsonb_build_object('id',bag.id,'code',bag.code,'sorted_at',bag.sorted_at,'customer_acknowledged_at',bag.customer_acknowledged_at)),'[]') from private.laundry_bags bag where bag.operation_id=operation.id and exists(select 1 from private.laundry_items item where item.bag_id=bag.id and app_private.operation_item_access(operation.id,item.id))));end if;
 if staff then result=result||jsonb_build_object('tasks',(select coalesce(jsonb_agg(to_jsonb(link)),'[]') from private.operation_tasks link where link.operation_id=operation.id),
 'batches',(select coalesce(jsonb_agg(to_jsonb(batch)),'[]') from private.laundry_processing_batches batch where batch.operation_id=operation.id),
 'balances',(select coalesce(jsonb_agg(to_jsonb(balance)),'[]') from private.laundry_custody_balances balance where balance.operation_id=operation.id),
 'transfers',(select coalesce(jsonb_agg(to_jsonb(transfer)||jsonb_build_object('lines',(select coalesce(jsonb_agg(to_jsonb(line)),'[]') from private.laundry_transfer_items line where line.transfer_id=transfer.id))),'[]') from private.laundry_custody_transfers transfer where transfer.operation_id=operation.id));
 else result=result||jsonb_build_object('transfers',(select coalesce(jsonb_agg(jsonb_build_object('id',transfer.id,'status',transfer.status,'destination_customer',transfer.destination_customer,'destination_resource_id',transfer.destination_resource_id,'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',line.id,'item_id',balance.item_id,'sent_units',line.sent_units,'received_units',line.received_units)),'[]') from private.laundry_transfer_items line join private.laundry_custody_balances balance on balance.id=line.source_balance_id where line.transfer_id=transfer.id))),'[]') from private.laundry_custody_transfers transfer where transfer.operation_id=operation.id and ((transfer.destination_customer and app_private.order_customer(operation.primary_order_id,'approve')) or app_private.operation_resource(operation.id,transfer.destination_resource_id) or exists(select 1 from private.laundry_transfer_items line join private.laundry_custody_balances balance on balance.id=line.source_balance_id where line.transfer_id=transfer.id and ((balance.customer_holder and app_private.order_customer(operation.primary_order_id,'approve')) or app_private.operation_resource(operation.id,balance.resource_id))))));end if;
 return result;
end$$;
create function public.read_service_operation(p_operation uuid,p_after uuid default null,p_limit integer default 25) returns jsonb language sql stable set search_path='' as $$select app_private.read_service_operation(p_operation,p_after,p_limit)$$;
revoke all on function public.read_service_operation(uuid,uuid,integer) from public,anon;
grant execute on function public.read_service_operation(uuid,uuid,integer),app_private.read_service_operation(uuid,uuid,integer) to authenticated;
commit;
