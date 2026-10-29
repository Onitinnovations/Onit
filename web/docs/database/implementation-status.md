> Verified combined Increments 5–6 deployment (2026-10-29): OnIt utoxjlsvqfmmzsjruzsm, PostgreSQL 17.11, 48 recorded migrations / 180 RLS tables (51 public, 129 private). Original rows and tested definitions verified; canonical types regenerated. [Consolidated report](phase-2-increments-5-6-report.md). Authenticated workflow HTTP tests and real operational configuration remain outstanding. Earlier dated entries are historical.

> Increment 5 local candidate (2026-10-27): six additive migrations, 16 private tables; 32 migrations / 142 RLS tables (51 public, 91 private). Hosted remains at Increment 4: 26 / 126. See [fulfilment report](phase-2-increment-5-report.md), [dictionary](phase-2-increment-5-dictionary.md) and [ERD](phase-2-increment-5-erd.md). No commit/push/deployment or Increment 6 work. Earlier status entries below are historical.

> Hosted checkpoint (2026-10-27): Increment 4 deployed and verified on OnIt, PostgreSQL 17.11: 26 migrations / 126 RLS tables (51 public, 75 private); canonical types updated. [Deployment report](phase-2-increment-4-hosted-deployment-report.md). Increment 5 was not started. Earlier local-only progress entries below are historical.

> Current hosted checkpoint (2026-10-27): Increment 3 deployed and verified on OnIt: 22 migrations, 115 RLS tables (51 public / 64 private), PostgreSQL 17.11. Canonical types updated. See [deployment report](phase-2-increment-3-hosted-deployment-report.md). Increments 4?6 remain unimplemented; earlier status entries below are historical.

> Current hosted status (2026-10-26): Phase 2 Increments 1 and 2 deployed to OnIt; 17 migrations and 93 RLS tables verified. Canonical hosted types and application checks passed. Authenticated workflow HTTP tests remain outstanding. See [release checkpoint](phase-2-hosted-deployment-report.md). Earlier local-only statements below are historical.

> **Current hosted status (2026-10-24): Phase 1 deployed and verified on OnIt, PostgreSQL 17.11. All 12 migrations applied; 79 tables have RLS. Native backup restore and 126 SQL assertions passed. Official hosted types and app checks passed. See [hosted deployment report](hosted-deployment-report.md). Earlier blocked-readiness statements below are historical and superseded.

Local development: [Phase 2 request/quotation increment](phase-2-report.md) adds two migrations and ten tables, tested on PostgreSQL 17. It is not deployed and does not complete provider/dispatch/fulfilment or specialised operations.

Latest local increment: [pricing/assessments and quotation completion](phase-2-increment-2-report.md), with three additional migrations/four private tables. Local total93 RLS tables; hosted Phase 1 unchanged. Provider Network Increment 3 is the next domain boundary.

# Implementation status — foundation phase

**Current record:** [phase-1-report.md](phase-1-report.md). The latest implementation request superseded the runtime stop described below. Twelve migrations, 79 RLS-protected tables and public TypeScript types are implemented; embedded SQL and upgrade validation ran. Hosted/Supabase validation remains blocked by Docker and authorised inventory access. All sections below are retained historical progress notes and must not be read as the current delivered scope.

Date: 2026-10-24, Africa/Lagos. The user approved continuing after the initial architecture review pause, and subsequently asked to fix the missing runtime.

## Latest conditional approval and readiness recheck

The latest request conditionally approves the architecture, limits implementation to Phase 0/Phase 1 and explicitly requires stopping before local migrations if the environment is unavailable. Current checks found Supabase CLI 2.122.0 and Docker Client 29.9.2, but the Docker Linux server returns HTTP 500. `wsl --status` reports that WSL2 cannot start because virtualization/Virtual Machine Platform is not enabled/effective. An installed/running Docker Desktop UI does not meet the readiness requirement.

Hosted read-only inventory also remains blocked: `supabase projects list --output json` returned “Access token not provided”; no linked project/database connection/management token was found. Only public app configuration names were inspected, without printing their values. No hosted schema or migration history is assumed empty or declared inspected.

Accordingly this request changes **documentation only**: [refinement addendum](phase-1-approval-refinements.md), [exact Windows/access steps and command results](windows-readiness.md), architecture plan, inventory, ERD, README and this status. No new SQL, migration application, seed, embedded/local database test, type generation or deployment was attempted. Existing six SQL files and earlier test results below remain historical and do not implement the newly requested refinements.

The exact new requirements are mapped to proposed pricing modes, conditional/versioned booking schemas, repeatable groups, rule/dependency integrity, branch-scoped corporate membership and centralised billing/credit/approval versions. Delivery responsibility/custody and CMS/catalogue/location references are documented for later phases; their modules remain unimplemented. No separate Auth system/ORM, AWS deployment or hosted mutation is introduced.

Next steps are prerequisite actions, not another architecture approval: complete Windows runtime recovery and verify Docker Server readiness; authenticate the CLI or make an authorised read-only schema/history export available; then resume the small Phase 1 refinements and real local Supabase validation. All earlier 70-table dictionary and 76-assertion results remain explicitly supplemental until that validation succeeds.

## Delivered

| Artifact | Implemented scope |
| --- | --- |
| `20261024000100_identity_access.sql` | Auth-linked profiles, idempotent provisioning/backfill, organisations/membership/departments/teams, minimal employment anchor, scoped roles/permissions, preferences/devices/session metadata, immutable audit/activity, secure authorization helpers and RLS/grants. |
| `20261024000200_geography_customers.sql` | NG/currency/geography structures, operational zones/coverage, individual/corporate accounts and explicit corporate access, addresses and immutable location snapshots, private CRM basics, customer support/consent/preferences with account isolation. |
| `20261024000300_service_catalogue.sql` | Versioned areas/families/services, variants/options/forms/checklists, private rates/pricing, availability/exclusions/FAQ snapshots and publication RLS; immutable published version content. |
| `20261024000400_approvals_documents.sql` | Shared approval routing skeleton, settings, document registry and typed links, service media, seven private buckets and one public marketing bucket, registry-based Storage policies. |
| `20261024000500_foundation_commands.sql` | Authorized/idempotent individual-account RPC, own-address and quarantined-upload RPCs, rate-card currency FK, historical TRUNCATE guards, FK/query indexes and public-schema creation restrictions. |
| `20261024000600_configuration_integrity.sql` | Released policy/rate/configuration immutability, parent locking for rate-card child edits and additional security audit triggers. |
| `supabase/seed.sql` | Idempotent NG/NGN/Lagos reference data; four draft service areas, six draft families and fifteen plain-name draft services; no prices, taxes, payroll, payouts, live credentials or real users. |
| `supabase/config.toml`, `supabase/.gitignore` | Pinned local CLI configuration, private schemas not exposed, explicit-grant API model, local Auth settings and ignored CLI state. |
| `supabase/tests/001_foundation.sql` | 76 rollback-only SQL/security assertions with synthetic users and scoped actor fixtures. |
| `scripts/database/` | Embedded SQL runner/bootstrap, fixed-local-container SQL runner, local Auth/REST/Storage API test, safe type generation, catalog-derived dictionary/FK graph generator, elevated no-restart WSL setup script. |
| `package.json`, `package-lock.json`, `.gitignore` | Exact development pins for Supabase CLI 2.122.0 and PGlite 0.5.11, database scripts and ignored local installation logs. PGlite is a test dependency, not an ORM. |
| Documentation | Architecture, requirement inventory, conceptual ERD, generated per-table dictionary and physical graph, validation/recovery procedure, local development instructions and this report. |

**70 base tables** are implemented with RLS. This is the identity/geography/customer/catalogue foundation plus early audit/approval/file/configuration infrastructure. Supplier/provider-specific business tables, booking/dispatch/delivery, service-specific operations, BFS, procurement/inventory, the financial posting engine, full HR, CMS and remaining governance are **not yet implemented**. Their complete proposed mapping remains in `schema-inventory.md`. The employee identity table is an early access-control anchor, not a completed HR system. Approval tables are structural only; typed domain targets and approval executors come with their phases. Published service FAQs currently store immutable version snapshots; later shared CMS FAQ sources may link without replacing history.

## Executed verification

- All six migrations applied successfully in a new in-memory PGlite PostgreSQL instance. No hosted or local Supabase database migration was applied.
- Reference seed executed twice successfully; no duplicate reference data.
- **76 SQL/security assertions passed**, covering Auth-trigger/backfill behavior against the SQL scaffold, customer/corporate isolation, membership expiry/revocation, neutral provider/supplier subject denial, multi-role individual provisioning, unauthorized writes, employment/permission requirements, tenant/geographic constraints, publication/version/rate immutability, independent approval constraint, immutable audit, SQL-level Storage isolation/quarantine/path forgery and privilege catalogs.
- Dictionary generated from PostgreSQL catalogs for all 70 tables, including columns/types/defaults, FKs/deletion rules, uniqueness/checks, indexes, RLS/grants, physical/business ownership, lifecycle and function boundaries. Foundation FK graph generated from actual constraints.
- `npm run lint` completed successfully on the new JavaScript tooling and existing application during implementation. Final verification is recorded below if amended.
- The local Supabase start attempt failed with `DockerLifecycleInspectError`: Docker's Linux engine pipe was unavailable. Real Auth/REST/Storage HTTP tests, Supabase SQL tests, type generation, upgrade/recovery rehearsals and full later-domain security tests have **not** passed or been claimed.

The embedded suite found that schema-local function default privilege revocation does not subtract PostgreSQL's global PUBLIC EXECUTE default. The migration now revokes that global default for the migration owner, and the catalog assertion verifies no PUBLIC execution on internal helpers. Tests also validate safe helper ownership/search paths without FORCE RLS recursion.

## Runtime repair performed

Docker Desktop was discovered in the per-user install outside PATH. Docker CLI **29.6.2** is verified. The installed Desktop package reports 4.83.0; a winget per-user upgrade attempt offered no applicable upgrade and changed no package.

Windows hardware virtualization is enabled, with 16 GB RAM and sufficient disk. WSL was absent. The reviewed `enable-wsl.ps1` script was run through Windows administrator elevation, `wsl --install --no-distribution --web-download` completed with exit code 0, and Windows reported the requested changes will **not be effective until reboot**. No distro user setup, automatic restart, Docker volume deletion or hosted database operation was performed. WSL installation logs/status remain local and ignored; do not commit machine details from them.

**Next dependency: save work, restart Windows and start Docker Desktop's Linux engine.** Then execute the local sequence in `README.md`, fix any genuine Supabase differences, and pass the foundation SQL and HTTP gate before generating phase 2 migrations. This pause is required by the original execution order, not another architecture approval request.

## Limitations and unresolved decisions

Remote schema/role/Storage policy history remains unverified. Never deploy these migrations to the hosted project until authorized read-only reconciliation/baseline and backup/recovery review are complete. Existing object conflicts intentionally fail instead of silently adopting or replacing them. No service-role secret is added to frontend code or `.env.local`.

Security-definer functions run as the trusted migration/table owner with pinned empty search paths, not a newly created privileged role. This is an explicit implementation adjustment from the initial non-login-owner proposal; it avoids inventing unsupported hosted role grants. Private schemas are unexposed and browser grants are narrow. Subject-scoped server commands for contracts, HR, invoice and field evidence downloads are deferred; these buckets deny direct end-user access meanwhile. There is no production document-scanning worker or live sender/payment handler.

Wallet/payout/live-email defaults are false; those executors and the accounting ledger are absent, not activated. Finance balancing/replay/concurrency tests cannot be claimed until finance SQL exists. Reference catalogue and coverage remain draft; approvals, commercial terms, zones, retention/legal holds, tax/payroll and compliance activation still need operational configuration in their respective phases.

`npm audit` also reported existing Next.js and transitive Zod vulnerabilities. No unrelated framework/dependency upgrade was performed. This finding is recorded for follow-up and is not attributed to the database migrations. No qualifying Next.js runtime/CLI/documentation issue was observed during this work; the Next.js feedback pass has no candidates.
