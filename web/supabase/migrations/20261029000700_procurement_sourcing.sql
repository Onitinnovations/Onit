begin;
alter table private.procurement_rfqs add column customer_approved_by uuid references public.profiles(id) on delete restrict,add column customer_approved_at timestamptz;
alter table private.procurement_receipts add column declared_at timestamptz not null default clock_timestamp(),add column inspected_at timestamptz;
alter table private.procurement_returns add column kind text not null default 'rejected' check(kind in ('accepted','rejected'));
create unique index procurement_one_approved_selection on private.procurement_selections(rfq_id) where status='approved';
create unique index procurement_one_po_selection on private.purchase_order_versions(selection_id);
create function app_private.supplier_actor(p_organisation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.is_active_member(p_organisation) and exists(select 1 from public.organisations organisation where organisation.id=p_organisation and organisation.organisation_type in ('supplier','mixed') and organisation.status='active')
 and exists(select 1 from private.user_role_assignments assignment join private.roles role on role.id=assignment.role_id and role.archived_at is null join private.role_permissions grant_row on grant_row.role_id=role.id join private.permissions permission on permission.id=grant_row.permission_id and permission.code='supplier.portal'
 where assignment.profile_id=auth.uid() and assignment.scope='organisation' and assignment.organisation_id=p_organisation and assignment.revoked_at is null and(assignment.valid_until is null or assignment.valid_until>now()))
$$;
create function app_private.supplier_eligible(p_eligibility uuid,p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.supplier_eligibility_versions eligibility join private.service_operations operation on operation.id=p_operation join private.service_orders parent on parent.id=operation.primary_order_id
 join public.organisations supplier on supplier.id=eligibility.organisation_id and supplier.status='active' and supplier.organisation_type in ('supplier','mixed')
 join private.document_objects document on document.id=eligibility.document_id and document.organisation_id=supplier.id and document.scan_status='clean' and document.archived_at is null
 where eligibility.id=p_eligibility and eligibility.status='approved' and eligibility.approved_by is not null and eligibility.approved_by<>eligibility.created_by and eligibility.service_version_id=operation.service_version_id and eligibility.zone_id=parent.zone_id and eligibility.valid_from<=now() and eligibility.valid_until>=parent.ends_at)
$$;
create function app_private.procurement_supplier_access(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.procurement_rfqs rfq join private.procurement_rfq_recipients recipient on recipient.rfq_id=rfq.id where rfq.operation_id=p_operation and rfq.status<>'draft' and app_private.supplier_actor(recipient.supplier_organisation_id))
$$;
create function app_private.procurement_source_action(p_operation uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;parent private.service_orders;eligibility private.supplier_eligibility_versions;rfq private.procurement_rfqs;recipient private.procurement_rfq_recipients;
 item private.procurement_rfq_items;quote private.supplier_quotation_versions;selection private.procurement_selections;po private.purchase_orders;version_row private.purchase_order_versions;
 tax private.quotation_tax_rules;commercial private.order_commercial_versions;line jsonb;result uuid;quote_id uuid;units integer;quantity numeric;price numeric;discount numeric;gross numeric;net numeric;tax_value numeric;v_total numeric=0;country uuid;staff boolean;begin
 select * into operation from private.service_operations where id=p_operation;select * into parent from private.service_orders where id=operation.primary_order_id;
 if operation.kind<>'procurement' then raise exception 'procurement operation required' using errcode='23514';end if;
 staff=app_private.operation_staff(operation.id,'procurement.source');
 if p_action not in ('rfq.customer','quote.submit','quote.withdraw','po.acknowledge') and not staff then raise exception 'scoped sourcing authority required' using errcode='42501';end if;
 case p_action
 when 'supplier.prepare' then
 if not app_private.has_permission('procurement.source') then raise exception 'global OnIt supplier configuration authority required' using errcode='42501';end if;
 if not exists(select 1 from public.organisations where id=(p_data->>'supplier_id')::uuid and organisation_type in ('supplier','mixed') and status='active') or not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and organisation_id=(p_data->>'supplier_id')::uuid and scan_status='clean' and archived_at is null and classification in ('identity','contract','work')) then raise exception 'active supplier identity and clean organisation verification evidence required' using errcode='23514';end if;
 insert into private.supplier_eligibility_versions(organisation_id,service_version_id,zone_id,version,valid_from,valid_until,document_id,created_by)
 select(p_data->>'supplier_id')::uuid,operation.service_version_id,parent.zone_id,coalesce(max(version),0)+1,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,(p_data->>'document_id')::uuid,auth.uid() from private.supplier_eligibility_versions where organisation_id=(p_data->>'supplier_id')::uuid and service_version_id=operation.service_version_id and zone_id=parent.zone_id returning id into result;
 when 'supplier.approve','supplier.retire' then
 if not app_private.has_permission('procurement.approve') then raise exception 'global independent supplier verification authority required' using errcode='42501';end if;
 select * into eligibility from private.supplier_eligibility_versions where id=(p_data->>'id')::uuid and service_version_id=operation.service_version_id and zone_id=parent.zone_id for update;
 if eligibility.id is null or eligibility.created_by=auth.uid() or app_private.is_active_member(eligibility.organisation_id) or not app_private.operation_staff(operation.id,'procurement.approve') then raise exception 'independent supplier verification authority required' using errcode='42501';end if;
 if p_action='supplier.approve' then
 if eligibility.status<>'draft' or not exists(select 1 from private.document_objects where id=eligibility.document_id and organisation_id=eligibility.organisation_id and scan_status='clean' and archived_at is null) then raise exception 'draft eligibility and clean evidence required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('supplier-eligibility:'||eligibility.organisation_id::text||eligibility.service_version_id::text||eligibility.zone_id::text,0));
 if exists(select 1 from private.supplier_eligibility_versions other where other.id<>eligibility.id and other.organisation_id=eligibility.organisation_id and other.service_version_id=eligibility.service_version_id and other.zone_id=eligibility.zone_id and other.status='approved' and tstzrange(other.valid_from,other.valid_until,'[)')&&tstzrange(eligibility.valid_from,eligibility.valid_until,'[)')) then raise exception 'overlapping supplier verification version' using errcode='23514';end if;
 update private.supplier_eligibility_versions set status='approved',approved_by=auth.uid() where id=eligibility.id;
 else if eligibility.status<>'approved' then raise exception 'approved supplier version required' using errcode='23514';end if;update private.supplier_eligibility_versions set status='retired' where id=eligibility.id;end if;result=eligibility.id;
 when 'rfq.prepare' then
 if operation.status<>'planning' or not exists(select 1 from private.document_objects where id=(p_data->>'authorisation_document_id')::uuid and customer_account_id=operation.customer_account_id and scan_status='clean' and archived_at is null) or jsonb_typeof(p_data->'terms') is distinct from 'object' or(p_data->>'closes_at')::timestamptz<=clock_timestamp() or(p_data->>'required_at')::timestamptz<=(p_data->>'closes_at')::timestamptz then raise exception 'explicit customer-demand evidence, terms and future deadlines required' using errcode='23514';end if;
 insert into private.procurement_rfqs(operation_id,version,closes_at,required_at,authorisation_document_id,terms,created_by)
 select operation.id,coalesce(max(version),0)+1,(p_data->>'closes_at')::timestamptz,(p_data->>'required_at')::timestamptz,(p_data->>'authorisation_document_id')::uuid,p_data->'terms',auth.uid() from private.procurement_rfqs where operation_id=operation.id returning id into result;
 when 'rfq.item' then
 select * into rfq from private.procurement_rfqs where id=(p_data->>'rfq_id')::uuid and operation_id=operation.id;
 if rfq.id is null or rfq.status<>'draft' or rfq.customer_approved_by is not null or jsonb_typeof(p_data->'specification') is distinct from 'object' or p_data->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' then raise exception 'unapproved RFQ and exact item specification required' using errcode='23514';end if;
 if(select count(*) from private.procurement_rfq_items where rfq_id=rfq.id)>=100 then raise exception 'RFQ supports at most 100 comparable specified items per version' using errcode='23514';end if;
 insert into private.procurement_rfq_items(operation_id,rfq_id,code,description,specification,quantity,unit,created_by) values(operation.id,rfq.id,p_data->>'code',p_data->>'description',p_data->'specification',(p_data->>'quantity')::numeric,p_data->>'unit',auth.uid()) returning id into result;
 when 'rfq.customer' then
 select * into rfq from private.procurement_rfqs where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if rfq.id is null or rfq.status<>'draft' or rfq.customer_approved_by is not null or not app_private.order_customer(parent.id,'approve') or not exists(select 1 from private.procurement_rfq_items where rfq_id=rfq.id) then raise exception 'current customer approval of specified demand required' using errcode='42501';end if;
 update private.procurement_rfqs set customer_approved_by=auth.uid(),customer_approved_at=clock_timestamp() where id=rfq.id;result=rfq.id;
 when 'rfq.invite' then
 select * into rfq from private.procurement_rfqs where id=(p_data->>'rfq_id')::uuid and operation_id=operation.id;
 select * into eligibility from private.supplier_eligibility_versions where id=(p_data->>'eligibility_id')::uuid;
 if rfq.id is null or rfq.status<>'draft' or not app_private.supplier_eligible(eligibility.id,operation.id) then raise exception 'draft RFQ and independently verified covered supplier required' using errcode='23514';end if;
 insert into private.procurement_rfq_recipients(rfq_id,supplier_organisation_id,eligibility_id,created_by) values(rfq.id,eligibility.organisation_id,eligibility.id,auth.uid()) returning id into result;
 when 'rfq.cancel' then
 select * into rfq from private.procurement_rfqs where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if rfq.id is null or rfq.status not in ('draft','issued') or rfq.created_by=auth.uid() or not app_private.operation_staff(operation.id,'procurement.approve') or exists(select 1 from private.purchase_orders po_row join private.purchase_order_versions version on version.purchase_order_id=po_row.id join private.procurement_selections choice on choice.id=version.selection_id where choice.rfq_id=rfq.id and po_row.status<>'cancelled') then raise exception 'independent uncommitted RFQ cancellation required' using errcode='42501';end if;
 update private.procurement_rfqs set status='cancelled' where id=rfq.id;result=rfq.id;
 when 'rfq.issue' then
 select * into rfq from private.procurement_rfqs where id=(p_data->>'id')::uuid and operation_id=operation.id;
 if rfq.id is null or rfq.status<>'draft' or rfq.customer_approved_by is null or rfq.closes_at<=clock_timestamp() or not exists(select 1 from private.procurement_rfq_recipients where rfq_id=rfq.id) or exists(select 1 from private.procurement_rfq_recipients where rfq_id=rfq.id and not app_private.supplier_eligible(eligibility_id,operation.id)) then raise exception 'approved customer demand and current invited supplier eligibility required' using errcode='23514';end if;
 update private.procurement_rfqs set status='issued' where id=rfq.id;result=rfq.id;
 when 'quote.submit' then
 select * into recipient from private.procurement_rfq_recipients where id=(p_data->>'recipient_id')::uuid;
 select * into rfq from private.procurement_rfqs where id=recipient.rfq_id and operation_id=operation.id;
 if rfq.id is null or rfq.status<>'issued' or clock_timestamp()>=rfq.closes_at or not app_private.supplier_actor(recipient.supplier_organisation_id) or not app_private.supplier_eligible(recipient.eligibility_id,operation.id) then raise exception 'current invited supplier, verification and open RFQ required' using errcode='42501';end if;
 select * into commercial from private.order_commercial_versions where order_id=parent.id order by version desc limit 1;
 select minor_units into units from public.currencies where id=(p_data->>'currency_id')::uuid;
 if units is null or commercial.currency_id<>(p_data->>'currency_id')::uuid or(p_data->>'valid_until')::timestamptz<rfq.required_at or jsonb_typeof(p_data->'conditions') is distinct from 'object' or jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'matching currency, valid delivery quote and bounded lines required' using errcode='23514';end if;
 if exists(select 1 from private.procurement_selections choice join private.supplier_quotation_versions chosen on chosen.id=choice.quotation_version_id where choice.rfq_id=rfq.id and chosen.supplier_organisation_id=recipient.supplier_organisation_id and choice.status='approved') then raise exception 'selected quote cannot be revised' using errcode='55000';end if;
 update private.supplier_quotation_versions set status='superseded' where rfq_id=rfq.id and supplier_organisation_id=recipient.supplier_organisation_id and status='submitted';
 insert into private.supplier_quotation_versions(rfq_id,supplier_organisation_id,recipient_id,version,currency_id,minor_units,valid_until,status,conditions,total,created_by)
 select rfq.id,recipient.supplier_organisation_id,recipient.id,coalesce(max(version),0)+1,commercial.currency_id,units,(p_data->>'valid_until')::timestamptz,'draft',p_data->'conditions',0,auth.uid() from private.supplier_quotation_versions where rfq_id=rfq.id and supplier_organisation_id=recipient.supplier_organisation_id returning id into quote_id;
 select country_id into country from public.service_locations where id=parent.service_location_id;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
 select * into item from private.procurement_rfq_items where id=(line->>'item_id')::uuid and rfq_id=rfq.id;
 if item.id is null or line->>'quantity' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or line->>'unit_price' !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' or coalesce(line->>'discount','0') !~ '^[0-9]{1,15}(\.[0-9]{1,4})?$' then raise exception 'exact specified quote line required' using errcode='23514';end if;
 quantity=(line->>'quantity')::numeric;price=(line->>'unit_price')::numeric;discount=coalesce(line->>'discount','0')::numeric;gross=round(quantity*price,units);
 if quantity<>item.quantity or discount>gross or discount<>round(discount,units) then raise exception 'quantity and discount must match requested comparison scope' using errcode='23514';end if;
 net=gross-discount;tax_value=0;tax=null;
 if line->>'tax_rule_id' is not null then select * into tax from private.quotation_tax_rules where id=(line->>'tax_rule_id')::uuid and country_id=country and status='active' and valid_from<=now() and(valid_until is null or valid_until>now());if tax.id is null then raise exception 'effective country tax rule required' using errcode='23514';end if;tax_value=round(net*tax.rate/100,units);end if;
 insert into private.supplier_quotation_lines(quotation_version_id,rfq_id,rfq_item_id,quantity,unit_price,discount,tax_rule_id,tax_snapshot,line_total,created_by)
 values(quote_id,rfq.id,item.id,quantity,price,discount,tax.id,jsonb_build_object('rate',coalesce(tax.rate,0)::text,'tax',tax_value::text,'label',tax.code),net+tax_value,auth.uid());v_total=v_total+net+tax_value;
 end loop;
 if (select count(*) from private.procurement_rfq_items where rfq_id=rfq.id)<>jsonb_array_length(p_data->'lines') then raise exception 'quote must cover every requested item exactly once' using errcode='23514';end if;
 update private.supplier_quotation_versions set total=v_total,status='submitted' where id=quote_id;result=quote_id;
 when 'quote.withdraw' then
 select * into quote from private.supplier_quotation_versions where id=(p_data->>'id')::uuid;
 if quote.id is null or not exists(select 1 from private.procurement_rfqs where id=quote.rfq_id and operation_id=operation.id) or not app_private.supplier_actor(quote.supplier_organisation_id) or quote.status<>'submitted' or exists(select 1 from private.procurement_selections where quotation_version_id=quote.id and status='approved') then raise exception 'own unselected supplier quote required' using errcode='42501';end if;
 update private.supplier_quotation_versions set status='withdrawn' where id=quote.id;result=quote.id;
 when 'selection.propose' then
 select * into quote from private.supplier_quotation_versions where id=(p_data->>'quote_id')::uuid;
 select * into rfq from private.procurement_rfqs where id=quote.rfq_id and operation_id=operation.id;
 if rfq.id is null or quote.status<>'submitted' or quote.valid_until<rfq.required_at or quote.valid_until<=now() or app_private.is_active_member(quote.supplier_organisation_id) or not app_private.supplier_eligible((select eligibility_id from private.procurement_rfq_recipients where id=quote.recipient_id),operation.id) then raise exception 'current comparable supplier quotation required' using errcode='23514';end if;
 insert into private.procurement_selections(operation_id,rfq_id,quotation_version_id,rationale,created_by) values(operation.id,rfq.id,quote.id,p_data->>'reason',auth.uid()) returning id into result;
 when 'selection.retire' then
 select * into selection from private.procurement_selections where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if selection.id is null or selection.status<>'approved' or selection.created_by=auth.uid() or not app_private.operation_staff(operation.id,'procurement.approve') or exists(select 1 from private.purchase_order_versions version join private.procurement_receipts receipt on receipt.version_id=version.id where version.selection_id=selection.id) then raise exception 'independent unreceived selection retirement required' using errcode='42501';end if;
 update private.procurement_selections set status='superseded' where id=selection.id;result=selection.id;
 when 'selection.decide' then
 select * into selection from private.procurement_selections where id=(p_data->>'id')::uuid and operation_id=operation.id for update;select * into quote from private.supplier_quotation_versions where id=selection.quotation_version_id;
 if selection.id is null or selection.status<>'proposed' or selection.created_by=auth.uid() or app_private.is_active_member(quote.supplier_organisation_id) or not app_private.operation_staff(operation.id,'procurement.approve') or not app_private.operation_independent(operation.id,auth.uid()) or jsonb_typeof(p_data->'approve') is distinct from 'boolean' then raise exception 'independent sourcing selection approval required' using errcode='42501';end if;
 select * into commercial from private.order_commercial_versions where order_id=parent.id order by version desc limit 1;
 if(p_data->>'approve')::boolean and (quote.status<>'submitted' or quote.valid_until<now() or quote.currency_id<>commercial.currency_id or quote.total>commercial.total or not app_private.order_gate(parent.id) or not app_private.supplier_eligible((select eligibility_id from private.procurement_rfq_recipients where id=quote.recipient_id),operation.id)) then raise exception 'valid approved budget, commercial release and supplier required' using errcode='23514';end if;
 update private.procurement_selections set status=case when(p_data->>'approve')::boolean then 'approved' else 'rejected' end,approved_by=auth.uid() where id=selection.id;result=selection.id;
 when 'po.issue','po.amend' then
 select * into selection from private.procurement_selections where id=(p_data->>'selection_id')::uuid and operation_id=operation.id;
 select * into quote from private.supplier_quotation_versions where id=selection.quotation_version_id;select * into rfq from private.procurement_rfqs where id=selection.rfq_id;
 if selection.id is null or selection.status<>'approved' or quote.status<>'submitted' or quote.valid_until<=now() or not app_private.order_gate(parent.id) or not app_private.supplier_eligible((select eligibility_id from private.procurement_rfq_recipients where id=quote.recipient_id),operation.id) then raise exception 'current approved selection and released demand required' using errcode='23514';end if;
 if p_action='po.issue' and exists(select 1 from private.purchase_orders existing_po join private.purchase_order_versions existing_version on existing_version.purchase_order_id=existing_po.id join private.procurement_selections existing_selection on existing_selection.id=existing_version.selection_id where existing_selection.rfq_id=rfq.id and existing_po.status<>'cancelled') then raise exception 'the approved RFQ already has a live purchase commitment; amend or independently cancel it' using errcode='23514';end if;
 select * into commercial from private.order_commercial_versions where order_id=parent.id order by version desc limit 1;
 if quote.total+coalesce((select sum(current_version.total) from private.purchase_orders other join lateral(select total from private.purchase_order_versions where purchase_order_id=other.id order by version desc limit 1) current_version on true where other.operation_id=operation.id and other.status<>'cancelled' and(p_action<>'po.amend' or other.id<>(p_data->>'id')::uuid)),0)>commercial.total then raise exception 'combined procurement commitments exceed accepted customer authorisation' using errcode='23514';end if;
 if p_action='po.issue' then insert into private.purchase_orders(operation_id,supplier_organisation_id,created_by) values(operation.id,quote.supplier_organisation_id,auth.uid()) returning * into po;
 else select * into po from private.purchase_orders where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if po.id is null or po.supplier_organisation_id<>quote.supplier_organisation_id or po.status not in ('issued','acknowledged') or exists(select 1 from private.procurement_receipts receipt join private.purchase_order_versions version on version.id=receipt.version_id where version.purchase_order_id=po.id) then raise exception 'unreceived same-supplier purchase order required for version amendment' using errcode='23514';end if;
 update private.purchase_orders set status='issued',revision=revision+1 where id=po.id;end if;
 insert into private.purchase_order_versions(operation_id,purchase_order_id,selection_id,version,currency_id,minor_units,total,terms_snapshot,created_by)
 select operation.id,po.id,selection.id,coalesce(max(version),0)+1,quote.currency_id,quote.minor_units,quote.total,jsonb_build_object('supplier_conditions',quote.conditions,'rfq_terms',rfq.terms,'required_at',rfq.required_at,'commercial_version_id',(select id from private.order_commercial_versions where order_id=parent.id order by version desc limit 1)),auth.uid() from private.purchase_order_versions where purchase_order_id=po.id returning * into version_row;
 insert into private.purchase_order_lines(operation_id,version_id,source_quotation_line_id,quantity,unit,line_total,specification_snapshot,created_by)
 select operation.id,version_row.id,line_row.id,line_row.quantity,item_row.unit,line_row.line_total,item_row.specification,auth.uid() from private.supplier_quotation_lines line_row join private.procurement_rfq_items item_row on item_row.id=line_row.rfq_item_id where line_row.quotation_version_id=quote.id;result=po.id;
 when 'po.acknowledge' then
 select * into po from private.purchase_orders where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if po.id is null or po.status<>'issued' or not app_private.supplier_actor(po.supplier_organisation_id) then raise exception 'addressed supplier acknowledgement required' using errcode='42501';end if;
 select * into version_row from private.purchase_order_versions where purchase_order_id=po.id order by version desc limit 1;
 update private.purchase_order_versions set acknowledged_by=auth.uid(),acknowledged_at=clock_timestamp() where id=version_row.id;update private.purchase_orders set status='acknowledged',revision=revision+1 where id=po.id;result=po.id;
 when 'po.cancel' then
 select * into po from private.purchase_orders where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 if po.id is null or po.status not in ('issued','acknowledged') or po.created_by=auth.uid() or not app_private.operation_staff(operation.id,'procurement.approve') or exists(select 1 from private.procurement_receipts receipt join private.purchase_order_versions version on version.id=receipt.version_id where version.purchase_order_id=po.id) then raise exception 'independent unreceived purchase order cancellation required' using errcode='42501';end if;
 update private.purchase_orders set status='cancelled',revision=revision+1 where id=po.id;result=po.id;
 else raise exception 'unknown sourcing command' using errcode='23514';end case;return result;
end$$;
revoke all on function app_private.supplier_actor(uuid),app_private.supplier_eligible(uuid,uuid),app_private.procurement_supplier_access(uuid),app_private.procurement_source_action(uuid,text,jsonb) from public,anon,authenticated;
commit;
