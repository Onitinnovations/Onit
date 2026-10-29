begin;
create function app_private.procurement_net_received(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(line.accepted_quantity) from private.procurement_receipt_lines line join private.procurement_receipts receipt on receipt.id=line.receipt_id and receipt.status in ('accepted','rejected') where line.purchase_order_line_id=p_line),0)
 -coalesce((select sum(return_row.quantity) from private.procurement_returns return_row join private.procurement_receipt_lines line on line.id=return_row.receipt_line_id where line.purchase_order_line_id=p_line and return_row.kind='accepted' and return_row.status in ('received','replaced','resolved')),0)
$$;
create function app_private.procurement_ready(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.purchase_orders where operation_id=p_operation and status='closed')
 and not exists(select 1 from private.purchase_orders where operation_id=p_operation and status not in ('closed','cancelled'))
 and not exists(select 1 from private.procurement_rfqs rfq where rfq.operation_id=p_operation and rfq.status not in ('closed','cancelled'))
 and not exists(select 1 from private.procurement_returns return_row join private.procurement_receipt_lines line on line.id=return_row.receipt_line_id where line.operation_id=p_operation and return_row.status not in ('replaced','resolved'))
 and exists(select 1 from private.operation_tasks link join private.work_tasks task on task.id=link.task_id where link.operation_id=p_operation and link.purpose='procurement_handover' and task.status in ('qa_approved','closed'))
$$;
create function app_private.procurement_receiving_action(p_operation uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;po private.purchase_orders;version_row private.purchase_order_versions;receipt private.procurement_receipts;line_row private.procurement_receipt_lines;po_line private.purchase_order_lines;
 return_row private.procurement_returns;replacement private.procurement_receipt_lines;task private.work_tasks;entry jsonb;result uuid;quantity numeric;accepted numeric;rejected numeric;received numeric;total_sent numeric;total_received numeric;total_accepted numeric;begin
 select * into operation from private.service_operations where id=p_operation;
 if operation.kind<>'procurement' then raise exception 'procurement operation required' using errcode='23514';end if;
 case p_action
 when 'receipt.declare' then
 select * into version_row from private.purchase_order_versions where id=(p_data->>'version_id')::uuid and operation_id=operation.id;
 select * into po from private.purchase_orders where id=version_row.purchase_order_id for update;
 select task_row.* into task from private.operation_tasks link join private.work_tasks task_row on task_row.id=link.task_id where link.operation_id=operation.id and link.purpose='procurement_receiving' and task_row.id=(p_data->>'task_id')::uuid;
 if po.id is null or not app_private.supplier_actor(po.supplier_organisation_id) or po.status not in ('acknowledged','part_received') or version_row.acknowledged_by is null or version_row.version<>(select max(version) from private.purchase_order_versions where purchase_order_id=po.id) or task.id is null or not exists(select 1 from private.document_objects where id=(p_data->>'shipping_document_id')::uuid and organisation_id=po.supplier_organisation_id and scan_status='clean' and archived_at is null) or jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'addressed acknowledged PO, clean supplier document and receiving task required' using errcode='42501';end if;
 insert into private.procurement_receipts(operation_id,version_id,receiving_task_id,shipping_document_id,created_by) values(operation.id,version_row.id,task.id,(p_data->>'shipping_document_id')::uuid,auth.uid()) returning id into result;
 for entry in select value from jsonb_array_elements(p_data->'lines') loop
 select * into po_line from private.purchase_order_lines where id=(entry->>'line_id')::uuid and version_id=version_row.id;
 if po_line.id is null or entry->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or jsonb_typeof(entry->'condition') is distinct from 'object' then raise exception 'exact PO line and declared condition required' using errcode='23514';end if;
 quantity=(entry->>'quantity')::numeric;
 if quantity<=0 or quantity+app_private.procurement_net_received(po_line.id)+coalesce((select sum(line.sent_quantity) from private.procurement_receipt_lines line join private.procurement_receipts header on header.id=line.receipt_id and header.status in ('declared','inspected') where line.purchase_order_line_id=po_line.id),0)>po_line.quantity then raise exception 'delivery declaration exceeds unreceived approved quantity' using errcode='23514';end if;
 insert into private.procurement_receipt_lines(operation_id,receipt_id,purchase_order_line_id,sent_quantity,condition_snapshot,created_by) values(operation.id,result,po_line.id,quantity,entry->'condition',auth.uid());
 end loop;
 when 'receipt.inspect' then
 select * into receipt from private.procurement_receipts where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 select * into version_row from private.purchase_order_versions where id=receipt.version_id;select * into po from private.purchase_orders where id=version_row.purchase_order_id for update;
 if receipt.id is null or receipt.status<>'declared' or receipt.created_by=auth.uid() or app_private.is_active_member(po.supplier_organisation_id) or not(app_private.operation_staff(operation.id,'procurement.source') or app_private.execution_worker(receipt.receiving_task_id)) or jsonb_typeof(p_data->'lines') is distinct from 'array' or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) then raise exception 'independent authorised receiving inspection and accepted evidence required' using errcode='42501';end if;
 select * into task from private.work_tasks where id=receipt.receiving_task_id;perform app_private.operation_validate_resource(operation.id,task.resource_id);
 if jsonb_array_length(p_data->'lines')<>(select count(*) from private.procurement_receipt_lines where receipt_id=receipt.id) or (select count(distinct candidate.value->>'id') from jsonb_array_elements(p_data->'lines') candidate(value))<>jsonb_array_length(p_data->'lines') then raise exception 'inspect every receipt line once' using errcode='23514';end if;
 for entry in select value from jsonb_array_elements(p_data->'lines') loop
 select * into line_row from private.procurement_receipt_lines where id=(entry->>'id')::uuid and receipt_id=receipt.id for update;
 if line_row.id is null or entry->>'accepted' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or entry->>'rejected' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' then raise exception 'exact accepted and rejected quantities required' using errcode='23514';end if;
 accepted=(entry->>'accepted')::numeric;rejected=(entry->>'rejected')::numeric;
 if accepted+rejected>line_row.sent_quantity or ((accepted+rejected<line_row.sent_quantity or rejected>0) and not exists(select 1 from private.service_cases where id=(entry->>'case_id')::uuid and order_id=operation.primary_order_id)) then raise exception 'quantity discrepancy requires same-order retained case' using errcode='23514';end if;
 select * into po_line from private.purchase_order_lines where id=line_row.purchase_order_line_id;
 if accepted+app_private.procurement_net_received(po_line.id)>po_line.quantity then raise exception 'receipt exceeds approved demand' using errcode='23514';end if;
 update private.procurement_receipt_lines set accepted_quantity=accepted,rejected_quantity=rejected,case_id=(entry->>'case_id')::uuid,condition_snapshot=condition_snapshot||jsonb_build_object('inspection',entry->'condition','evidence_id',p_data->>'evidence_id') where id=line_row.id;
 end loop;
 select sum(sent_quantity),sum(accepted_quantity+rejected_quantity),sum(accepted_quantity) into total_sent,total_received,total_accepted from private.procurement_receipt_lines where receipt_id=receipt.id;
 update private.procurement_receipts set status=case when total_accepted>0 then 'accepted' else 'rejected' end,inspected_by=auth.uid(),inspected_at=clock_timestamp() where id=receipt.id;
 update private.purchase_orders set status=case when not exists(select 1 from private.purchase_order_lines line where line.version_id=version_row.id and app_private.procurement_net_received(line.id)<line.quantity) then 'received' else 'part_received' end,revision=revision+1 where id=po.id;
 insert into private.supplier_performance_observations(supplier_organisation_id,receipt_id,metric,successful,observations,created_by) values
 (po.supplier_organisation_id,receipt.id,'quantity',total_received,total_sent,auth.uid()),
 (po.supplier_organisation_id,receipt.id,'timeliness',case when clock_timestamp()<=(version_row.terms_snapshot->>'required_at')::timestamptz then 1 else 0 end,1,auth.uid());
 if total_received>0 then insert into private.supplier_performance_observations(supplier_organisation_id,receipt_id,metric,successful,observations,created_by) values(po.supplier_organisation_id,receipt.id,'condition',total_accepted,total_received,auth.uid());end if;result=receipt.id;
 when 'return.propose' then
 if not app_private.operation_staff(operation.id,'procurement.source') then raise exception 'sourcing return authority required' using errcode='42501';end if;
 select * into line_row from private.procurement_receipt_lines where id=(p_data->>'line_id')::uuid and operation_id=operation.id for update;
 if line_row.id is null or line_row.accepted_quantity is null or p_data->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or p_data->>'kind' not in ('accepted','rejected') or not exists(select 1 from private.service_cases where id=(p_data->>'case_id')::uuid and order_id=operation.primary_order_id) or not app_private.operation_evidence(operation.id,(p_data->>'evidence_id')::uuid) then raise exception 'inspected goods, same-order case and return evidence required' using errcode='23514';end if;
 quantity=(p_data->>'quantity')::numeric;
 if quantity<=0 or quantity+coalesce((select sum(existing.quantity) from private.procurement_returns existing where existing.receipt_line_id=line_row.id and existing.kind=p_data->>'kind'),0)>(case p_data->>'kind' when 'accepted' then line_row.accepted_quantity else line_row.rejected_quantity end) then raise exception 'return quantity exceeds actual inspected goods' using errcode='23514';end if;
 insert into private.procurement_returns(receipt_line_id,quantity,case_id,evidence_id,kind,created_by) values(line_row.id,quantity,(p_data->>'case_id')::uuid,(p_data->>'evidence_id')::uuid,p_data->>'kind',auth.uid()) returning id into result;
 when 'return.send','return.receive','return.replace','return.resolve' then
 select returned.* into return_row from private.procurement_returns returned join private.procurement_receipt_lines line on line.id=returned.receipt_line_id where returned.id=(p_data->>'id')::uuid and line.operation_id=operation.id for update of returned;
 select * into line_row from private.procurement_receipt_lines where id=return_row.receipt_line_id;select * into receipt from private.procurement_receipts where id=line_row.receipt_id;select * into version_row from private.purchase_order_versions where id=receipt.version_id;select * into po from private.purchase_orders where id=version_row.purchase_order_id;
 if return_row.id is null then raise exception 'return unavailable' using errcode='42501';end if;
 if p_action='return.receive' then
 if return_row.status<>'sent' or return_row.created_by=auth.uid() or not app_private.supplier_actor(po.supplier_organisation_id) then raise exception 'actual supplier acknowledgement required' using errcode='42501';end if;
 update private.procurement_returns set status='received',supplier_received_by=auth.uid() where id=return_row.id;update private.purchase_orders set status='part_received',revision=revision+1 where id=po.id;
 else
 if not app_private.operation_staff(operation.id,'procurement.source') then raise exception 'sourcing return authority required' using errcode='42501';end if;
 if p_action='return.send' then
 if return_row.status<>'proposed' then raise exception 'proposed return required' using errcode='23514';end if;
 update private.procurement_returns set status='sent' where id=return_row.id;
 elsif p_action='return.replace' then
 select * into replacement from private.procurement_receipt_lines where id=(p_data->>'replacement_line_id')::uuid and operation_id=operation.id;
 if return_row.status<>'received' or replacement.id is null or replacement.receipt_id=receipt.id or replacement.accepted_quantity<return_row.quantity or replacement.purchase_order_line_id<>line_row.purchase_order_line_id or exists(select 1 from private.procurement_returns where replacement_receipt_line_id=replacement.id) then raise exception 'distinct actual accepted replacement for the same approved item required' using errcode='23514';end if;
 update private.procurement_returns set status='replaced',replacement_receipt_line_id=replacement.id where id=return_row.id;
 else
 if return_row.status<>'received' or not app_private.operation_staff(operation.id,'procurement.approve') or return_row.created_by=auth.uid() or not exists(select 1 from private.service_cases where id=return_row.case_id and status in ('resolved','closed')) then raise exception 'independently resolved case required for nonreplacement return' using errcode='42501';end if;
 update private.procurement_returns set status='resolved' where id=return_row.id;
 end if;end if;result=return_row.id;
 when 'po.close' then
 select * into po from private.purchase_orders where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if po.id is null or not app_private.operation_staff(operation.id,'procurement.approve') or app_private.is_active_member(po.supplier_organisation_id) or po.created_by=auth.uid() or po.status not in ('received','part_received') then raise exception 'independent procurement reconciliation authority required' using errcode='42501';end if;
 select * into version_row from private.purchase_order_versions where purchase_order_id=po.id order by version desc limit 1;
 if exists(select 1 from private.purchase_order_lines line where version_id=version_row.id and app_private.procurement_net_received(line.id)<>line.quantity) or exists(select 1 from private.procurement_receipts where version_id=version_row.id and status in ('declared','inspected')) or exists(select 1 from private.procurement_returns returned join private.procurement_receipt_lines line on line.id=returned.receipt_line_id join private.procurement_receipts header on header.id=line.receipt_id where header.version_id=version_row.id and returned.status not in ('replaced','resolved')) then raise exception 'actual quantities, returns and discrepancies must reconcile before PO closure' using errcode='23514';end if;
 update private.purchase_orders set status='closed',revision=revision+1 where id=po.id;update private.procurement_rfqs set status='closed' where id=(select rfq_id from private.procurement_selections where id=version_row.selection_id);result=po.id;
 else raise exception 'unknown receiving command' using errcode='23514';end case;return result;
end$$;
revoke all on function app_private.procurement_net_received(uuid),app_private.procurement_ready(uuid),app_private.procurement_receiving_action(uuid,text,jsonb) from public,anon,authenticated;
do $$declare source text;begin
 source=pg_get_functiondef('app_private.operation_access(uuid)'::regprocedure);
 source=replace(source,'select app_private.operation_staff(p_operation,','select app_private.procurement_supplier_access(p_operation) or app_private.operation_staff(p_operation,');execute source;
 source=pg_get_functiondef('app_private.service_operation_command(uuid,text,jsonb,text)'::regprocedure);
 source=replace(source,'when ''construction'' then app_private.construction_ready(operation.id) else false','when ''construction'' then app_private.construction_ready(operation.id) when ''procurement'' then app_private.procurement_ready(operation.id) else false');
 source=replace(source,$fragment$else raise exception 'unsupported specialised command' using errcode='23514';end if;$fragment$,$fragment$elsif operation.kind='procurement' then
 if p_action like 'receipt.%' or p_action like 'return.%' or p_action='po.close' then result=app_private.procurement_receiving_action(operation.id,p_action,p_data);else result=app_private.procurement_source_action(operation.id,p_action,p_data);end if;
 else raise exception 'unsupported specialised command' using errcode='23514';end if;$fragment$);execute source;
end$$;
commit;
