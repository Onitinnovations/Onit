begin;
create function app_private.supplier_subject(p_organisation uuid,p_actor uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.organisation_members where organisation_id=p_organisation and profile_id=p_actor)
$$;
revoke all on function app_private.supplier_subject(uuid,uuid) from public,anon,authenticated;
do $$declare source text;fragment text;begin
 source=pg_get_functiondef('app_private.procurement_source_action(uuid,text,jsonb)'::regprocedure);
 source=replace(source,'app_private.is_active_member(','app_private.supplier_subject(');
 source=replace(source,'selection.created_by=auth.uid() or app_private.supplier_subject(quote.supplier_organisation_id)','selection.created_by=auth.uid() or quote.created_by=auth.uid() or app_private.supplier_subject(quote.supplier_organisation_id)');execute source;
 source=pg_get_functiondef('app_private.procurement_source_action(uuid,text,jsonb)'::regprocedure);
 source=replace(source,$fragment$selection.status<>'approved' or selection.created_by=auth.uid() or not app_private.operation_staff$fragment$,$fragment$selection.status<>'approved' or selection.created_by=auth.uid() or app_private.supplier_subject(selection.supplier_organisation_id) or not app_private.operation_staff$fragment$);
 source=replace(source,$fragment$or po.created_by=auth.uid() or not app_private.operation_staff(operation.id,'procurement.approve')$fragment$,$fragment$or po.created_by=auth.uid() or app_private.supplier_subject(po.supplier_organisation_id) or not app_private.operation_staff(operation.id,'procurement.approve')$fragment$);
 source=replace(source,$fragment$if selection.id is null or selection.status<>'approved' or quote.status<>'submitted' or quote.valid_until<=now()$fragment$,$fragment$if selection.id is null or selection.status<>'approved' or app_private.supplier_subject(quote.supplier_organisation_id) or quote.status<>'submitted' or quote.valid_until<=now()$fragment$);execute source;
 source=pg_get_functiondef('app_private.procurement_receiving_action(uuid,text,jsonb)'::regprocedure);
 source=replace(source,'app_private.is_active_member(','app_private.supplier_subject(');
 source=replace(source,$fragment$if return_row.status<>'received' or not app_private.operation_staff(operation.id,'procurement.approve')$fragment$,$fragment$if return_row.status<>'received' or app_private.supplier_subject(po.supplier_organisation_id) or not app_private.operation_staff(operation.id,'procurement.approve')$fragment$);
 fragment=$fragment$if quantity<=0 or quantity+app_private.procurement_net_received(po_line.id)+coalesce((select sum(line.sent_quantity) from private.procurement_receipt_lines line join private.procurement_receipts header on header.id=line.receipt_id and header.status in ('declared','inspected') where line.purchase_order_line_id=po_line.id),0)>po_line.quantity then raise exception 'delivery declaration exceeds unreceived approved quantity' using errcode='23514';end if;$fragment$;
 if position(fragment in source)=0 then raise exception 'review changed supplier declaration implementation';end if;
 source=replace(source,fragment,$fragment$if quantity<=0 then raise exception 'positive actual declared goods quantity required' using errcode='23514';end if;
 -- A notice may declare excess physical goods. It neither increases approved
 -- purchase demand nor constitutes receiving, ownership or payment evidence.$fragment$);
 fragment=$fragment$update private.purchase_orders set status='closed',revision=revision+1 where id=po.id;$fragment$;
 if position(fragment in source)=0 then raise exception 'review changed purchase reconciliation boundary';end if;
 source=replace(source,fragment,$fragment$if exists(select 1 from private.procurement_receipt_lines inspected join private.procurement_receipts header on header.id=inspected.receipt_id where header.version_id=version_row.id and(inspected.rejected_quantity>coalesce((select sum(returned.quantity) from private.procurement_returns returned where returned.receipt_line_id=inspected.id and returned.kind='rejected' and returned.status in ('received','replaced','resolved')),0) or(inspected.case_id is not null and not exists(select 1 from private.service_cases issue where issue.id=inspected.case_id and issue.status in ('resolved','closed'))))) then raise exception 'rejected/excess goods need actual supplier return acknowledgement and independently resolved cases' using errcode='23514';end if;
 update private.purchase_orders set status='closed',revision=revision+1 where id=po.id;$fragment$);execute source;
end$$;
commit;
