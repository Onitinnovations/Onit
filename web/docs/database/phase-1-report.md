> **Current hosted status (2026-10-24): Phase 1 deployed and verified on OnIt, PostgreSQL 17.11. All 12 migrations applied; 79 tables have RLS. Native backup restore and 126 SQL assertions passed. Official hosted types and app checks passed. See [hosted deployment report](hosted-deployment-report.md). Earlier blocked-readiness statements below are historical and superseded.

# OnIt Phase 1 implementation and validation report

Date: 2026-10-24, Africa/Lagos. This is the current implementation record and supersedes earlier readiness-stop documentation. The latest task explicitly authorised local migration development when remote access is unavailable. No hosted SQL, migration, data mutation, AWS deployment, reset or Windows configuration change was performed in this implementation pass.

## A. Implementation summary

Phase 1 is implemented and reviewable in the repository: **12 ordered migrations; 79 application tables with RLS (45 public, 34 private); public-schema TypeScript types integrated with the existing Supabase client; tests, safe seeds, dictionary, ERD, RLS guide and deployment procedure**. The original six migrations are preserved; six additive migrations implement the required refinements. No new ORM/password system or Phase 2 booking/dispatch/payment/wallet workflow is introduced.

| Domain | Delivered |
| --- | --- |
| Identity/access | Supabase Auth shared-PK profiles; neutral idempotent provisioning/backfill; organisation/department/team membership; roles/permissions with global/organisation/team boundaries; active internal employment prerequisite; lifecycle and audited privileged changes. |
| Individual/corporate accounts | Canonical individual-or-organisation customer account; approved corporate membership; requester/approver flags; branch-specific grants, canonical operating locations, contact/address separation, central billing identity versions and independently approved payment-day configuration. No invoice, credit balance or full credit authorizer. |
| Geography | UUID country/currency/state/city/LGA/zone hierarchy, same-state coverage FKs, lifecycle and service availability. New-address command checks active consistent geography. No Lagos-specific business logic. |
| Catalogue | Four approved roots, service families/services/variants/versions, publication gates and immutable terms; fixed/starting/quantity/assessment/custom pricing-method configuration without a pricing engine or invented amount. |
| Dynamic forms | Stable form identity, numbered effective schemas pinned to service versions, ordered repeatable groups, field types/options/requiredness/visibility, same-schema typed dependencies with cycle protection, bounded validation rules and publication integrity. No customer submission/booking engine. |
| Documents | Private metadata registry, immutable ownership/path, classification-derived visibility, typed customer links, generated quarantined uploads, seven private Storage buckets and a separate reviewed public marketing bucket. No binary blobs in PostgreSQL. |
| Governance | Append-only audit/approval evidence, actor/target/correlation metadata and changed-column names instead of raw sensitive payloads. Released configuration immutable; makers cannot approve their own decisions. |

The earlier six files already included additional CRM/support/preferences/checklist scaffolding. It is retained for repository compatibility, not silently removed or relabelled as a new Phase 2 implementation. The generated dictionary enumerates it. A minimal employee identity anchor is present; full HR/payroll is not. CMS and delivery-responsibility/custody relationships remain design commitments for later phases.

## B. Exact migration inventory

Execute in filename order under `supabase/migrations/`:

| Order/file | Purpose | Provenance |
| --- | --- | --- |
| `20261024000100_identity_access.sql` | Private/helper schemas, safe defaults, Auth profiles/provisioning, organisations/RBAC, audit/access policies | Existing baseline retained. |
| `20261024000200_geography_customers.sql` | Geography/currency, customer/corporate accounts, account-owned records and isolation | Existing baseline retained. |
| `20261024000300_service_catalogue.sql` | Versioned catalogue, forms fields/options, pricing/availability and history guards | Existing baseline retained. |
| `20261024000400_approvals_documents.sql` | Approval/settings skeleton, registry/media, Storage buckets and policies | Existing baseline retained. |
| `20261024000500_foundation_commands.sql` | Validated own-account/address/upload RPCs, FK/query indexes and hardening | Existing baseline retained. |
| `20261024000600_configuration_integrity.sql` | Released configuration/rate history and security audit triggers | Existing baseline retained. |
| `20261024000700_geography_pricing_lifecycle.sql` | Active geography, explicit pricing modes, tenant unique keys and public geography gates | New. |
| `20261024000800_versioned_booking_forms.sql` | Form/schema/group/dependency/rule tables, additive historical backfill, publication/immutability and RLS | New. |
| `20261024000900_corporate_branch_billing_foundation.sql` | Corporate branches, scoped grants, billing/credit-term configuration and isolation | New. |
| `20261024001000_phase_one_integrity.sql` | Audit correlation/change keys, document visibility, form/choice hardening and FK indexes | New. |
| `20261024001100_scoped_staff_access.sql` | Scoped customer/staff/team helpers, private HR file denial, governance auditing and active address validation | New. |
| `20261024001200_corporate_approval_configuration.sql` | Typed independently evidenced credit configuration approvals; no credit execution | New. |

All twelve were applied **only to new disposable embedded PostgreSQL databases**, not to hosted Supabase or the unavailable local Supabase stack. UUID generation uses PostgreSQL's built-in `gen_random_uuid`; no speculative extension installation is required. The hosted extension/version inventory is still unknown.

## C. Schema and security relationships

Auth users -> neutral profiles -> independent customer/employee/membership relationships. Customer account owner is exactly one individual profile or organisation. Corporate accounts extend organisation-owned customers; branches reference real same-organisation locations; allowed-branch grants link to exact account users. Membership/role expiry and revocation are read from current database state, not user-editable metadata/JWT role strings.

Service area -> family -> service -> service version -> form schema -> groups/fields/options/dependencies/rules. Published content is immutable; dependent objects use composite FKs for exact version/schema consistency. Dependency graph changes are serialized under parent locks and cycles rejected. AND applies within a condition group, OR across groups. Runtime answer validation belongs to Phase 2; these definitions contain no executable expressions.

Sensitive operations, RBAC, billing/credit configuration, registry and audit remain in unexposed `private`. Boolean/command implementations live in unexposed `app_private`; public RPC wrappers use invoker rights. Definers use the trusted migration owner and pinned empty search paths. All table privileges are deliberate and RLS is enabled. Exact grants/policies are in [data-dictionary.md](data-dictionary.md); intent/limitations in [rls-policies.md](rls-policies.md). See the actual [foundation FK graph](foundation-erd.md) and conceptual [ERD](erd.md).

## D. Executed validation and failures

| Command/check | Actual result |
| --- | --- |
| Repository and four architecture documents | Present and reviewed; existing Next.js 16.4/TypeScript/Supabase JS client conventions retained. Installed Next.js security guide read. |
| Bounded Docker `version` | Timed out after 20 seconds; Linux server unavailable. Earlier observed server HTTP 500/WSL virtualization failure remains relevant. |
| Supabase CLI `--version` | 2.122.0. |
| CLI `projects list --output json` | Failed: management access token/login absent. No schema inventory inferred. |
| Read-only public OpenAPI GET via configured anon configuration | Initial sandbox network error; retried with approved network access; HTTP 401. No data queries/hosted SQL. Sanitised report: `remote-public-inventory.json`. |
| Fresh embedded migrations | All 12 applied in dependency order successfully, on PostgreSQL **18.6** through PGlite 0.5.11. Test-only Auth/Storage scaffolding is not Supabase HTTP. |
| Reference seeds | Two passes; five count assertions verify one country, four areas, seven role definitions and no illustrative services/zones in reference data. |
| `001_foundation.sql` | 76 SQL/security assertions passed. |
| `002_phase_one_refinements.sql` | 50 SQL/security assertions passed. |
| `test-upgrade.mjs` | Four assertions passed: earlier six-migration database upgrades with existing published fields without losing IDs, text, anonymous visibility or publication state. |
| Dictionary/FK/type generation | Catalog-derived output generated after successful migration/SQL tests. 79-table dictionary; 45-table public API types; private schemas excluded. |
| ESLint and TypeScript | Passed separately with exit code 0: `node node_modules/eslint/bin/eslint.js .` and `node node_modules/typescript/bin/tsc --noEmit`. Compile-only client contracts enforce typed RPC arguments and absence of private/password APIs. |
| Documentation and diff checks | All 13 database Markdown files passed link/fence/whitespace validation; `git diff --check` passed, with only Windows line-ending notices. |

Total executed database assertions: **135** (126 SQL, five seed, four upgrade). The initial form-visibility test failed while schema publication was not yet reflected in its fixture; it was fixed and rerun. Upgrade testing motivated preserving existing publication state during backfill. An ESLint empty-object type issue in generated no-argument RPC types was fixed and lint rerun. No failures are silently marked passed.

Not executed/passed: actual Supabase/PostgreSQL **17** fresh install, real Auth JWT/trigger behavior, REST/Storage HTTP suite, canonical Supabase CLI type generation, concurrent connections, hosted-schema diff, remote production/test classification, restore/PITR rehearsal. Docker and authorised remote inventory are the exact blockers. PostgreSQL 18.6 embedded success does not certify the configured Supabase 17 target. Tests use only synthetic disposable identities and no live credentials/prices.

## E. Tooling, reference data and TypeScript

No new dependency was required in this pass; pinned Supabase CLI and development-only PGlite already existed. `supabase/seed.sql` now contains only Nigeria/NGN/Lagos State, four draft service areas, baseline role/permission definitions and disabled safe settings. It creates no users, staff memberships, customer accounts, prices, packages or operational zones.

`supabase/fixtures/catalogue-development.sql` contains labelled illustrative draft service families/services/Lagos pilot for tests only. SQL runners inject it inside each fixture's rollback transaction. It is not listed as a production/reference seed. No new booking or finance seed exists.

`types/database.generated.ts` is a **catalog-generated embedded fallback**, explicitly labelled as such, with row/insert/update/relationship/RPC types. `supabaseClient.js` uses it through JSDoc while preserving current environment names and Next.js imports. TypeScript negative checks validate private schema exclusion and mandatory RPC args. Regenerate via `npm run db:types:embedded`; use `npm run db:types` for canonical local Supabase output after runtime recovery. Type metadata grants no database access.

## F. Deployment and Phase 2 readiness

**Not ready to apply to hosted Supabase.** Project identity is known from configuration, but full remote schema, tables/indexes/constraints/functions/triggers/extensions/policies, actual PostgreSQL version, existing migration history and data classification are unknown. No comparison/deduplication can be certified. Risks include name collisions, an existing profile trigger, divergent history, incompatible default privileges, old broad Storage policies/bucket settings and the PostgreSQL 18-versus-17 validation gap.

Follow [phase-1-deployment.md](phase-1-deployment.md) for read-only inventory, local tests, backups, staged reconciliation, exact dry-run/apply commands and explicit approval gate. Do not run hosted apply commands until the final reconciled candidate has user approval. No request to deploy is made while readiness blockers remain.

Phase 2 can build on stable identities/accounts/branches, active geography, immutable catalogue/form versions, scoped authorisation, independent approval structures, documents and audit. It must add booking submissions and server-side answer validation, request/quote/order state machines, typed contractual-provider/execution/partner responsibility and custody, and task-specific provider/supplier access. No Phase 2 screens, orders, dispatch, provider allocation, payments or wallets were built.

## Changed-file map

- New SQL: migrations 007–012 above; `supabase/tests/002_phase_one_refinements.sql`; `supabase/inspection/remote_inventory.sql`; `supabase/fixtures/catalogue-development.sql`.
- Updated SQL: `supabase/seed.sql`; `supabase/tests/001_foundation.sql` (explicit schema publication in fixture).
- New tooling: `scripts/database/write-types.mjs`, `inspect-remote-public.mjs`, `test-upgrade.mjs`, `type-contract.ts`.
- Updated tooling: `test-embedded.mjs`, `local.mjs`, `local-client.mjs`, `generate-types.mjs`, `write-dictionary.mjs`; package scripts in `package.json`.
- Client/types: JSDoc typing in `supabaseClient.js`; generated `types/database.generated.ts`.
- Generated/revised docs: root plan, schema inventory, conceptual and physical ERDs, data dictionary, refinement addendum, validation/recovery, README/status, policy guide, deployment guide, this report and sanitized remote inspection JSON. The original untracked baseline files remain part of the reviewable repository change set; no commit is created.

No `.env.local` value or secret was changed, printed or committed. No qualifying Next.js feedback issue was observed; the reporting pass has no candidates.
