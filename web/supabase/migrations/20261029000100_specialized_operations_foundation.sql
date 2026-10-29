begin;
-- Typed extensions of the existing operational spine; no independent order or capacity store.
insert into private.permissions(code,description) values
 ('specialized.read','Read scoped specialised service operations'),
 ('specialized.manage','Coordinate scoped specialised operations'),
 ('specialized.approve','Independently approve specialised operational decisions'),
 ('specialized.policy.manage','Prepare specialised service capability policy'),
 ('specialized.policy.approve','Independently approve specialised capability policy'),
 ('procurement.source','Source goods against approved customer demand'),
 ('procurement.approve','Independently approve supplier selection and purchase obligations'),
 ('supplier.portal','Access explicitly addressed supplier commercial records') on conflict(code) do nothing;

create table private.specialized_service_policies (
 id uuid primary key default gen_random_uuid(),service_version_id uuid not null references public.service_versions(id) on delete restrict,
 kind text not null check(kind in ('laundry','construction','procurement','field_campaign')),version integer not null check(version>0),
 valid_from timestamptz not null,valid_until timestamptz,status text not null default 'draft' check(status in ('draft','approved','retired')),
 configuration jsonb not null check(jsonb_typeof(configuration)='object' and octet_length(configuration::text)<=32768),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 check(valid_until is null or valid_until>valid_from),unique(service_version_id,kind,version),unique(id,service_version_id,kind)
);
create table private.service_operations (
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('OPS-'||upper(replace(gen_random_uuid()::text,'-',''))),
 primary_order_id uuid not null,customer_account_id uuid not null,service_version_id uuid not null,kind text not null,
 policy_id uuid not null,status text not null default 'planning' check(status in ('planning','active','ready','closed','cancelled')),
 revision integer not null default 1 check(revision>0),scope_snapshot jsonb not null,
 foreign key(primary_order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 foreign key(policy_id,service_version_id,kind) references private.specialized_service_policies(id,service_version_id,kind) on delete restrict,
 unique(id,customer_account_id),unique(primary_order_id,kind)
);
create table private.operation_orders (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,order_id uuid not null,customer_account_id uuid not null,
 foreign key(operation_id,customer_account_id) references private.service_operations(id,customer_account_id) on delete restrict,
 foreign key(order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 unique(operation_id,order_id),unique(operation_id,order_id,customer_account_id)
);
create table private.operation_tasks (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,order_id uuid not null,customer_account_id uuid not null,
 work_order_id uuid not null,task_id uuid not null,purpose text not null check(purpose in ('pickup','intake','processing','laundry_delivery','site_inspection','construction_milestone','procurement_receiving','procurement_handover','field_visit')),
 foreign key(operation_id,order_id,customer_account_id) references private.operation_orders(operation_id,order_id,customer_account_id) on delete restrict,
 foreign key(task_id,work_order_id,order_id,customer_account_id) references private.work_tasks(id,work_order_id,order_id,customer_account_id) on delete restrict,
 unique(operation_id,task_id),unique(id,operation_id),unique(task_id,operation_id)
);
create table private.operation_documents (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,customer_account_id uuid not null,document_id uuid not null,
 task_id uuid,classification text not null check(classification in ('intake_condition','custody','technical_specification','drawing','measurement','supplier_response','shipping','receipt','field_evidence','client_deliverable')),
 foreign key(operation_id,customer_account_id) references private.service_operations(id,customer_account_id) on delete restrict,
 foreign key(document_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
 foreign key(task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,
 unique(operation_id,document_id,classification)
);

create table private.laundry_bags (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 code text not null,seal_reference text,instructions text not null default '',declared_condition jsonb not null default '{}',
 customer_acknowledged_by uuid references public.profiles(id) on delete restrict,customer_acknowledged_at timestamptz,
 unique(operation_id,code),unique(id,operation_id)
);
create table private.laundry_items (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,bag_id uuid not null,reference text not null,
 garment_category text not null,units integer not null check(units>0),tag text not null,treatment text not null,condition_snapshot jsonb not null,
 foreign key(bag_id,operation_id) references private.laundry_bags(id,operation_id) on delete restrict,
 unique(operation_id,reference),unique(operation_id,tag),unique(id,operation_id)
);
create table private.laundry_processing_batches (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,processing_task_id uuid not null,code text not null,
 status text not null default 'allocated' check(status in ('allocated','received','processing','quality_review','packaged','returned')),
 foreign key(processing_task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,
 unique(operation_id,code),unique(id,operation_id)
);
create table private.laundry_batch_items (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,batch_id uuid not null,item_id uuid not null,units integer not null check(units>0),
 foreign key(batch_id,operation_id) references private.laundry_processing_batches(id,operation_id) on delete restrict,
 foreign key(item_id,operation_id) references private.laundry_items(id,operation_id) on delete restrict,unique(batch_id,item_id)
);
create table private.laundry_custody_balances (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,item_id uuid not null,resource_id uuid references private.assignment_resources(id) on delete restrict,
 customer_holder boolean not null default false,exception_case_id uuid references private.service_cases(id) on delete restrict,
 units integer not null check(units>=0),foreign key(item_id,operation_id) references private.laundry_items(id,operation_id) on delete restrict,
 check((customer_holder::integer)+(resource_id is not null)::integer+(exception_case_id is not null)::integer=1),
 unique nulls not distinct(item_id,resource_id,customer_holder,exception_case_id),unique(id,operation_id)
);
create table private.laundry_custody_transfers (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 destination_resource_id uuid references private.assignment_resources(id) on delete restrict,destination_customer boolean not null,
 evidence_id uuid not null references private.execution_evidence(id) on delete restrict,
 status text not null default 'proposed' check(status in ('proposed','sent','received','rejected','discrepant','resolved')),
 sent_by uuid references public.profiles(id) on delete restrict,sent_at timestamptz,received_by uuid references public.profiles(id) on delete restrict,received_at timestamptz,
 check(destination_customer<>(destination_resource_id is not null)),check(received_by is null or received_by<>sent_by),unique(id,operation_id)
);
create table private.laundry_transfer_items (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,transfer_id uuid not null,source_balance_id uuid not null,
 sent_units integer not null check(sent_units>0),received_units integer check(received_units>=0 and received_units<=sent_units),
 discrepancy_case_id uuid references private.service_cases(id) on delete restrict,
 foreign key(transfer_id,operation_id) references private.laundry_custody_transfers(id,operation_id) on delete restrict,
 foreign key(source_balance_id,operation_id) references private.laundry_custody_balances(id,operation_id) on delete restrict,
 unique(transfer_id,source_balance_id),check(received_units is null or received_units=sent_units or discrepancy_case_id is not null)
);
create table private.laundry_custody_events (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,transfer_id uuid not null,item_id uuid not null,
 action text not null check(action in ('sent','received','rejected','discrepancy','resolved')),units integer not null check(units>=0),
 source_balance_id uuid references private.laundry_custody_balances(id) on delete restrict,destination_balance_id uuid references private.laundry_custody_balances(id) on delete restrict,
 foreign key(transfer_id,operation_id) references private.laundry_custody_transfers(id,operation_id) on delete restrict,
 foreign key(item_id,operation_id) references private.laundry_items(id,operation_id) on delete restrict,
 unique(transfer_id,item_id,action)
);

create table private.construction_projects (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null unique references private.service_operations(id) on delete restrict,
 site_location_id uuid not null,customer_account_id uuid not null,technical_specification jsonb not null,access_instructions text not null,
 foreign key(site_location_id,customer_account_id) references public.service_locations(id,customer_account_id) on delete restrict,unique(id,operation_id)
);
create table private.construction_milestones (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,project_id uuid not null,task_id uuid not null,code text not null,
 trade text not null,scope_snapshot jsonb not null,measurements jsonb not null,customer_approved_by uuid references public.profiles(id) on delete restrict,customer_approved_at timestamptz,
 foreign key(project_id,operation_id) references private.construction_projects(id,operation_id) on delete restrict,
 foreign key(task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,
 unique(operation_id,code),unique(id,operation_id)
);
create table private.construction_material_requirements (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 code text not null,version integer not null check(version>0),description text not null,unit text not null,quantity numeric(20,4) not null check(quantity>0),
 status text not null default 'draft' check(status in ('draft','approved','retired')),approved_by uuid references public.profiles(id) on delete restrict,
 unique(operation_id,code,version),unique(id,operation_id)
);
create table private.construction_material_events (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,requirement_id uuid not null,task_id uuid not null,
 kind text not null check(kind in ('received','consumed','returned','waste')),quantity numeric(20,4) not null check(quantity>0),
 evidence_id uuid not null references private.execution_evidence(id) on delete restrict,
 foreign key(requirement_id,operation_id) references private.construction_material_requirements(id,operation_id) on delete restrict,
 foreign key(task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict
);
create table private.construction_variations (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 version integer not null check(version>0),original_commercial_version_id uuid not null references private.order_commercial_versions(id) on delete restrict,
 proposed_quote_version_id uuid references public.quotation_versions(id) on delete restrict,
 reason text not null,scope_snapshot jsonb not null,time_impact_seconds integer not null,
 currency_id uuid not null references public.currencies(id) on delete restrict,cost_impact numeric(20,4) not null,
 status text not null default 'proposed' check(status in ('proposed','customer_accepted','approved','implemented','rejected','withdrawn')),
 customer_decided_by uuid references public.profiles(id) on delete restrict,commercial_approved_by uuid references public.profiles(id) on delete restrict,
 implemented_task_id uuid,foreign key(implemented_task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,
 unique(operation_id,version)
);

create table private.supplier_eligibility_versions (
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id) on delete restrict,
 service_version_id uuid not null references public.service_versions(id) on delete restrict,zone_id uuid not null references public.service_zones(id) on delete restrict,
 version integer not null check(version>0),valid_from timestamptz not null,valid_until timestamptz not null,
 document_id uuid not null references private.document_objects(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','approved','retired')),approved_by uuid references public.profiles(id) on delete restrict,
 check(valid_until>valid_from),unique(organisation_id,service_version_id,zone_id,version)
);
create table private.procurement_rfqs (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 reference text not null unique default ('RFQ-'||upper(replace(gen_random_uuid()::text,'-',''))),version integer not null check(version>0),
 closes_at timestamptz not null,required_at timestamptz not null,status text not null default 'draft' check(status in ('draft','issued','closed','cancelled')),
 authorisation_document_id uuid not null references private.document_objects(id) on delete restrict,terms jsonb not null,
 unique(operation_id,version),unique(id,operation_id)
);
create table private.procurement_rfq_items (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,rfq_id uuid not null,code text not null,description text not null,
 specification jsonb not null,quantity numeric(20,4) not null check(quantity>0),unit text not null,
 foreign key(rfq_id,operation_id) references private.procurement_rfqs(id,operation_id) on delete restrict,unique(rfq_id,code),unique(id,rfq_id)
);
create table private.procurement_rfq_recipients (
 id uuid primary key default gen_random_uuid(),rfq_id uuid not null references private.procurement_rfqs(id) on delete restrict,
 supplier_organisation_id uuid not null references public.organisations(id) on delete restrict,eligibility_id uuid not null references private.supplier_eligibility_versions(id) on delete restrict,
 unique(rfq_id,supplier_organisation_id),unique(id,rfq_id,supplier_organisation_id)
);
create table private.supplier_quotation_versions (
 id uuid primary key default gen_random_uuid(),rfq_id uuid not null,supplier_organisation_id uuid not null,recipient_id uuid not null,
 version integer not null check(version>0),currency_id uuid not null references public.currencies(id) on delete restrict,minor_units integer not null check(minor_units between 0 and 4),
 valid_until timestamptz not null,status text not null default 'draft' check(status in ('draft','submitted','withdrawn','superseded')),
 conditions jsonb not null,total numeric(20,4) not null check(total>=0 and total=round(total,minor_units)),
 foreign key(recipient_id,rfq_id,supplier_organisation_id) references private.procurement_rfq_recipients(id,rfq_id,supplier_organisation_id) on delete restrict,
 unique(rfq_id,supplier_organisation_id,version),unique(id,rfq_id)
);
create table private.supplier_quotation_lines (
 id uuid primary key default gen_random_uuid(),quotation_version_id uuid not null,rfq_id uuid not null,rfq_item_id uuid not null,
 quantity numeric(20,4) not null check(quantity>0),unit_price numeric(20,4) not null check(unit_price>=0),discount numeric(20,4) not null check(discount>=0),
 tax_rule_id uuid references private.quotation_tax_rules(id) on delete restrict,tax_snapshot jsonb not null,line_total numeric(20,4) not null check(line_total>=0),
 foreign key(quotation_version_id,rfq_id) references private.supplier_quotation_versions(id,rfq_id) on delete restrict,
 foreign key(rfq_item_id,rfq_id) references private.procurement_rfq_items(id,rfq_id) on delete restrict,unique(quotation_version_id,rfq_item_id)
);
create table private.procurement_selections (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,rfq_id uuid not null,quotation_version_id uuid not null,
 rationale text not null,status text not null default 'proposed' check(status in ('proposed','approved','rejected','superseded')),
 approved_by uuid references public.profiles(id) on delete restrict,
 foreign key(rfq_id,operation_id) references private.procurement_rfqs(id,operation_id) on delete restrict,
 foreign key(quotation_version_id,rfq_id) references private.supplier_quotation_versions(id,rfq_id) on delete restrict,unique(id,operation_id)
);
create table private.purchase_orders (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 reference text not null unique default ('PO-'||upper(replace(gen_random_uuid()::text,'-',''))),supplier_organisation_id uuid not null references public.organisations(id) on delete restrict,
 status text not null default 'issued' check(status in ('issued','acknowledged','part_received','received','cancelled','closed')),revision integer not null default 1,
 unique(id,operation_id)
);
create table private.purchase_order_versions (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,purchase_order_id uuid not null,selection_id uuid not null,
 version integer not null check(version>0),currency_id uuid not null references public.currencies(id) on delete restrict,minor_units integer not null check(minor_units between 0 and 4),
 total numeric(20,4) not null check(total>=0 and total=round(total,minor_units)),terms_snapshot jsonb not null,
 acknowledged_by uuid references public.profiles(id) on delete restrict,acknowledged_at timestamptz,
 foreign key(purchase_order_id,operation_id) references private.purchase_orders(id,operation_id) on delete restrict,
 foreign key(selection_id,operation_id) references private.procurement_selections(id,operation_id) on delete restrict,
 unique(purchase_order_id,version),unique(id,operation_id)
);
create table private.purchase_order_lines (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,version_id uuid not null,source_quotation_line_id uuid not null references private.supplier_quotation_lines(id) on delete restrict,
 quantity numeric(20,4) not null check(quantity>0),unit text not null,line_total numeric(20,4) not null check(line_total>=0),specification_snapshot jsonb not null,
 foreign key(version_id,operation_id) references private.purchase_order_versions(id,operation_id) on delete restrict,unique(id,operation_id),unique(version_id,source_quotation_line_id)
);
create table private.procurement_receipts (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,version_id uuid not null,receiving_task_id uuid not null,
 shipping_document_id uuid not null references private.document_objects(id) on delete restrict,
 status text not null default 'declared' check(status in ('declared','inspected','accepted','rejected')),inspected_by uuid references public.profiles(id) on delete restrict,
 foreign key(version_id,operation_id) references private.purchase_order_versions(id,operation_id) on delete restrict,
 foreign key(receiving_task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,unique(id,operation_id)
);
create table private.procurement_receipt_lines (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,receipt_id uuid not null,purchase_order_line_id uuid not null,
 sent_quantity numeric(20,4) not null check(sent_quantity>0),accepted_quantity numeric(20,4) check(accepted_quantity>=0),rejected_quantity numeric(20,4) check(rejected_quantity>=0),
 condition_snapshot jsonb not null,case_id uuid references private.service_cases(id) on delete restrict,
 foreign key(receipt_id,operation_id) references private.procurement_receipts(id,operation_id) on delete restrict,
 foreign key(purchase_order_line_id,operation_id) references private.purchase_order_lines(id,operation_id) on delete restrict,
 check(accepted_quantity is null or rejected_quantity is null or accepted_quantity+rejected_quantity<=sent_quantity),unique(receipt_id,purchase_order_line_id)
);
create table private.procurement_returns (
 id uuid primary key default gen_random_uuid(),receipt_line_id uuid not null references private.procurement_receipt_lines(id) on delete restrict,
 quantity numeric(20,4) not null check(quantity>0),case_id uuid not null references private.service_cases(id) on delete restrict,
 evidence_id uuid not null references private.execution_evidence(id) on delete restrict,
 status text not null default 'proposed' check(status in ('proposed','sent','received','replaced','resolved')),supplier_received_by uuid references public.profiles(id) on delete restrict,
 replacement_receipt_line_id uuid references private.procurement_receipt_lines(id) on delete restrict
);
create table private.supplier_performance_observations (
 id uuid primary key default gen_random_uuid(),supplier_organisation_id uuid not null references public.organisations(id) on delete restrict,
 receipt_id uuid not null references private.procurement_receipts(id) on delete restrict,metric text not null check(metric in ('quantity','condition','timeliness')),
 successful numeric(20,4) not null check(successful>=0),observations numeric(20,4) not null check(observations>0),check(successful<=observations),unique(supplier_organisation_id,receipt_id,metric)
);

create table private.field_campaigns (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null unique references private.service_operations(id) on delete restrict,
 reference text not null unique default ('CAM-'||upper(replace(gen_random_uuid()::text,'-',''))),specification jsonb not null,
 checklist_id uuid not null references public.service_checklists(id) on delete restrict,starts_at timestamptz not null,ends_at timestamptz not null,
 check(ends_at>starts_at),unique(id,operation_id)
);
create table private.field_campaign_locations (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,campaign_id uuid not null,task_id uuid not null,external_reference text not null,
 status text not null default 'pending' check(status in ('pending','submitted','rework','quality_approved','client_accepted','cancelled')),
 client_approved_by uuid references public.profiles(id) on delete restrict,
 foreign key(campaign_id,operation_id) references private.field_campaigns(id,operation_id) on delete restrict,
 foreign key(task_id,operation_id) references private.operation_tasks(task_id,operation_id) on delete restrict,
 unique(campaign_id,external_reference),unique(id,operation_id)
);
create table private.field_campaign_submissions (
 id uuid primary key default gen_random_uuid(),operation_id uuid not null,location_id uuid not null,execution_submission_id uuid not null unique references private.execution_submissions(id) on delete restrict,
 version integer not null check(version>0),status text not null default 'submitted' check(status in ('submitted','rejected','quality_approved','client_accepted')),
 reviewed_by uuid references public.profiles(id) on delete restrict,foreign key(location_id,operation_id) references private.field_campaign_locations(id,operation_id) on delete restrict,
 unique(location_id,version)
);

do $$declare table_name text;immutable boolean;begin
 foreach table_name in array array['specialized_service_policies','service_operations','operation_orders','operation_tasks','operation_documents','laundry_bags','laundry_items','laundry_processing_batches','laundry_batch_items','laundry_custody_balances','laundry_custody_transfers','laundry_transfer_items','laundry_custody_events','construction_projects','construction_milestones','construction_material_requirements','construction_material_events','construction_variations','supplier_eligibility_versions','procurement_rfqs','procurement_rfq_items','procurement_rfq_recipients','supplier_quotation_versions','supplier_quotation_lines','procurement_selections','purchase_orders','purchase_order_versions','purchase_order_lines','procurement_receipts','procurement_receipt_lines','procurement_returns','supplier_performance_observations','field_campaigns','field_campaign_locations','field_campaign_submissions'] loop
 execute format('alter table private.%I add column created_by uuid not null references public.profiles(id) on delete restrict, add column created_at timestamptz not null default now(),add column updated_at timestamptz not null default now()',table_name);
 execute format('alter table private.%I enable row level security',table_name);
 execute format('revoke all on private.%I from public,anon,authenticated',table_name);
 execute format('grant all on private.%I to service_role',table_name);
 immutable=table_name in ('operation_orders','operation_tasks','operation_documents','laundry_items','laundry_batch_items','laundry_custody_events','construction_material_events','supplier_quotation_lines','purchase_order_lines','supplier_performance_observations');
 if immutable then execute format('create trigger onit_specialized_immutable before update or delete on private.%I for each row execute function app_private.reject_mutation()',table_name);
 else execute format('create trigger onit_specialized_updated before update on private.%I for each row execute function app_private.touch_updated_at()',table_name);end if;
 execute format('create trigger onit_specialized_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',table_name);
 end loop;
end$$;
commit;
