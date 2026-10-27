# Increment 4 order/dispatch dictionary — local candidate

Generated from the successfully replayed PostgreSQL 17 catalog. The 11 new tables and two reused outbox tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increment-4-report.md). No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.

## private.order_policies

Independently approved effective service-version commercial and matching configuration; no operational defaults.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| service_version_id | uuid | yes |  |
| version | integer | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| payment_gate | text | yes |  |
| offer_seconds | integer | yes |  |
| performance_weight | numeric(8,4) | yes |  |
| workload_weight | numeric(8,4) | yes |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- order_policies_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_policies_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- order_policies_check1: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- order_policies_check2: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- order_policies_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_policies_offer_seconds_check: CHECK (((offer_seconds >= 30) AND (offer_seconds <= 86400)))
- order_policies_payment_gate_check: CHECK ((payment_gate = ANY (ARRAY['payment_required'::text, 'payment_or_credit'::text, 'no_upfront_payment'::text])))
- order_policies_performance_weight_check: CHECK (((performance_weight >= (0)::numeric) AND (performance_weight <= (1000)::numeric)))
- order_policies_pkey: PRIMARY KEY (id)
- order_policies_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- order_policies_service_version_id_version_key: UNIQUE (service_version_id, version)
- order_policies_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- order_policies_version_check: CHECK ((version > 0))
- order_policies_workload_weight_check: CHECK (((workload_weight >= (0)::numeric) AND (workload_weight <= (1000)::numeric)))

Indexes:

- CREATE INDEX ord_fk_order_policies_d48f996b72de691e ON private.order_policies USING btree (approved_by)
- CREATE INDEX order_policies_creator ON private.order_policies USING btree (created_by)
- CREATE UNIQUE INDEX order_policies_pkey ON private.order_policies USING btree (id)
- CREATE UNIQUE INDEX order_policies_service_version_id_version_key ON private.order_policies USING btree (service_version_id, version)

## private.service_orders

Canonical account/branch-owned order and controlled pre-fulfilment state, exact schedule and verified coverage.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

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
- service_orders_status_check: CHECK ((status = ANY (ARRAY['pending_authorization'::text, 'awaiting_dispatch'::text, 'assigned'::text, 'on_hold'::text, 'cancelled'::text])))
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

## private.order_commercial_versions

Append-only accepted quotation links and currency-aware customer commercial snapshots; one order per accepted quote.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

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
- CREATE UNIQUE INDEX order_commercial_versions_order_id_version_key ON private.order_commercial_versions USING btree (order_id, version)
- CREATE UNIQUE INDEX order_commercial_versions_pkey ON private.order_commercial_versions USING btree (id)
- CREATE UNIQUE INDEX order_commercial_versions_quotation_version_id_key ON private.order_commercial_versions USING btree (quotation_version_id)

## private.order_authorizations

Revision-bound independent external payment evidence, corporate terms or commercial exception decisions; not a payment ledger.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| customer_account_id | uuid | yes |  |
| order_revision | integer | yes |  |
| kind | text | yes |  |
| document_id | uuid | yes |  |
| reference | text | yes |  |
| currency_id | uuid | yes |  |
| amount | numeric(20,4) | yes |  |
| valid_until | timestamp with time zone | yes |  |
| status | text | yes | 'pending'::text |
| decided_by | uuid | no |  |
| decided_at | timestamp with time zone | no |  |
| reason | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- order_authorizations_amount_check: CHECK ((amount >= (0)::numeric))
- order_authorizations_check: CHECK (((decided_by IS NULL) OR (decided_by <> created_by)))
- order_authorizations_check1: CHECK (((status = 'pending'::text) = ((decided_by IS NULL) AND (decided_at IS NULL))))
- order_authorizations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_authorizations_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- order_authorizations_decided_by_fkey: FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_authorizations_document_id_customer_account_id_fkey: FOREIGN KEY (document_id, customer_account_id) REFERENCES private.document_objects(id, customer_account_id) ON DELETE RESTRICT
- order_authorizations_kind_check: CHECK ((kind = ANY (ARRAY['payment_evidence'::text, 'corporate_credit'::text, 'exception'::text])))
- order_authorizations_order_id_customer_account_id_fkey: FOREIGN KEY (order_id, customer_account_id) REFERENCES private.service_orders(id, customer_account_id) ON DELETE RESTRICT
- order_authorizations_pkey: PRIMARY KEY (id)
- order_authorizations_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- order_authorizations_reference_check: CHECK (((length(reference) >= 1) AND (length(reference) <= 160)))
- order_authorizations_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))

Indexes:

- CREATE INDEX ord_fk_order_authorizations_5dbdac38eaf8a7ed ON private.order_authorizations USING btree (document_id, customer_account_id)
- CREATE INDEX ord_fk_order_authorizations_7d6637d57fd30651 ON private.order_authorizations USING btree (order_id, customer_account_id)
- CREATE INDEX ord_fk_order_authorizations_c31fbb98ad05d8ea ON private.order_authorizations USING btree (decided_by)
- CREATE INDEX ord_fk_order_authorizations_dbf9b12f85e6f02f ON private.order_authorizations USING btree (currency_id)
- CREATE INDEX order_authorizations_creator ON private.order_authorizations USING btree (created_by)
- CREATE UNIQUE INDEX order_authorizations_pkey ON private.order_authorizations USING btree (id)

## private.order_changes

Customer or staff amendments/rescheduling/cancellation proposals and independent decisions; preserves original intent.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| order_revision | integer | yes |  |
| kind | text | yes |  |
| proposal | jsonb | yes |  |
| status | text | yes | 'pending'::text |
| decided_by | uuid | no |  |
| reason | text | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- order_changes_check: CHECK (((decided_by IS NULL) OR (decided_by <> created_by)))
- order_changes_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_changes_decided_by_fkey: FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- order_changes_kind_check: CHECK ((kind = ANY (ARRAY['reschedule'::text, 'cancel'::text, 'amend'::text])))
- order_changes_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- order_changes_pkey: PRIMARY KEY (id)
- order_changes_proposal_check: CHECK (((jsonb_typeof(proposal) = 'object'::text) AND (octet_length((proposal)::text) <= 8192)))
- order_changes_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- order_changes_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))

Indexes:

- CREATE INDEX ord_fk_order_changes_358811bafd5dbbcd ON private.order_changes USING btree (decided_by)
- CREATE INDEX ord_fk_order_changes_9556d857aca37690 ON private.order_changes USING btree (order_id)
- CREATE INDEX order_changes_creator ON private.order_changes USING btree (created_by)
- CREATE UNIQUE INDEX order_changes_pkey ON private.order_changes USING btree (id)

## private.order_history

Append-only actor/reason/permission/correlation and complete order metadata snapshots for every command.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| order_revision | integer | yes |  |
| action | text | yes |  |
| subject_id | uuid | yes |  |
| previous_state | text | no |  |
| new_state | text | no |  |
| order_snapshot | jsonb | yes |  |
| reason | text | yes |  |
| permission_code | text | yes |  |
| actor_id | uuid | no |  |
| actor_type | text | yes | 'user'::text |
| correlation_id | uuid | yes | gen_random_uuid() |
| created_at | timestamp with time zone | yes | clock_timestamp() |

Constraints (including FKs, unique and CHECK):

- order_history_actor_id_fkey: FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT
- order_history_actor_type_check: CHECK ((actor_type = ANY (ARRAY['user'::text, 'system_worker'::text])))
- order_history_check: CHECK (((actor_id IS NULL) = (actor_type = 'system_worker'::text)))
- order_history_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- order_history_pkey: PRIMARY KEY (id)
- order_history_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))

Indexes:

- CREATE INDEX ord_fk_order_history_a843b364b3519872 ON private.order_history USING btree (actor_id)
- CREATE INDEX order_history_page ON private.order_history USING btree (order_id, created_at DESC, id)
- CREATE UNIQUE INDEX order_history_pkey ON private.order_history USING btree (id)

## private.dispatch_candidates

Append-only explainable eligibility/ranking snapshots tied to the order revision and approved policy.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| order_revision | integer | yes |  |
| provider_id | uuid | yes |  |
| worker_id | uuid | yes |  |
| units | numeric(12,4) | yes |  |
| decision | jsonb | yes |  |
| score | numeric | yes |  |
| policy_id | uuid | yes |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- dispatch_candidates_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- dispatch_candidates_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- dispatch_candidates_pkey: PRIMARY KEY (id)
- dispatch_candidates_policy_id_fkey: FOREIGN KEY (policy_id) REFERENCES private.order_policies(id) ON DELETE RESTRICT
- dispatch_candidates_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- dispatch_candidates_units_check: CHECK ((units > (0)::numeric))
- dispatch_candidates_worker_id_fkey: FOREIGN KEY (worker_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX dispatch_candidate_rank ON private.dispatch_candidates USING btree (order_id, order_revision, score DESC, provider_id, worker_id)
- CREATE INDEX dispatch_candidates_creator ON private.dispatch_candidates USING btree (created_by)
- CREATE UNIQUE INDEX dispatch_candidates_pkey ON private.dispatch_candidates USING btree (id)
- CREATE INDEX ord_fk_dispatch_candidates_1e039ef671f20f1b ON private.dispatch_candidates USING btree (policy_id)
- CREATE INDEX ord_fk_dispatch_candidates_57eef71cdf9acaf8 ON private.dispatch_candidates USING btree (provider_id)
- CREATE INDEX ord_fk_dispatch_candidates_a69914a7072aa89c ON private.dispatch_candidates USING btree (worker_id)

## private.dispatch_proposals

Exclusive all-or-nothing dispatch bundle, expiry, independent manual preference override and confirmation.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| order_revision | integer | yes |  |
| status | text | yes | 'pending'::text |
| expires_at | timestamp with time zone | yes |  |
| override_reason | text | no |  |
| override_by | uuid | no |  |
| confirmed_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- dispatch_proposals_check: CHECK (((override_by IS NULL) OR (override_by <> created_by)))
- dispatch_proposals_confirmed_by_fkey: FOREIGN KEY (confirmed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- dispatch_proposals_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- dispatch_proposals_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- dispatch_proposals_override_by_fkey: FOREIGN KEY (override_by) REFERENCES profiles(id) ON DELETE RESTRICT
- dispatch_proposals_override_reason_check: CHECK (((override_reason IS NULL) OR ((length(override_reason) >= 1) AND (length(override_reason) <= 2000))))
- dispatch_proposals_pkey: PRIMARY KEY (id)
- dispatch_proposals_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'ready'::text, 'confirmed'::text, 'withdrawn'::text, 'expired'::text, 'rejected'::text])))

Indexes:

- CREATE INDEX dispatch_offer_expiry ON private.dispatch_proposals USING btree (expires_at) WHERE (status = ANY (ARRAY['pending'::text, 'ready'::text]))
- CREATE UNIQUE INDEX dispatch_one_live ON private.dispatch_proposals USING btree (order_id) WHERE (status = ANY (ARRAY['pending'::text, 'ready'::text, 'confirmed'::text]))
- CREATE INDEX dispatch_proposals_creator ON private.dispatch_proposals USING btree (created_by)
- CREATE UNIQUE INDEX dispatch_proposals_pkey ON private.dispatch_proposals USING btree (id)
- CREATE INDEX ord_fk_dispatch_proposals_0e7ad9554d9508c7 ON private.dispatch_proposals USING btree (confirmed_by)
- CREATE INDEX ord_fk_dispatch_proposals_cc41b132ed07c09f ON private.dispatch_proposals USING btree (override_by)

## private.assignment_offers

Explicit addressed contractual-provider response; multiple companies may participate in one bundle.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| proposal_id | uuid | yes |  |
| provider_id | uuid | yes |  |
| status | text | yes | 'pending'::text |
| responded_by | uuid | no |  |
| responded_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- assignment_offers_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- assignment_offers_id_provider_id_key: UNIQUE (id, provider_id)
- assignment_offers_pkey: PRIMARY KEY (id)
- assignment_offers_proposal_id_fkey: FOREIGN KEY (proposal_id) REFERENCES private.dispatch_proposals(id) ON DELETE RESTRICT
- assignment_offers_proposal_id_provider_id_key: UNIQUE (proposal_id, provider_id)
- assignment_offers_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- assignment_offers_responded_by_fkey: FOREIGN KEY (responded_by) REFERENCES profiles(id) ON DELETE RESTRICT
- assignment_offers_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text, 'withdrawn'::text, 'expired'::text])))

Indexes:

- CREATE INDEX assignment_offers_creator ON private.assignment_offers USING btree (created_by)
- CREATE UNIQUE INDEX assignment_offers_id_provider_id_key ON private.assignment_offers USING btree (id, provider_id)
- CREATE UNIQUE INDEX assignment_offers_pkey ON private.assignment_offers USING btree (id)
- CREATE UNIQUE INDEX assignment_offers_proposal_id_provider_id_key ON private.assignment_offers USING btree (proposal_id, provider_id)
- CREATE INDEX offer_provider_page ON private.assignment_offers USING btree (provider_id, status, id)
- CREATE INDEX ord_fk_assignment_offers_293e83d17b632753 ON private.assignment_offers USING btree (responded_by)

## private.assignment_resources

Immutable executing-person and existing provider/human reservation links; not a second capacity system.

Owner: OnIt service operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

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

Constraints (including FKs, unique and CHECK):

- assignment_resources_candidate_id_fkey: FOREIGN KEY (candidate_id) REFERENCES private.dispatch_candidates(id) ON DELETE RESTRICT
- assignment_resources_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- assignment_resources_offer_id_provider_id_fkey: FOREIGN KEY (offer_id, provider_id) REFERENCES private.assignment_offers(id, provider_id) ON DELETE RESTRICT
- assignment_resources_offer_id_worker_id_key: UNIQUE (offer_id, worker_id)
- assignment_resources_pkey: PRIMARY KEY (id)
- assignment_resources_reservation_id_fkey: FOREIGN KEY (reservation_id) REFERENCES private.provider_capacity_reservations(id) ON DELETE RESTRICT
- assignment_resources_reservation_id_key: UNIQUE (reservation_id)
- assignment_resources_worker_id_fkey: FOREIGN KEY (worker_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX assignment_resources_creator ON private.assignment_resources USING btree (created_by)
- CREATE UNIQUE INDEX assignment_resources_offer_id_worker_id_key ON private.assignment_resources USING btree (offer_id, worker_id)
- CREATE UNIQUE INDEX assignment_resources_pkey ON private.assignment_resources USING btree (id)
- CREATE UNIQUE INDEX assignment_resources_reservation_id_key ON private.assignment_resources USING btree (reservation_id)
- CREATE INDEX ord_fk_assignment_resources_074b327246510aa6 ON private.assignment_resources USING btree (worker_id)
- CREATE INDEX ord_fk_assignment_resources_4a71ecf9a0a1d713 ON private.assignment_resources USING btree (candidate_id)
- CREATE INDEX ord_fk_assignment_resources_7e0dc6a7e87b3000 ON private.assignment_resources USING btree (offer_id, provider_id)

## private.dispatch_escalations

Restricted dispatch failures/exceptions and authorised resolution history.

Owner: OnIt service operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| order_id | uuid | yes |  |
| reason | text | yes |  |
| resolved_at | timestamp with time zone | no |  |
| resolved_by | uuid | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- dispatch_escalations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- dispatch_escalations_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- dispatch_escalations_pkey: PRIMARY KEY (id)
- dispatch_escalations_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- dispatch_escalations_resolved_by_fkey: FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX dispatch_escalations_creator ON private.dispatch_escalations USING btree (created_by)
- CREATE UNIQUE INDEX dispatch_escalations_pkey ON private.dispatch_escalations USING btree (id)
- CREATE INDEX ord_fk_dispatch_escalations_7a2591793977c14b ON private.dispatch_escalations USING btree (order_id)
- CREATE INDEX ord_fk_dispatch_escalations_ed08a4c47df9f420 ON private.dispatch_escalations USING btree (resolved_by)

## private.operational_events

Existing append-only outbox, extended with a typed order FK and provider-or-order domain constraint.

Owner: OnIt platform operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | no |  |
| event_code | text | yes |  |
| subject_id | uuid | yes |  |
| correlation_id | uuid | yes |  |
| created_at | timestamp with time zone | yes | clock_timestamp() |
| order_id | uuid | no |  |

Constraints (including FKs, unique and CHECK):

- operational_event_domain: CHECK (((provider_id IS NOT NULL) OR (order_id IS NOT NULL)))
- operational_events_order_id_fkey: FOREIGN KEY (order_id) REFERENCES private.service_orders(id) ON DELETE RESTRICT
- operational_events_pkey: PRIMARY KEY (id)
- operational_events_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX operational_events_cc1d9398d1_fk ON private.operational_events USING btree (provider_id)
- CREATE UNIQUE INDEX operational_events_pkey ON private.operational_events USING btree (id)
- CREATE INDEX order_event_lookup ON private.operational_events USING btree (order_id, created_at, id)

## private.operational_event_deliveries

Existing lease/retry receipts, extended with explicit system-generated provenance and nullable creator only for system rows.

Owner: OnIt platform operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| event_id | uuid | yes |  |
| status | text | yes | 'pending'::text |
| attempts | integer | yes | 0 |
| available_at | timestamp with time zone | yes | now() |
| lease_until | timestamp with time zone | no |  |
| lease_token | uuid | no |  |
| processed_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | no |  |
| last_failure_code | text | no |  |
| last_receipt_token | uuid | no |  |
| last_receipt_action | text | no |  |
| last_receipt_hash | text | no |  |
| system_generated | boolean | yes | false |

Constraints (including FKs, unique and CHECK):

- event_delivery_creator: CHECK (((created_by IS NOT NULL) OR system_generated))
- operational_event_deliveries_attempts_check: CHECK ((attempts >= 0))
- operational_event_deliveries_check: CHECK (((status = 'leased'::text) = ((lease_until IS NOT NULL) AND (lease_token IS NOT NULL))))
- operational_event_deliveries_check1: CHECK (((status = 'processed'::text) = (processed_at IS NOT NULL)))
- operational_event_deliveries_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operational_event_deliveries_event_id_fkey: FOREIGN KEY (event_id) REFERENCES private.operational_events(id) ON DELETE RESTRICT
- operational_event_deliveries_event_id_key: UNIQUE (event_id)
- operational_event_deliveries_last_failure_code_check: CHECK ((last_failure_code ~ '^[A-Z0-9_]{1,80}$'::text))
- operational_event_deliveries_last_receipt_action_check: CHECK ((last_receipt_action = ANY (ARRAY['ack'::text, 'retry'::text])))
- operational_event_deliveries_pkey: PRIMARY KEY (id)
- operational_event_deliveries_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'leased'::text, 'processed'::text, 'dead'::text])))

Indexes:

- CREATE INDEX operational_event_claim ON private.operational_event_deliveries USING btree (status, available_at, lease_until)
- CREATE INDEX operational_event_deliveries_1743c77633_fk ON private.operational_event_deliveries USING btree (created_by)
- CREATE UNIQUE INDEX operational_event_deliveries_event_id_key ON private.operational_event_deliveries USING btree (event_id)
- CREATE UNIQUE INDEX operational_event_deliveries_pkey ON private.operational_event_deliveries USING btree (id)
