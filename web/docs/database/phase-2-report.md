# Phase 2 — request and quotation implementation increment

> Current local status: [Increment 2 pricing/assessment report](phase-2-increment-2-report.md) and [schema addendum](phase-2-increment-2-schema.md) supersede the pricing/assessment deferrals below. Five local Phase 2 migrations now accompany the 12 Phase 1 migrations, for 93 RLS tables. This document retains the original Increment 1 checkpoint; provider/dispatch/fulfilment remain future work. No Phase 2 deployment occurred.

Date: 2026-10-24, Africa/Lagos. **Local implementation only. Phase 2 is not deployed and the complete Phase 2 scope is not finished.** This increment delivers the shared request transaction foundation and the core quotation workflow. Provider management, dispatch, orders/fulfilment and specialised operations remain subsequent increments; no empty placeholder subsystems are presented as working features.

## Reviewed baseline

Reviewed Phase 1 migrations, root `DATABASE_PLAN.md`, conceptual ERD, schema inventory, validation/recovery plan, hosted deployment report, generated public types, account/branch/staff authorisation helpers and document/Storage policies. The verified deployed Phase 1 baseline is 12 migrations, 79 tables, PostgreSQL17.11. The native replay checks every Phase 1 migration and reference-seed SHA-256 against `deployment-candidate.sha256`; all remain unchanged. No hosted command or connection was used in this increment. The configured project remains `utoxjlsvqfmmzsjruzsm`.

## Delivered capability and explicit boundaries

| Module | Implemented in this increment | Remaining |
| --- | --- | --- |
| A: requests | Account/branch/department-scoped drafts, immutable catalogue/schema/location references, scheduling preferences, instructions, private revisions, customer-visible event history, clean document links, duplicate creation protection, row-locked optimistic amendments, submit/review/cancel commands, server-side form validation. | Post-submission amendment negotiation, address rescheduling history, branch-scoped upload preparation, explicit guaranteed availability/coverage promise and corporate pre-submission threshold-approval workflow. Existing upload preparation supports account-wide requesters; branch-only requests currently need an already-provisioned account address/document. |
| B: quotations | Versioned commercial proposals, independently approved release, customer/branch approver acceptance/rejection, expiry enforcement and recorded expiry, immutable accepted scope/lines, exact numeric quantity/prices/discount/tax calculations, tax configuration references, decimal-string money RPC, idempotent preparation. Five pricing modes inherited from the exact service version. | Assessments/appointments and evidence, automatic fixed/rate-card/starting/quantity pricing, variant/package selection, assessment-required release gates, configurable approval thresholds and currency minor-unit scales. Current commands are for manually scoped OnIt quotations; they do not claim to implement a pricing engine. |
| C: provider network | None added. Existing profiles/organisations/identity documents are reusable dependencies. | Provider identities, organisations, execution personnel/partners, eligibility/coverage, onboarding, verification/training, availability, capacity, restrictions, lifecycle and permissions. |
| D: dispatch | None added. | Explainable matching, staff-controlled proposals, offers/responses/expiry, assignments, reassignment, locking/reservation/release, override approvals and capacity concurrency tests. |
| E: fulfilment | None added. | Confirmed orders, work tasks, progress projections, checklists, supervision, QA/rework, confirmations, complaints/incidents, schedules and closure. |
| F: specialised operations | None added. | Laundry custody/counts/processing partners; construction milestones/change orders; field campaigns/task isolation; procurement suppliers/quotes/PO/delivery. These must extend shared orders/tasks rather than create parallel order systems. |

Quotation acceptance produces **no order, payment confirmation, wallet entry, payout or settlement**. These are separate future commands/domains. All quotes require independent approval in this increment; no new authority is assigned automatically to existing roles. No commercial or tax reference rates were seeded.

## Exact migration inventory

1. [`20261025000100_service_requests.sql`](../../supabase/migrations/20261025000100_service_requests.sql): four new permission definitions; requests, tenant-consistent location/branch/schema FKs; revision/history/idempotency/attachments; bounded form validation; transactional commands; RLS; narrowly extended linked-branch document reads.
2. [`20261025000200_quotation_workflow.sql`](../../supabase/migrations/20261025000200_quotation_workflow.sql): tax configuration, quotation identity/revisions/lines/decisions; exact decimal calculations; independent approval, acceptance/rejection/expiry; immutable accepted data; decimal-string read RPC; RLS and FK indexes for candidate-owned tables only.

Ten tables added, six public and four private. Combined local candidate: **89 application tables (51 public / 38 private)**. [Schema dictionary, relationships and ERD](phase-2-schema.md) describe ownership and lifecycle. Phase 1 SQL files and reference seeds were not edited.

## Server operations and types

[`lib/transactions/server.ts`](../../lib/transactions/server.ts) exports `transactionOperations(accessToken)` with typed create/change/review/attach/list-request and prepare/decide/read-quotation operations. It uses the public anon key with the caller JWT, validates the session using Auth `getUser`, and depends on database permissions/tenant checks for every write. It has a `server-only` boundary, no service-role client, no session persistence and no token/payload logging. The small `server-only@0.0.1` dependency enforces the browser import boundary. No route or UI exposes these candidate operations yet.

Request lists have account/status filters, deterministic created_at/id ordering, bounded offset and limit. SQL row locks and expected revisions reject stale edits. Create/quote commands use actor+operation+key uniqueness, an advisory transaction lock and exact payload comparison; a reused key with changed input fails. Decision retries by the same actor are idempotent. Amendments are full replacement of supplied answers and scheduling preferences: omitted start/end clears the preference window.

Money inputs are decimal strings; PostgreSQL performs all financial arithmetic. `read_quotation` returns quantities, prices, rates and totals as strings. Customer-facing quote rows contain no provider costs/margins. Currency is inherited explicitly from the customer account; this increment rounds commercial totals per line to two decimals and explicitly rejects currencies configured with another minor-unit scale. Multi-scale currency arithmetic is deferred; current operational reference currency is NGN. Do not calculate financial totals using JavaScript number-valued low-level table responses.

[`types/database.phase2.generated.ts`](../../types/database.phase2.generated.ts) is a separately labelled **local native PostgreSQL catalog-derived candidate**, generated after passing replay. Existing hosted [`database.generated.ts`](../../types/database.generated.ts) and the current browser client remain aligned with deployed Phase 1. Candidate types exclude private schemas. Canonical Supabase CLI generation is still required after a separately authorised hosted deployment.

## Executed validation

`node scripts/database/test-phase2-native.mjs` / `npm run db:test:phase2` restored the verified pre-Phase-1 Auth/Storage archive into a newly created, disposable loopback PostgreSQL17.11 database. It replayed all14 migrations, applied reference seeds twice, ran **190 SQL assertions** (76 Phase 1 foundation +50 refinements +64 transaction assertions), then used five separate connections for three concurrency checks. All passed. Catalog gates additionally verify89 RLS tables, private-schema exclusion, definer search paths and revoked client write/internal function grants. Local fixtures were committed only in that disposable database for multi-connection testing; normal SQL test files end with ROLLBACK. No hosted fixtures were inserted.

Coverage: individual/corporate/branch isolation; permission/self-elevation boundaries; typed/required/conditional/hidden/choice/numeric form validation; stale revisions; duplicate submissions and conflicting idempotency keys; cancellation; clean versus quarantined/foreign documents; linked branch downloads; quote revisions/supersession, exact discount/tax/rounding; independent approval; customer acceptance and retry; expiry; accepted-scope immutability; history immutability; all-table RLS. Two simultaneous creates converged on one UUID/command record; competing amendments produced one winner and one stale-revision error.

The first validator run found an uninitialised document-size record; corrected to a scalar. The first quote calculation run found an ambiguous PL/pgSQL column reference; qualified it. Corporate fixture required-field/UUID errors were corrected. The native type adapter's aggregate alias collision was corrected. Passing results are from subsequent full reruns, not inferred from fixes.

`node scripts/database/generate-phase2-types.mjs` generated candidate types. Final `node node_modules/typescript/bin/tsc --noEmit` and `node node_modules/eslint/bin/eslint.js .` both passed with exit code 0. `git diff --check` passed with Windows line-ending notices only. Machine database evidence: [phase-2-test-results.json](phase-2-test-results.json).

Not executed: hosted Phase 2 tests/deployment, real Auth JWT/REST/Storage HTTP for candidate functions, full Supabase Docker stack, server-adapter HTTP tests, dispatch/capacity, provider/supplier work access, fulfilment/QA or specialised-domain tests. Those modules are **not implemented**, so no passing results are claimed for them. SQL tests do not fully replace HTTP tests. Native Windows PostgreSQL uses local superuser migration ownership; hosted Supabase's managed DDL environment still needs a reviewed dry run.

Dependency audit during the server-only installation reported two advisories in existing Next16.4.0 and transitive Zod, with Next16.4.3 and Zod>=4.6.6 fixes reported by npm. `server-only` was not named as vulnerable. No framework upgrade or force audit repair was performed as part of these SQL changes. Resolve and revalidate these dependencies before exposing new web endpoints.

## Review/deployment readiness and recovery

This is a **reviewable local foundation increment**, not a complete Phase 2 deployment candidate. Do not apply it hosted under the prior Phase 1 approval. Complete the outstanding commercial/assessment gates and review operation authority/retention rules before production use; complete C–F in further additive increments. No application/UI changes or live payment mechanisms were introduced.

Before any future deployment: obtain separate explicit approval, inspect hosted migration/history drift and settings read-only, refresh/restore-test a backup, test an upgrade from deployed Phase 1 on PostgreSQL17 and the complete Supabase HTTP surface, compare candidate types, and review `db push --dry-run` for the exact approved files. Existing instructions that assume exactly12 migration files are historical Phase 1 evidence; do not run deployment helpers blindly against the new directory. Reference seed needs no new hosted execution for this increment.

Recovery is forward-fix/additive, retaining request and commercial history. Do not drop these tables or reset a real database. If a deployed command fails, pause the caller feature, inspect transaction rollback and audit evidence, and deploy a reviewed correction. Never replay synthetic fixtures against hosted data.

## Next increments and Phase 3 dependencies

Finish Module B assessment records/release gates and service configuration-driven pricing first. Build confirmed orders from accepted snapshots with a unique accepted-quote link and independently configured payment gate; preserve the distinction between acceptance and payment. Add provider parties/personnel/partners before eligibility, offers and concurrency-safe capacity reservations. Add fulfilment tasks/QA/rework and typed evidence access before Laundry custody, construction, field campaigns and procurement extensions. These are still Phase 2 work, not silently moved into Phase 3.

Phase 3 payment/financial work should depend on verified orders, immutable accepted quotation/currency/tax snapshots, idempotent commands, trusted provider/supplier identities and approval boundaries. Ledger/wallet/payout/compliance design remains separately scoped; this increment enables none of those live capabilities.

## Changed files

- New migrations: the two files listed above; new SQL tests: `supabase/tests/003_service_transactions.sql`.
- New server operations: `lib/transactions/server.ts`; candidate types: `types/database.phase2.generated.ts`.
- New tools: `scripts/database/test-phase2-native.mjs`, `test-request-concurrency.mjs`, `generate-phase2-types.mjs`. Updated `write-types.mjs` adds an optional output filename/source label while retaining embedded defaults.
- New documentation/evidence: this report, `phase-2-schema.md`, `phase-2-test-results.json`. Updated root plan, schema inventory, conceptual ERD and implementation status link to this local increment.
- `package.json` / lockfile: server-only boundary package and local test/type-generation scripts.

No Phase 1 migration, reference seed, hosted type file, browser Supabase client or .env.local value changed in this increment. No commit or deployment was performed.
