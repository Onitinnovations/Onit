> Local Increment 4 checkpoint (2026-10-27): [service orders, matching and dispatch](docs/database/phase-2-increment-4-report.md) implemented; candidate 26 migrations / 126 RLS tables (51 public, 75 private). Hosted remains 22 migrations / 115 tables. No push or deployment. Increment 5 must wait for checkpoint review. Earlier progress entries below are historical.

> Current hosted checkpoint (2026-10-27): Increment 3 deployed and verified on OnIt: 22 migrations, 115 RLS tables (51 public / 64 private), PostgreSQL 17.11. Canonical types updated. See [deployment report](docs/database/phase-2-increment-3-hosted-deployment-report.md). Increments 4?6 remain unimplemented; earlier status entries below are historical.

# OnIt database foundation — proposed architecture

Current execution: [Phase 1 hosted deployment](docs/database/hosted-deployment-report.md) is complete. [Phase 2 Increment 1](docs/database/phase-2-report.md) and [Increment 2 pricing/assessments](docs/database/phase-2-increment-2-report.md) add five local-only migrations and 14 tables, for 93 application tables with RLS and PostgreSQL 17 tests. Provider/dispatch/fulfilment remain future increments. Historical readiness statements below are superseded by these reports.

Status: **Phase 1 implemented in repository: twelve migrations, 79 RLS-protected tables, tested public TypeScript types; hosted deployment blocked pending authorised inventory and actual Supabase validation.** Date: 2026-10-24 (Africa/Lagos). The latest implementation instruction explicitly authorises local development despite remote/runtime limitations. See the [current implementation report](docs/database/phase-1-report.md), [policy guide](docs/database/rls-policies.md) and [deployment procedure](docs/database/phase-1-deployment.md). Repository findings below record the original inspection.

## Repository findings

| Evidence | Finding |
| --- | --- |
| `package.json`, `package-lock.json` | Next.js 16.4.0 App Router, React 19.3.0, TypeScript 5, Supabase JS 2.117.3 installed; npm lockfile. |
| `app/page.tsx`, `supabaseClient.js` | Starter customer web page; one Supabase client initialized with public URL and anon key. Preserve this interface during later implementation. |
| `app/supabase-connection-test.tsx` | Checks `/auth/v1/settings`; does not inspect PostgreSQL, authentication flows, tables, RLS, or Storage. |
| Repository file inventory | No `supabase/`, SQL migrations, ORM, database schema, generated database types, database tests, API routes, or server payment handlers found. No Prisma or alternative ORM will be introduced. |
| `.env.local` variable names only | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` exist. Values were not printed or included in documentation. No connection to the remote database was made. |
| Local tool discovery | `supabase`, `docker`, and `psql` were not found on PATH. A local database cannot yet be validated with the discovered tooling. |
| Git | Clean working tree before this documentation work; latest commit `a97e663`. |
| Installed Next.js documentation | Read the local App Router data-security and environment-variable guides. Privileged access belongs in server-only code; public environment variables enter browser bundles. |

**Remote schema remains unknown.** Absence of local migrations is not evidence of an empty hosted project. Local foundation implementation proceeds in isolation after the continuation instruction; **remote deployment remains blocked** until an authorized read-only schema and migration-history export is reconciled. Inspect tables, functions, policies, grants, extensions, triggers, Auth hooks, Storage buckets, existing data counts and dependencies. Do not infer database credentials from an anon key, reset the hosted database, or overwrite untracked remote objects. Reconcile any equivalents in the inventory and record a baseline before rollout.

## Review package and boundary

Phase 1 now implements fixed, starting, quantity-based, assessment and custom-quotation pricing configuration; versioned conditional/repeatable booking schemas; corporate branch/requester/approver scope; central billing and independently approved credit-term configuration; active/inactive geography; and audit/document hardening. Separate contractual responsibility, execution personnel, partner custody and typed CMS links remain documented later-phase designs. No bookings, dispatch, financial ledger/wallet, full credit management or remaining OMS modules are implemented in this request.

- [Proposed table inventory and requirements mapping](docs/database/schema-inventory.md): all sixteen capability groups, ownership, relationships, consolidation decisions and dictionary conventions.
- [Conceptual ERD](docs/database/erd.md): principal aggregates and security boundaries; not a claim that migrations exist.
- [Validation and recovery plan](docs/database/validation-and-recovery.md): acceptance tests, fixtures, deployment safeguards, type generation and recovery.

The original six migrations are retained; six additive refinements extend them. The [dictionary](docs/database/data-dictionary.md) and [physical FK graph](docs/database/foundation-erd.md) are regenerated from tested PostgreSQL catalogs. Reference seeds exclude illustrative services/zones, which are isolated in rollback-only test fixtures. Fresh embedded PostgreSQL 18.6 validation passes 124 SQL assertions plus five reference-seed checks; an incremental upgrade passes four checks. Full Supabase/PostgreSQL 17 Auth/Storage/API validation remains outstanding because Docker is unavailable. Public types are catalog-generated via an explicitly labelled embedded fallback; the canonical CLI command remains ready for a functioning local Supabase stack. No remote database changes are authorised or performed.

## Platform model

OnIt centrally scopes, prices, approves, dispatches, supervises, assures quality and settles work. Customers request a service; they never select or directly book a provider. Independent providers are Service Associates or Field Agents. Employment is a separate relationship; holding a provider role does not grant staff access.

Four plain service areas: **Home & Utilities, Construction, Procurement, Business Field Services**. Laundry is a service in Home & Utilities. No legacy brands, published prices, invented tax rates, salaries or payout rates enter reference seeds.

Use Supabase PostgreSQL and Auth for every future client. No second identity system. UUID IDs default to `gen_random_uuid()` except shared-primary-key extensions (notably `profiles.id = auth.users.id`). Use `timestamptz`; Nigeria defaults to NGN and Africa/Lagos. Money uses `numeric(20,4)` and an explicit currency FK, with currency-aware rounding at financial boundaries; quantities use appropriate numeric precision. Never mix currencies in a balanced posting or implicitly use FX. Add a `currencies` reference table as an explicit supporting entity.

### Schemas and API surface

- `public`: curated externally accessible business records with RLS and minimal column grants. Compatibility with the existing default Supabase client is retained. Ordinary users have no blanket schema/table grants.
- `private`: internal CRM, staff, HR, dispatch scoring, bank metadata, raw webhooks, audit, accounting and integration internals. Exclude from exposed API schemas; RLS and restrictive grants also apply. No direct browser access. Internal OMS uses authorized server operations, not a service-role key in a browser.
- `app_private`: narrowly scoped security helpers, transition and posting functions; not API-exposed. Explicit owners, fixed search paths, schema-qualified objects, and revoked PUBLIC execution. Client-callable RPC wrappers receive explicit execute grants and validate `auth.uid()` themselves.

Default privileges must deny new application objects until policies and grants are deliberately added. Private service credentials are server-only. Avoid security-definer views that bypass RLS; use invoker views with explicit grants where needed. Never expose private columns through a broad view, function result, Realtime publication, export or nested relation.

### Identity and tenancy

`profiles` references Auth; its insert trigger is idempotent and creates only neutral identity data. Never derive staff roles, approvals, organisation membership or provider eligibility from user-editable Auth metadata. A privileged, audited invitation/provisioning path creates approved relationships. Backfill existing Auth users after remote reconciliation.

`customer_profiles` represents a customer account and has exactly one of `individual_profile_id` or `organisation_id`. Corporate accounts extend organisation-owned customer accounts; corporate access comes from active `organisation_members` and approved `corporate_account_users`. Provider and supplier organisations can have multiple users. A person may hold several independent roles without acquiring all permissions on all records.

Every tenant aggregate has an explicit `customer_account_id`, `organisation_id` or provider/supplier owner, as appropriate. Child rows reference their parent and use composite FKs such as `(order_id, customer_account_id)` to prevent cross-account attachment. Policy checks on parent alone are insufficient if a caller can substitute a different tenant FK. Foreign keys and functions must reject these mismatches. Use composite unique keys on referenced pairs where needed.

Roles are permission bundles. Assignments carry one explicit scope: internal global, organisation, team, or own subject. Global staff access additionally requires an active employee record and the relevant permission; a role string alone never implies staff status. Scope columns have XOR/consistency checks. Include expiration and revocation; authorization helpers query current membership, not stale role claims in JWTs. Only access administrators grant roles, with separation of duties and audited emergency access.

### RLS and write model

| Actor | Read boundary | Write boundary |
| --- | --- | --- |
| Anonymous | Published, currently visible catalogue/CMS projection and public marketing assets only | No business-table writes; optional lead intake through validated server endpoint. |
| Individual customer | Own customer account, approved quotes/orders, invoices and customer-visible evidence | Own addresses/preferences and draft requests; acceptance/cancellation through validated functions. No provider allocation, price or QA edits. |
| Corporate user | Explicit approved account plus active organisation membership; department/location limits where assigned | Permission-specific requests and approvals within account limits. No cross-client access. |
| Provider | Own onboarding records and redacted offers/active assignment details; own settlement statements | Accept/decline own unexpired offer, submit evidence and execution progress through functions. No candidate lists, competitor prices, customer-wide history or QA approval. |
| Supplier | Own business profile and addressed RFQs, quotes, POs and statements | Own draft quote/version submission and fulfillment evidence. No comparisons or other suppliers' offers. |
| Staff | Explicit permission plus tenant/operational scope | Validated operational commands; finance/HR/editorial require separate permissions. |
| Trusted workers | Narrow function-level capabilities where possible | Idempotent dispatch, verified webhook processing, notifications, posting, retention; all audited. |

RLS enabled for all application tables, including private tables. Owner/bypass capabilities remain tightly controlled. Foundation security-definer helpers use the trusted migration/table owner with an empty search path to avoid recursive RLS; that role must never be granted to application users. FORCE RLS is deliberately not enabled for this design. A dedicated non-login helper owner can be introduced only after testing its grants against the hosted project's role model. RLS uses USING and WITH CHECK for permitted updates; column grants and RPC-only mutation protect account IDs, roles, workflow status, pricing, approval and payment fields. Security helpers must not accept caller-chosen identity as authority. Future views expose only redacted DTOs. Scope access to assignment lifetime; expired offers and closed work lose sensitive customer address access under the retention policy.

### Relationship and lifecycle rules

- UUID PKs, `created_at`, `updated_at` and nullable `created_by -> profiles` on mutable application entities; `updated_at` set by a safe trigger. Immutable rows keep insertion metadata only, with attempted UPDATE/DELETE rejected. Auth-owned and third-party-managed system tables are not modified beyond approved hooks/policies.
- Historical and financial parents use RESTRICT/NO ACTION deletes, archive/status timestamps and pseudonymisation where lawful. CASCADE is limited to disposable dependent drafts and configuration bridges with no history. Actor FKs are normally RESTRICT with retained pseudonymous profiles; any SET NULL exception is documented and preserves a non-PII actor reference in the audit event.
- Lookup codes and CHECK-constrained text replace PostgreSQL enums. State transitions are explicit allowlists enforced by database functions/triggers, permission checks and expected current status/version. No generic free-form status updates.
- Reference snapshots pin service, booking-form, quote, contract, price, tax and checklist versions. Transactions retain currency, description and price snapshots even after catalogue changes. Parent IDs remain navigable; submitted versions are immutable.
- Index every FK that supports joins/deletion checks; tenant-first indexes for common list queries, status/time indexes for queues, partial unique indexes for active relationships and one active assignment, and unique `(parent_id, sequence)` ordering. Avoid low-selectivity indexes without query evidence. JSONB holds versioned form/evidence/metadata payloads only, not core relationships or financial amounts.
- Use `version` counters and row locking for concurrent changes, date/amount range checks, positive quantities, unique public reference codes, and normalized email/slug codes where needed. Use exclusion constraints for genuinely exclusive time allocations, not all provider schedules.

## Operational and financial invariants

Request -> optional assessment -> versioned quotation -> required approvals -> order -> dispatch -> fulfillment -> independent QA -> closure. Payment gates are configured per approved service/contract version (none, deposit, milestone, completion, or approved credit terms). No universal prepaid requirement. Quote acceptance locks the accepted version and amounts atomically; order creation is idempotent. An order may have several assignments over time and several work packages, with one active assignment per exclusive work package. Reassignment closes the predecessor and records who/why.

Eligibility is rechecked inside the assignment acceptance transaction: service eligibility, qualification validity, restriction status, availability and capacity. Lock offer, dispatch work package and capacity rows to prevent double acceptance. Only authorized OnIt operators/workers create dispatch requests and candidates. Expired/declined offers cannot create assignments. Providers cannot QA their own work; QA decisions and rework link back to the specific execution and checklist versions.

Inventory is a stock movement journal. An immutable movement has one or more normalized movement lines between locations, quantity, item, reference and idempotency key. Reservations lock available stock; posting locks item/location balances in deterministic order. Negative available stock is forbidden unless an explicitly approved future backorder policy exists. Corrections are reversal movements. `inventory_balances` is a transactionally maintained projection reconcilable to movements.

One double-entry engine serves wallet and accounting. `accounting_journals`/`accounting_journal_lines` are authoritative. `wallet_ledger_transactions`/`wallet_ledger_entries` are restricted projections of wallet-related postings, not parallel writable ledgers. Each posted journal has at least two positive debit/credit lines with exactly one side per line, and equal debits/credits per currency. Posting validates account status, currency, open financial period and authorization, under one transaction and deferred constraints. Draft journals cannot affect balances; posted journals and lines cannot be edited/deleted. Reversal journals reference originals; prevent duplicate full reversals. Direct client INSERT/UPDATE/DELETE on financial posting tables is revoked.

Wallet availability = posted liability balance minus active holds, calculated and checked while locking the wallet balance projection. Concurrent debits/holds cannot overspend; failed posting rolls back every line/projection. Journal idempotency keys are scoped and unique; repeat with a different payload hash is rejected. Balanced journals alone do not prove authorized spending, so source documents, approvers and permissions are also verified. Currencies cannot cross-balance. Wallet funding and payouts are **disabled by default in database functions and server endpoints** pending an approved compliance/operating model; UI flags are insufficient.

Paystack callbacks only request a pending-status refresh. Server webhook intake verifies authenticity using server-held secrets and verifies authoritative transaction status, amount, currency, merchant account and reference before posting. Persist unique `(provider_account_id, provider_event_id)` plus unique provider transaction reference; process retries using a locked event and idempotent posting. Different events for the same payment cannot credit twice. Store sanitized verification metadata, never PAN/CVV, secrets or unbounded raw PII. Refunds, allocation reversals and settlement failures create explicit compensating records. Independent approvers are required for payroll, expenses, payouts and designated financial adjustments; reject self-approval and enforce policy version/threshold.

## Storage design

Proposed private buckets: `identity-documents`, `contracts`, `field-evidence`, `invoices`, `customer-documents`, `employee-documents`, `work-evidence`. `marketing-assets` is a separate public bucket containing only reviewed public assets. Do not grant public listing of private buckets.

Add `document_objects` as the shared file registry: UUID, bucket/object key unique pair, uploader, exact tenant/subject scope, classification, content type, byte size, checksum, scan status, retention state. Typed link tables such as provider/customer/employee documents and order attachments carry real FKs to the registry. An object path is not authorization. Storage policies require a registry row, matching bucket/path and permission over the linked subject; prohibit caller-controlled ownership escalation, overwrite and cross-tenant attachment. Uploads enter quarantine; publishing/serving requires validation/scanning. Downloads use short-lived signed URLs issued after current authorization checks; URLs are bearer capabilities. Deletes require permission plus retention/legal-hold checks; asynchronous object/database reconciliation handles partial failures. Test Storage API access separately from SQL metadata RLS.

## Proposed migration order

Files use Supabase timestamped SQL filenames under `supabase/migrations`; each step may split into small schema/constraint/policy files. SQL generation began only after the review continuation.

| Phase | Dependency-ordered content | Exit gate |
| --- | --- | --- |
| 0 | Remote inventory and baseline; pin CLI; local config; private schemas, grants/default privileges, extensions actually required | Existing objects/data reconciled; disposable environment ready. |
| 1a | Auth profile provisioning; organisation and RBAC core; geography/currency; customer accounts | Provisioning and membership tests. |
| 1b | Versioned catalogue; CRM basics; shared file registry; private Storage; audit/approval skeleton | **Foundation migrations and RLS tests pass before generating phase 2 SQL.** |
| 2a | Requests, assessment, quotations, approvals, contracts and orders | Ownership, tenant FKs, transition and idempotency tests. |
| 2b | Provider eligibility; dispatch/offers/assignments; execution, QA, complaints/logistics | Concurrent acceptance, reassignment and QA separation tests. |
| 3a | Laundry, property/cleaning/maintenance/construction | Typed extensions reconcile to their order/project roots. |
| 3b | Client engagements, BFS campaigns/forms/tasks/verified deliverables | Client/territory scope, evidence and form-version tests. |
| 3c | Suppliers, procurement and inventory/assets | Supplier isolation, quote versions, stock concurrency and reconciliation. |
| 4a | Finance periods/chart/journals, invoices/payments, disabled wallet/payout paths, settlement integrations | Balanced append-only postings, replay and race tests. |
| 4b | HR/payroll/work management; CMS/marketing/notifications; remaining governance | HR privacy, independent approval, editorial and job isolation tests. |
| 5 | Idempotent safe seeds; all-policy catalog checks; full fresh-install and upgrade rehearsals; dictionary/types | Reproducible disposable-local run; reviewed deployment and recovery evidence. |

Cross-phase finance references (for example provider earnings and supplier settlement postings) are added after the journal engine exists. Early operational tables do not use fake finance IDs or circular creation dependencies. Shared audit/approval/configuration/job skeletons precede consumers; later phases extend them. Separate DDL transactions from operations such as concurrent indexes that cannot run inside them.

## Seed and configuration boundaries

Seed only NG/Nigeria, NGN, Africa/Lagos; Lagos state and a clearly labelled operational Lagos city/zone sample without fabricated official LGA lists or GIS polygons. Coverage boundaries remain unverified/inactive until operations approves them. Version rate cards without invented amounts. Seed service families and representative draft services: Laundry, Home Cleaning, Plumbing, Electrical Repairs, Air Conditioner Maintenance, Building Renovation, Construction Project Management, Product Sourcing, Bulk Purchasing, Merchant Onboarding, Address Verification, Outlet Mapping, Surveys, Document Collection and Field Support. Representative records are not assertions of commercial availability; availability stays disabled pending operational approval.

Permissions and safe feature defaults may be seeded; no real users, tenant memberships, bank details, payroll, tax percentages or live credentials. Synthetic identities and price examples belong exclusively to test fixtures in a disposable environment. Zoho ZeptoMail/Campaigns integration metadata stores provider names and secret references, never credentials; outbox records prepare future sends, with live delivery disabled.

## Decisions for this review

Proposed defaults are explicit so approval can focus on concrete architecture:

1. Approve the shared customer-account model and per-account corporate membership gate, private schema/API separation, and shared ledger with wallet projections.
2. Approve the consolidations and added integrity tables in the inventory; retain typed service/HR/procurement relationships rather than generic unvalidated entity IDs.
3. Confirm service examples/families and Lagos operational seed scope; financial values and operational availability remain unset.
4. Before implementation, establish authorized read-only remote schema access and disposable Supabase tooling. Before production activation, separately decide retention/legal holds, wallet compliance, payment terms, approval limits, zone coverage, payroll/tax configuration and authoritative external integrations. Unresolved commercial decisions remain inactive/configurable and must not receive invented defaults.

## Original review verification

Repository, dependency versions, client usage, environment variable names, tool availability and relevant installed Next.js guides were inspected. No application code changed; no database connection, migration, seed, SQL/security test or runtime build was executed. Documentation consistency is checked separately. No qualifying Next.js issue was observed; the feedback reporting pass has no candidates.

Current implementation evidence is maintained in [implementation-status.md](docs/database/implementation-status.md), replacing this historical review-only status.
