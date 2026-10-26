# Phase 2 Increment 2 — pricing, assessments and quotations

Date: **2026-10-26, Africa/Lagos**. Implemented and tested locally on PostgreSQL **17.11**. No hosted connection, migration, seed, project-link change or live-data modification was performed. The configured project remains `utoxjlsvqfmmzsjruzsm`. No payment, wallet, payout, settlement, order-confirmation or provider-dispatch functionality was introduced.

## Implementation summary

Increment 2 extends the existing request/quotation architecture with approved configuration-driven pricing, assessments and commercial approval gates. All five service pricing methods are supported: fixed packages, starting prices, quantity pricing, assessment-derived pricing and custom quotations. Existing rate cards/rules, catalogue versions/variants/options, corporate accounts/branches, document registry, tax rules, approval policies, audit and quotation tables are reused.

Three additive migrations add **four private tables**. Combined local schema: **17 migrations, 93 application tables (51 public / 42 private), all with RLS**. The 12 deployed Phase 1 migrations, two Increment 1 migrations, reference seed, hosted types, browser client and environment values were not edited. One Phase 1 SQL test fixture now supplies an independent pricing approver when the newer approval command exists; its original assertions remain in place.

| Migration | Purpose |
| --- | --- |
| [`20261025000300_pricing_configuration.sql`](../../supabase/migrations/20261025000300_pricing_configuration.sql) | Extend existing rate cards, rules and approval policies; package/corporate/branch scope; charges, costs, discounts/minimums/tax references; independent configuration approval and retirement; currency precision expansion; secured configuration commands/read projections. |
| [`20261025000400_assessment_workflow.sql`](../../supabase/migrations/20261025000400_assessment_workflow.sql) | Versioned remote/physical assessments; internal assessor scheduling, checklists, measurements, findings and registry evidence; independent approval; scoped read/Storage access; immutable completed/final content. |
| [`20261025000500_pricing_quotation_engine.sql`](../../supabase/migrations/20261025000500_pricing_quotation_engine.sql) | Shared currency-aware quotation writer; automatic and assessment-derived preparation; commercial snapshots/cost privacy; override and multi-person approval gates; legacy-entry-point protection; exact decimal DTOs; targeted FK indexes. |

## Pricing workflow

Staff prepare a draft rate card against an exact service version/currency and optional variant, zone, corporate account and branch. Corporate-specific cards require a contract reference and finite validity window. A different active employee with scoped `pricing.approve` must approve it. Released rules and terms cannot be edited; corrections use new versions. Approval serializes by service/currency and rejects overlapping approved applicability windows. Future non-overlapping versions can be approved in advance. Open-ended cards can be independently retired with an idempotent, private reason receipt; no history is deleted.

`generate_quotation` selects currently effective, independently approved pricing. Exact package matching is required. Scope precedence is corporate branch, corporate account, then general pricing; zone-specific pricing wins within the same account scope. Ambiguity fails. Zone selection requires active same-state, verified city coverage in the latest coverage version. An applicable zoned card cannot be bypassed by omitting the zone. Quote expiry cannot exceed agreement expiry.

Fixed rules charge one unit; per-unit rules require positive exact decimal quantities and enforce minimum quantities. Optional values must be priced by the selected card; required catalogue options must be supplied. Rules distinguish service, labour, materials, logistics and other charges. Configured discounts apply before taxes; per-rule and whole-service minimum shortfalls become separately described adjustment lines. All amounts use PostgreSQL numeric, never JavaScript financial arithmetic.

Assessment-required pricing uses approved assessment measurements as the authoritative quantity map, keyed by rate-rule code. Callers cannot substitute their own quantities. Custom scope rules accept bounded manual line descriptions/quantities/prices, apply the configured discount and minimums, and enforce any configured default tax. Without a configured default tax on a custom scope rule, authorised staff may select effective country tax rules for individual manual lines. At most one custom scope rule is supported per card. Manual custom quotations without an applicable rate card remain available through the existing API; configured services cannot use that API to bypass their card.

Price overrides require `quotes.override.request`, an explanation and an independent approver holding both `quotes.approve` and `quotes.override.approve`. Overrides produce new immutable quotation versions with their original configuration, selection and reason snapshots. They do not modify prices in the catalogue.

Internal unit-cost estimates are private. Missing components are explicitly flagged by `internal_cost_complete=false`; zero is not asserted to be a complete cost estimate. No customer DTO contains costs, margins, pricing snapshots or approval votes.

## Assessments and release gates

`assessment_command` creates an idempotent request revision, schedules an active internal employee, attaches clean same-account registry documents, completes required versioned checklist answers and decimal-string measurements, then records independent approval or rejection. Both remote and physical modes use this workflow. Scheduling uses an assessor transaction lock and rejects overlapping scheduled appointments. Creation of a new revision preserves prior approved findings; completed findings cannot be edited. A revised assessment is independently completed/approved again.

Assessment/request/account/service FKs are composite where needed. Evidence has matching assessment/account and document/account FKs. An assigned assessor or scoped assessment manager/approver can read the assessment/checklist/evidence projection. Storage access extends only to the exact clean linked assessment evidence; identity, HR and unrelated files remain protected.

Release **and customer acceptance** require the latest assessment revision to be approved, match the request revision, and match the quotation's pinned assessment. Evidence scan status is rechecked. Older manually prepared drafts cannot bypass approved pricing or assessment requirements. A new assessment revision prevents acceptance of an unaccepted stale quotation. Accepted quotations cannot acquire a new assessment through this request workflow; later changes need the future order-change process.

## Approval policies and corporate isolation

The shared versioned `approval_policies` registry now distinguishes internal and customer-side quotation policies and can scope them to a corporate account/branch. Policy preparation and activation have separate maker/checker permissions. Thresholds carry an explicit currency. A card's policy cannot weaken a stronger applicable company/account policy. Below-threshold quotations retain one independent internal approval; higher configured counts require distinct voters.

Votes are unique per quotation version, side and actor. Duplicate approvals do not count twice. Both sides use the strongest applicable approval count, so a weaker branch rule cannot undermine an account-wide requirement. Only the threshold-completing decision changes the quotation to offered/accepted and writes the existing final decision event. Intermediate votes return the quotation UUID while it remains draft/offered; callers should refresh `readQuote` and authorised `readQuoteCommercial` for status/counts.

Corporate acceptance requires current approved membership, branch/department scope and `can_approve`, independently of `can_request`. A requester cannot satisfy an independently configured customer-side approval policy. Negotiated pricing does not imply credit terms; unrelated branches/clients receive their applicable default card. Activating a stronger policy or retiring a referenced policy prevents pending quotations from using stale approval requirements; prepare a new revision. Terminal accepted history remains unchanged.

## Currency and tax

Quotation headers and lines snapshot `currencies.minor_units` (0–4). Exact numeric columns now preserve four fractional digits; legacy rows retain their original scale of 2 and original values. Gross, discount precision, per-line tax and totals are constrained at the snapshot scale. Quantities/unit prices retain up to four decimal digits before boundary rounding. Monetary RPC outputs are decimal strings formatted at the quotation scale; internal estimates/configuration monetary values also return strings.

Existing immutable, country-specific `quotation_tax_rules` supply labels, percentages and effective dates. Tax selection is validated at preparation and snapshotted. Null tax references do not imply universal VAT. There is no production tax-rate or commercial-price seed. Tax treatment at a future invoice/service tax point remains part of the separately scoped financial implementation; a quotation does not establish payment or accounting treatment.

## Server operations and types

[`lib/transactions/server.ts`](../../lib/transactions/server.ts) adds typed configuration prepare/approve/read/retire, commercial policy prepare/approve, assessment create/schedule/evidence/complete/approve/reject/read, automatic quotation generation and private commercial-read methods. Existing create/change/review/list request and manual quote/decision/read methods remain available.

The adapter is server-only, validates the caller through Auth `getUser`, and sends that caller's JWT with the public anon key. No service-role credential, unrestricted admin client, new ORM or second identity system was added. Database commands independently authorise current identity/membership/employee permissions; direct client writes remain revoked. Database errors are mapped to safe typed application errors, without raw SQL/token/payload logging.

[`database.phase2.generated.ts`](../../types/database.phase2.generated.ts) is regenerated from the passing native PostgreSQL candidate, separately from hosted Phase 1 types. Generation verifies migration SHA-256 values against the successful test run, preventing accidental generation from stale validation. Private schemas are excluded. This remains a catalog-derived local fallback, not a claim of canonical hosted Supabase CLI type generation.

## Executed validation

| Check | Result |
| --- | --- |
| Fresh PostgreSQL17.11 replay | All **17 migrations** applied to a newly created disposable local database restored from the verified Auth/Storage baseline. |
| Phase 1 / Increment 1 SQL regressions | **190 assertions passed** (76 +50 +64). |
| Increment 2 SQL suite | **71 assertions passed** in [`004_pricing_assessments.sql`](../../supabase/tests/004_pricing_assessments.sql), for **261 primary SQL assertions** overall. |
| Real concurrency | **4 checks passed**, using 10 connections: duplicate request creation, competing amendments, one idempotency receipt, simultaneous quote revisions preserving two versions and one live proposal. |
| Increment 1 upgrade rehearsal | **6 checks passed**: accepted quotation values, accepted lines and request rows unchanged; historical scale retained; direct legacy release execution denied; accepted retries through the public RPC work in the same session that used it before upgrade. The rehearsal creates its accepted baseline with the existing 64-assertion Increment 1 fixture before applying the three new migrations. |
| Catalog security | All 93 tables have RLS; no public definers, unsafe definer search paths, PUBLIC internal-function execution, private-schema browser USAGE or client transaction-write grants. |
| Migration integrity | All 12 deployed migration hashes and reference seed matched the existing manifest. SHA-256 for each of the 17 tested migration files is recorded in [test evidence](phase-2-test-results.json) and the [candidate manifest](phase-2-candidate.sha256). |
| Reference seed | Replayed twice; unchanged. No fictional operational data added to reference seeds. |

Commands: `npm run db:test:phase2`; `npm run db:types:phase2`; `node node_modules/typescript/bin/tsc --noEmit`; `node node_modules/eslint/bin/eslint.js .`; `git diff --check`. TypeScript and ESLint completed successfully with exit code 0; diff checks passed with Windows line-ending notices only.

Coverage includes all five pricing methods, effective/expired pricing, package/options, quantity/minimum/discount calculations, zone verification, mandatory assessment gates on old/new quote APIs, assessment-derived quantities, costs/override protection, internal/corporate thresholds and branch isolation, tax timing, all five minor-unit scales, immutable accepted history, idempotency and concurrent revisions. Synthetic fixtures execute only on loopback disposable databases. The normal new SQL suite rolls back; retained local concurrency fixtures and upgrade fixtures never connect hosted.

During development, tests caught a fixture still using the former owner-only rate approval shortcut, an unauthorised direct checklist-table query, malformed synthetic currency UUIDs and a local PostgreSQL startup/recovery race. Fixtures now use independent approval/checklist projections, UUIDs were corrected, and the runner waits for a successful SQL probe. Passing evidence comes from subsequent full reruns.

## Remaining limits and deployment boundary

- Actual Supabase Auth JWT/REST/Storage HTTP, full Docker-stack behaviour and server-adapter HTTP integration were not executed. Native same-major PostgreSQL tests exercise the restored managed schemas and SQL roles but do not replace those tests. Local migration owner is superuser; hosted managed-DDL compatibility still needs separately authorised inventory/dry-run review.
- Zone applicability uses existing verified city coverage, not a newly invented polygon/geocoding engine. Partial-neighbourhood coverage needs a future explicit verified geographic model.
- Pricing supports deterministic fixed/per-unit/custom-scope rules, percentage card discounts, options and minimums. Arbitrary executable formulae, external tax engines, FX conversion, promotions stacking and supplier cost feeds are outside this increment.
- Checklist answers are boolean and measurements are positive decimal strings keyed to rule codes. Customer request amendment negotiation, customer-facing assessment publishing, general staff upload/scanning infrastructure and full task/provider dispatch remain separate work. Assessment evidence uses existing approved registry uploads.
- New privileges are defined but assigned to no real user/role automatically. Administrators must review operational role grants and configure real approved cards/tax/policies; no invented rates or identities were activated.
- Legacy approved rate cards without an independently recorded approver remain preserved but are not eligible for automatic pricing. Create an independently approved successor version rather than rewrite them. Retirement intentionally prevents pending release/acceptance against a withdrawn card; requotation is required.
- Existing dependency advisories documented in Increment 1 were not repaired or recertified here. Resolve them and complete HTTP validation before exposing new web endpoints. No unrelated framework dependency upgrade was performed.

This local increment is ready for review and **Provider Network Increment 3 development**. It is not deployed. Before hosted rollout, separately approve the final candidate, inspect drift read-only, refresh/restore-test recovery, complete Supabase API tests, review grants/configuration, dry-run the exact candidate and regenerate canonical types after approved deployment. Prior Phase 1 deployment approval does not cover these files.

Provider Increment 3 can reuse exact service/quote/assessment IDs, currency and pricing snapshots, scoped identities, documents and approval boundaries. Keep contractual providers, executing personnel and processing partners distinct. Confirmed orders must later link uniquely to accepted quote versions with separate payment gates. No order/payment side effect was added to quote acceptance.

## Changed-file map

- Three new migration files above; new `supabase/tests/004_pricing_assessments.sql`; adjusted synthetic approval fixture in `001_foundation.sql`.
- Extended `lib/transactions/server.ts`; regenerated candidate types only.
- Updated `test-phase2-native.mjs`, `test-request-concurrency.mjs`, `generate-phase2-types.mjs`; new `test-pricing-upgrade.mjs`.
- This report and [schema addendum](phase-2-increment-2-schema.md), updated progress/inventory/ERD links and machine test evidence. No commit was created.
