> Current hosted status (2026-10-26): Phase 2 Increments 1 and 2 deployed to OnIt; 17 migrations and 93 RLS tables verified. Canonical hosted types and application checks passed. Authenticated workflow HTTP tests remain outstanding. See [release checkpoint](phase-2-hosted-deployment-report.md). Earlier local-only statements below are historical.

# Proposed schema inventory and requirements mapping

Current delta: [Phase 2 Increment 1 dictionary](phase-2-schema.md) maps ten local request/quotation tables, and [Increment 2 addendum](phase-2-increment-2-schema.md) adds four private assessment/commercial tables plus shared pricing extensions. Hosted Phase 1 remains79 tables; local candidate is93. [Latest execution report](phase-2-increment-2-report.md) distinguishes delivered pricing/assessments from future provider/dispatch/fulfilment work. Later inventory rows remain capability plans.

Status: proposed, subject to review and remote-schema reconciliation. Table names below are proposed base tables unless identified as views/consolidations. A comma-separated list denotes separate tables, not a JSON document. This is a capability-level inventory; full column-by-column dictionary and executable policy definitions follow approved migrations.

Implementation update: **79 foundation tables** now exist in twelve ordered migrations and are described with actual columns, FKs, uniqueness, indexes, grants and RLS in [data-dictionary.md](data-dictionary.md). The full platform inventory below remains a capability checklist, not a claim that later domains are implemented. [phase-1-report.md](phase-1-report.md) is the current execution record; older status sections are historical.

Implemented refinements: `service_booking_forms`, `service_booking_schemas`, `service_booking_field_groups`, `service_booking_field_dependencies`, `service_booking_field_validation_rules`, `corporate_account_branches`, `corporate_account_user_branches`, `corporate_billing_profiles`, and `corporate_credit_terms`, plus service pricing modes, geography status, scoped staff helpers and audited configuration approval. Corporate credit is configuration only; there are no balances, credit authorizers or invoice workflows. Responsibility/custody and CMS typed links remain later-phase design commitments. Docker failure blocks full Supabase validation and deployment, not the local SQL development explicitly authorised in the latest task.

## Dictionary contract

Every eventual dictionary entry must specify qualified schema/table, purpose, data owner, primary key, columns/types/nullability/defaults, all FKs and ON DELETE actions, unique/check/exclusion constraints, indexes and query intent, RLS policy names per SQL action and actor, column grants/RPC mutation paths, versioning, retention/archive/reversal lifecycle and classification. Immutable projections/views must identify the source and invoker semantics. The following owner/policy/lifecycle codes make the proposed inventory reviewable before SQL exists:

| Code | Owner and policy scope | Lifecycle |
| --- | --- | --- |
| ID | Identity/access administrators; user sees only own neutral profile/preferences; staff directory private | Revoke/archive; Auth erasure handled by reviewed retention workflow. |
| REF | Operations/catalogue administrators; only approved published subset anonymously readable | Stable unique code; deactivate/version, RESTRICT historical references. |
| C | Customer account plus explicitly scoped staff; active corporate membership where applicable | Mutable drafts, submitted history retained, customer-visible flag for shared output. |
| OPS | Permission-scoped operations staff; customer/provider sees only approved projection or owned task | Transition functions, archive on closure, immutable history. |
| P | Provider subject/organisation plus scoped network staff; sensitive checks restricted to verifiers | Version qualifications, expire/revoke eligibility, retain signed agreements. |
| S | Supplier organisation plus procurement staff; own addressed commercial records only | Draft/submitted versions; approved history retained. |
| F | Finance staff and trusted posting workers; subject-specific redacted statements only | Posted records append-only; explicit reversals and open-period controls. |
| H | HR/payroll permissions; narrowly authorized employee self-service projection | Retention-controlled confidential records; independent approvals. |
| E | Editorial/marketing permissions; only published/scheduled-visible approved output public | Draft/review/publish/archive; consent/version history retained. |
| G | Governance/security administrators or scoped workers; subject access only through reviewed DTOs | Append-only events, configured retention and legal holds. |

All base tables receive UUID PKs except explicit shared-PK extensions; mutable tables receive audit timestamps/actor. Owner/parent FKs and indexes are mandatory. Unique scope keys mentioned below supplement those defaults. Deny-by-default RLS applies even where a row has no external reader. Polymorphic audit subject references are informational only and never confer access. Operational links require real FKs or typed bridges.

## 1. Identity, organisations and access — ID/G

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `profiles` | Shared PK to `auth.users`; display name, lifecycle. No privilege-bearing client-editable metadata. |
| `organisations`, `organisation_members`, `organisation_locations` | Legal/business entities, memberships and sites; members FK organisation/profile, unique active pair; locations unique organisation/location code. Organisation type does not itself grant permissions. |
| `departments`, `teams`, **`team_members`** | Organisation-scoped hierarchy and explicit team membership; unique scoped codes and membership pairs. Department/team FKs must match organisation. |
| `roles`, `permissions`, `role_permissions`, `user_role_assignments` | Unique permission/role codes, unique role-permission pair, typed scoped assignments with validity. Grants restricted to access administration. |
| `user_preferences`, `user_devices`, `user_sessions_metadata` | Profile-owned settings; unique profile/device installation; sessions reference Auth session identifier as metadata, no copied credentials/tokens or independent authentication. |
| `audit_logs`, `activity_events` | Audit is immutable security history; activity is a separately redacted user-facing feed. Actor/tenant/time indexes; audited actions never rely on activity visibility. |
| `approval_policies`, `approval_requests`, `approval_steps` | Versioned policy/thresholds, routed requests, ordered independent decisions; unique request/step sequence. Typed workflow links enforce target FKs; no unchecked target UUID approval. |
| `notification_preferences` | Profile/channel/event preferences, unique profile/channel/event/scope; distinct from legal marketing consent. |

## 2. Geography and coverage — REF/C

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `countries`, **`currencies`**, `states`, `cities`, `local_government_areas` | Country/currency codes unique; scoped state/city/LGA codes. City and LGA are not assumed to form an exhaustive single-parent geographic hierarchy; crosslinks must have matching state/country. |
| `service_zones`, `zone_boundaries_or_coverage` | Operational zone and versioned city/LGA/validated geographic coverage. Distinguish operational coverage from official administrative data; enforce exactly one coverage representation per row. PostGIS optional only after need/availability verified. |
| `service_locations`, `customer_addresses` | Immutable/versioned service location snapshots and account-owned address-book records; country/state consistency; orders reference location snapshots. Coordinates constrained numeric values; confidential. |
| `provider_coverage_areas`, `zone_transport_rates`, `city_service_availability` | Unique provider/zone; approved currency/rate effective interval; unique service/city/effective version. Transport rates remain unpriced in seed. |

## 3. Customer and CRM — C/private OPS

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `customer_profiles`, `corporate_accounts`, `corporate_account_users` | Canonical customer account, exactly one individual or organisation owner; corporate shared-PK extension, account approval/credit status; account/user permission grants require active organisation membership. |
| `customer_contacts`, `leads`, `lead_activities`, `opportunities` | Contacts by account; internal lead pipeline, timestamped activities and conversion links to real accounts/requests. Lead PII never public. |
| `customer_segments`, **`customer_segment_assignments`** | Segment definitions and account membership; unique segment/account. Saved rules versioned, do not bypass account RLS. |
| `customer_notes`, `customer_tags`, `customer_tag_assignments` | Private CRM notes and scoped tags; unique account/tag assignment. Customers cannot read internal notes. |
| `support_tickets`, `support_messages`, `customer_feedback` | Account/order linked support; message sender/visibility and chronology; customer reads customer-visible messages only, feedback authored by linked customer. |
| `customer_consents`, `communication_preferences` | Purpose/legal-basis/version/evidence/withdrawal; separate operational channel choices unique account/contact/channel/purpose. Consent history append-only. |
| `customer_documents` | Typed account/document-object links and classification; unique account/document/purpose as applicable. |
| `saved_addresses` → `customer_addresses` | Consolidate into one canonical account-owned address table; saved/default labels are columns. Compatibility view only if an existing client needs the old name. |

## 4. Catalogue and configuration — REF

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `service_areas`, `service_families`, `services`, `service_variants` | Stable unique slugs/codes within parent; service area -> family -> service -> variant. Family/variant inheritance validated. |
| `service_versions`, `service_options`, `service_option_values` | Immutable published versions; unique service/version; version-owned options and unique option/value code. Historical selections FK versioned values. |
| `service_requirements`, `service_booking_fields`, `service_booking_field_options` | Versioned eligibility/intake schema; unique version/field key and field/option code; type/value checks at request submission. |
| `service_checklists`, `service_checklist_items` | Versioned execution/QA checklist definitions; unique checklist/version/item key and ordered positions. |
| `service_pricing_rules`, `service_rate_cards` | Versioned scoped pricing inputs, approval, currency, effective dates and configurable payment gates; immutable accepted transaction snapshots. |
| `service_availability`, `service_exclusions` | Version/zone/capacity windows and explicit constraints; no seed assertion of availability. City availability handles city-level gate, zones handle finer coverage. |
| `service_media`, `service_faqs` | Ordered approved media-object links and service-specific FAQ associations; reusable FAQ content from `faq_entries`. |
| `configurable_system_settings` → `system_configurations` | One versioned typed settings registry; service-scoped keys allowed. Secrets excluded; no generic table that can override permissions. |

## 5. Requests, quotations and orders — C/OPS

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `service_requests`, `request_answers` | Account/service-version/location/request status; answers reference the exact booking field version, unique request/field/repeat index. |
| `site_assessments`, `assessment_evidence` | Request, assigned assessor and versioned findings; evidence links registry objects and assessment. |
| `quotations`, `quotation_versions`, `quotation_line_items`, `quotation_approvals` | Stable quote header, immutable submitted numbered versions, version-owned quantity/price/currency/tax snapshots; approval links canonical approval request and exact version. |
| `orders`, `order_items` | Accepted quote version/account/payment-policy snapshot; unique request acceptance/idempotency reference; item service version and line snapshots. Multiple orders per request require explicit scope partition. |
| `order_status_history`, `order_milestones`, `order_schedules` | Append-only transitions; configurable ordered milestone definitions; versioned service windows. |
| `order_instructions`, `order_attachments`, `order_notes` | Explicit customer-visible versus private content; typed document links. Notes cannot leak dispatch or pricing internals. |
| `order_change_requests`, `order_cancellations` | Approved delta scope/quote versions, cancellation reason/financial effect; no rewriting the accepted commercial record. |
| `recurring_service_plans`, `recurring_service_occurrences` | Timezone-aware recurrence, unique plan/scheduled occurrence, independently linked request/order and idempotent generation. |
| `service_contracts`, `service_contract_milestones`, **`client_engagements`** | Versioned client terms and configurable deliverables; explicit account-owned engagement root for BFS and long-running work, contracts linked to engagement. |

## 6. Provider network — P/private OPS/F

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `provider_profiles`, **`provider_members`**, `provider_categories` | Provider business/person subject, independent Service Associate/Field Agent classification; approved profile access via typed member link, unique provider/profile membership. Category definitions do not imply employment. |
| `provider_skills`, `provider_certifications`, `provider_documents`, `provider_verification_checks` | Skills/qualifications with validity, confidential identity document-object links and verifier-only checks. Unique external certificate issuer/reference where available. |
| `provider_training_courses`, `provider_training_enrolments`, `provider_assessments` | Versioned curriculum, unique provider/course/version enrollment, assessment attempts and outcomes. |
| `provider_availability`, `provider_capacity`, `provider_service_eligibility` | Provider/time windows, capacity units/version, unique provider/service/version qualification state. Capacity locks participate in assignment acceptance. |
| `provider_performance_metrics`, `provider_incidents`, `provider_restrictions` | Periodic computed metrics unique provider/period/metric; incident findings and effective restrictions scoped to service/zone. Internal scoring private. |
| `provider_agreements` | Signed version/effective dates and document-object FK; historical terms retained. |
| `provider_bank_accounts_metadata` → `bank_accounts_metadata` + typed provider link | Central masked/token-reference bank registry, explicit owner links; avoid duplicate bank stores. Full account information only in approved payment vault when required. |
| `provider_earnings`, `provider_earning_adjustments`, `provider_settlements` | Assignment-earned entitlements, append-only approved adjustments, grouped settlements with journal/payout references. Add **`provider_settlement_items`** to allocate earnings and prevent duplicate settlement. |

## 7. Dispatch and delivery — OPS/P/C

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `dispatch_requests`, **`order_work_packages`**, `dispatch_candidates` | Explicit order-item work units; OnIt-created dispatch rounds/candidate scoring, unique dispatch/provider. Candidate scores staff-only. |
| `assignment_offers`, `assignments` | Recipient/provider, dispatch work package, expiration and predecessor assignment; unique accepted offer and partial unique active assignment/work package. |
| `assignment_status_history`, `assignment_acceptances` | Immutable transition/acceptance evidence, one acceptance/offer; provider can only accept addressed valid offer through locked RPC. |
| `service_execution_steps`, `execution_checklist_responses`, `work_evidence` | Assignment/checklist-version progress, unique execution step/item/attempt; file-object references; task-scoped provider write. |
| `quality_inspections`, `quality_findings`, `quality_decisions`, `rework_requests` | Independent inspector, findings, signed decision and linked rework cycle; decisions immutable with superseding decisions. |
| `service_incidents`, `customer_complaints`, `complaint_resolutions` | Assignment/order safety events versus customer complaints and approved resolutions. Provider incidents record network disciplinary consequences and link originating event. |
| `logistics_jobs`, `logistics_stops`, `logistics_events`, `custody_transfers`, `delivery_proofs` | Order-linked route, ordered stops/events, from/to custodian and proof document-object/signature metadata. Immutable handover chronology and unique job/stop sequence. |

## 8. Laundry — OPS/C

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `laundry_orders`, `laundry_order_items`, `laundry_item_categories` | Shared order/order-item extensions, category reference and counts/special instructions. Service name is Laundry. |
| `laundry_bags`, `laundry_pickups`, `laundry_intake_counts`, `laundry_item_tags` | Unique bag/tag codes, logistics pickup link, independent expected/received/reconciled counts; discrepancies require explicit resolution. |
| `laundry_processing_partners`, `laundry_processing_batches`, `laundry_batch_items` | Approved supplier-backed processing partners, allocation batches and quantity/item allocations with conservation checks; item cannot be double allocated. |
| `laundry_processing_stages`, `laundry_quality_checks`, `laundry_packaging` | Configurable batch stage history, checks and package records referencing actual tags/bags. |
| `laundry_handover_events`, `laundry_delivery_records` | Typed extensions/links to shared custody transfers and delivery proofs; no second independent custody journal. |
| `laundry_discrepancies` | Count/damage/loss incident, linked intake/batch/custody record and approved resolution; retained history. |

## 9. Cleaning, maintenance and construction — OPS/C

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `property_profiles`, `property_rooms` | Account-owned property/service location and room inventory, unique property/room code. |
| `cleaning_job_scopes`, `cleaning_scope_items`, `cleaning_material_requirements` | Order-item scope/version, room/tasks, inventory-item quantities; preserve accepted scope. |
| `maintenance_job_details`, `equipment_details`, `fault_diagnostics` | Order-item details; customer equipment distinct from OnIt-owned assets; diagnostic attempts/evidence and approved remedy. |
| `construction_projects`, `project_sites`, `project_scopes`, `project_boq_items` | Account/engagement and contract root; site/location; versioned scope and quantity/rate snapshots with currency. |
| `project_phases`, `project_milestones`, `project_inspections` | Project-configurable phase ordering and approvals; no fixed universal construction stages. |
| `project_variations`, `project_material_usage`, `project_completion_records` | Approved scope/BOQ deltas, inventory movement references, signed completion/inspection references. Variations link exact approval policy version. |

## 10. Business Field Services — OPS/C/P

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `field_campaigns`, `field_campaign_contracts` | Client engagement -> campaigns; typed link to versioned shared service contracts, unique campaign/contract/version. |
| `field_territories`, `field_batches`, `field_task_templates` | Campaign-scoped territories, batches and versioned task types; unique campaign/code. Types include merchant onboarding, address verification, outlet mapping, surveys, document collection, field support. |
| `field_tasks`, `field_task_assignments` | Campaign/batch/territory/form-version deliverable, unique campaign/external task key; link to shared assignments, never an independent dispatch bypass. |
| `field_forms`, `field_form_fields`, **`field_form_field_options`** | Published versioned form definitions and choice values; unique form/version/field key. |
| `field_submissions`, `field_submission_answers`, `field_evidence` | Immutable submitted attempts, typed answers to exact field versions, file/GPS consent metadata; unique task/attempt and submission/field/repeat index. |
| `field_qa_reviews`, `field_exceptions`, `field_supervisors`, `field_agent_certifications` | Independent QA/exception workflow, scoped employee supervision, links to provider qualification evidence. Reviewed verified units distinct from submitted units. |
| `field_campaign_costs`, `field_campaign_reports`, `field_campaign_billing_milestones`, `field_client_approvals` | Cost/journal links, immutable report snapshots, configurable verified-deliverable billing, explicit client acceptance and reconciliation. Field agent sees own tasks only; client sees approved campaign output within its account. |

## 11. Procurement and suppliers — S/OPS/C/F

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `supplier_profiles`, `supplier_verifications`, `supplier_locations`, `supplier_categories` | Supplier organisation, verifier-only due diligence, sites, category associations; unique approved organisation supplier identity. |
| `product_categories`, `supplier_products`, `product_variants`, `product_images` | Supplier-scoped SKUs, variants and approved document/media links; no public supplier marketplace. |
| `supplier_inventory_offers` | Supplier/variant/time/version quantity and price/currency snapshots; historical offers immutable when submitted. |
| `procurement_requests`, `procurement_request_items` | Explicit `purpose = customer/internal`; CHECK requires customer account/request for customer procurement and internal cost centre/approval for internal procurement. Item quantity/specification and accepted versions. |
| `supplier_quote_requests`, `supplier_quotes`, `supplier_quote_items`, `supplier_quote_comparisons` | Addressed RFQs, numbered immutable quote versions/items, private comparison records linking exact quoted versions. Unique supplier/RFQ/version. |
| `purchase_orders`, `purchase_order_items` | Approved supplier/quote version/purpose/request references and line snapshots; one supplier/currency per PO. |
| `goods_receipts`, `goods_receipt_items`, `procurement_deliveries` | PO receipt/inspection, line quantities and inventory movement links; receipt totals cannot exceed approved tolerance. Delivery references shared logistics/proofs. |
| `supplier_invoices`, `supplier_performance_reviews`, `supplier_settlements` | AP source invoice distinct from customer invoice, unique supplier/invoice reference; evidence-based reviews; settlement/journal/payout links. Add **`supplier_settlement_items`** for allocated obligations. |

## 12. Inventory and assets — private OPS/F

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `inventory_items`, `inventory_locations`, `inventory_balances` | Internal SKU/unit definitions, warehouses/sites, unique item/location balance projection. Customer/supplier goods ownership explicitly tracked to avoid treating consigned goods as OnIt stock. |
| `inventory_movements`, **`inventory_movement_lines`** | Immutable idempotent movement headers and item/from/to/quantity lines; typed source links and reversal references. Atomic transfer legs and balances. |
| `stock_reservations`, `stock_counts`, `stock_adjustments` | Expiring item/location reservations, counted evidence and independently approved adjustment authorizations; posting creates immutable movements. |
| `assets`, `asset_assignments`, `asset_maintenance_records`, `equipment_custody`, `consumable_usage` | Serialized owned assets, accountable holder/time assignments, maintenance, custody links and inventory consumption evidence. Employee asset view uses this source. |

## 13. Payments, wallet and accounting — F

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `invoices`, `invoice_lines`, `invoice_adjustments`, `credit_notes` | Account/order/contract billing and immutable issued line snapshots; sequential unique invoice references per legal issuer; adjustments/credits explicit. |
| `payment_intents`, `payment_transactions`, `payment_webhook_events` | Expected merchant reference/amount/currency; verified provider transaction; sanitized event intake. Unique provider-account/event ID and provider-account/transaction reference, intent idempotency key. |
| `payment_allocations`, `payment_refunds`, `payment_reconciliation_records` | Explicit transaction-to-invoice allocation amounts, authorized refund and reconciliation evidence; allocations/refunds bounded under lock. |
| `payment_provider_accounts` | Merchant provider/currency/config references, no secrets; status and server-owned verification policy. |
| `wallet_accounts`, `wallet_holds`, `wallet_funding_requests`, `wallet_refunds` | Account/currency wallet liability ledger mapping, expiring/released holds and disabled funding/refund workflow; unique customer/currency/wallet purpose. |
| `wallet_ledger_transactions`, `wallet_ledger_entries` | **Read-only invoker projections** of canonical posted journals/lines linked to wallet accounts; no parallel posting mechanism. Subject-filtered statements only. |
| `payout_requests`, `payout_batches`, `payout_items` | Independently approved obligations -> provider execution batches/items; unique provider payout reference/idempotency; live execution disabled pending compliance approval. |
| `chart_of_accounts`, `accounting_journals`, `accounting_journal_lines` | Unique legal-entity/account code, atomic balanced journal headers and lines; currency, debit/credit, source, idempotency hash and reversal FK. No posted UPDATE/DELETE. |
| `financial_periods`, `cost_centres`, `budgets`, `budget_lines` | Legal-entity fiscal periods and close locks; scoped cost centre codes and approved budget versions/lines. |
| `expenses`, `expense_approvals`, `imprest_accounts`, `imprest_transactions`, `imprest_retirements` | Evidence-backed expense/independent approvals, accountable floats, journal-linked activity and retirement evidence. No second cash ledger. |
| `accounts_payable`, `accounts_receivable` | Due-date/status/allocation subledger documents referencing source supplier invoices/expenses or customer invoices and journal lines; no independently editable ledger balance. |
| `bank_accounts_metadata`, **`provider_bank_account_links`**, **`organisation_bank_account_links`** | Central masked/tokenized bank identity; typed owner FKs; prevent conflicting ownership and unauthorized reassociation. Supplier ownership through organisation link. |
| `bank_reconciliation_records`, `tax_rates`, `tax_documents`, `financial_adjustments` | Verified statement/journal matching, versioned approved tax definitions, retained tax records and approved journal adjustment source; no guessed tax rates in seed. |

## 14. Employees, HR and internal work — H/private OPS

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `employee_profiles`, `employment_contracts`, `job_positions` | Profile-linked employee relationship with organisation and employment history; unique employee reference, confidential signed contract versions. Independent from providers. |
| `job_requisitions`, `job_applications`, `employee_onboarding_tasks` | Approved hiring request, applicant PII/evidence and onboarding assigned tasks. Applicants use Auth only if an account is needed. |
| `attendance_records`, `attendance_adjustments`, `work_schedules` | Employee shift evidence, append-only authorized corrections, timezone-aware schedules and duplicate shift controls. |
| `leave_types`, `leave_requests`, `leave_balances` | Policy version, independently approved time interval and transactionally maintained entitlement projection; overlap/race tests. |
| `employee_compensation_history`, `payroll_periods`, `payroll_runs`, `payroll_items` | Effective compensation snapshots, unique period/run/version and employee line items; maker/checker approval via shared workflow, postings linked to canonical ledger. |
| `employee_benefits`, `employee_documents`, `employee_assets` | Benefit enrollments and protected typed documents; **employee_assets is a restricted projection of asset_assignments**, preserving one custody authority. |
| `performance_reviews`, `performance_goals`, `key_results`, `goal_checkins`, `employee_training` | Scoped manager/subject performance and learning records, versioned review outcomes. No general staff-directory visibility. |
| `disciplinary_cases`, `employee_exits` | Restricted case evidence and exit/revocation workflow; retention and legal holds. |
| `internal_projects`, `internal_tasks`, `task_comments`, `task_checklists`, `task_dependencies` | Team-scoped internal delivery; unique dependency edge, reject self/cyclic dependencies; private comments and assignee scopes. |
| `team_meetings`, `meeting_actions`, `knowledge_documents` | Team membership visibility, action/task link and permission-scoped knowledge/document versions. |

## 15. Marketing, content, SEO and notifications — E/G

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `content_pages`, `blog_posts`, `landing_pages`, `faq_entries` | Draft/review/published/archive state, unique locale/slug, approved publication schedule and canonical URL; anonymous reads require current published state. |
| `blog_categories`, `blog_tags`, `blog_post_tags`, `blog_authors`, **`blog_post_categories`** | Unique scoped slugs, post/tag/category bridges, author public biography separate from private employee/profile. |
| `media_assets`, `seo_metadata`, `seo_redirects` | Shared document-object marketing links, typed page/post/landing associations with exactly one target; structured-data JSON validated and sanitized; unique redirect source, reject loops. |
| `marketing_subscribers`, `marketing_lists`, `marketing_segments`, **`marketing_list_memberships`**, **`marketing_segment_memberships`** | Consented contact identity, lists and saved segmentation rules/membership; unique list/subscriber; private audiences never public. |
| `marketing_consents` | Append-only purpose/provider/version consent and withdrawal history; separate from transactional notification preference. |
| `email_templates`, `notification_templates` | Versioned channel-specific render templates; email templates extend a shared notification definition rather than duplicate routing rules. |
| `notification_events`, `notification_deliveries`, `email_delivery_logs` | Transactional outbox with unique source/event/recipient/channel, retry/delivery evidence and sanitized email-specific outcomes; no actual sends in this foundation. |
| `integration_connections_metadata`, `integration_webhook_events` | Central non-secret integration connection/provider/tenant references and sanitized unique external event intake. Payment-specific events retain stricter finance verification and isolation. Prepare Zoho provider codes only. |

## 16. Platform governance — G

| Proposed tables | Purpose, key fields and relationships / uniqueness |
| --- | --- |
| `feature_flags`, `system_configurations`, `integration_settings` | Versioned environment/scope/key unique flags and typed settings. Integration settings extend shared connection metadata; secret values stored outside database. No bypass of wallet compliance lock. |
| `idempotency_keys`, `background_job_records` | Unique actor/tenant/operation/key with request hash and result state, TTL; jobs include lease/attempt/status/run time, unique deduplication key. Finance permanent uniqueness remains in journals even if short-lived keys expire. |
| `operational_alerts`, `incident_reports` | Internal platform alerts/incidents; operational service/provider incident consequences remain typed domain records linked to central case where relevant. |
| `compliance_obligations`, `compliance_reviews`, `privacy_requests`, `data_retention_policies`, `access_review_records` | Jurisdiction/policy/effective evidence and reviews, authenticated data subject requests, legal holds/retention and permission review decisions. No automatic financial deletion. |
| `export_jobs`, `import_jobs`, `import_rows` | Requester/tenant/permission-scoped import/export manifests, private output object links; staged rows validated before atomic scoped commit. Exports recheck authorization at download. |
| `audit_logs` | Reuse central table from group 1. Never create a second audit authority. |
| **`document_objects`** | Shared private/public file registry with typed subject links, unique bucket/object key, classification, scan/retention state and uploader; described in the plan. |

## Consolidation and implementation rules

The named checklist is fully mapped above; consolidations are proposed explicitly, not silently omitted. Additional integrity entities are bold. Further typed approval/source/document bridges will be named in the SQL dictionary when exact consumer FKs are approved. Avoid a generic `entity_type/entity_id` replacing order, campaign, employee or financial relationships.

Configuration registries merge; address books merge; audit is central. Wallet history and employee assets are views. Provider bank metadata uses the shared finance registry with typed ownership. Shared approval requests/steps carry decisions, while domain approval tables are typed target/version links. Shared logistics/custody is authoritative; Laundry adds bag/count-specific details. Shared assignments control field task dispatch. Shared contract versions control campaign obligations. Separate customer/supplier invoices remain intentional because legal direction, source and access differ.

Schema placement follows sensitivity, not the group title: for example public provider-owned document metadata must exclude verifier-only results; bank and payroll rows stay private. If an external projection cannot safely redact mixed rows/columns, split a dedicated projection or typed extension rather than broaden a policy. Final schema-qualified per-table assignments and exact SQL constraints must be reviewed with each migration phase.
