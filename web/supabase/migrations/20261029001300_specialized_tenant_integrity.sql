begin;
alter table private.service_orders add unique(id,customer_account_id,service_version_id);
alter table private.service_operations add unique(id,primary_order_id),add unique(id,service_version_id),add foreign key(primary_order_id,customer_account_id,service_version_id) references private.service_orders(id,customer_account_id,service_version_id) on delete restrict;
alter table private.construction_projects add foreign key(operation_id,customer_account_id) references private.service_operations(id,customer_account_id) on delete restrict;
alter table private.order_commercial_versions add unique(id,order_id);
alter table private.construction_variations add column order_id uuid not null,
 add foreign key(operation_id,order_id) references private.service_operations(id,primary_order_id) on delete restrict,
 add foreign key(original_commercial_version_id,order_id) references private.order_commercial_versions(id,order_id) on delete restrict,
 add foreign key(implemented_commercial_version_id,order_id) references private.order_commercial_versions(id,order_id) on delete restrict;
alter table private.document_objects add unique(id,organisation_id);
alter table private.supplier_eligibility_versions add unique(id,organisation_id),add foreign key(document_id,organisation_id) references private.document_objects(id,organisation_id) on delete restrict;
alter table private.procurement_rfq_recipients add foreign key(eligibility_id,supplier_organisation_id) references private.supplier_eligibility_versions(id,organisation_id) on delete restrict;
alter table private.supplier_quotation_versions add unique(id,supplier_organisation_id);
alter table private.procurement_selections add column supplier_organisation_id uuid not null,add unique(id,operation_id,supplier_organisation_id),
 add foreign key(quotation_version_id,supplier_organisation_id) references private.supplier_quotation_versions(id,supplier_organisation_id) on delete restrict;
alter table private.purchase_orders add unique(id,operation_id,supplier_organisation_id);
alter table private.purchase_order_versions add column supplier_organisation_id uuid not null,add unique(id,operation_id,supplier_organisation_id),
 add foreign key(purchase_order_id,operation_id,supplier_organisation_id) references private.purchase_orders(id,operation_id,supplier_organisation_id) on delete restrict,
 add foreign key(selection_id,operation_id,supplier_organisation_id) references private.procurement_selections(id,operation_id,supplier_organisation_id) on delete restrict;
alter table private.procurement_receipts add column supplier_organisation_id uuid not null,add unique(id,supplier_organisation_id),add unique(id,operation_id,version_id),
 add foreign key(version_id,operation_id,supplier_organisation_id) references private.purchase_order_versions(id,operation_id,supplier_organisation_id) on delete restrict,
 add foreign key(shipping_document_id,supplier_organisation_id) references private.document_objects(id,organisation_id) on delete restrict;
alter table private.purchase_order_lines add unique(id,operation_id,version_id);
alter table private.procurement_receipt_lines add column version_id uuid not null,add unique(id,operation_id),
 add foreign key(receipt_id,operation_id,version_id) references private.procurement_receipts(id,operation_id,version_id) on delete restrict,
 add foreign key(purchase_order_line_id,operation_id,version_id) references private.purchase_order_lines(id,operation_id,version_id) on delete restrict;
alter table private.service_cases add unique(id,order_id);
alter table private.procurement_returns add column operation_id uuid not null,add column order_id uuid not null,
 add foreign key(receipt_line_id,operation_id) references private.procurement_receipt_lines(id,operation_id) on delete restrict,
 add foreign key(operation_id,order_id) references private.service_operations(id,primary_order_id) on delete restrict,
 add foreign key(case_id,order_id) references private.service_cases(id,order_id) on delete restrict,
 add foreign key(replacement_receipt_line_id,operation_id) references private.procurement_receipt_lines(id,operation_id) on delete restrict;
alter table private.supplier_performance_observations add foreign key(receipt_id,supplier_organisation_id) references private.procurement_receipts(id,supplier_organisation_id) on delete restrict;
alter table private.execution_submissions add unique(id,task_id);
alter table private.field_campaign_submissions add column task_id uuid not null,
 add foreign key(execution_submission_id,task_id) references private.execution_submissions(id,task_id) on delete restrict,
 add foreign key(task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict;
alter table private.field_campaigns add column service_version_id uuid not null,
 add foreign key(operation_id,service_version_id) references private.service_operations(id,service_version_id) on delete restrict,
 add foreign key(checklist_id,service_version_id) references public.service_checklists(id,service_version_id) on delete restrict;
create function app_private.specialized_insert_scope() returns trigger language plpgsql security definer set search_path='' as $$begin
 case tg_table_name
 when 'construction_variations' then select primary_order_id into new.order_id from private.service_operations where id=new.operation_id;
 when 'procurement_selections' then select supplier_organisation_id into new.supplier_organisation_id from private.supplier_quotation_versions where id=new.quotation_version_id;
 when 'purchase_order_versions' then select supplier_organisation_id into new.supplier_organisation_id from private.purchase_orders where id=new.purchase_order_id;
 when 'procurement_receipts' then select supplier_organisation_id into new.supplier_organisation_id from private.purchase_order_versions where id=new.version_id;
 when 'procurement_receipt_lines' then select version_id into new.version_id from private.procurement_receipts where id=new.receipt_id;
 when 'procurement_returns' then select operation_id into new.operation_id from private.procurement_receipt_lines where id=new.receipt_line_id;select primary_order_id into new.order_id from private.service_operations where id=new.operation_id;
 when 'field_campaign_submissions' then select task_id into new.task_id from private.execution_submissions where id=new.execution_submission_id;
 when 'field_campaigns' then select service_version_id into new.service_version_id from private.service_operations where id=new.operation_id;
 else raise exception 'unsupported specialised scope';end case;return new;end$$;
do $$declare name text;begin foreach name in array array['construction_variations','procurement_selections','purchase_order_versions','procurement_receipts','procurement_receipt_lines','procurement_returns','field_campaign_submissions','field_campaigns'] loop execute format('create trigger specialized_insert_scope before insert on private.%I for each row execute function app_private.specialized_insert_scope()',name);end loop;end$$;
revoke all on function app_private.specialized_insert_scope() from public,anon,authenticated;
-- Every introduced FK gets a leading-key supporting index, without broad changes to deployed indexes.
do $$declare relation record;foreign_key record;columns text;begin
 for relation in select tablename from pg_tables where schemaname='private' and tablename in ('specialized_service_policies','service_operations','operation_orders','operation_tasks','operation_documents','laundry_bags','laundry_items','laundry_processing_batches','laundry_batch_items','laundry_custody_balances','laundry_custody_transfers','laundry_transfer_items','laundry_custody_events','laundry_allocation_changes','construction_projects','construction_milestones','construction_material_requirements','construction_material_events','construction_variations','construction_milestone_successors','supplier_eligibility_versions','procurement_rfqs','procurement_rfq_items','procurement_rfq_recipients','supplier_quotation_versions','supplier_quotation_lines','procurement_selections','purchase_orders','purchase_order_versions','purchase_order_lines','procurement_receipts','procurement_receipt_lines','procurement_returns','supplier_performance_observations','field_campaigns','field_campaign_locations','field_campaign_submissions') loop
 for foreign_key in select oid,conname,conkey from pg_constraint where conrelid=format('private.%I',relation.tablename)::regclass and contype='f' order by cardinality(conkey) desc,conname loop
 if not exists(select 1 from pg_index index_row where index_row.indrelid=format('private.%I',relation.tablename)::regclass and index_row.indisvalid and(index_row.indkey::smallint[])[0:cardinality(foreign_key.conkey)-1]=foreign_key.conkey) then
 select string_agg(quote_ident(attribute.attname),',' order by ordinal) into columns from unnest(foreign_key.conkey) with ordinality key(attnum,ordinal) join pg_attribute attribute on attribute.attrelid=format('private.%I',relation.tablename)::regclass and attribute.attnum=key.attnum;
 execute format('create index %I on private.%I(%s)','specialized_fk_'||substr(md5(relation.tablename||foreign_key.conname),1,20),relation.tablename,columns);end if;end loop;end loop;end$$;
create index specialized_queue on private.service_operations(kind,status,id);
create index laundry_receipt_queue on private.laundry_custody_transfers(operation_id,status,id);
create index construction_milestone_queue on private.construction_milestones(operation_id,customer_approved_at,id);
create index procurement_receipt_queue on private.procurement_receipts(operation_id,status,id);
create index field_location_queue on private.field_campaign_locations(operation_id,status,id);
commit;
