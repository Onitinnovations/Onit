# Increment 6 specialised operations dictionary — local candidate

Generated from the successfully replayed PostgreSQL 17 catalog. The 38 new tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increments-5-6-report.md). Six reused tables are also documented; existing public feedback access retains its original RLS. No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.

## private.supplier_document_links

Immutable supplier/operation/PO or invitation provenance for quarantined registry uploads.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| supplier_organisation_id | uuid | yes |  |
| document_id | uuid | yes |  |
| kind | text | yes |  |
| rfq_id | uuid | no |  |
| purchase_order_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- supplier_document_links_check: CHECK ((((kind = 'verification'::text) AND (rfq_id IS NULL) AND (purchase_order_id IS NULL)) OR ((kind = 'response'::text) AND (rfq_id IS NOT NULL) AND (purchase_order_id IS NULL)) OR ((kind = 'shipping'::text) AND (purchase_order_id IS NOT NULL) AND (rfq_id IS NULL))))
- supplier_document_links_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_document_links_document_id_key: UNIQUE (document_id)
- supplier_document_links_document_id_supplier_organisation__fkey: FOREIGN KEY (document_id, supplier_organisation_id) REFERENCES private.document_objects(id, organisation_id) ON DELETE RESTRICT
- supplier_document_links_kind_check: CHECK ((kind = ANY (ARRAY['verification'::text, 'response'::text, 'shipping'::text])))
- supplier_document_links_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- supplier_document_links_pkey: PRIMARY KEY (id)
- supplier_document_links_purchase_order_id_operation_id_sup_fkey: FOREIGN KEY (purchase_order_id, operation_id, supplier_organisation_id) REFERENCES private.purchase_orders(id, operation_id, supplier_organisation_id) ON DELETE RESTRICT
- supplier_document_links_rfq_id_operation_id_fkey: FOREIGN KEY (rfq_id, operation_id) REFERENCES private.procurement_rfqs(id, operation_id) ON DELETE RESTRICT
- supplier_document_links_supplier_organisation_id_fkey: FOREIGN KEY (supplier_organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX supplier_document_creator ON private.supplier_document_links USING btree (created_by)
- CREATE UNIQUE INDEX supplier_document_links_document_id_key ON private.supplier_document_links USING btree (document_id)
- CREATE UNIQUE INDEX supplier_document_links_pkey ON private.supplier_document_links USING btree (id)
- CREATE INDEX supplier_document_operation ON private.supplier_document_links USING btree (operation_id, supplier_organisation_id)
- CREATE INDEX supplier_document_organisation ON private.supplier_document_links USING btree (supplier_organisation_id)
- CREATE INDEX supplier_document_po ON private.supplier_document_links USING btree (purchase_order_id, operation_id, supplier_organisation_id)
- CREATE INDEX supplier_document_rfq ON private.supplier_document_links USING btree (rfq_id, operation_id)

## private.specialized_service_policies

Independently approved service-category capability configuration.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| service_version_id | uuid | yes |  |
| kind | text | yes |  |
| version | integer | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| status | text | yes | 'draft'::text |
| configuration | jsonb | yes |  |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- specialized_service_policies_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- specialized_service_policies_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- specialized_service_policies_configuration_check: CHECK (((jsonb_typeof(configuration) = 'object'::text) AND (octet_length((configuration)::text) <= 32768)))
- specialized_service_policies_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- specialized_service_policies_id_service_version_id_kind_key: UNIQUE (id, service_version_id, kind)
- specialized_service_policies_kind_check: CHECK ((kind = ANY (ARRAY['laundry'::text, 'construction'::text, 'procurement'::text, 'field_campaign'::text])))
- specialized_service_policies_pkey: PRIMARY KEY (id)
- specialized_service_policies_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- specialized_service_policies_service_version_id_kind_versio_key: UNIQUE (service_version_id, kind, version)
- specialized_service_policies_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- specialized_service_policies_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX specialized_fk_4470cefd0aeefb719322 ON private.specialized_service_policies USING btree (created_by)
- CREATE INDEX specialized_fk_552da193301ca3efe4fe ON private.specialized_service_policies USING btree (approved_by)
- CREATE UNIQUE INDEX specialized_service_policies_id_service_version_id_kind_key ON private.specialized_service_policies USING btree (id, service_version_id, kind)
- CREATE UNIQUE INDEX specialized_service_policies_pkey ON private.specialized_service_policies USING btree (id)
- CREATE UNIQUE INDEX specialized_service_policies_service_version_id_kind_versio_key ON private.specialized_service_policies USING btree (service_version_id, kind, version)

## private.service_operations

Single typed extension of an existing released order.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| reference | text | yes | ('OPS-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| primary_order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| kind | text | yes |  |
| policy_id | uuid | yes |  |
| status | text | yes | 'planning'::text |
| revision | integer | yes | 1 |
| scope_snapshot | jsonb | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- service_operations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_operations_id_customer_account_id_key: UNIQUE (id, customer_account_id)
- service_operations_id_primary_order_id_key: UNIQUE (id, primary_order_id)
- service_operations_id_service_version_id_key: UNIQUE (id, service_version_id)
- service_operations_pkey: PRIMARY KEY (id)
- service_operations_policy_id_service_version_id_kind_fkey: FOREIGN KEY (policy_id, service_version_id, kind) REFERENCES private.specialized_service_policies(id, service_version_id, kind) ON DELETE RESTRICT
- service_operations_primary_order_id_customer_account_id_fkey: FOREIGN KEY (primary_order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- service_operations_primary_order_id_customer_account_id_se_fkey: FOREIGN KEY (primary_order_id, customer_account_id, service_version_id) REFERENCES private.service_orders(id, customer_account_id, service_version_id) ON DELETE RESTRICT
- service_operations_primary_order_id_kind_key: UNIQUE (primary_order_id, kind)
- service_operations_reference_key: UNIQUE (reference)
- service_operations_revision_check: CHECK ((revision > 0))
- service_operations_status_check: CHECK ((status = ANY (ARRAY['planning'::text, 'active'::text, 'ready'::text, 'closed'::text, 'cancelled'::text])))

Indexes:

- CREATE UNIQUE INDEX service_operations_id_customer_account_id_key ON private.service_operations USING btree (id, customer_account_id)
- CREATE UNIQUE INDEX service_operations_id_primary_order_id_key ON private.service_operations USING btree (id, primary_order_id)
- CREATE UNIQUE INDEX service_operations_id_service_version_id_key ON private.service_operations USING btree (id, service_version_id)
- CREATE UNIQUE INDEX service_operations_pkey ON private.service_operations USING btree (id)
- CREATE UNIQUE INDEX service_operations_primary_order_id_kind_key ON private.service_operations USING btree (primary_order_id, kind)
- CREATE UNIQUE INDEX service_operations_reference_key ON private.service_operations USING btree (reference)
- CREATE INDEX specialized_fk_15dcd25a907e5cbf507b ON private.service_operations USING btree (created_by)
- CREATE INDEX specialized_fk_a0750d07c76a858b7f9f ON private.service_operations USING btree (primary_order_id, customer_account_id, service_version_id)
- CREATE INDEX specialized_fk_b39a673275231213ffb2 ON private.service_operations USING btree (policy_id, service_version_id, kind)
- CREATE INDEX specialized_queue ON private.service_operations USING btree (kind, status, id)

## private.operation_orders

Tenant-consistent additional campaign order links.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- operation_orders_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operation_orders_operation_id_customer_account_id_fkey: FOREIGN KEY (operation_id, customer_account_id) REFERENCES private.service_operations(id, customer_account_id) ON DELETE RESTRICT
- operation_orders_operation_id_order_id_customer_account_id_key: UNIQUE (operation_id, order_id, customer_account_id)
- operation_orders_operation_id_order_id_key: UNIQUE (operation_id, order_id)
- operation_orders_order_id_customer_account_id_fkey: FOREIGN KEY (order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- operation_orders_pkey: PRIMARY KEY (id)

Indexes:

- CREATE UNIQUE INDEX operation_orders_operation_id_order_id_customer_account_id_key ON private.operation_orders USING btree (operation_id, order_id, customer_account_id)
- CREATE UNIQUE INDEX operation_orders_operation_id_order_id_key ON private.operation_orders USING btree (operation_id, order_id)
- CREATE UNIQUE INDEX operation_orders_pkey ON private.operation_orders USING btree (id)
- CREATE INDEX specialized_fk_823f234cb927a59755fa ON private.operation_orders USING btree (order_id, customer_account_id)
- CREATE INDEX specialized_fk_9f4fe5d7a062349be4f7 ON private.operation_orders USING btree (operation_id, customer_account_id)
- CREATE INDEX specialized_fk_f1fab8ec54bad39ffdc9 ON private.operation_orders USING btree (created_by)

## private.operation_tasks

Typed shared work/task and exact assignment links.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| work_order_id | uuid | yes |  |
| task_id | uuid | yes |  |
| purpose | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- operation_tasks_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operation_tasks_id_operation_id_key: UNIQUE (id, operation_id)
- operation_tasks_operation_id_order_id_customer_account_id_fkey: FOREIGN KEY (operation_id, order_id, customer_account_id) REFERENCES private.operation_orders(operation_id, order_id, customer_account_id) ON DELETE RESTRICT
- operation_tasks_operation_id_task_id_key: UNIQUE (operation_id, task_id)
- operation_tasks_pkey: PRIMARY KEY (id)
- operation_tasks_purpose_check: CHECK ((purpose = ANY (ARRAY['pickup'::text, 'intake'::text, 'processing'::text, 'laundry_delivery'::text, 'site_inspection'::text, 'construction_milestone'::text, 'procurement_receiving'::text, 'procurement_handover'::text, 'field_visit'::text])))
- operation_tasks_task_id_operation_id_key: UNIQUE (task_id, operation_id)
- operation_tasks_task_id_work_order_id_order_id_customer_ac_fkey: FOREIGN KEY (task_id, work_order_id, order_id, customer_account_id) REFERENCES private.work_tasks(id, work_order_id, order_id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX operation_tasks_id_operation_id_key ON private.operation_tasks USING btree (id, operation_id)
- CREATE UNIQUE INDEX operation_tasks_operation_id_task_id_key ON private.operation_tasks USING btree (operation_id, task_id)
- CREATE UNIQUE INDEX operation_tasks_pkey ON private.operation_tasks USING btree (id)
- CREATE UNIQUE INDEX operation_tasks_task_id_operation_id_key ON private.operation_tasks USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_31e554268d270977bcc9 ON private.operation_tasks USING btree (created_by)
- CREATE INDEX specialized_fk_938777fd5d84fd59666b ON private.operation_tasks USING btree (operation_id, order_id, customer_account_id)
- CREATE INDEX specialized_fk_c8f568d98f0c13dd9dc5 ON private.operation_tasks USING btree (task_id, work_order_id, order_id, customer_account_id)

## private.operation_documents

Account-owned document registry references.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| document_id | uuid | yes |  |
| task_id | uuid | no |  |
| classification | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- operation_documents_classification_check: CHECK ((classification = ANY (ARRAY['intake_condition'::text, 'custody'::text, 'technical_specification'::text, 'drawing'::text, 'measurement'::text, 'supplier_response'::text, 'shipping'::text, 'receipt'::text, 'field_evidence'::text, 'client_deliverable'::text])))
- operation_documents_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operation_documents_document_id_customer_account_id_fkey: FOREIGN KEY (document_id, customer_account_id) REFERENCES private.document_objects(id, customer_account_id) ON DELETE RESTRICT
- operation_documents_operation_id_customer_account_id_fkey: FOREIGN KEY (operation_id, customer_account_id) REFERENCES private.service_operations(id, customer_account_id) ON DELETE RESTRICT
- operation_documents_operation_id_document_id_classification_key: UNIQUE (operation_id, document_id, classification)
- operation_documents_pkey: PRIMARY KEY (id)
- operation_documents_task_id_operation_id_fkey: FOREIGN KEY (task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX operation_documents_operation_id_document_id_classification_key ON private.operation_documents USING btree (operation_id, document_id, classification)
- CREATE UNIQUE INDEX operation_documents_pkey ON private.operation_documents USING btree (id)
- CREATE INDEX specialized_fk_052a99d09ed1872b5c03 ON private.operation_documents USING btree (document_id, customer_account_id)
- CREATE INDEX specialized_fk_2a71670340d9fc03a8b9 ON private.operation_documents USING btree (created_by)
- CREATE INDEX specialized_fk_30895368cc299583dd9b ON private.operation_documents USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_dc7e4a60c61b305fc086 ON private.operation_documents USING btree (operation_id, customer_account_id)

## private.laundry_bags

Sealed intake and customer acknowledgement.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| code | text | yes |  |
| seal_reference | text | no |  |
| instructions | text | yes | ''::text |
| declared_condition | jsonb | yes | '{}'::jsonb |
| customer_acknowledged_by | uuid | no |  |
| customer_acknowledged_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| sorted_by | uuid | no |  |
| sorted_at | timestamp with time zone | no |  |

Constraints (including FKs, unique and CHECK):

- laundry_bags_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_bags_customer_acknowledged_by_fkey: FOREIGN KEY (customer_acknowledged_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_bags_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_bags_operation_id_code_key: UNIQUE (operation_id, code)
- laundry_bags_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- laundry_bags_pkey: PRIMARY KEY (id)
- laundry_bags_sorted_by_fkey: FOREIGN KEY (sorted_by) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX laundry_bags_id_operation_id_key ON private.laundry_bags USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_bags_operation_id_code_key ON private.laundry_bags USING btree (operation_id, code)
- CREATE UNIQUE INDEX laundry_bags_pkey ON private.laundry_bags USING btree (id)
- CREATE INDEX specialized_fk_585017125ff8e0479abc ON private.laundry_bags USING btree (created_by)
- CREATE INDEX specialized_fk_6768d3837006a04b0267 ON private.laundry_bags USING btree (sorted_by)
- CREATE INDEX specialized_fk_f705d982ddfb865d3a8e ON private.laundry_bags USING btree (customer_acknowledged_by)

## private.laundry_items

Immutable tagged garment or counted batch intake.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| bag_id | uuid | yes |  |
| reference | text | yes |  |
| garment_category | text | yes |  |
| units | integer | yes |  |
| tag | text | yes |  |
| treatment | text | yes |  |
| condition_snapshot | jsonb | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_intake_conservation: TRIGGER DEFERRABLE INITIALLY DEFERRED
- laundry_items_bag_id_operation_id_fkey: FOREIGN KEY (bag_id, operation_id) REFERENCES private.laundry_bags(id, operation_id) ON DELETE RESTRICT
- laundry_items_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_items_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_items_operation_id_reference_key: UNIQUE (operation_id, reference)
- laundry_items_operation_id_tag_key: UNIQUE (operation_id, tag)
- laundry_items_pkey: PRIMARY KEY (id)
- laundry_items_units_check: CHECK ((units > 0))

Indexes:

- CREATE UNIQUE INDEX laundry_items_id_operation_id_key ON private.laundry_items USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_items_operation_id_reference_key ON private.laundry_items USING btree (operation_id, reference)
- CREATE UNIQUE INDEX laundry_items_operation_id_tag_key ON private.laundry_items USING btree (operation_id, tag)
- CREATE UNIQUE INDEX laundry_items_pkey ON private.laundry_items USING btree (id)
- CREATE INDEX specialized_fk_34f4a26f2cc2267c73b7 ON private.laundry_items USING btree (bag_id, operation_id)
- CREATE INDEX specialized_fk_58e0c8dda76fb15585de ON private.laundry_items USING btree (created_by)

## private.laundry_processing_batches

Assigned processing task and explicit party-capacity share.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| processing_task_id | uuid | yes |  |
| code | text | yes |  |
| status | text | yes | 'allocated'::text |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| capacity_units | numeric(20,4) | yes |  |

Constraints (including FKs, unique and CHECK):

- laundry_processing_batches_capacity_units_check: CHECK ((capacity_units > (0)::numeric))
- laundry_processing_batches_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_processing_batches_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_processing_batches_operation_id_code_key: UNIQUE (operation_id, code)
- laundry_processing_batches_pkey: PRIMARY KEY (id)
- laundry_processing_batches_processing_task_id_operation_id_fkey: FOREIGN KEY (processing_task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- laundry_processing_batches_status_check: CHECK ((status = ANY (ARRAY['allocated'::text, 'received'::text, 'processing'::text, 'quality_review'::text, 'packaged'::text, 'returned'::text])))

Indexes:

- CREATE UNIQUE INDEX laundry_processing_batches_id_operation_id_key ON private.laundry_processing_batches USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_processing_batches_operation_id_code_key ON private.laundry_processing_batches USING btree (operation_id, code)
- CREATE UNIQUE INDEX laundry_processing_batches_pkey ON private.laundry_processing_batches USING btree (id)
- CREATE INDEX specialized_fk_3bf8e0c3c776220fa882 ON private.laundry_processing_batches USING btree (created_by)
- CREATE INDEX specialized_fk_f35a7c28978cc2f3b830 ON private.laundry_processing_batches USING btree (processing_task_id, operation_id)

## private.laundry_batch_items

Immutable item allocation and pinned item-level quality task.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| batch_id | uuid | yes |  |
| item_id | uuid | yes |  |
| units | integer | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| inspection_task_id | uuid | no |  |

Constraints (including FKs, unique and CHECK):

- laundry_batch_items_batch_id_item_id_key: UNIQUE (batch_id, item_id)
- laundry_batch_items_batch_id_operation_id_fkey: FOREIGN KEY (batch_id, operation_id) REFERENCES private.laundry_processing_batches(id, operation_id) ON DELETE RESTRICT
- laundry_batch_items_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_batch_items_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_batch_items_inspection_task_id_operation_id_fkey: FOREIGN KEY (inspection_task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- laundry_batch_items_item_id_operation_id_fkey: FOREIGN KEY (item_id, operation_id) REFERENCES private.laundry_items(id, operation_id) ON DELETE RESTRICT
- laundry_batch_items_pkey: PRIMARY KEY (id)
- laundry_batch_items_units_check: CHECK ((units > 0))

Indexes:

- CREATE UNIQUE INDEX laundry_batch_items_batch_id_item_id_key ON private.laundry_batch_items USING btree (batch_id, item_id)
- CREATE UNIQUE INDEX laundry_batch_items_id_operation_id_key ON private.laundry_batch_items USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_batch_items_pkey ON private.laundry_batch_items USING btree (id)
- CREATE UNIQUE INDEX laundry_one_item_inspection ON private.laundry_batch_items USING btree (operation_id, inspection_task_id) WHERE (inspection_task_id IS NOT NULL)
- CREATE INDEX specialized_fk_0b66ebb226f4b20cf6b6 ON private.laundry_batch_items USING btree (inspection_task_id, operation_id)
- CREATE INDEX specialized_fk_0c25e9a0741315687b5a ON private.laundry_batch_items USING btree (item_id, operation_id)
- CREATE INDEX specialized_fk_41e843bebf2e193373e1 ON private.laundry_batch_items USING btree (created_by)
- CREATE INDEX specialized_fk_503b25e36ba26d29e2d6 ON private.laundry_batch_items USING btree (batch_id, operation_id)

## private.laundry_custody_balances

Conserved physical quantity positions; no inventory ownership or financial ledger.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| item_id | uuid | yes |  |
| resource_id | uuid | no |  |
| customer_holder | boolean | yes | false |
| exception_case_id | uuid | no |  |
| units | integer | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_balance_conservation: TRIGGER DEFERRABLE INITIALLY DEFERRED
- laundry_custody_balances_check: CHECK (((((customer_holder)::integer + ((resource_id IS NOT NULL))::integer) + ((exception_case_id IS NOT NULL))::integer) = 1))
- laundry_custody_balances_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_custody_balances_exception_case_id_fkey: FOREIGN KEY (exception_case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- laundry_custody_balances_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_custody_balances_item_id_operation_id_fkey: FOREIGN KEY (item_id, operation_id) REFERENCES private.laundry_items(id, operation_id) ON DELETE RESTRICT
- laundry_custody_balances_item_id_resource_id_customer_holde_key: UNIQUE NULLS NOT DISTINCT (item_id, resource_id, customer_holder, exception_case_id)
- laundry_custody_balances_pkey: PRIMARY KEY (id)
- laundry_custody_balances_resource_id_fkey: FOREIGN KEY (resource_id) REFERENCES private.assignment_resources(id) ON DELETE RESTRICT
- laundry_custody_balances_units_check: CHECK ((units >= 0))

Indexes:

- CREATE UNIQUE INDEX laundry_custody_balances_id_operation_id_key ON private.laundry_custody_balances USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_custody_balances_item_id_resource_id_customer_holde_key ON private.laundry_custody_balances USING btree (item_id, resource_id, customer_holder, exception_case_id) NULLS NOT DISTINCT
- CREATE UNIQUE INDEX laundry_custody_balances_pkey ON private.laundry_custody_balances USING btree (id)
- CREATE INDEX specialized_fk_643a098b5d3f80ac6cf9 ON private.laundry_custody_balances USING btree (item_id, operation_id)
- CREATE INDEX specialized_fk_8d6ec00f3d61b699cb1a ON private.laundry_custody_balances USING btree (created_by)
- CREATE INDEX specialized_fk_ba11d4344e715dec9b75 ON private.laundry_custody_balances USING btree (resource_id)
- CREATE INDEX specialized_fk_f695d5aae19e55e13a8d ON private.laundry_custody_balances USING btree (exception_case_id)

## private.laundry_custody_transfers

Addressed sender/receiver transfer acknowledgements.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| destination_resource_id | uuid | no |  |
| destination_customer | boolean | yes |  |
| evidence_id | uuid | yes |  |
| status | text | yes | 'proposed'::text |
| sent_by | uuid | no |  |
| sent_at | timestamp with time zone | no |  |
| received_by | uuid | no |  |
| received_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_custody_transfers_check: CHECK ((destination_customer <> (destination_resource_id IS NOT NULL)))
- laundry_custody_transfers_check1: CHECK (((received_by IS NULL) OR (received_by <> sent_by)))
- laundry_custody_transfers_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_custody_transfers_destination_resource_id_fkey: FOREIGN KEY (destination_resource_id) REFERENCES private.assignment_resources(id) ON DELETE RESTRICT
- laundry_custody_transfers_evidence_id_fkey: FOREIGN KEY (evidence_id) REFERENCES private.execution_evidence(id) ON DELETE RESTRICT
- laundry_custody_transfers_id_operation_id_key: UNIQUE (id, operation_id)
- laundry_custody_transfers_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- laundry_custody_transfers_pkey: PRIMARY KEY (id)
- laundry_custody_transfers_received_by_fkey: FOREIGN KEY (received_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_custody_transfers_sent_by_fkey: FOREIGN KEY (sent_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_custody_transfers_status_check: CHECK ((status = ANY (ARRAY['proposed'::text, 'sent'::text, 'received'::text, 'rejected'::text, 'discrepant'::text, 'resolved'::text])))

Indexes:

- CREATE UNIQUE INDEX laundry_custody_transfers_id_operation_id_key ON private.laundry_custody_transfers USING btree (id, operation_id)
- CREATE UNIQUE INDEX laundry_custody_transfers_pkey ON private.laundry_custody_transfers USING btree (id)
- CREATE INDEX laundry_receipt_queue ON private.laundry_custody_transfers USING btree (operation_id, status, id)
- CREATE INDEX specialized_fk_17499bb8ad16f29f1f9b ON private.laundry_custody_transfers USING btree (received_by)
- CREATE INDEX specialized_fk_516f03032d5fe8892f57 ON private.laundry_custody_transfers USING btree (sent_by)
- CREATE INDEX specialized_fk_59a46ca862ab721d0d68 ON private.laundry_custody_transfers USING btree (created_by)
- CREATE INDEX specialized_fk_8818c57f65410b342bd0 ON private.laundry_custody_transfers USING btree (destination_resource_id)
- CREATE INDEX specialized_fk_893dc057176d233cf25b ON private.laundry_custody_transfers USING btree (operation_id)
- CREATE INDEX specialized_fk_e72697de2bc6ffa04366 ON private.laundry_custody_transfers USING btree (evidence_id)

## private.laundry_transfer_items

Original sent and independently counted received quantities.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| transfer_id | uuid | yes |  |
| source_balance_id | uuid | yes |  |
| sent_units | integer | yes |  |
| received_units | integer | no |  |
| discrepancy_case_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_transfer_items_check: CHECK (((received_units >= 0) AND (received_units <= sent_units)))
- laundry_transfer_items_check1: CHECK (((received_units IS NULL) OR (received_units = sent_units) OR (discrepancy_case_id IS NOT NULL)))
- laundry_transfer_items_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_transfer_items_discrepancy_case_id_fkey: FOREIGN KEY (discrepancy_case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- laundry_transfer_items_pkey: PRIMARY KEY (id)
- laundry_transfer_items_sent_units_check: CHECK ((sent_units > 0))
- laundry_transfer_items_source_balance_id_operation_id_fkey: FOREIGN KEY (source_balance_id, operation_id) REFERENCES private.laundry_custody_balances(id, operation_id) ON DELETE RESTRICT
- laundry_transfer_items_transfer_id_operation_id_fkey: FOREIGN KEY (transfer_id, operation_id) REFERENCES private.laundry_custody_transfers(id, operation_id) ON DELETE RESTRICT
- laundry_transfer_items_transfer_id_source_balance_id_key: UNIQUE (transfer_id, source_balance_id)

Indexes:

- CREATE UNIQUE INDEX laundry_transfer_items_pkey ON private.laundry_transfer_items USING btree (id)
- CREATE UNIQUE INDEX laundry_transfer_items_transfer_id_source_balance_id_key ON private.laundry_transfer_items USING btree (transfer_id, source_balance_id)
- CREATE INDEX specialized_fk_159311dfef4875cd5b87 ON private.laundry_transfer_items USING btree (transfer_id, operation_id)
- CREATE INDEX specialized_fk_1bc6cd6e2c66454901cd ON private.laundry_transfer_items USING btree (discrepancy_case_id)
- CREATE INDEX specialized_fk_3472a7e87eccc3d5ef7e ON private.laundry_transfer_items USING btree (created_by)
- CREATE INDEX specialized_fk_c765581c5da1c75588eb ON private.laundry_transfer_items USING btree (source_balance_id, operation_id)

## private.laundry_custody_events

Immutable physical acknowledgement and discrepancy history.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| transfer_id | uuid | yes |  |
| item_id | uuid | yes |  |
| action | text | yes |  |
| units | integer | yes |  |
| source_balance_id | uuid | no |  |
| destination_balance_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_custody_events_action_check: CHECK ((action = ANY (ARRAY['sent'::text, 'received'::text, 'rejected'::text, 'discrepancy'::text, 'resolved'::text])))
- laundry_custody_events_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_custody_events_destination_balance_id_fkey: FOREIGN KEY (destination_balance_id) REFERENCES private.laundry_custody_balances(id) ON DELETE RESTRICT
- laundry_custody_events_item_id_operation_id_fkey: FOREIGN KEY (item_id, operation_id) REFERENCES private.laundry_items(id, operation_id) ON DELETE RESTRICT
- laundry_custody_events_pkey: PRIMARY KEY (id)
- laundry_custody_events_source_balance_id_fkey: FOREIGN KEY (source_balance_id) REFERENCES private.laundry_custody_balances(id) ON DELETE RESTRICT
- laundry_custody_events_transfer_id_item_id_action_key: UNIQUE (transfer_id, item_id, action)
- laundry_custody_events_transfer_id_operation_id_fkey: FOREIGN KEY (transfer_id, operation_id) REFERENCES private.laundry_custody_transfers(id, operation_id) ON DELETE RESTRICT
- laundry_custody_events_units_check: CHECK ((units >= 0))

Indexes:

- CREATE UNIQUE INDEX laundry_custody_events_pkey ON private.laundry_custody_events USING btree (id)
- CREATE UNIQUE INDEX laundry_custody_events_transfer_id_item_id_action_key ON private.laundry_custody_events USING btree (transfer_id, item_id, action)
- CREATE INDEX specialized_fk_26cee137f08ba897fb5a ON private.laundry_custody_events USING btree (destination_balance_id)
- CREATE INDEX specialized_fk_498011c686054fc76f52 ON private.laundry_custody_events USING btree (source_balance_id)
- CREATE INDEX specialized_fk_66ac1c30c23896c8dde9 ON private.laundry_custody_events USING btree (transfer_id, operation_id)
- CREATE INDEX specialized_fk_b5baa953b6a2029876f7 ON private.laundry_custody_events USING btree (created_by)
- CREATE INDEX specialized_fk_e1ee93488cc5f454da9d ON private.laundry_custody_events USING btree (item_id, operation_id)

## private.laundry_allocation_changes

Independent append-only corrections without rewriting original allocation.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| allocation_id | uuid | yes |  |
| delta | integer | yes |  |
| case_id | uuid | no |  |
| status | text | yes | 'pending'::text |
| approved_by | uuid | no |  |
| created_by | uuid | yes |  |
| reason | text | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- laundry_allocation_changes_allocation_id_operation_id_fkey: FOREIGN KEY (allocation_id, operation_id) REFERENCES private.laundry_batch_items(id, operation_id) ON DELETE RESTRICT
- laundry_allocation_changes_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_allocation_changes_case_id_fkey: FOREIGN KEY (case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- laundry_allocation_changes_check: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- laundry_allocation_changes_check1: CHECK (((status = 'pending'::text) = (approved_by IS NULL)))
- laundry_allocation_changes_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- laundry_allocation_changes_delta_check: CHECK ((delta <> 0))
- laundry_allocation_changes_pkey: PRIMARY KEY (id)
- laundry_allocation_changes_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- laundry_allocation_changes_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))

Indexes:

- CREATE UNIQUE INDEX laundry_allocation_changes_pkey ON private.laundry_allocation_changes USING btree (id)
- CREATE INDEX specialized_fk_0cdd129f73017adce9a2 ON private.laundry_allocation_changes USING btree (allocation_id, operation_id)
- CREATE INDEX specialized_fk_46991934b50a9b30fb8f ON private.laundry_allocation_changes USING btree (created_by)
- CREATE INDEX specialized_fk_677a3f98ab3e5d27e55f ON private.laundry_allocation_changes USING btree (case_id)
- CREATE INDEX specialized_fk_a4ab3d6dcbb227e5823e ON private.laundry_allocation_changes USING btree (approved_by)

## private.construction_projects

Original order site and immutable technical specification.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| site_location_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| technical_specification | jsonb | yes |  |
| access_instructions | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- construction_projects_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_projects_id_operation_id_key: UNIQUE (id, operation_id)
- construction_projects_operation_id_customer_account_id_fkey: FOREIGN KEY (operation_id, customer_account_id) REFERENCES private.service_operations(id, customer_account_id) ON DELETE RESTRICT
- construction_projects_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- construction_projects_operation_id_key: UNIQUE (operation_id)
- construction_projects_pkey: PRIMARY KEY (id)
- construction_projects_site_location_id_customer_account_id_fkey: FOREIGN KEY (site_location_id, customer_account_id) REFERENCES service_locations(id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX construction_projects_id_operation_id_key ON private.construction_projects USING btree (id, operation_id)
- CREATE UNIQUE INDEX construction_projects_operation_id_key ON private.construction_projects USING btree (operation_id)
- CREATE UNIQUE INDEX construction_projects_pkey ON private.construction_projects USING btree (id)
- CREATE INDEX specialized_fk_1d457e84d8487a8aaf67 ON private.construction_projects USING btree (created_by)
- CREATE INDEX specialized_fk_6b8f35d15773ab27d08f ON private.construction_projects USING btree (operation_id, customer_account_id)
- CREATE INDEX specialized_fk_6e5b8802d9b72348968b ON private.construction_projects USING btree (site_location_id, customer_account_id)

## private.construction_milestones

Trade tasks, measurement snapshots, inspected and client-accepted handover.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| project_id | uuid | yes |  |
| task_id | uuid | yes |  |
| code | text | yes |  |
| trade | text | yes |  |
| scope_snapshot | jsonb | yes |  |
| measurements | jsonb | yes |  |
| customer_approved_by | uuid | no |  |
| customer_approved_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| inspection_evidence_id | uuid | no |  |
| source_variation_id | uuid | no |  |

Constraints (including FKs, unique and CHECK):

- construction_milestones_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_milestones_customer_approved_by_fkey: FOREIGN KEY (customer_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_milestones_id_operation_id_key: UNIQUE (id, operation_id)
- construction_milestones_inspection_evidence_id_fkey: FOREIGN KEY (inspection_evidence_id) REFERENCES private.execution_evidence(id) ON DELETE RESTRICT
- construction_milestones_operation_id_code_key: UNIQUE (operation_id, code)
- construction_milestones_pkey: PRIMARY KEY (id)
- construction_milestones_project_id_operation_id_fkey: FOREIGN KEY (project_id, operation_id) REFERENCES private.construction_projects(id, operation_id) ON DELETE RESTRICT
- construction_milestones_source_variation_id_operation_id_fkey: FOREIGN KEY (source_variation_id, operation_id) REFERENCES private.construction_variations(id, operation_id) ON DELETE RESTRICT
- construction_milestones_task_id_operation_id_fkey: FOREIGN KEY (task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX construction_milestone_queue ON private.construction_milestones USING btree (operation_id, customer_approved_at, id)
- CREATE UNIQUE INDEX construction_milestones_id_operation_id_key ON private.construction_milestones USING btree (id, operation_id)
- CREATE UNIQUE INDEX construction_milestones_operation_id_code_key ON private.construction_milestones USING btree (operation_id, code)
- CREATE UNIQUE INDEX construction_milestones_pkey ON private.construction_milestones USING btree (id)
- CREATE INDEX specialized_fk_3021843e3513e234236d ON private.construction_milestones USING btree (customer_approved_by)
- CREATE INDEX specialized_fk_363925650540e69da53b ON private.construction_milestones USING btree (source_variation_id, operation_id)
- CREATE INDEX specialized_fk_3df934595a301067eba2 ON private.construction_milestones USING btree (inspection_evidence_id)
- CREATE INDEX specialized_fk_4dbd35e7f0aff1f59fd8 ON private.construction_milestones USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_aa92791e3702f2ca05cd ON private.construction_milestones USING btree (created_by)
- CREATE INDEX specialized_fk_b3228e447fffa2a784b1 ON private.construction_milestones USING btree (project_id, operation_id)

## private.construction_material_requirements

Independently approved customer-demand material quantities.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| code | text | yes |  |
| version | integer | yes |  |
| description | text | yes |  |
| unit | text | yes |  |
| quantity | numeric(20,4) | yes |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- construction_material_requirement_operation_id_code_version_key: UNIQUE (operation_id, code, version)
- construction_material_requirements_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_material_requirements_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_material_requirements_id_operation_id_key: UNIQUE (id, operation_id)
- construction_material_requirements_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- construction_material_requirements_pkey: PRIMARY KEY (id)
- construction_material_requirements_quantity_check: CHECK ((quantity > (0)::numeric))
- construction_material_requirements_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- construction_material_requirements_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX construction_material_requirement_operation_id_code_version_key ON private.construction_material_requirements USING btree (operation_id, code, version)
- CREATE UNIQUE INDEX construction_material_requirements_id_operation_id_key ON private.construction_material_requirements USING btree (id, operation_id)
- CREATE UNIQUE INDEX construction_material_requirements_pkey ON private.construction_material_requirements USING btree (id)
- CREATE INDEX specialized_fk_31a0de63c5e4508351d1 ON private.construction_material_requirements USING btree (created_by)
- CREATE INDEX specialized_fk_646cdadc4e0aef2a31cf ON private.construction_material_requirements USING btree (approved_by)

## private.construction_material_events

Evidenced actual receipt, use, return and waste conservation.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| requirement_id | uuid | yes |  |
| task_id | uuid | yes |  |
| kind | text | yes |  |
| quantity | numeric(20,4) | yes |  |
| evidence_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- construction_material_events_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_material_events_evidence_id_fkey: FOREIGN KEY (evidence_id) REFERENCES private.execution_evidence(id) ON DELETE RESTRICT
- construction_material_events_kind_check: CHECK ((kind = ANY (ARRAY['received'::text, 'consumed'::text, 'returned'::text, 'waste'::text])))
- construction_material_events_pkey: PRIMARY KEY (id)
- construction_material_events_quantity_check: CHECK ((quantity > (0)::numeric))
- construction_material_events_requirement_id_operation_id_fkey: FOREIGN KEY (requirement_id, operation_id) REFERENCES private.construction_material_requirements(id, operation_id) ON DELETE RESTRICT
- construction_material_events_task_id_operation_id_fkey: FOREIGN KEY (task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX construction_material_events_pkey ON private.construction_material_events USING btree (id)
- CREATE INDEX specialized_fk_42794e6465cd7adc03e7 ON private.construction_material_events USING btree (evidence_id)
- CREATE INDEX specialized_fk_503c5e3da19737c8a64a ON private.construction_material_events USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_c780924fced39d151e68 ON private.construction_material_events USING btree (created_by)
- CREATE INDEX specialized_fk_ddbf9caaeaf4f356cd8c ON private.construction_material_events USING btree (requirement_id, operation_id)

## private.construction_variations

Customer and independent OnIt commercial decisions tied to accepted order versions.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| version | integer | yes |  |
| original_commercial_version_id | uuid | yes |  |
| proposed_quote_version_id | uuid | no |  |
| reason | text | yes |  |
| scope_snapshot | jsonb | yes |  |
| time_impact_seconds | integer | yes |  |
| currency_id | uuid | yes |  |
| cost_impact | numeric(20,4) | yes |  |
| status | text | yes | 'proposed'::text |
| customer_decided_by | uuid | no |  |
| commercial_approved_by | uuid | no |  |
| implemented_task_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| customer_decided_at | timestamp with time zone | no |  |
| commercial_approved_at | timestamp with time zone | no |  |
| implemented_commercial_version_id | uuid | no |  |
| order_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- construction_variations_commercial_approved_by_fkey: FOREIGN KEY (commercial_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_variations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_variations_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- construction_variations_customer_decided_by_fkey: FOREIGN KEY (customer_decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_variations_id_operation_id_key: UNIQUE (id, operation_id)
- construction_variations_implemented_commercial_version_id__fkey: FOREIGN KEY (implemented_commercial_version_id, order_id) REFERENCES private.order_commercial_versions(id, order_id) ON DELETE RESTRICT
- construction_variations_implemented_commercial_version_id_fkey: FOREIGN KEY (implemented_commercial_version_id) REFERENCES private.order_commercial_versions(id) ON DELETE RESTRICT
- construction_variations_implemented_task_id_operation_id_fkey: FOREIGN KEY (implemented_task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- construction_variations_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- construction_variations_operation_id_order_id_fkey: FOREIGN KEY (operation_id, order_id) REFERENCES private.service_operations(id, primary_order_id) ON DELETE RESTRICT
- construction_variations_operation_id_version_key: UNIQUE (operation_id, version)
- construction_variations_original_commercial_version_id_fkey: FOREIGN KEY (original_commercial_version_id) REFERENCES private.order_commercial_versions(id) ON DELETE RESTRICT
- construction_variations_original_commercial_version_id_ord_fkey: FOREIGN KEY (original_commercial_version_id, order_id) REFERENCES private.order_commercial_versions(id, order_id) ON DELETE RESTRICT
- construction_variations_pkey: PRIMARY KEY (id)
- construction_variations_proposed_quote_version_id_fkey: FOREIGN KEY (proposed_quote_version_id) REFERENCES quotation_versions(id) ON DELETE RESTRICT
- construction_variations_status_check: CHECK ((status = ANY (ARRAY['proposed'::text, 'customer_accepted'::text, 'approved'::text, 'implemented'::text, 'rejected'::text, 'withdrawn'::text])))
- construction_variations_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX construction_variations_id_operation_id_key ON private.construction_variations USING btree (id, operation_id)
- CREATE UNIQUE INDEX construction_variations_operation_id_version_key ON private.construction_variations USING btree (operation_id, version)
- CREATE UNIQUE INDEX construction_variations_pkey ON private.construction_variations USING btree (id)
- CREATE INDEX specialized_fk_13e56a26d4772cabddf1 ON private.construction_variations USING btree (currency_id)
- CREATE INDEX specialized_fk_215a6917f5e5d7191be0 ON private.construction_variations USING btree (implemented_task_id, operation_id)
- CREATE INDEX specialized_fk_64055b88b87da9b2a9a4 ON private.construction_variations USING btree (original_commercial_version_id, order_id)
- CREATE INDEX specialized_fk_9dcba8d796b2a73e2aa4 ON private.construction_variations USING btree (customer_decided_by)
- CREATE INDEX specialized_fk_a2a494c615ed6aa6e6c4 ON private.construction_variations USING btree (operation_id, order_id)
- CREATE INDEX specialized_fk_ad989282c941219db8f0 ON private.construction_variations USING btree (implemented_commercial_version_id, order_id)
- CREATE INDEX specialized_fk_b3fe5ce3481b2dcb61d7 ON private.construction_variations USING btree (commercial_approved_by)
- CREATE INDEX specialized_fk_cbf84b4c92f69e056350 ON private.construction_variations USING btree (created_by)
- CREATE INDEX specialized_fk_dd9366f7c72531fb5453 ON private.construction_variations USING btree (proposed_quote_version_id)

## private.construction_milestone_successors

Explicit immutable predecessor/replacement mappings after commercial replan.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| variation_id | uuid | yes |  |
| original_milestone_id | uuid | yes |  |
| successor_milestone_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- construction_milestone_succes_original_milestone_id_operat_fkey: FOREIGN KEY (original_milestone_id, operation_id) REFERENCES private.construction_milestones(id, operation_id) ON DELETE RESTRICT
- construction_milestone_succes_successor_milestone_id_opera_fkey: FOREIGN KEY (successor_milestone_id, operation_id) REFERENCES private.construction_milestones(id, operation_id) ON DELETE RESTRICT
- construction_milestone_successor_variation_id_operation_id_fkey: FOREIGN KEY (variation_id, operation_id) REFERENCES private.construction_variations(id, operation_id) ON DELETE RESTRICT
- construction_milestone_successors_check: CHECK ((original_milestone_id <> successor_milestone_id))
- construction_milestone_successors_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- construction_milestone_successors_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- construction_milestone_successors_original_milestone_id_key: UNIQUE (original_milestone_id)
- construction_milestone_successors_pkey: PRIMARY KEY (id)

Indexes:

- CREATE UNIQUE INDEX construction_milestone_successors_original_milestone_id_key ON private.construction_milestone_successors USING btree (original_milestone_id)
- CREATE UNIQUE INDEX construction_milestone_successors_pkey ON private.construction_milestone_successors USING btree (id)
- CREATE INDEX specialized_fk_2ba4fac80c33f6db13bd ON private.construction_milestone_successors USING btree (successor_milestone_id, operation_id)
- CREATE INDEX specialized_fk_737f77e4038026bba8c6 ON private.construction_milestone_successors USING btree (variation_id, operation_id)
- CREATE INDEX specialized_fk_b925fe28eba4ef321deb ON private.construction_milestone_successors USING btree (created_by)
- CREATE INDEX specialized_fk_c2216f483aea8a7dec33 ON private.construction_milestone_successors USING btree (operation_id)
- CREATE INDEX specialized_fk_ee9ccbdcc5253a69fb52 ON private.construction_milestone_successors USING btree (original_milestone_id, operation_id)

## private.supplier_eligibility_versions

Independently verified exact service/zone supplier terms and evidence.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| organisation_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| version | integer | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | yes |  |
| document_id | uuid | yes |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- supplier_eligibility_versions_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_eligibility_versions_check: CHECK ((valid_until > valid_from))
- supplier_eligibility_versions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_eligibility_versions_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- supplier_eligibility_versions_document_id_organisation_id_fkey: FOREIGN KEY (document_id, organisation_id) REFERENCES private.document_objects(id, organisation_id) ON DELETE RESTRICT
- supplier_eligibility_versions_id_organisation_id_key: UNIQUE (id, organisation_id)
- supplier_eligibility_versions_organisation_id_fkey: FOREIGN KEY (organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT
- supplier_eligibility_versions_organisation_id_service_versi_key: UNIQUE (organisation_id, service_version_id, zone_id, version)
- supplier_eligibility_versions_pkey: PRIMARY KEY (id)
- supplier_eligibility_versions_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- supplier_eligibility_versions_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- supplier_eligibility_versions_version_check: CHECK ((version > 0))
- supplier_eligibility_versions_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX specialized_fk_124ae5d4677c54c30703 ON private.supplier_eligibility_versions USING btree (created_by)
- CREATE INDEX specialized_fk_bc5e81c3922c31ba443b ON private.supplier_eligibility_versions USING btree (approved_by)
- CREATE INDEX specialized_fk_c2e289a26a9d4d8c80d6 ON private.supplier_eligibility_versions USING btree (service_version_id)
- CREATE INDEX specialized_fk_c943456d9cb80e0c2144 ON private.supplier_eligibility_versions USING btree (document_id, organisation_id)
- CREATE INDEX specialized_fk_d398b515077e3d7c33f9 ON private.supplier_eligibility_versions USING btree (zone_id)
- CREATE UNIQUE INDEX supplier_eligibility_versions_id_organisation_id_key ON private.supplier_eligibility_versions USING btree (id, organisation_id)
- CREATE UNIQUE INDEX supplier_eligibility_versions_organisation_id_service_versi_key ON private.supplier_eligibility_versions USING btree (organisation_id, service_version_id, zone_id, version)
- CREATE UNIQUE INDEX supplier_eligibility_versions_pkey ON private.supplier_eligibility_versions USING btree (id)

## private.procurement_rfqs

Versioned customer-authorised zero-inventory demand.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| reference | text | yes | ('RFQ-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| version | integer | yes |  |
| closes_at | timestamp with time zone | yes |  |
| required_at | timestamp with time zone | yes |  |
| status | text | yes | 'draft'::text |
| authorisation_document_id | uuid | yes |  |
| terms | jsonb | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| customer_approved_by | uuid | no |  |
| customer_approved_at | timestamp with time zone | no |  |

Constraints (including FKs, unique and CHECK):

- procurement_rfqs_authorisation_document_id_fkey: FOREIGN KEY (authorisation_document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- procurement_rfqs_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_rfqs_customer_approved_by_fkey: FOREIGN KEY (customer_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_rfqs_id_operation_id_key: UNIQUE (id, operation_id)
- procurement_rfqs_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- procurement_rfqs_operation_id_version_key: UNIQUE (operation_id, version)
- procurement_rfqs_pkey: PRIMARY KEY (id)
- procurement_rfqs_reference_key: UNIQUE (reference)
- procurement_rfqs_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'issued'::text, 'closed'::text, 'cancelled'::text])))
- procurement_rfqs_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX procurement_rfqs_id_operation_id_key ON private.procurement_rfqs USING btree (id, operation_id)
- CREATE UNIQUE INDEX procurement_rfqs_operation_id_version_key ON private.procurement_rfqs USING btree (operation_id, version)
- CREATE UNIQUE INDEX procurement_rfqs_pkey ON private.procurement_rfqs USING btree (id)
- CREATE UNIQUE INDEX procurement_rfqs_reference_key ON private.procurement_rfqs USING btree (reference)
- CREATE INDEX specialized_fk_11212f4ff777117d5822 ON private.procurement_rfqs USING btree (created_by)
- CREATE INDEX specialized_fk_4f35c3d856d71522d8ef ON private.procurement_rfqs USING btree (customer_approved_by)
- CREATE INDEX specialized_fk_74238a458d9abd0153b7 ON private.procurement_rfqs USING btree (authorisation_document_id)

## private.procurement_rfq_items

Immutable comparable specifications, units and quantities.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| rfq_id | uuid | yes |  |
| code | text | yes |  |
| description | text | yes |  |
| specification | jsonb | yes |  |
| quantity | numeric(20,4) | yes |  |
| unit | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- procurement_rfq_items_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_rfq_items_id_rfq_id_key: UNIQUE (id, rfq_id)
- procurement_rfq_items_pkey: PRIMARY KEY (id)
- procurement_rfq_items_quantity_check: CHECK ((quantity > (0)::numeric))
- procurement_rfq_items_rfq_id_code_key: UNIQUE (rfq_id, code)
- procurement_rfq_items_rfq_id_operation_id_fkey: FOREIGN KEY (rfq_id, operation_id) REFERENCES private.procurement_rfqs(id, operation_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX procurement_rfq_items_id_rfq_id_key ON private.procurement_rfq_items USING btree (id, rfq_id)
- CREATE UNIQUE INDEX procurement_rfq_items_pkey ON private.procurement_rfq_items USING btree (id)
- CREATE UNIQUE INDEX procurement_rfq_items_rfq_id_code_key ON private.procurement_rfq_items USING btree (rfq_id, code)
- CREATE INDEX specialized_fk_72cb8d379db3dd39401a ON private.procurement_rfq_items USING btree (created_by)
- CREATE INDEX specialized_fk_81284f98f9a6b72a66ca ON private.procurement_rfq_items USING btree (rfq_id, operation_id)

## private.procurement_rfq_recipients

Exact verified supplier invitations.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| rfq_id | uuid | yes |  |
| supplier_organisation_id | uuid | yes |  |
| eligibility_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- procurement_rfq_recipients_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_rfq_recipients_eligibility_id_fkey: FOREIGN KEY (eligibility_id) REFERENCES private.supplier_eligibility_versions(id) ON DELETE RESTRICT
- procurement_rfq_recipients_eligibility_id_supplier_organis_fkey: FOREIGN KEY (eligibility_id, supplier_organisation_id) REFERENCES private.supplier_eligibility_versions(id, organisation_id) ON DELETE RESTRICT
- procurement_rfq_recipients_id_rfq_id_supplier_organisation__key: UNIQUE (id, rfq_id, supplier_organisation_id)
- procurement_rfq_recipients_pkey: PRIMARY KEY (id)
- procurement_rfq_recipients_rfq_id_fkey: FOREIGN KEY (rfq_id) REFERENCES private.procurement_rfqs(id) ON DELETE RESTRICT
- procurement_rfq_recipients_rfq_id_supplier_organisation_id_key: UNIQUE (rfq_id, supplier_organisation_id)
- procurement_rfq_recipients_supplier_organisation_id_fkey: FOREIGN KEY (supplier_organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX procurement_rfq_recipients_id_rfq_id_supplier_organisation__key ON private.procurement_rfq_recipients USING btree (id, rfq_id, supplier_organisation_id)
- CREATE UNIQUE INDEX procurement_rfq_recipients_pkey ON private.procurement_rfq_recipients USING btree (id)
- CREATE UNIQUE INDEX procurement_rfq_recipients_rfq_id_supplier_organisation_id_key ON private.procurement_rfq_recipients USING btree (rfq_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_1027e932381ec04e9b20 ON private.procurement_rfq_recipients USING btree (supplier_organisation_id)
- CREATE INDEX specialized_fk_1411a660e0852c5aae38 ON private.procurement_rfq_recipients USING btree (eligibility_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_52f2680ecdaa33777f33 ON private.procurement_rfq_recipients USING btree (created_by)

## private.supplier_quotation_versions

Confidential exact-decimal supplier proposal versions.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| rfq_id | uuid | yes |  |
| supplier_organisation_id | uuid | yes |  |
| recipient_id | uuid | yes |  |
| version | integer | yes |  |
| currency_id | uuid | yes |  |
| minor_units | integer | yes |  |
| valid_until | timestamp with time zone | yes |  |
| status | text | yes | 'draft'::text |
| conditions | jsonb | yes |  |
| total | numeric(20,4) | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- supplier_quotation_versions_check: CHECK (((total >= (0)::numeric) AND (total = round(total, minor_units))))
- supplier_quotation_versions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_quotation_versions_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- supplier_quotation_versions_id_rfq_id_key: UNIQUE (id, rfq_id)
- supplier_quotation_versions_id_supplier_organisation_id_key: UNIQUE (id, supplier_organisation_id)
- supplier_quotation_versions_minor_units_check: CHECK (((minor_units >= 0) AND (minor_units <= 4)))
- supplier_quotation_versions_pkey: PRIMARY KEY (id)
- supplier_quotation_versions_recipient_id_rfq_id_supplier_o_fkey: FOREIGN KEY (recipient_id, rfq_id, supplier_organisation_id) REFERENCES private.procurement_rfq_recipients(id, rfq_id, supplier_organisation_id) ON DELETE RESTRICT
- supplier_quotation_versions_rfq_id_supplier_organisation_id_key: UNIQUE (rfq_id, supplier_organisation_id, version)
- supplier_quotation_versions_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'withdrawn'::text, 'superseded'::text])))
- supplier_quotation_versions_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX specialized_fk_9cf542f9f5f70676a3f0 ON private.supplier_quotation_versions USING btree (created_by)
- CREATE INDEX specialized_fk_a00d72f858abe5e030b3 ON private.supplier_quotation_versions USING btree (currency_id)
- CREATE INDEX specialized_fk_ed51353ef940cd9d1d43 ON private.supplier_quotation_versions USING btree (recipient_id, rfq_id, supplier_organisation_id)
- CREATE UNIQUE INDEX supplier_quotation_versions_id_rfq_id_key ON private.supplier_quotation_versions USING btree (id, rfq_id)
- CREATE UNIQUE INDEX supplier_quotation_versions_id_supplier_organisation_id_key ON private.supplier_quotation_versions USING btree (id, supplier_organisation_id)
- CREATE UNIQUE INDEX supplier_quotation_versions_pkey ON private.supplier_quotation_versions USING btree (id)
- CREATE UNIQUE INDEX supplier_quotation_versions_rfq_id_supplier_organisation_id_key ON private.supplier_quotation_versions USING btree (rfq_id, supplier_organisation_id, version)

## private.supplier_quotation_lines

Immutable quantity, discount, tax and line-total snapshots.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| quotation_version_id | uuid | yes |  |
| rfq_id | uuid | yes |  |
| rfq_item_id | uuid | yes |  |
| quantity | numeric(20,4) | yes |  |
| unit_price | numeric(20,4) | yes |  |
| discount | numeric(20,4) | yes |  |
| tax_rule_id | uuid | no |  |
| tax_snapshot | jsonb | yes |  |
| line_total | numeric(20,4) | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- supplier_quotation_lines_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_quotation_lines_discount_check: CHECK ((discount >= (0)::numeric))
- supplier_quotation_lines_line_total_check: CHECK ((line_total >= (0)::numeric))
- supplier_quotation_lines_pkey: PRIMARY KEY (id)
- supplier_quotation_lines_quantity_check: CHECK ((quantity > (0)::numeric))
- supplier_quotation_lines_quotation_version_id_rfq_id_fkey: FOREIGN KEY (quotation_version_id, rfq_id) REFERENCES private.supplier_quotation_versions(id, rfq_id) ON DELETE RESTRICT
- supplier_quotation_lines_quotation_version_id_rfq_item_id_key: UNIQUE (quotation_version_id, rfq_item_id)
- supplier_quotation_lines_rfq_item_id_rfq_id_fkey: FOREIGN KEY (rfq_item_id, rfq_id) REFERENCES private.procurement_rfq_items(id, rfq_id) ON DELETE RESTRICT
- supplier_quotation_lines_tax_rule_id_fkey: FOREIGN KEY (tax_rule_id) REFERENCES private.quotation_tax_rules(id) ON DELETE RESTRICT
- supplier_quotation_lines_unit_price_check: CHECK ((unit_price >= (0)::numeric))

Indexes:

- CREATE INDEX specialized_fk_488e1522f286693aa036 ON private.supplier_quotation_lines USING btree (tax_rule_id)
- CREATE INDEX specialized_fk_4f7eb597da9d93e09da1 ON private.supplier_quotation_lines USING btree (quotation_version_id, rfq_id)
- CREATE INDEX specialized_fk_6c588fdc8196bcc9580f ON private.supplier_quotation_lines USING btree (rfq_item_id, rfq_id)
- CREATE INDEX specialized_fk_774b73dd0ddcbd0b35c4 ON private.supplier_quotation_lines USING btree (created_by)
- CREATE UNIQUE INDEX supplier_quotation_lines_pkey ON private.supplier_quotation_lines USING btree (id)
- CREATE UNIQUE INDEX supplier_quotation_lines_quotation_version_id_rfq_item_id_key ON private.supplier_quotation_lines USING btree (quotation_version_id, rfq_item_id)

## private.procurement_selections

Independently approved evidenced supplier selection.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| rfq_id | uuid | yes |  |
| quotation_version_id | uuid | yes |  |
| rationale | text | yes |  |
| status | text | yes | 'proposed'::text |
| approved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| supplier_organisation_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- procurement_selections_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_selections_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_selections_id_operation_id_key: UNIQUE (id, operation_id)
- procurement_selections_id_operation_id_supplier_organisatio_key: UNIQUE (id, operation_id, supplier_organisation_id)
- procurement_selections_pkey: PRIMARY KEY (id)
- procurement_selections_quotation_version_id_rfq_id_fkey: FOREIGN KEY (quotation_version_id, rfq_id) REFERENCES private.supplier_quotation_versions(id, rfq_id) ON DELETE RESTRICT
- procurement_selections_quotation_version_id_supplier_organ_fkey: FOREIGN KEY (quotation_version_id, supplier_organisation_id) REFERENCES private.supplier_quotation_versions(id, supplier_organisation_id) ON DELETE RESTRICT
- procurement_selections_rfq_id_operation_id_fkey: FOREIGN KEY (rfq_id, operation_id) REFERENCES private.procurement_rfqs(id, operation_id) ON DELETE RESTRICT
- procurement_selections_status_check: CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])))

Indexes:

- CREATE UNIQUE INDEX procurement_one_approved_selection ON private.procurement_selections USING btree (rfq_id) WHERE (status = 'approved'::text)
- CREATE UNIQUE INDEX procurement_selections_id_operation_id_key ON private.procurement_selections USING btree (id, operation_id)
- CREATE UNIQUE INDEX procurement_selections_id_operation_id_supplier_organisatio_key ON private.procurement_selections USING btree (id, operation_id, supplier_organisation_id)
- CREATE UNIQUE INDEX procurement_selections_pkey ON private.procurement_selections USING btree (id)
- CREATE INDEX specialized_fk_329c8875b872bad16880 ON private.procurement_selections USING btree (created_by)
- CREATE INDEX specialized_fk_b74ddeff5c371d8a76f1 ON private.procurement_selections USING btree (quotation_version_id, rfq_id)
- CREATE INDEX specialized_fk_bba89afff5432da6cd82 ON private.procurement_selections USING btree (rfq_id, operation_id)
- CREATE INDEX specialized_fk_d340554ef0644d27b099 ON private.procurement_selections USING btree (approved_by)
- CREATE INDEX specialized_fk_ebd0f4f60c05113b85da ON private.procurement_selections USING btree (quotation_version_id, supplier_organisation_id)

## private.purchase_orders

Supplier-addressed customer-demand obligations; no payment execution.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| reference | text | yes | ('PO-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| supplier_organisation_id | uuid | yes |  |
| status | text | yes | 'issued'::text |
| revision | integer | yes | 1 |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- purchase_orders_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- purchase_orders_id_operation_id_key: UNIQUE (id, operation_id)
- purchase_orders_id_operation_id_supplier_organisation_id_key: UNIQUE (id, operation_id, supplier_organisation_id)
- purchase_orders_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- purchase_orders_pkey: PRIMARY KEY (id)
- purchase_orders_reference_key: UNIQUE (reference)
- purchase_orders_status_check: CHECK ((status = ANY (ARRAY['issued'::text, 'acknowledged'::text, 'part_received'::text, 'received'::text, 'cancelled'::text, 'closed'::text])))
- purchase_orders_supplier_organisation_id_fkey: FOREIGN KEY (supplier_organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX purchase_orders_id_operation_id_key ON private.purchase_orders USING btree (id, operation_id)
- CREATE UNIQUE INDEX purchase_orders_id_operation_id_supplier_organisation_id_key ON private.purchase_orders USING btree (id, operation_id, supplier_organisation_id)
- CREATE UNIQUE INDEX purchase_orders_pkey ON private.purchase_orders USING btree (id)
- CREATE UNIQUE INDEX purchase_orders_reference_key ON private.purchase_orders USING btree (reference)
- CREATE INDEX specialized_fk_206221f06076b962d452 ON private.purchase_orders USING btree (created_by)
- CREATE INDEX specialized_fk_4235217c96a28ef68e9e ON private.purchase_orders USING btree (operation_id)
- CREATE INDEX specialized_fk_e793bf8424f2fae4d0a1 ON private.purchase_orders USING btree (supplier_organisation_id)

## private.purchase_order_versions

Immutable approved selection and acknowledged terms.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| purchase_order_id | uuid | yes |  |
| selection_id | uuid | yes |  |
| version | integer | yes |  |
| currency_id | uuid | yes |  |
| minor_units | integer | yes |  |
| total | numeric(20,4) | yes |  |
| terms_snapshot | jsonb | yes |  |
| acknowledged_by | uuid | no |  |
| acknowledged_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| supplier_organisation_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- purchase_order_versions_acknowledged_by_fkey: FOREIGN KEY (acknowledged_by) REFERENCES profiles(id) ON DELETE RESTRICT
- purchase_order_versions_check: CHECK (((total >= (0)::numeric) AND (total = round(total, minor_units))))
- purchase_order_versions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- purchase_order_versions_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- purchase_order_versions_id_operation_id_key: UNIQUE (id, operation_id)
- purchase_order_versions_id_operation_id_supplier_organisati_key: UNIQUE (id, operation_id, supplier_organisation_id)
- purchase_order_versions_minor_units_check: CHECK (((minor_units >= 0) AND (minor_units <= 4)))
- purchase_order_versions_pkey: PRIMARY KEY (id)
- purchase_order_versions_purchase_order_id_operation_id_fkey: FOREIGN KEY (purchase_order_id, operation_id) REFERENCES private.purchase_orders(id, operation_id) ON DELETE RESTRICT
- purchase_order_versions_purchase_order_id_operation_id_sup_fkey: FOREIGN KEY (purchase_order_id, operation_id, supplier_organisation_id) REFERENCES private.purchase_orders(id, operation_id, supplier_organisation_id) ON DELETE RESTRICT
- purchase_order_versions_purchase_order_id_version_key: UNIQUE (purchase_order_id, version)
- purchase_order_versions_selection_id_operation_id_fkey: FOREIGN KEY (selection_id, operation_id) REFERENCES private.procurement_selections(id, operation_id) ON DELETE RESTRICT
- purchase_order_versions_selection_id_operation_id_supplier_fkey: FOREIGN KEY (selection_id, operation_id, supplier_organisation_id) REFERENCES private.procurement_selections(id, operation_id, supplier_organisation_id) ON DELETE RESTRICT
- purchase_order_versions_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX procurement_one_po_selection ON private.purchase_order_versions USING btree (selection_id)
- CREATE UNIQUE INDEX purchase_order_versions_id_operation_id_key ON private.purchase_order_versions USING btree (id, operation_id)
- CREATE UNIQUE INDEX purchase_order_versions_id_operation_id_supplier_organisati_key ON private.purchase_order_versions USING btree (id, operation_id, supplier_organisation_id)
- CREATE UNIQUE INDEX purchase_order_versions_pkey ON private.purchase_order_versions USING btree (id)
- CREATE UNIQUE INDEX purchase_order_versions_purchase_order_id_version_key ON private.purchase_order_versions USING btree (purchase_order_id, version)
- CREATE INDEX specialized_fk_235c409fa0905a6d3960 ON private.purchase_order_versions USING btree (currency_id)
- CREATE INDEX specialized_fk_577448058acca62b0b76 ON private.purchase_order_versions USING btree (purchase_order_id, operation_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_7ef0b35692c131c487db ON private.purchase_order_versions USING btree (acknowledged_by)
- CREATE INDEX specialized_fk_af099696a7c05d08461f ON private.purchase_order_versions USING btree (selection_id, operation_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_f5f98dcbd8c83fde4ca0 ON private.purchase_order_versions USING btree (created_by)

## private.purchase_order_lines

Accepted supplier quote item snapshots.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| version_id | uuid | yes |  |
| source_quotation_line_id | uuid | yes |  |
| quantity | numeric(20,4) | yes |  |
| unit | text | yes |  |
| line_total | numeric(20,4) | yes |  |
| specification_snapshot | jsonb | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- purchase_order_lines_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- purchase_order_lines_id_operation_id_key: UNIQUE (id, operation_id)
- purchase_order_lines_id_operation_id_version_id_key: UNIQUE (id, operation_id, version_id)
- purchase_order_lines_line_total_check: CHECK ((line_total >= (0)::numeric))
- purchase_order_lines_pkey: PRIMARY KEY (id)
- purchase_order_lines_quantity_check: CHECK ((quantity > (0)::numeric))
- purchase_order_lines_source_quotation_line_id_fkey: FOREIGN KEY (source_quotation_line_id) REFERENCES private.supplier_quotation_lines(id) ON DELETE RESTRICT
- purchase_order_lines_version_id_operation_id_fkey: FOREIGN KEY (version_id, operation_id) REFERENCES private.purchase_order_versions(id, operation_id) ON DELETE RESTRICT
- purchase_order_lines_version_id_source_quotation_line_id_key: UNIQUE (version_id, source_quotation_line_id)

Indexes:

- CREATE UNIQUE INDEX purchase_order_lines_id_operation_id_key ON private.purchase_order_lines USING btree (id, operation_id)
- CREATE UNIQUE INDEX purchase_order_lines_id_operation_id_version_id_key ON private.purchase_order_lines USING btree (id, operation_id, version_id)
- CREATE UNIQUE INDEX purchase_order_lines_pkey ON private.purchase_order_lines USING btree (id)
- CREATE UNIQUE INDEX purchase_order_lines_version_id_source_quotation_line_id_key ON private.purchase_order_lines USING btree (version_id, source_quotation_line_id)
- CREATE INDEX specialized_fk_3bcfa37fb7c813c67dbd ON private.purchase_order_lines USING btree (created_by)
- CREATE INDEX specialized_fk_483822f90fa025084d4c ON private.purchase_order_lines USING btree (version_id, operation_id)
- CREATE INDEX specialized_fk_9134b5cff1cedc77a43e ON private.purchase_order_lines USING btree (source_quotation_line_id)

## private.procurement_receipts

Supplier declaration and independent actual inspection.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| version_id | uuid | yes |  |
| receiving_task_id | uuid | yes |  |
| shipping_document_id | uuid | yes |  |
| status | text | yes | 'declared'::text |
| inspected_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| declared_at | timestamp with time zone | yes | clock_timestamp() |
| inspected_at | timestamp with time zone | no |  |
| supplier_organisation_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- procurement_receipts_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_receipts_id_operation_id_key: UNIQUE (id, operation_id)
- procurement_receipts_id_operation_id_version_id_key: UNIQUE (id, operation_id, version_id)
- procurement_receipts_id_supplier_organisation_id_key: UNIQUE (id, supplier_organisation_id)
- procurement_receipts_inspected_by_fkey: FOREIGN KEY (inspected_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_receipts_pkey: PRIMARY KEY (id)
- procurement_receipts_receiving_task_id_operation_id_fkey: FOREIGN KEY (receiving_task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- procurement_receipts_shipping_document_id_fkey: FOREIGN KEY (shipping_document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- procurement_receipts_shipping_document_id_supplier_organis_fkey: FOREIGN KEY (shipping_document_id, supplier_organisation_id) REFERENCES private.document_objects(id, organisation_id) ON DELETE RESTRICT
- procurement_receipts_status_check: CHECK ((status = ANY (ARRAY['declared'::text, 'inspected'::text, 'accepted'::text, 'rejected'::text])))
- procurement_receipts_version_id_operation_id_fkey: FOREIGN KEY (version_id, operation_id) REFERENCES private.purchase_order_versions(id, operation_id) ON DELETE RESTRICT
- procurement_receipts_version_id_operation_id_supplier_orga_fkey: FOREIGN KEY (version_id, operation_id, supplier_organisation_id) REFERENCES private.purchase_order_versions(id, operation_id, supplier_organisation_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX procurement_receipt_queue ON private.procurement_receipts USING btree (operation_id, status, id)
- CREATE UNIQUE INDEX procurement_receipts_id_operation_id_key ON private.procurement_receipts USING btree (id, operation_id)
- CREATE UNIQUE INDEX procurement_receipts_id_operation_id_version_id_key ON private.procurement_receipts USING btree (id, operation_id, version_id)
- CREATE UNIQUE INDEX procurement_receipts_id_supplier_organisation_id_key ON private.procurement_receipts USING btree (id, supplier_organisation_id)
- CREATE UNIQUE INDEX procurement_receipts_pkey ON private.procurement_receipts USING btree (id)
- CREATE INDEX specialized_fk_1ea9809a827c326b9b69 ON private.procurement_receipts USING btree (receiving_task_id, operation_id)
- CREATE INDEX specialized_fk_7540be1af09870bc6264 ON private.procurement_receipts USING btree (shipping_document_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_75c9b7ba85510b310cfa ON private.procurement_receipts USING btree (inspected_by)
- CREATE INDEX specialized_fk_9f151ff795c8c48661ef ON private.procurement_receipts USING btree (created_by)
- CREATE INDEX specialized_fk_cab84286c31d72c5caf7 ON private.procurement_receipts USING btree (version_id, operation_id, supplier_organisation_id)

## private.procurement_receipt_lines

Actual accepted/rejected/missing goods quantities.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| receipt_id | uuid | yes |  |
| purchase_order_line_id | uuid | yes |  |
| sent_quantity | numeric(20,4) | yes |  |
| accepted_quantity | numeric(20,4) | no |  |
| rejected_quantity | numeric(20,4) | no |  |
| condition_snapshot | jsonb | yes |  |
| case_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| version_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- procurement_receipt_lines_accepted_quantity_check: CHECK ((accepted_quantity >= (0)::numeric))
- procurement_receipt_lines_case_id_fkey: FOREIGN KEY (case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- procurement_receipt_lines_check: CHECK (((accepted_quantity IS NULL) OR (rejected_quantity IS NULL) OR ((accepted_quantity + rejected_quantity) <= sent_quantity)))
- procurement_receipt_lines_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_receipt_lines_id_operation_id_key: UNIQUE (id, operation_id)
- procurement_receipt_lines_pkey: PRIMARY KEY (id)
- procurement_receipt_lines_purchase_order_line_id_operatio_fkey1: FOREIGN KEY (purchase_order_line_id, operation_id, version_id) REFERENCES private.purchase_order_lines(id, operation_id, version_id) ON DELETE RESTRICT
- procurement_receipt_lines_purchase_order_line_id_operation_fkey: FOREIGN KEY (purchase_order_line_id, operation_id) REFERENCES private.purchase_order_lines(id, operation_id) ON DELETE RESTRICT
- procurement_receipt_lines_receipt_id_operation_id_fkey: FOREIGN KEY (receipt_id, operation_id) REFERENCES private.procurement_receipts(id, operation_id) ON DELETE RESTRICT
- procurement_receipt_lines_receipt_id_operation_id_version__fkey: FOREIGN KEY (receipt_id, operation_id, version_id) REFERENCES private.procurement_receipts(id, operation_id, version_id) ON DELETE RESTRICT
- procurement_receipt_lines_receipt_id_purchase_order_line_id_key: UNIQUE (receipt_id, purchase_order_line_id)
- procurement_receipt_lines_rejected_quantity_check: CHECK ((rejected_quantity >= (0)::numeric))
- procurement_receipt_lines_sent_quantity_check: CHECK ((sent_quantity > (0)::numeric))

Indexes:

- CREATE UNIQUE INDEX procurement_receipt_lines_id_operation_id_key ON private.procurement_receipt_lines USING btree (id, operation_id)
- CREATE UNIQUE INDEX procurement_receipt_lines_pkey ON private.procurement_receipt_lines USING btree (id)
- CREATE UNIQUE INDEX procurement_receipt_lines_receipt_id_purchase_order_line_id_key ON private.procurement_receipt_lines USING btree (receipt_id, purchase_order_line_id)
- CREATE INDEX specialized_fk_3e667b8478e9a2685695 ON private.procurement_receipt_lines USING btree (created_by)
- CREATE INDEX specialized_fk_4a08687b24ef03bfe6bd ON private.procurement_receipt_lines USING btree (purchase_order_line_id, operation_id, version_id)
- CREATE INDEX specialized_fk_ddf62e27ecdbcb94fd86 ON private.procurement_receipt_lines USING btree (case_id)
- CREATE INDEX specialized_fk_e2ff0d883c3602732e45 ON private.procurement_receipt_lines USING btree (receipt_id, operation_id, version_id)

## private.procurement_returns

Actual return sender/receiver acknowledgement and replacement reconciliation.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| receipt_line_id | uuid | yes |  |
| quantity | numeric(20,4) | yes |  |
| case_id | uuid | yes |  |
| evidence_id | uuid | yes |  |
| status | text | yes | 'proposed'::text |
| supplier_received_by | uuid | no |  |
| replacement_receipt_line_id | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| kind | text | yes | 'rejected'::text |
| operation_id | uuid | yes |  |
| order_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- procurement_returns_case_id_fkey: FOREIGN KEY (case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- procurement_returns_case_id_order_id_fkey: FOREIGN KEY (case_id, order_id) REFERENCES private.service_cases(id, order_id) ON DELETE RESTRICT
- procurement_returns_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- procurement_returns_evidence_id_fkey: FOREIGN KEY (evidence_id) REFERENCES private.execution_evidence(id) ON DELETE RESTRICT
- procurement_returns_kind_check: CHECK ((kind = ANY (ARRAY['accepted'::text, 'rejected'::text])))
- procurement_returns_operation_id_order_id_fkey: FOREIGN KEY (operation_id, order_id) REFERENCES private.service_operations(id, primary_order_id) ON DELETE RESTRICT
- procurement_returns_pkey: PRIMARY KEY (id)
- procurement_returns_quantity_check: CHECK ((quantity > (0)::numeric))
- procurement_returns_receipt_line_id_fkey: FOREIGN KEY (receipt_line_id) REFERENCES private.procurement_receipt_lines(id) ON DELETE RESTRICT
- procurement_returns_receipt_line_id_operation_id_fkey: FOREIGN KEY (receipt_line_id, operation_id) REFERENCES private.procurement_receipt_lines(id, operation_id) ON DELETE RESTRICT
- procurement_returns_replacement_receipt_line_id_fkey: FOREIGN KEY (replacement_receipt_line_id) REFERENCES private.procurement_receipt_lines(id) ON DELETE RESTRICT
- procurement_returns_replacement_receipt_line_id_operation__fkey: FOREIGN KEY (replacement_receipt_line_id, operation_id) REFERENCES private.procurement_receipt_lines(id, operation_id) ON DELETE RESTRICT
- procurement_returns_status_check: CHECK ((status = ANY (ARRAY['proposed'::text, 'sent'::text, 'received'::text, 'replaced'::text, 'resolved'::text])))
- procurement_returns_supplier_received_by_fkey: FOREIGN KEY (supplier_received_by) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX procurement_returns_pkey ON private.procurement_returns USING btree (id)
- CREATE INDEX specialized_fk_387770828fa0eb9773c7 ON private.procurement_returns USING btree (case_id, order_id)
- CREATE INDEX specialized_fk_788fcfa59128bbb7236d ON private.procurement_returns USING btree (created_by)
- CREATE INDEX specialized_fk_7bf22c0959dfc987f61f ON private.procurement_returns USING btree (supplier_received_by)
- CREATE INDEX specialized_fk_7f44f1aeb78cc9ee3464 ON private.procurement_returns USING btree (replacement_receipt_line_id, operation_id)
- CREATE INDEX specialized_fk_7fa18e7e7b80908d1c15 ON private.procurement_returns USING btree (evidence_id)
- CREATE INDEX specialized_fk_889d6e0652c0d0b286c0 ON private.procurement_returns USING btree (operation_id, order_id)
- CREATE INDEX specialized_fk_c0ef75116e2cb8584fbe ON private.procurement_returns USING btree (receipt_line_id, operation_id)

## private.supplier_performance_observations

Exactly-once evidenced receipt quality/quantity/timeliness observations.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| supplier_organisation_id | uuid | yes |  |
| receipt_id | uuid | yes |  |
| metric | text | yes |  |
| successful | numeric(20,4) | yes |  |
| observations | numeric(20,4) | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- supplier_performance_observat_receipt_id_supplier_organisa_fkey: FOREIGN KEY (receipt_id, supplier_organisation_id) REFERENCES private.procurement_receipts(id, supplier_organisation_id) ON DELETE RESTRICT
- supplier_performance_observat_supplier_organisation_id_rece_key: UNIQUE (supplier_organisation_id, receipt_id, metric)
- supplier_performance_observations_check: CHECK ((successful <= observations))
- supplier_performance_observations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- supplier_performance_observations_metric_check: CHECK ((metric = ANY (ARRAY['quantity'::text, 'condition'::text, 'timeliness'::text])))
- supplier_performance_observations_observations_check: CHECK ((observations > (0)::numeric))
- supplier_performance_observations_pkey: PRIMARY KEY (id)
- supplier_performance_observations_receipt_id_fkey: FOREIGN KEY (receipt_id) REFERENCES private.procurement_receipts(id) ON DELETE RESTRICT
- supplier_performance_observations_successful_check: CHECK ((successful >= (0)::numeric))
- supplier_performance_observations_supplier_organisation_id_fkey: FOREIGN KEY (supplier_organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX specialized_fk_05bc4a8a5b0ebd39f271 ON private.supplier_performance_observations USING btree (receipt_id, supplier_organisation_id)
- CREATE INDEX specialized_fk_515067604ce4182b192e ON private.supplier_performance_observations USING btree (created_by)
- CREATE UNIQUE INDEX supplier_performance_observat_supplier_organisation_id_rece_key ON private.supplier_performance_observations USING btree (supplier_organisation_id, receipt_id, metric)
- CREATE UNIQUE INDEX supplier_performance_observations_pkey ON private.supplier_performance_observations USING btree (id)

## private.field_campaigns

Corporate scope and independently published shared field form.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| reference | text | yes | ('CAM-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| specification | jsonb | yes |  |
| checklist_id | uuid | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| customer_approved_by | uuid | no |  |
| customer_approved_at | timestamp with time zone | no |  |
| service_version_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- field_campaigns_check: CHECK ((ends_at > starts_at))
- field_campaigns_checklist_id_fkey: FOREIGN KEY (checklist_id) REFERENCES service_checklists(id) ON DELETE RESTRICT
- field_campaigns_checklist_id_service_version_id_fkey: FOREIGN KEY (checklist_id, service_version_id) REFERENCES service_checklists(id, service_version_id) ON DELETE RESTRICT
- field_campaigns_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaigns_customer_approved_by_fkey: FOREIGN KEY (customer_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaigns_id_operation_id_key: UNIQUE (id, operation_id)
- field_campaigns_operation_id_fkey: FOREIGN KEY (operation_id) REFERENCES private.service_operations(id) ON DELETE RESTRICT
- field_campaigns_operation_id_key: UNIQUE (operation_id)
- field_campaigns_operation_id_service_version_id_fkey: FOREIGN KEY (operation_id, service_version_id) REFERENCES private.service_operations(id, service_version_id) ON DELETE RESTRICT
- field_campaigns_pkey: PRIMARY KEY (id)
- field_campaigns_reference_key: UNIQUE (reference)

Indexes:

- CREATE UNIQUE INDEX field_campaigns_id_operation_id_key ON private.field_campaigns USING btree (id, operation_id)
- CREATE UNIQUE INDEX field_campaigns_operation_id_key ON private.field_campaigns USING btree (operation_id)
- CREATE UNIQUE INDEX field_campaigns_pkey ON private.field_campaigns USING btree (id)
- CREATE UNIQUE INDEX field_campaigns_reference_key ON private.field_campaigns USING btree (reference)
- CREATE INDEX specialized_fk_706b683bccfcb7eb147a ON private.field_campaigns USING btree (created_by)
- CREATE INDEX specialized_fk_c1047d9d56fcdd6f4d35 ON private.field_campaigns USING btree (checklist_id, service_version_id)
- CREATE INDEX specialized_fk_d8c227acd0c17e556af2 ON private.field_campaigns USING btree (operation_id, service_version_id)
- CREATE INDEX specialized_fk_f9f4db119e60ab05cb74 ON private.field_campaigns USING btree (customer_approved_by)

## private.field_campaign_locations

Assigned tasks, declared target locations and client-accepted deliverables.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| campaign_id | uuid | yes |  |
| task_id | uuid | yes |  |
| external_reference | text | yes |  |
| status | text | yes | 'pending'::text |
| client_approved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| location_snapshot | jsonb | yes | '{}'::jsonb |
| milestone | text | yes | 'delivery'::text |
| mandatory | boolean | yes | true |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| service_location_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- field_campaign_locations_campaign_id_external_reference_key: UNIQUE (campaign_id, external_reference)
- field_campaign_locations_campaign_id_operation_id_fkey: FOREIGN KEY (campaign_id, operation_id) REFERENCES private.field_campaigns(id, operation_id) ON DELETE RESTRICT
- field_campaign_locations_campaign_id_task_id_key: UNIQUE (campaign_id, task_id)
- field_campaign_locations_client_approved_by_fkey: FOREIGN KEY (client_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaign_locations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaign_locations_id_operation_id_key: UNIQUE (id, operation_id)
- field_campaign_locations_location_snapshot_check: CHECK ((jsonb_typeof(location_snapshot) = 'object'::text))
- field_campaign_locations_operation_id_order_id_customer_ac_fkey: FOREIGN KEY (operation_id, order_id, customer_account_id) REFERENCES private.operation_orders(operation_id, order_id, customer_account_id) ON DELETE RESTRICT
- field_campaign_locations_order_id_customer_account_id_zone_fkey: FOREIGN KEY (order_id, customer_account_id, zone_id, service_location_id) REFERENCES private.service_orders(id, customer_account_id, zone_id, service_location_id) ON DELETE RESTRICT
- field_campaign_locations_pkey: PRIMARY KEY (id)
- field_campaign_locations_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'submitted'::text, 'rework'::text, 'quality_approved'::text, 'client_accepted'::text, 'cancelled'::text])))
- field_campaign_locations_task_id_operation_id_fkey: FOREIGN KEY (task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- field_campaign_locations_task_id_order_id_customer_account_fkey: FOREIGN KEY (task_id, order_id, customer_account_id) REFERENCES private.work_tasks(id, order_id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX field_campaign_locations_campaign_id_external_reference_key ON private.field_campaign_locations USING btree (campaign_id, external_reference)
- CREATE UNIQUE INDEX field_campaign_locations_campaign_id_task_id_key ON private.field_campaign_locations USING btree (campaign_id, task_id)
- CREATE UNIQUE INDEX field_campaign_locations_id_operation_id_key ON private.field_campaign_locations USING btree (id, operation_id)
- CREATE UNIQUE INDEX field_campaign_locations_pkey ON private.field_campaign_locations USING btree (id)
- CREATE INDEX field_location_order_scope ON private.field_campaign_locations USING btree (order_id, customer_account_id, zone_id, service_location_id)
- CREATE INDEX field_location_queue ON private.field_campaign_locations USING btree (operation_id, status, id)
- CREATE INDEX field_location_task_scope ON private.field_campaign_locations USING btree (task_id, order_id, customer_account_id)
- CREATE INDEX specialized_fk_21c7f9e02251bd5b4f5d ON private.field_campaign_locations USING btree (created_by)
- CREATE INDEX specialized_fk_7352c77ac5bd11df989b ON private.field_campaign_locations USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_a047f5801aa0e91accb4 ON private.field_campaign_locations USING btree (client_approved_by)
- CREATE INDEX specialized_fk_d8e28178d6d70cb33542 ON private.field_campaign_locations USING btree (campaign_id, operation_id)

## private.field_campaign_submissions

Versioned shared form references and retained review/quality outcomes.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| operation_id | uuid | yes |  |
| location_id | uuid | yes |  |
| execution_submission_id | uuid | yes |  |
| version | integer | yes |  |
| status | text | yes | 'submitted'::text |
| reviewed_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes |  |
| content_digest | text | yes |  |
| task_id | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- field_campaign_submissions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaign_submissions_execution_round_check: CHECK ((execution_round > 0))
- field_campaign_submissions_execution_submission_id_fkey: FOREIGN KEY (execution_submission_id) REFERENCES private.execution_submissions(id) ON DELETE RESTRICT
- field_campaign_submissions_execution_submission_id_key: UNIQUE (execution_submission_id)
- field_campaign_submissions_execution_submission_id_task_id_fkey: FOREIGN KEY (execution_submission_id, task_id) REFERENCES private.execution_submissions(id, task_id) ON DELETE RESTRICT
- field_campaign_submissions_location_id_execution_round_cont_key: UNIQUE (location_id, execution_round, content_digest)
- field_campaign_submissions_location_id_operation_id_fkey: FOREIGN KEY (location_id, operation_id) REFERENCES private.field_campaign_locations(id, operation_id) ON DELETE RESTRICT
- field_campaign_submissions_location_id_version_key: UNIQUE (location_id, version)
- field_campaign_submissions_pkey: PRIMARY KEY (id)
- field_campaign_submissions_reviewed_by_fkey: FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- field_campaign_submissions_status_check: CHECK ((status = ANY (ARRAY['submitted'::text, 'rejected'::text, 'quality_approved'::text, 'client_accepted'::text])))
- field_campaign_submissions_task_id_operation_id_fkey: FOREIGN KEY (task_id, operation_id) REFERENCES private.operation_tasks(task_id, operation_id) ON DELETE RESTRICT
- field_campaign_submissions_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX field_campaign_submissions_execution_submission_id_key ON private.field_campaign_submissions USING btree (execution_submission_id)
- CREATE UNIQUE INDEX field_campaign_submissions_location_id_execution_round_cont_key ON private.field_campaign_submissions USING btree (location_id, execution_round, content_digest)
- CREATE UNIQUE INDEX field_campaign_submissions_location_id_version_key ON private.field_campaign_submissions USING btree (location_id, version)
- CREATE UNIQUE INDEX field_campaign_submissions_pkey ON private.field_campaign_submissions USING btree (id)
- CREATE INDEX specialized_fk_0cb08b0c399e5601b088 ON private.field_campaign_submissions USING btree (task_id, operation_id)
- CREATE INDEX specialized_fk_7c86ccea5a819f7868ca ON private.field_campaign_submissions USING btree (location_id, operation_id)
- CREATE INDEX specialized_fk_caeded16348b854075e6 ON private.field_campaign_submissions USING btree (created_by)
- CREATE INDEX specialized_fk_e4606bb1a4ee1070297c ON private.field_campaign_submissions USING btree (execution_submission_id, task_id)
- CREATE INDEX specialized_fk_f676b1dec5c9f764f2d7 ON private.field_campaign_submissions USING btree (reviewed_by)

## private.service_orders

Reused order adds composite service/tenant key only.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| reference | text | yes | ('ORD-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| request_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| organisation_id | uuid | no |  |
| branch_id | uuid | no |  |
| department_id | uuid | no |  |
| service_version_id | uuid | yes |  |
| service_location_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| policy_id | uuid | yes |  |
| classification | text | yes |  |
| status | text | yes | 'pending_authorization'::text |
| revision | integer | yes | 1 |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| released_by | uuid | no |  |
| released_revision | integer | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- service_orders_branch_id_customer_account_id_organisation__fkey: FOREIGN KEY (branch_id, customer_account_id, organisation_id) REFERENCES corporate_account_branches(id, customer_account_id, organisation_id) ON DELETE RESTRICT
- service_orders_check: CHECK (((ends_at > starts_at) AND ((ends_at - starts_at) <= '31 days'::interval)))
- service_orders_check1: CHECK (((branch_id IS NULL) OR (organisation_id IS NOT NULL)))
- service_orders_check2: CHECK (((released_by IS NULL) OR (released_by <> created_by)))
- service_orders_classification_check: CHECK ((classification = ANY (ARRAY['individual'::text, 'corporate'::text])))
- service_orders_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_orders_department_id_organisation_id_fkey: FOREIGN KEY (department_id, organisation_id) REFERENCES private.departments(id, organisation_id) ON DELETE RESTRICT
- service_orders_id_customer_account_id_key: UNIQUE (id, customer_account_id)
- service_orders_id_customer_account_id_service_version_id_key: UNIQUE (id, customer_account_id, service_version_id)
- service_orders_id_customer_account_id_zone_id_service_locat_key: UNIQUE (id, customer_account_id, zone_id, service_location_id)
- service_orders_organisation_id_fkey: FOREIGN KEY (organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT
- service_orders_pkey: PRIMARY KEY (id)
- service_orders_policy_id_fkey: FOREIGN KEY (policy_id) REFERENCES private.order_policies(id) ON DELETE RESTRICT
- service_orders_reference_key: UNIQUE (reference)
- service_orders_released_by_fkey: FOREIGN KEY (released_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_orders_request_id_customer_account_id_fkey: FOREIGN KEY (request_id, customer_account_id) REFERENCES service_requests(id, customer_account_id) ON DELETE RESTRICT
- service_orders_revision_check: CHECK ((revision > 0))
- service_orders_service_location_id_customer_account_id_fkey: FOREIGN KEY (service_location_id, customer_account_id) REFERENCES service_locations(id, customer_account_id) ON DELETE RESTRICT
- service_orders_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- service_orders_status_check: CHECK ((status = ANY (ARRAY['pending_authorization'::text, 'awaiting_dispatch'::text, 'assigned'::text, 'on_hold'::text, 'in_progress'::text, 'awaiting_qa'::text, 'awaiting_customer_confirmation'::text, 'customer_disputed'::text, 'completed'::text, 'closed'::text, 'cancelled'::text])))
- service_orders_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX ord_fk_service_orders_05564bc333a9ffd9 ON private.service_orders USING btree (request_id, customer_account_id)
- CREATE INDEX ord_fk_service_orders_0bfa779c86d1256a ON private.service_orders USING btree (service_location_id, customer_account_id)
- CREATE INDEX ord_fk_service_orders_2250d86a0277ee57 ON private.service_orders USING btree (service_version_id)
- CREATE INDEX ord_fk_service_orders_593c81d9e2077f9d ON private.service_orders USING btree (zone_id)
- CREATE INDEX ord_fk_service_orders_5b16039cf7db5267 ON private.service_orders USING btree (policy_id)
- CREATE INDEX ord_fk_service_orders_7c05c5c4989bc0f0 ON private.service_orders USING btree (branch_id, customer_account_id, organisation_id)
- CREATE INDEX ord_fk_service_orders_a1f9fe00b09ec84e ON private.service_orders USING btree (released_by)
- CREATE INDEX ord_fk_service_orders_d24822d95dd9effe ON private.service_orders USING btree (organisation_id)
- CREATE INDEX ord_fk_service_orders_efd995597adeb570 ON private.service_orders USING btree (department_id, organisation_id)
- CREATE INDEX orders_account ON private.service_orders USING btree (customer_account_id, created_at, id)
- CREATE INDEX orders_queue ON private.service_orders USING btree (status, starts_at, id)
- CREATE INDEX service_orders_creator ON private.service_orders USING btree (created_by)
- CREATE UNIQUE INDEX service_orders_id_customer_account_id_key ON private.service_orders USING btree (id, customer_account_id)
- CREATE UNIQUE INDEX service_orders_id_customer_account_id_service_version_id_key ON private.service_orders USING btree (id, customer_account_id, service_version_id)
- CREATE UNIQUE INDEX service_orders_id_customer_account_id_zone_id_service_locat_key ON private.service_orders USING btree (id, customer_account_id, zone_id, service_location_id)
- CREATE UNIQUE INDEX service_orders_pkey ON private.service_orders USING btree (id)
- CREATE UNIQUE INDEX service_orders_reference_key ON private.service_orders USING btree (reference)

## private.order_commercial_versions

Reused immutable accepted commercial versions add order-consistent key.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| quotation_version_id | uuid | yes |  |
| version | integer | yes |  |
| snapshot | jsonb | yes |  |
| currency_id | uuid | yes |  |
| total | numeric(20,4) | yes |  |
| minor_units | integer | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- order_commercial_versions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_commercial_versions_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- order_commercial_versions_id_order_id_key: UNIQUE (id, order_id)
- order_commercial_versions_minor_units_check: CHECK (((minor_units >= 0) AND (minor_units <= 4)))
- order_commercial_versions_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- order_commercial_versions_order_id_version_key: UNIQUE (order_id, version)
- order_commercial_versions_pkey: PRIMARY KEY (id)
- order_commercial_versions_quotation_version_id_fkey: FOREIGN KEY (quotation_version_id) REFERENCES quotation_versions(id) ON DELETE RESTRICT
- order_commercial_versions_quotation_version_id_key: UNIQUE (quotation_version_id)
- order_commercial_versions_snapshot_check: CHECK ((jsonb_typeof(snapshot) = 'object'::text))
- order_commercial_versions_total_check: CHECK ((total >= (0)::numeric))
- order_commercial_versions_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX ord_fk_order_commercial_ver_f385e75846e5e001 ON private.order_commercial_versions USING btree (currency_id)
- CREATE INDEX order_commercial_versions_creator ON private.order_commercial_versions USING btree (created_by)
- CREATE UNIQUE INDEX order_commercial_versions_id_order_id_key ON private.order_commercial_versions USING btree (id, order_id)
- CREATE UNIQUE INDEX order_commercial_versions_order_id_version_key ON private.order_commercial_versions USING btree (order_id, version)
- CREATE UNIQUE INDEX order_commercial_versions_pkey ON private.order_commercial_versions USING btree (id)
- CREATE UNIQUE INDEX order_commercial_versions_quotation_version_id_key ON private.order_commercial_versions USING btree (quotation_version_id)

## private.document_objects

Reused private registry adds organisation-consistent key.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| bucket_id | text | yes |  |
| object_name | text | yes |  |
| customer_account_id | uuid | no |  |
| owner_profile_id | uuid | no |  |
| organisation_id | uuid | no |  |
| uploaded_by | uuid | yes |  |
| classification | text | yes |  |
| content_type | text | yes |  |
| byte_size | bigint | yes |  |
| sha256 | text | no |  |
| scan_status | text | yes | 'pending'::text |
| upload_expires_at | timestamp with time zone | yes | (now() + '01:00:00'::interval) |
| retained_until | timestamp with time zone | no |  |
| legal_hold | boolean | yes | false |
| archived_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | no |  |
| visibility | text | no |  CASE classification     WHEN 'public'::text THEN 'public'::text     WHEN 'customer'::text THEN 'account'::text     WHEN 'identity'::text THEN 'owner'::text     ELSE 'restricted'::text END |

Constraints (including FKs, unique and CHECK):

- document_content_types: CHECK ((content_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'text/plain'::text, 'video/mp4'::text, 'video/webm'::text])))
- document_objects_bucket_id_object_name_key: UNIQUE (bucket_id, object_name)
- document_objects_byte_size_check: CHECK (((byte_size > 0) AND (byte_size <= 20971520)))
- document_objects_check: CHECK ((num_nonnulls(customer_account_id, owner_profile_id, organisation_id) = 1))
- document_objects_check1: CHECK ((((bucket_id = 'identity-documents'::text) AND (classification = 'identity'::text) AND (owner_profile_id IS NOT NULL)) OR ((bucket_id = 'customer-documents'::text) AND (classification = 'customer'::text) AND (customer_account_id IS NOT NULL)) OR ((bucket_id = 'contracts'::text) AND (classification = 'contract'::text)) OR ((bucket_id = 'field-evidence'::text) AND (classification = 'field'::text)) OR ((bucket_id = 'invoices'::text) AND (classification = 'invoice'::text)) OR ((bucket_id = 'employee-documents'::text) AND (classification = 'employee'::text) AND (owner_profile_id IS NOT NULL)) OR ((bucket_id = 'work-evidence'::text) AND (classification = 'work'::text)) OR ((bucket_id = 'marketing-assets'::text) AND (classification = 'public'::text) AND (organisation_id IS NOT NULL))))
- document_objects_classification_check: CHECK ((classification = ANY (ARRAY['customer'::text, 'identity'::text, 'contract'::text, 'field'::text, 'invoice'::text, 'employee'::text, 'work'::text, 'public'::text])))
- document_objects_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- document_objects_customer_account_id_fkey: FOREIGN KEY (customer_account_id) REFERENCES customer_profiles(id) ON DELETE RESTRICT
- document_objects_id_customer_account_id_key: UNIQUE (id, customer_account_id)
- document_objects_id_organisation_id_key: UNIQUE (id, organisation_id)
- document_objects_object_name_check: CHECK (((length(object_name) > 0) AND (object_name !~ '(^/\|(^\|/)\.\.(/\|$))'::text)))
- document_objects_organisation_id_fkey: FOREIGN KEY (organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT
- document_objects_owner_profile_id_fkey: FOREIGN KEY (owner_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT
- document_objects_pkey: PRIMARY KEY (id)
- document_objects_scan_status_check: CHECK ((scan_status = ANY (ARRAY['pending'::text, 'clean'::text, 'rejected'::text])))
- document_objects_sha256_check: CHECK ((sha256 ~ '^[a-f0-9]{64}$'::text))
- document_objects_uploaded_by_fkey: FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE UNIQUE INDEX document_objects_bucket_id_object_name_key ON private.document_objects USING btree (bucket_id, object_name)
- CREATE UNIQUE INDEX document_objects_id_customer_account_id_key ON private.document_objects USING btree (id, customer_account_id)
- CREATE UNIQUE INDEX document_objects_id_organisation_id_key ON private.document_objects USING btree (id, organisation_id)
- CREATE INDEX document_objects_pending_idx ON private.document_objects USING btree (scan_status, created_at) WHERE (scan_status = 'pending'::text)
- CREATE UNIQUE INDEX document_objects_pkey ON private.document_objects USING btree (id)
- CREATE INDEX onit_fk_00f9aba212546f351b409501 ON private.document_objects USING btree (organisation_id)
- CREATE INDEX onit_fk_08ba1b03aff5593de58c8c68 ON private.document_objects USING btree (customer_account_id)
- CREATE INDEX onit_fk_cdb32439d295189820b82884 ON private.document_objects USING btree (owner_profile_id)
- CREATE INDEX onit_fk_e45ed7f71a2364c591bbee71 ON private.document_objects USING btree (uploaded_by)
- CREATE INDEX onit_fk_f3045fa183361e7291bf9969 ON private.document_objects USING btree (created_by)

## private.service_cases

Reused confidential cases add order-consistent key.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| reference | text | yes | ('CASE-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| work_order_id | uuid | no |  |
| task_id | uuid | no |  |
| provider_id | uuid | no |  |
| category | text | yes |  |
| severity | text | yes |  |
| priority | text | yes |  |
| confidential | boolean | yes | false |
| blocking | boolean | yes | true |
| status | text | yes | 'open'::text |
| revision | integer | yes | 1 |
| owner_id | uuid | no |  |
| description | text | yes |  |
| resolution_requirements | jsonb | no |  |
| resolution_proposed_by | uuid | no |  |
| resolved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- service_cases_check: CHECK (((task_id IS NULL) OR (work_order_id IS NOT NULL)))
- service_cases_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_cases_id_order_id_key: UNIQUE (id, order_id)
- service_cases_order_id_customer_account_id_fkey: FOREIGN KEY (order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- service_cases_owner_id_fkey: FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE RESTRICT
- service_cases_pkey: PRIMARY KEY (id)
- service_cases_priority_check: CHECK ((priority = ANY (ARRAY['normal'::text, 'urgent'::text, 'critical'::text])))
- service_cases_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- service_cases_reference_key: UNIQUE (reference)
- service_cases_resolution_proposed_by_fkey: FOREIGN KEY (resolution_proposed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_cases_resolved_by_fkey: FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_cases_severity_check: CHECK ((severity = ANY (ARRAY['minor'::text, 'major'::text, 'critical'::text])))
- service_cases_status_check: CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'investigating'::text, 'escalated'::text, 'resolution_proposed'::text, 'resolved'::text, 'closed'::text])))
- service_cases_task_id_work_order_id_order_id_customer_acco_fkey: FOREIGN KEY (task_id, work_order_id, order_id, customer_account_id) REFERENCES private.work_tasks(id, work_order_id, order_id, customer_account_id) ON DELETE RESTRICT
- service_cases_work_order_id_order_id_customer_account_id_fkey: FOREIGN KEY (work_order_id, order_id, customer_account_id) REFERENCES private.work_orders(id, order_id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_service_cases_3efa82c97d0e70b4 ON private.service_cases USING btree (resolved_by)
- CREATE INDEX exe_fk_service_cases_4bd83127b61bdfa8 ON private.service_cases USING btree (resolution_proposed_by)
- CREATE INDEX exe_fk_service_cases_9da9b4f396f71946 ON private.service_cases USING btree (provider_id)
- CREATE INDEX exe_fk_service_cases_b21b617d62b0131e ON private.service_cases USING btree (task_id, work_order_id, order_id, customer_account_id)
- CREATE INDEX exe_fk_service_cases_c06b7b3c811bca0b ON private.service_cases USING btree (work_order_id, order_id, customer_account_id)
- CREATE INDEX exe_fk_service_cases_d40c40a876fb2871 ON private.service_cases USING btree (owner_id)
- CREATE INDEX service_case_queue ON private.service_cases USING btree (order_id, status, severity, id)
- CREATE INDEX service_cases_creator_idx ON private.service_cases USING btree (created_by)
- CREATE UNIQUE INDEX service_cases_id_order_id_key ON private.service_cases USING btree (id, order_id)
- CREATE UNIQUE INDEX service_cases_pkey ON private.service_cases USING btree (id)
- CREATE UNIQUE INDEX service_cases_reference_key ON private.service_cases USING btree (reference)

## private.execution_submissions

Reused versioned form answers add task-consistent key.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| task_id | uuid | yes |  |
| checklist_id | uuid | yes |  |
| phase | text | yes |  |
| version | integer | yes |  |
| answers | jsonb | yes |  |
| definition_snapshot | jsonb | yes |  |
| task_revision | integer | yes |  |
| status | text | yes | 'draft'::text |
| reviewed_by | uuid | no |  |
| review_reason | text | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes | 1 |

Constraints (including FKs, unique and CHECK):

- execution_submissions_check: CHECK (((reviewed_by IS NULL) OR (reviewed_by <> created_by)))
- execution_submissions_checklist_id_fkey: FOREIGN KEY (checklist_id) REFERENCES service_checklists(id) ON DELETE RESTRICT
- execution_submissions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_submissions_id_task_id_key: UNIQUE (id, task_id)
- execution_submissions_phase_check: CHECK ((phase = ANY (ARRAY['execution'::text, 'quality'::text, 'handover'::text])))
- execution_submissions_pkey: PRIMARY KEY (id)
- execution_submissions_reviewed_by_fkey: FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_submissions_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text])))
- execution_submissions_task_id_fkey: FOREIGN KEY (task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- execution_submissions_task_id_phase_version_key: UNIQUE (task_id, phase, version)
- execution_submissions_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX exe_fk_execution_submission_80241bab2ab930f3 ON private.execution_submissions USING btree (checklist_id)
- CREATE INDEX exe_fk_execution_submission_a0605f5ef156c471 ON private.execution_submissions USING btree (reviewed_by)
- CREATE INDEX execution_submissions_creator_idx ON private.execution_submissions USING btree (created_by)
- CREATE UNIQUE INDEX execution_submissions_id_task_id_key ON private.execution_submissions USING btree (id, task_id)
- CREATE UNIQUE INDEX execution_submissions_pkey ON private.execution_submissions USING btree (id)
- CREATE UNIQUE INDEX execution_submissions_task_id_phase_version_key ON private.execution_submissions USING btree (task_id, phase, version)

## public.service_checklists

Reused published execution/QA form definitions.

Owner: OnIt service operations. Lifecycle: retained; existing public RLS is preserved; work-linked feedback and execution standards use guarded commands. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| service_version_id | uuid | yes |  |
| code | text | yes |  |
| checklist_type | text | yes |  |
| name | text | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | no |  |
| version | integer | yes | 1 |
| publication_status | text | yes | 'draft'::text |
| published_by | uuid | no |  |
| published_at | timestamp with time zone | no |  |

Constraints (including FKs, unique and CHECK):

- service_checklists_checklist_type_check: CHECK ((checklist_type = ANY (ARRAY['assessment'::text, 'execution'::text, 'quality'::text])))
- service_checklists_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_checklists_id_service_version_id_key: UNIQUE (id, service_version_id)
- service_checklists_pkey: PRIMARY KEY (id)
- service_checklists_publication_status_check: CHECK ((publication_status = ANY (ARRAY['draft'::text, 'published'::text, 'retired'::text])))
- service_checklists_published_by_fkey: FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_checklists_service_version_id_code_version_key: UNIQUE (service_version_id, code, version)
- service_checklists_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- service_checklists_version_check: CHECK ((version > 0))

Indexes:

- CREATE UNIQUE INDEX assessment_checklist_code ON public.service_checklists USING btree (service_version_id, code) WHERE (checklist_type = 'assessment'::text)
- CREATE INDEX onit_fk_0eca9d988c89a2bdfe5952fd ON public.service_checklists USING btree (created_by)
- CREATE UNIQUE INDEX service_checklists_id_service_version_id_key ON public.service_checklists USING btree (id, service_version_id)
- CREATE UNIQUE INDEX service_checklists_pkey ON public.service_checklists USING btree (id)
- CREATE UNIQUE INDEX service_checklists_service_version_id_code_version_key ON public.service_checklists USING btree (service_version_id, code, version)
