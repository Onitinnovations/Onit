# Increment 5 fulfilment dictionary — local candidate

Generated from the successfully replayed PostgreSQL 17 catalog. The 16 new tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increment-5-report.md). Six reused tables are also documented; existing public feedback access retains its original RLS. No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.

## private.fulfilment_policies

Independent versioned execution, checklist and SLA configuration.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| service_version_id | uuid | yes |  |
| customer_account_id | uuid | no |  |
| contract_reference | text | no |  |
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

- approved_execution_policy_checker: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- fulfilment_policies_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- fulfilment_policies_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- fulfilment_policies_check1: CHECK (((contract_reference IS NULL) OR (customer_account_id IS NOT NULL)))
- fulfilment_policies_check2: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- fulfilment_policies_configuration_check: CHECK (((jsonb_typeof(configuration) = 'object'::text) AND (octet_length((configuration)::text) <= 65536)))
- fulfilment_policies_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- fulfilment_policies_customer_account_id_fkey: FOREIGN KEY (customer_account_id) REFERENCES customer_profiles(id) ON DELETE RESTRICT
- fulfilment_policies_pkey: PRIMARY KEY (id)
- fulfilment_policies_service_version_id_customer_account_id__key: UNIQUE NULLS NOT DISTINCT (service_version_id, customer_account_id, contract_reference, version)
- fulfilment_policies_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- fulfilment_policies_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- fulfilment_policies_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX exe_fk_fulfilment_policies_01e05021b8e07870 ON private.fulfilment_policies USING btree (approved_by)
- CREATE INDEX exe_fk_fulfilment_policies_99d1fe2d49230cdb ON private.fulfilment_policies USING btree (customer_account_id)
- CREATE INDEX fulfilment_policies_creator_idx ON private.fulfilment_policies USING btree (created_by)
- CREATE UNIQUE INDEX fulfilment_policies_pkey ON private.fulfilment_policies USING btree (id)
- CREATE UNIQUE INDEX fulfilment_policies_service_version_id_customer_account_id__key ON private.fulfilment_policies USING btree (service_version_id, customer_account_id, contract_reference, version) NULLS NOT DISTINCT

## private.work_orders

Confirmed-bundle work scope and supervision.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| reference | text | yes | ('WO-'::text \|\| upper(replace((gen_random_uuid())::text, '-'::text, ''::text))) |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| proposal_id | uuid | yes |  |
| policy_id | uuid | yes |  |
| code | text | yes |  |
| scope_snapshot | jsonb | yes |  |
| instructions | text | yes | ''::text |
| supervisor_id | uuid | yes |  |
| owner_id | uuid | yes |  |
| priority | text | yes |  |
| status | text | yes | 'awaiting_mobilisation'::text |
| revision | integer | yes | 1 |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| completed_at | timestamp with time zone | no |  |
| closed_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| plan_revision | integer | yes | 1 |
| paused_from | text | no |  |

Constraints (including FKs, unique and CHECK):

- execution_work_states: CHECK ((status = ANY (ARRAY['awaiting_mobilisation'::text, 'in_progress'::text, 'work_completed'::text, 'awaiting_qa'::text, 'rework_required'::text, 'qa_approved'::text, 'awaiting_customer_confirmation'::text, 'customer_disputed'::text, 'completed'::text, 'closed'::text, 'cancelled'::text, 'suspended'::text])))
- work_orders_check: CHECK ((ends_at > starts_at))
- work_orders_code_check: CHECK (((length(code) >= 1) AND (length(code) <= 80)))
- work_orders_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- work_orders_id_order_id_customer_account_id_key: UNIQUE (id, order_id, customer_account_id)
- work_orders_instructions_check: CHECK ((length(instructions) <= 8000))
- work_orders_order_id_code_key: UNIQUE (order_id, code)
- work_orders_order_id_customer_account_id_fkey: FOREIGN KEY (order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- work_orders_owner_id_fkey: FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE RESTRICT
- work_orders_pkey: PRIMARY KEY (id)
- work_orders_policy_id_fkey: FOREIGN KEY (policy_id) REFERENCES private.fulfilment_policies(id) ON DELETE RESTRICT
- work_orders_priority_check: CHECK ((priority = ANY (ARRAY['normal'::text, 'urgent'::text, 'critical'::text])))
- work_orders_proposal_id_fkey: FOREIGN KEY (proposal_id) REFERENCES private.dispatch_proposals(id) ON DELETE RESTRICT
- work_orders_reference_key: UNIQUE (reference)
- work_orders_revision_check: CHECK ((revision > 0))
- work_orders_supervisor_id_fkey: FOREIGN KEY (supervisor_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_work_orders_5e0c41471272454c ON private.work_orders USING btree (policy_id)
- CREATE INDEX exe_fk_work_orders_be1494a43275df08 ON private.work_orders USING btree (owner_id)
- CREATE INDEX exe_fk_work_orders_f70cda5e570dc66b ON private.work_orders USING btree (proposal_id)
- CREATE INDEX exe_fk_work_orders_fd947dbf22a900b0 ON private.work_orders USING btree (supervisor_id)
- CREATE INDEX execution_work_queue ON private.work_orders USING btree (status, starts_at, id)
- CREATE INDEX work_orders_creator_idx ON private.work_orders USING btree (created_by)
- CREATE UNIQUE INDEX work_orders_id_order_id_customer_account_id_key ON private.work_orders USING btree (id, order_id, customer_account_id)
- CREATE UNIQUE INDEX work_orders_order_id_code_key ON private.work_orders USING btree (order_id, code)
- CREATE UNIQUE INDEX work_orders_pkey ON private.work_orders USING btree (id)
- CREATE UNIQUE INDEX work_orders_reference_key ON private.work_orders USING btree (reference)

## private.work_tasks

Assigned personnel tasks, dependencies, rounds and schedules.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| work_order_id | uuid | yes |  |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| parent_task_id | uuid | no |  |
| resource_id | uuid | yes |  |
| code | text | yes |  |
| description | text | yes |  |
| mandatory | boolean | yes | true |
| status | text | yes | 'awaiting_mobilisation'::text |
| revision | integer | yes | 1 |
| accepted_at | timestamp with time zone | no |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| actual_start | timestamp with time zone | no |  |
| actual_finish | timestamp with time zone | no |  |
| supervisor_verified_by | uuid | no |  |
| completion_actor | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes | 1 |
| is_container | boolean | yes | false |

Constraints (including FKs, unique and CHECK):

- execution_task_states: CHECK ((status = ANY (ARRAY['awaiting_mobilisation'::text, 'awaiting_capacity'::text, 'mobilising'::text, 'en_route'::text, 'arrived'::text, 'awaiting_customer_access'::text, 'started'::text, 'in_progress'::text, 'paused'::text, 'awaiting_materials'::text, 'awaiting_customer_decision'::text, 'work_completed'::text, 'awaiting_qa'::text, 'qa_rejected'::text, 'rework_required'::text, 'qa_approved'::text, 'closed'::text, 'cancelled'::text])))
- work_tasks_check: CHECK (((parent_task_id IS NULL) OR (parent_task_id <> id)))
- work_tasks_check1: CHECK ((ends_at > starts_at))
- work_tasks_completion_actor_fkey: FOREIGN KEY (completion_actor) REFERENCES profiles(id) ON DELETE RESTRICT
- work_tasks_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- work_tasks_description_check: CHECK (((length(description) >= 1) AND (length(description) <= 4000)))
- work_tasks_execution_round_check: CHECK ((execution_round > 0))
- work_tasks_id_work_order_id_key: UNIQUE (id, work_order_id)
- work_tasks_id_work_order_id_order_id_customer_account_id_key: UNIQUE (id, work_order_id, order_id, customer_account_id)
- work_tasks_parent_task_id_work_order_id_fkey: FOREIGN KEY (parent_task_id, work_order_id) REFERENCES private.work_tasks(id, work_order_id) ON DELETE RESTRICT
- work_tasks_pkey: PRIMARY KEY (id)
- work_tasks_resource_id_fkey: FOREIGN KEY (resource_id) REFERENCES private.assignment_resources(id) ON DELETE RESTRICT
- work_tasks_revision_check: CHECK ((revision > 0))
- work_tasks_supervisor_verified_by_fkey: FOREIGN KEY (supervisor_verified_by) REFERENCES profiles(id) ON DELETE RESTRICT
- work_tasks_work_order_id_code_key: UNIQUE (work_order_id, code)
- work_tasks_work_order_id_order_id_customer_account_id_fkey: FOREIGN KEY (work_order_id, order_id, customer_account_id) REFERENCES private.work_orders(id, order_id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_work_tasks_4da6fd0ce1e2873c ON private.work_tasks USING btree (supervisor_verified_by)
- CREATE INDEX exe_fk_work_tasks_928834b888c13e3a ON private.work_tasks USING btree (resource_id)
- CREATE INDEX exe_fk_work_tasks_ab0f099dd4545558 ON private.work_tasks USING btree (parent_task_id, work_order_id)
- CREATE INDEX exe_fk_work_tasks_fd2ac22f77301184 ON private.work_tasks USING btree (completion_actor)
- CREATE INDEX execution_task_queue ON private.work_tasks USING btree (work_order_id, status, id)
- CREATE INDEX work_tasks_creator_idx ON private.work_tasks USING btree (created_by)
- CREATE UNIQUE INDEX work_tasks_id_work_order_id_key ON private.work_tasks USING btree (id, work_order_id)
- CREATE UNIQUE INDEX work_tasks_id_work_order_id_order_id_customer_account_id_key ON private.work_tasks USING btree (id, work_order_id, order_id, customer_account_id)
- CREATE UNIQUE INDEX work_tasks_pkey ON private.work_tasks USING btree (id)
- CREATE UNIQUE INDEX work_tasks_work_order_id_code_key ON private.work_tasks USING btree (work_order_id, code)

## private.task_dependencies

Same-work acyclic task dependencies.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| task_id | uuid | yes |  |
| depends_on_id | uuid | yes |  |
| work_order_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- task_dependencies_check: CHECK ((task_id <> depends_on_id))
- task_dependencies_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- task_dependencies_depends_on_id_work_order_id_fkey: FOREIGN KEY (depends_on_id, work_order_id) REFERENCES private.work_tasks(id, work_order_id) ON DELETE RESTRICT
- task_dependencies_pkey: PRIMARY KEY (id)
- task_dependencies_task_id_depends_on_id_key: UNIQUE (task_id, depends_on_id)
- task_dependencies_task_id_work_order_id_fkey: FOREIGN KEY (task_id, work_order_id) REFERENCES private.work_tasks(id, work_order_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_task_dependencies_d34182961b5419b8 ON private.task_dependencies USING btree (depends_on_id, work_order_id)
- CREATE INDEX task_dependencies_creator_idx ON private.task_dependencies USING btree (created_by)
- CREATE UNIQUE INDEX task_dependencies_pkey ON private.task_dependencies USING btree (id)
- CREATE UNIQUE INDEX task_dependencies_task_id_depends_on_id_key ON private.task_dependencies USING btree (task_id, depends_on_id)

## private.execution_history

Append-only actor, system provenance, revisions and snapshots.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| work_order_id | uuid | no |  |
| task_id | uuid | no |  |
| action | text | yes |  |
| subject_id | uuid | yes |  |
| previous_state | text | no |  |
| new_state | text | no |  |
| revision | integer | no |  |
| details | jsonb | yes | '{}'::jsonb |
| reason | text | yes |  |
| actor_id | uuid | no |  |
| actor_type | text | yes | 'user'::text |
| permission_code | text | yes |  |
| correlation_id | uuid | yes | gen_random_uuid() |
| created_at | timestamp with time zone | yes | clock_timestamp() |

Constraints (including FKs, unique and CHECK):

- execution_history_actor_id_fkey: FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_history_actor_type_check: CHECK ((actor_type = ANY (ARRAY['user'::text, 'system_worker'::text])))
- execution_history_check: CHECK (((actor_id IS NULL) = (actor_type = 'system_worker'::text)))
- execution_history_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- execution_history_pkey: PRIMARY KEY (id)
- execution_history_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- execution_history_task_id_fkey: FOREIGN KEY (task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- execution_history_work_order_id_fkey: FOREIGN KEY (work_order_id) REFERENCES private.work_orders(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_execution_history_00eef4535023f31f ON private.execution_history USING btree (order_id)
- CREATE INDEX exe_fk_execution_history_39975c7e7b5c51bb ON private.execution_history USING btree (task_id)
- CREATE INDEX exe_fk_execution_history_8293022526227079 ON private.execution_history USING btree (actor_id)
- CREATE INDEX execution_history_page ON private.execution_history USING btree (work_order_id, created_at DESC, id)
- CREATE UNIQUE INDEX execution_history_pkey ON private.execution_history USING btree (id)

## private.execution_attendance

Declared attendance and separate independent acknowledgements.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| task_id | uuid | yes |  |
| worker_id | uuid | yes |  |
| kind | text | yes |  |
| occurred_at | timestamp with time zone | yes |  |
| declared_latitude | numeric(9,6) | no |  |
| declared_longitude | numeric(9,6) | no |  |
| verifies_id | uuid | no |  |
| reason | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes | 1 |

Constraints (including FKs, unique and CHECK):

- execution_attendance_check: CHECK ((num_nonnulls(declared_latitude, declared_longitude) = ANY (ARRAY[0, 2])))
- execution_attendance_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_attendance_declared_latitude_check: CHECK (((declared_latitude >= ('-90'::integer)::numeric) AND (declared_latitude <= (90)::numeric)))
- execution_attendance_declared_longitude_check: CHECK (((declared_longitude >= ('-180'::integer)::numeric) AND (declared_longitude <= (180)::numeric)))
- execution_attendance_kind_check: CHECK ((kind = ANY (ARRAY['mobilisation'::text, 'departure'::text, 'arrival'::text, 'check_in'::text, 'check_out'::text, 'no_show'::text, 'late'::text, 'missed_appointment'::text, 'access_problem'::text, 'interruption'::text, 'discrepancy'::text, 'supervisor_acknowledgement'::text])))
- execution_attendance_pkey: PRIMARY KEY (id)
- execution_attendance_task_id_fkey: FOREIGN KEY (task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- execution_attendance_verifies_id_fkey: FOREIGN KEY (verifies_id) REFERENCES private.execution_attendance(id) ON DELETE RESTRICT
- execution_attendance_worker_id_fkey: FOREIGN KEY (worker_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_execution_attendance_0839bfd43187504b ON private.execution_attendance USING btree (worker_id)
- CREATE INDEX exe_fk_execution_attendance_4d9050e3c90cfdca ON private.execution_attendance USING btree (task_id)
- CREATE INDEX execution_attendance_creator_idx ON private.execution_attendance USING btree (created_by)
- CREATE UNIQUE INDEX execution_attendance_pkey ON private.execution_attendance USING btree (id)
- CREATE UNIQUE INDEX verified_attendance_once ON private.execution_attendance USING btree (verifies_id) WHERE (verifies_id IS NOT NULL)

## private.execution_evidence

Private account-consistent registry linkage and independent review.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| task_id | uuid | yes |  |
| work_order_id | uuid | yes |  |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| document_id | uuid | yes |  |
| classification | text | yes |  |
| task_revision | integer | yes |  |
| status | text | yes | 'pending'::text |
| reviewed_by | uuid | no |  |
| reviewed_at | timestamp with time zone | no |  |
| review_reason | text | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes | 1 |
| customer_visible | boolean | yes | false |

Constraints (including FKs, unique and CHECK):

- execution_evidence_check: CHECK (((reviewed_by IS NULL) OR (reviewed_by <> created_by)))
- execution_evidence_classification_check: CHECK (((length(classification) >= 1) AND (length(classification) <= 60)))
- execution_evidence_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_evidence_document_id_customer_account_id_fkey: FOREIGN KEY (document_id, customer_account_id) REFERENCES private.document_objects(id, customer_account_id) ON DELETE RESTRICT
- execution_evidence_pkey: PRIMARY KEY (id)
- execution_evidence_reviewed_by_fkey: FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- execution_evidence_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
- execution_evidence_task_id_document_id_key: UNIQUE (task_id, document_id)
- execution_evidence_task_id_work_order_id_order_id_customer_fkey: FOREIGN KEY (task_id, work_order_id, order_id, customer_account_id) REFERENCES private.work_tasks(id, work_order_id, order_id, customer_account_id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_execution_evidence_804f09df443a30ec ON private.execution_evidence USING btree (document_id, customer_account_id)
- CREATE INDEX exe_fk_execution_evidence_d77135f25337ceaf ON private.execution_evidence USING btree (reviewed_by)
- CREATE INDEX execution_evidence_creator_idx ON private.execution_evidence USING btree (created_by)
- CREATE UNIQUE INDEX execution_evidence_pkey ON private.execution_evidence USING btree (id)
- CREATE INDEX execution_evidence_round ON private.execution_evidence USING btree (task_id, execution_round, status)
- CREATE UNIQUE INDEX execution_evidence_task_id_document_id_key ON private.execution_evidence USING btree (task_id, document_id)

## private.execution_submissions

Existing checklist definitions and versioned answers.

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
- CREATE UNIQUE INDEX execution_submissions_pkey ON private.execution_submissions USING btree (id)
- CREATE UNIQUE INDEX execution_submissions_task_id_phase_version_key ON private.execution_submissions USING btree (task_id, phase, version)

## private.quality_inspections

Independent scheduled inspection and retained outcome.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| task_id | uuid | yes |  |
| version | integer | yes |  |
| inspector_id | uuid | yes |  |
| scheduled_at | timestamp with time zone | yes |  |
| status | text | yes | 'requested'::text |
| submission_id | uuid | no |  |
| decided_by | uuid | no |  |
| decision_reason | text | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| execution_round | integer | yes | 1 |

Constraints (including FKs, unique and CHECK):

- quality_inspections_check: CHECK (((decided_by IS NULL) OR ((decided_by <> inspector_id) AND (decided_by <> created_by))))
- quality_inspections_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- quality_inspections_decided_by_fkey: FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- quality_inspections_inspector_id_fkey: FOREIGN KEY (inspector_id) REFERENCES profiles(id) ON DELETE RESTRICT
- quality_inspections_pkey: PRIMARY KEY (id)
- quality_inspections_status_check: CHECK ((status = ANY (ARRAY['requested'::text, 'submitted'::text, 'approved'::text, 'rejected'::text, 'conditional'::text])))
- quality_inspections_submission_id_fkey: FOREIGN KEY (submission_id) REFERENCES private.execution_submissions(id) ON DELETE RESTRICT
- quality_inspections_task_id_fkey: FOREIGN KEY (task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- quality_inspections_task_id_version_key: UNIQUE (task_id, version)
- quality_inspections_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX exe_fk_quality_inspections_13a59cb229f9f5b5 ON private.quality_inspections USING btree (decided_by)
- CREATE INDEX exe_fk_quality_inspections_c322d250b2eb4ec5 ON private.quality_inspections USING btree (inspector_id)
- CREATE INDEX exe_fk_quality_inspections_dfa32eed9a2b4e98 ON private.quality_inspections USING btree (submission_id)
- CREATE UNIQUE INDEX one_live_inspection ON private.quality_inspections USING btree (task_id, execution_round) WHERE (status = ANY (ARRAY['requested'::text, 'submitted'::text]))
- CREATE INDEX quality_inspections_creator_idx ON private.quality_inspections USING btree (created_by)
- CREATE UNIQUE INDEX quality_inspections_pkey ON private.quality_inspections USING btree (id)
- CREATE UNIQUE INDEX quality_inspections_task_id_version_key ON private.quality_inspections USING btree (task_id, version)

## private.quality_findings

Immutable evidenced defects and corrective requirements.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| inspection_id | uuid | yes |  |
| code | text | yes |  |
| severity | text | yes |  |
| description | text | yes |  |
| corrective_action | text | yes |  |
| blocking | boolean | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- quality_findings_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- quality_findings_inspection_id_fkey: FOREIGN KEY (inspection_id) REFERENCES private.quality_inspections(id) ON DELETE RESTRICT
- quality_findings_pkey: PRIMARY KEY (id)
- quality_findings_severity_check: CHECK ((severity = ANY (ARRAY['minor'::text, 'major'::text, 'critical'::text])))

Indexes:

- CREATE INDEX exe_fk_quality_findings_afb4521e4f504c99 ON private.quality_findings USING btree (inspection_id)
- CREATE INDEX quality_findings_creator_idx ON private.quality_findings USING btree (created_by)
- CREATE UNIQUE INDEX quality_findings_pkey ON private.quality_findings USING btree (id)

## private.rework_requests

Original defect, corrective task and retained resolution.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| finding_id | uuid | yes |  |
| original_task_id | uuid | yes |  |
| rework_task_id | uuid | yes |  |
| due_at | timestamp with time zone | yes |  |
| status | text | yes | 'active'::text |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- rework_requests_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- rework_requests_finding_id_fkey: FOREIGN KEY (finding_id) REFERENCES private.quality_findings(id) ON DELETE RESTRICT
- rework_requests_original_task_id_fkey: FOREIGN KEY (original_task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- rework_requests_pkey: PRIMARY KEY (id)
- rework_requests_rework_task_id_fkey: FOREIGN KEY (rework_task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- rework_requests_rework_task_id_key: UNIQUE (rework_task_id)
- rework_requests_status_check: CHECK ((status = ANY (ARRAY['active'::text, 'accepted'::text, 'cancelled'::text])))

Indexes:

- CREATE INDEX exe_fk_rework_requests_d92b80834986e72f ON private.rework_requests USING btree (original_task_id)
- CREATE UNIQUE INDEX one_unresolved_defect_rework ON private.rework_requests USING btree (finding_id) WHERE (status = 'active'::text)
- CREATE INDEX rework_requests_creator_idx ON private.rework_requests USING btree (created_by)
- CREATE UNIQUE INDEX rework_requests_pkey ON private.rework_requests USING btree (id)
- CREATE UNIQUE INDEX rework_requests_rework_task_id_key ON private.rework_requests USING btree (rework_task_id)

## private.service_cases

Restricted customer or operational case lifecycle.

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
- CREATE UNIQUE INDEX service_cases_pkey ON private.service_cases USING btree (id)
- CREATE UNIQUE INDEX service_cases_reference_key ON private.service_cases USING btree (reference)

## private.service_case_entries

Append-only investigation and communication evidence.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| case_id | uuid | yes |  |
| kind | text | yes |  |
| document_id | uuid | no |  |
| visibility | text | yes |  |
| content | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- service_case_entries_case_id_fkey: FOREIGN KEY (case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- service_case_entries_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_case_entries_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- service_case_entries_kind_check: CHECK ((kind = ANY (ARRAY['evidence'::text, 'investigation'::text, 'finding'::text, 'corrective_action'::text, 'communication'::text, 'escalation'::text, 'resolution'::text, 'reopen'::text, 'note'::text])))
- service_case_entries_pkey: PRIMARY KEY (id)
- service_case_entries_visibility_check: CHECK ((visibility = ANY (ARRAY['internal'::text, 'customer'::text])))

Indexes:

- CREATE INDEX exe_fk_service_case_entries_456a0838f155e711 ON private.service_case_entries USING btree (case_id)
- CREATE INDEX exe_fk_service_case_entries_cae675fa49cc7f22 ON private.service_case_entries USING btree (document_id)
- CREATE INDEX service_case_entries_creator_idx ON private.service_case_entries USING btree (created_by)
- CREATE UNIQUE INDEX service_case_entries_pkey ON private.service_case_entries USING btree (id)

## private.customer_confirmations

Current-plan customer decision and sign-off.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| work_order_id | uuid | yes |  |
| work_revision | integer | yes |  |
| decision | text | yes |  |
| document_id | uuid | no |  |
| comment | text | yes | ''::text |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- customer_confirmations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- customer_confirmations_decision_check: CHECK ((decision = ANY (ARRAY['confirmed'::text, 'disputed'::text])))
- customer_confirmations_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- customer_confirmations_pkey: PRIMARY KEY (id)
- customer_confirmations_work_order_id_fkey: FOREIGN KEY (work_order_id) REFERENCES private.work_orders(id) ON DELETE RESTRICT
- customer_confirmations_work_order_id_work_revision_key: UNIQUE (work_order_id, work_revision)

Indexes:

- CREATE INDEX customer_confirmations_creator_idx ON private.customer_confirmations USING btree (created_by)
- CREATE UNIQUE INDEX customer_confirmations_pkey ON private.customer_confirmations USING btree (id)
- CREATE UNIQUE INDEX customer_confirmations_work_order_id_work_revision_key ON private.customer_confirmations USING btree (work_order_id, work_revision)
- CREATE INDEX exe_fk_customer_confirmatio_b48bc748d7ad7599 ON private.customer_confirmations USING btree (document_id)

## private.operational_exceptions

Independent revision-bound operational exceptions.

Owner: OnIt platform operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| work_order_id | uuid | yes |  |
| work_revision | integer | yes |  |
| kind | text | yes |  |
| proposal | jsonb | yes |  |
| status | text | yes | 'pending'::text |
| decided_by | uuid | no |  |
| reason | text | yes |  |
| valid_until | timestamp with time zone | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- operational_exceptions_check: CHECK (((decided_by IS NULL) OR (decided_by <> created_by)))
- operational_exceptions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operational_exceptions_decided_by_fkey: FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operational_exceptions_kind_check: CHECK ((kind = ANY (ARRAY['substitution'::text, 'sla_extension'::text, 'partial_completion'::text, 'closure_without_confirmation'::text, 'cancel_work'::text])))
- operational_exceptions_pkey: PRIMARY KEY (id)
- operational_exceptions_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'consumed'::text])))
- operational_exceptions_work_order_id_fkey: FOREIGN KEY (work_order_id) REFERENCES private.work_orders(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_operational_exceptio_a3258e66742b1d09 ON private.operational_exceptions USING btree (work_order_id)
- CREATE INDEX exe_fk_operational_exceptio_ddbfc71e53d03c0e ON private.operational_exceptions USING btree (decided_by)
- CREATE INDEX operational_exceptions_creator_idx ON private.operational_exceptions USING btree (created_by)
- CREATE UNIQUE INDEX operational_exceptions_pkey ON private.operational_exceptions USING btree (id)

## private.sla_tracks

Explicit due times, pauses and immutable breach event linkage.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| work_order_id | uuid | no |  |
| task_id | uuid | no |  |
| case_id | uuid | no |  |
| target | text | yes |  |
| source_event_id | uuid | yes |  |
| due_at | timestamp with time zone | yes |  |
| status | text | yes | 'running'::text |
| remaining | interval | no |  |
| breached_at | timestamp with time zone | no |  |
| created_by | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- sla_tracks_case_id_fkey: FOREIGN KEY (case_id) REFERENCES private.service_cases(id) ON DELETE RESTRICT
- sla_tracks_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- sla_tracks_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- sla_tracks_pkey: PRIMARY KEY (id)
- sla_tracks_source_event_id_fkey: FOREIGN KEY (source_event_id) REFERENCES private.execution_history(id) ON DELETE RESTRICT
- sla_tracks_source_event_id_target_task_id_case_id_key: UNIQUE NULLS NOT DISTINCT (source_event_id, target, task_id, case_id)
- sla_tracks_status_check: CHECK ((status = ANY (ARRAY['running'::text, 'paused'::text, 'met'::text, 'breached'::text])))
- sla_tracks_task_id_fkey: FOREIGN KEY (task_id) REFERENCES private.work_tasks(id) ON DELETE RESTRICT
- sla_tracks_work_order_id_fkey: FOREIGN KEY (work_order_id) REFERENCES private.work_orders(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX exe_fk_sla_tracks_08aad6e5d78ea69e ON private.sla_tracks USING btree (order_id)
- CREATE INDEX exe_fk_sla_tracks_3258679ed60280e8 ON private.sla_tracks USING btree (task_id)
- CREATE INDEX exe_fk_sla_tracks_9cc1171989029c0c ON private.sla_tracks USING btree (case_id)
- CREATE INDEX exe_fk_sla_tracks_dcc897b316122723 ON private.sla_tracks USING btree (work_order_id)
- CREATE INDEX execution_sla_due ON private.sla_tracks USING btree (status, due_at, id)
- CREATE INDEX sla_tracks_creator_idx ON private.sla_tracks USING btree (created_by)
- CREATE UNIQUE INDEX sla_tracks_pkey ON private.sla_tracks USING btree (id)
- CREATE UNIQUE INDEX sla_tracks_source_event_id_target_task_id_case_id_key ON private.sla_tracks USING btree (source_event_id, target, task_id, case_id) NULLS NOT DISTINCT

## public.service_checklists

Reused independently published execution/quality checklist versions; assessment semantics preserved.

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

## public.service_checklist_items

Reused fields with typed answers, choices, validation, conditions and evidence requirements.

Owner: OnIt service operations. Lifecycle: retained; existing public RLS is preserved; work-linked feedback and execution standards use guarded commands. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| checklist_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| item_key | text | yes |  |
| label | text | yes |  |
| required | boolean | yes | true |
| position | integer | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | no |  |
| field_type | text | yes | 'boolean'::text |
| choices | jsonb | yes | '[]'::jsonb |
| validation | jsonb | yes | '{}'::jsonb |
| condition | jsonb | no |  |
| evidence_required | boolean | yes | false |

Constraints (including FKs, unique and CHECK):

- service_checklist_items_checklist_id_item_key_key: UNIQUE (checklist_id, item_key)
- service_checklist_items_checklist_id_position_key: UNIQUE (checklist_id, "position")
- service_checklist_items_checklist_id_service_version_id_fkey: FOREIGN KEY (checklist_id, service_version_id) REFERENCES service_checklists(id, service_version_id) ON DELETE RESTRICT
- service_checklist_items_choices_check: CHECK (((jsonb_typeof(choices) = 'array'::text) AND (jsonb_array_length(choices) <= 100)))
- service_checklist_items_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- service_checklist_items_field_type_check: CHECK ((field_type = ANY (ARRAY['boolean'::text, 'text'::text, 'number'::text, 'single_choice'::text, 'multiple_choice'::text])))
- service_checklist_items_pkey: PRIMARY KEY (id)
- service_checklist_items_position_check: CHECK (("position" >= 0))
- service_checklist_items_validation_check: CHECK ((jsonb_typeof(validation) = 'object'::text))

Indexes:

- CREATE INDEX onit_fk_e46c4f518d7acc04368eb791 ON public.service_checklist_items USING btree (checklist_id, service_version_id)
- CREATE INDEX onit_fk_e746a2154a1ce02b5735d6e0 ON public.service_checklist_items USING btree (created_by)
- CREATE UNIQUE INDEX service_checklist_items_checklist_id_item_key_key ON public.service_checklist_items USING btree (checklist_id, item_key)
- CREATE UNIQUE INDEX service_checklist_items_checklist_id_position_key ON public.service_checklist_items USING btree (checklist_id, "position")
- CREATE UNIQUE INDEX service_checklist_items_pkey ON public.service_checklist_items USING btree (id)

## public.customer_feedback

Reused customer feedback with append-only linked work revision chains.

Owner: OnIt service operations. Lifecycle: retained; existing public RLS is preserved; work-linked feedback and execution standards use guarded commands. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| customer_account_id | uuid | yes |  |
| rating | integer | yes |  |
| comment | text | no |  |
| created_at | timestamp with time zone | yes | now() |
| created_by | uuid | no |  |
| order_id | uuid | no |  |
| work_order_id | uuid | no |  |
| revision | integer | no |  |
| previous_id | uuid | no |  |

Constraints (including FKs, unique and CHECK):

- customer_feedback_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- customer_feedback_customer_account_id_fkey: FOREIGN KEY (customer_account_id) REFERENCES customer_profiles(id) ON DELETE RESTRICT
- customer_feedback_order_id_customer_account_id_fkey: FOREIGN KEY (order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- customer_feedback_pkey: PRIMARY KEY (id)
- customer_feedback_previous_id_fkey: FOREIGN KEY (previous_id) REFERENCES customer_feedback(id) ON DELETE RESTRICT
- customer_feedback_rating_check: CHECK (((rating >= 1) AND (rating <= 5)))
- customer_feedback_work_order_id_order_id_customer_account__fkey: FOREIGN KEY (work_order_id, order_id, customer_account_id) REFERENCES private.work_orders(id, order_id, customer_account_id) ON DELETE RESTRICT
- customer_feedback_work_order_id_revision_key: UNIQUE (work_order_id, revision)
- feedback_execution_revision: CHECK ((((order_id IS NULL) AND (work_order_id IS NULL) AND (revision IS NULL)) OR ((order_id IS NOT NULL) AND (work_order_id IS NOT NULL) AND (revision > 0))))

Indexes:

- CREATE UNIQUE INDEX customer_feedback_pkey ON public.customer_feedback USING btree (id)
- CREATE UNIQUE INDEX customer_feedback_work_order_id_revision_key ON public.customer_feedback USING btree (work_order_id, revision)
- CREATE INDEX onit_fk_1d234bff9507a31415eedaec ON public.customer_feedback USING btree (customer_account_id)
- CREATE INDEX onit_fk_ea15f91c947cce5ad8b0e1b8 ON public.customer_feedback USING btree (created_by)

## private.service_orders

Existing order gains controlled execution and closure states.

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
- CREATE UNIQUE INDEX service_orders_pkey ON private.service_orders USING btree (id)
- CREATE UNIQUE INDEX service_orders_reference_key ON private.service_orders USING btree (reference)

## private.assignment_resources

Existing dispatch resource history gains substitution version identity.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| offer_id | uuid | yes |  |
| provider_id | uuid | yes |  |
| worker_id | uuid | yes |  |
| reservation_id | uuid | yes |  |
| candidate_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| resource_version | integer | yes | 1 |

Constraints (including FKs, unique and CHECK):

- assignment_resources_candidate_id_fkey: FOREIGN KEY (candidate_id) REFERENCES private.dispatch_candidates(id) ON DELETE RESTRICT
- assignment_resources_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- assignment_resources_offer_id_provider_id_fkey: FOREIGN KEY (offer_id, provider_id) REFERENCES private.assignment_offers(id, provider_id) ON DELETE RESTRICT
- assignment_resources_offer_id_worker_id_resource_version_key: UNIQUE (offer_id, worker_id, resource_version)
- assignment_resources_pkey: PRIMARY KEY (id)
- assignment_resources_reservation_id_fkey: FOREIGN KEY (reservation_id) REFERENCES private.provider_capacity_reservations(id) ON DELETE RESTRICT
- assignment_resources_reservation_id_key: UNIQUE (reservation_id)
- assignment_resources_worker_id_fkey: FOREIGN KEY (worker_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX assignment_resources_creator ON private.assignment_resources USING btree (created_by)
- CREATE UNIQUE INDEX assignment_resources_offer_id_worker_id_resource_version_key ON private.assignment_resources USING btree (offer_id, worker_id, resource_version)
- CREATE UNIQUE INDEX assignment_resources_pkey ON private.assignment_resources USING btree (id)
- CREATE UNIQUE INDEX assignment_resources_reservation_id_key ON private.assignment_resources USING btree (reservation_id)
- CREATE INDEX ord_fk_assignment_resources_074b327246510aa6 ON private.assignment_resources USING btree (worker_id)
- CREATE INDEX ord_fk_assignment_resources_4a71ecf9a0a1d713 ON private.assignment_resources USING btree (candidate_id)
- CREATE INDEX ord_fk_assignment_resources_7e0dc6a7e87b3000 ON private.assignment_resources USING btree (offer_id, provider_id)

## private.provider_performance_events

Existing immutable observations accept unique verified execution source events.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| metric | text | yes |  |
| successful | integer | yes |  |
| observations | integer | yes |  |
| source_reference | text | yes |  |
| document_id | uuid | no |  |
| occurred_at | timestamp with time zone | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |
| source_event_id | uuid | no |  |

Constraints (including FKs, unique and CHECK):

- performance_evidence_source: CHECK (((document_id IS NOT NULL) OR (source_event_id IS NOT NULL)))
- provider_performance_events_check: CHECK (((observations > 0) AND (observations >= successful)))
- provider_performance_events_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_performance_events_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- provider_performance_events_metric_check: CHECK ((metric = ANY (ARRAY['acceptance'::text, 'completion'::text, 'timeliness'::text, 'quality'::text, 'reliability'::text])))
- provider_performance_events_pkey: PRIMARY KEY (id)
- provider_performance_events_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_performance_events_provider_id_metric_source_event_key: UNIQUE (provider_id, metric, source_event_id)
- provider_performance_events_provider_id_metric_source_refer_key: UNIQUE (provider_id, metric, source_reference)
- provider_performance_events_source_event_id_fkey: FOREIGN KEY (source_event_id) REFERENCES private.execution_history(id) ON DELETE RESTRICT
- provider_performance_events_source_reference_check: CHECK (((length(source_reference) >= 1) AND (length(source_reference) <= 160)))
- provider_performance_events_successful_check: CHECK ((successful >= 0))

Indexes:

- CREATE INDEX provider_performance_events_12103c561d_fk ON private.provider_performance_events USING btree (document_id)
- CREATE INDEX provider_performance_events_d070d2c7ef_fk ON private.provider_performance_events USING btree (created_by)
- CREATE UNIQUE INDEX provider_performance_events_pkey ON private.provider_performance_events USING btree (id)
- CREATE UNIQUE INDEX provider_performance_events_provider_id_metric_source_event_key ON private.provider_performance_events USING btree (provider_id, metric, source_event_id)
- CREATE UNIQUE INDEX provider_performance_events_provider_id_metric_source_refer_key ON private.provider_performance_events USING btree (provider_id, metric, source_reference)
