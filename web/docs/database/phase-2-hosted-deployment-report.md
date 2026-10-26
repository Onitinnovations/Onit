# Phase 2 Increments 1 and 2 — hosted release checkpoint

Date: 2026-10-26, Africa/Lagos. **Deployment completed and hosted catalog/API boundaries verified.** Authenticated end-to-end business workflows remain outstanding because the project has no Auth users and this release did not authorise creating hosted test identities or transactions. Increment 3 was not started.

## Repository and security checkpoint

Repository: https://github.com/Onitinnovations/Onit, existing `main` branch. Implementation commit **97267ee2407ac88ec011b1f612e7aefbe451f65b**, message `feat: complete OnIt Phase 2 requests pricing and assessments`, pushed successfully without force or history rewriting. The final release-evidence/canonical-types checkpoint is a separate commit; obtain its exact hash with `git log -1` after checkout.

All 12 deployed Phase 1 migration hashes and the reference seed match the original deployment manifest. The five candidate migration hashes match the successful PostgreSQL 17 replay and [candidate manifest](phase-2-candidate.sha256). No deployed migration was edited. The only Phase 1 test adjustment supplies an independently approved synthetic pricing fixture when the new command exists.

Compatible security updates: Next.js and eslint-config-next **16.4.3**, transitive Zod **4.6.7**. Final `npm audit --json` reported **zero vulnerabilities**. No force audit repair or breaking upgrade was used. This audit result is a dependency advisory check, not a guarantee against all vulnerabilities.

Secrets, environment files, node_modules, local database state, external backups and temporary files were excluded. The unrelated untracked `public/OnIt Final Logo.png` was preserved and excluded. Environment values were not changed. No Next.js runtime/documentation issue qualified for the agent feedback reporting pass.

## Target, recovery and predeployment checks

Verified target: **OnIt**, project **utoxjlsvqfmmzsjruzsm**, region eu-west-1, ACTIVE_HEALTHY, PostgreSQL **17.11**. CLI authentication succeeded. The existing project link was not changed.

Hosted history contained exactly the expected 12 Phase 1 versions and no Phase 2 versions. An inventory examined application columns, constraints, indexes, functions, triggers, RLS, extensions and Storage configuration. Application definitions, including function bodies, policy predicates, constraints, indexes and relevant triggers, matched a fresh Phase 1 replay. Private schema grants and RLS checks passed. Evidence: [predeployment inventory and recovery checks](phase-2-predeployment.json).

Fresh backup: `%USERPROFILE%\OnIt Database Backups\phase2-20261026\pre-phase2-1793050904684.dump`, **788,785 bytes**. The directory is outside the Git repository, with inherited access removed and access restricted to the current Windows user and SYSTEM. The SHA-256 is recorded in the predeployment evidence. Preserve this file and its restricted ACLs; do not add it to Git.

Scope: logical archive of `public`, `private`, `app_private`, `auth`, `storage`, `extensions` and `supabase_migrations`, including rows, definitions and recorded privileges. The archive restored successfully into an isolated loopback PostgreSQL 17 database. Catalog comparison and all 79 application-table row-count/digest comparisons passed. The five candidate migrations also applied successfully to that restored database, producing 93 RLS tables.

This is **not complete managed Supabase recovery**: Storage binaries, global roles, Vault secrets, platform settings, external integrations and managed PITR are not included. Auth/Storage SQL metadata is included; hosted user/object counts were zero. Global provider roles were already available in the local rehearsal environment. Managed recovery availability was not certified.

Recovery: preserve the original archive/hash, restore into an isolated PostgreSQL 17 environment using `pg_restore --list` to inspect contents and `pg_restore --exit-on-error --no-owner --use-list <reviewed-list> --dbname <isolated-database> <archive>`. A fresh PG17 database already has `public`; the rehearsal list excludes only its schema-creation entry, retaining contents and ACLs. Never restore this archive over the live project automatically. For live incidents, pause affected callers, retain audit/history and use a reviewed additive forward fix. Any managed recovery or destructive restoration requires a separate plan and approval.

During rehearsal, the CLI rejected a SQL string beginning with a comment; file-based input fixed it. Initial comparison attempts encountered object-key ordering and timestamp timezone differences; order-independent comparison and UTC/C-collation row digests resolved these. The final successful recovery evidence is from a complete rerun. No migration was deployed while these checks were unresolved.

## Official migration deployment

Predeployment `db push --dry-run` listed exactly these five files; seeds and roles were empty:

1. `20261025000100_service_requests.sql`
2. `20261025000200_quotation_workflow.sql`
3. `20261025000300_pricing_configuration.sql`
4. `20261025000400_assessment_workflow.sql`
5. `20261025000500_pricing_quotation_engine.sql`

Executed with the pinned official CLI:

```powershell
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --dry-run
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --yes
```

All five applied successfully. The original 12 were already present and were not reapplied. `--skip-vault` avoided unrelated Vault synchronisation. No seed, synthetic fixture, real identity, price card, tax rate, customer, payment or role assignment was created. No reset, destructive rollback or migration-history repair occurred. The final identical dry-run command returned `upToDate: true`, migrations/seeds/roles all empty.

## Validation and hosted results

| Check | Result |
| --- | --- |
| Disposable native PostgreSQL 17.11 | All 17 migrations; **261 SQL assertions**, **4 real concurrency checks**, **6 upgrade checks** passed. |
| Migration/seed integrity | All 12 Phase 1 files and seed unchanged; all 17 candidate hashes checked. |
| Hosted history/table count | Exactly **17 migration versions**, **93 application tables** (51 public / 42 private). |
| Hosted RLS/grants | No missing RLS, public definers, unsafe helper search paths, PUBLIC internal execution, client transaction-write grants or browser private-schema USAGE. |
| Original Phase 1 data | Counts and digests of original columns/rows unchanged across all 79 tables. New permission definitions and audit events are additive. |
| Storage | Seven private buckets and public marketing bucket settings preserved; no anonymous bucket metadata returned. |
| Application connection | Existing configured target/key worked: Auth settings and catalogue HTTP 200. |
| API exposure | Anonymous request/quotation reads HTTP 401; private and helper schema requests HTTP 406. |
| Authenticated workflows | **Not executed hosted:** zero Auth users; no approved identities available. No hosted fixtures created. |
| Canonical types | Official CLI `gen types typescript --project-id utoxjlsvqfmmzsjruzsm --schema public`; updated `types/database.generated.ts`. Private schemas excluded. |
| Application checks | Post-generation TypeScript and ESLint exit 0; `git diff --check` passed with line-ending notices only. |
| Dependency audit | Zero reported vulnerabilities after compatible patches. |

Hosted evidence: [verification results](phase-2-hosted-verification.json). Local evidence: [database test results](phase-2-test-results.json). Increment reports/schema documents describe the 14 new tables and reused pricing/governance relationships.

Local SQL tests cover individual/corporate/branch isolation, request/form commands, quotation arithmetic/revisions/immutability, approval restrictions, mandatory assessment gates and concurrency. Hosted catalog checks confirm the deployed guards and grants; they do **not** replace authenticated HTTP verification. Customer/staff/approver sessions, private-file downloads and server-adapter workflow HTTP tests remain outstanding. No claim of hosted business-transaction execution is made.

## Final readiness

The completed Increments 1 and 2 are deployed and ready to support **Provider Network Increment 3 development**. Complete authenticated API/Storage tests with separately approved identities before enabling production-facing transaction endpoints. Review operational permissions and independently approve real pricing/tax/policy configuration before commercial use; no new authority was automatically assigned. Orders, dispatch, providers, payments, wallets, payouts and settlement remain outside this release.

The final repository checkpoint includes canonical hosted types, sanitised release evidence, this report and reproducible inspection/verification scripts. The candidate type file remains explicitly labelled as the historical local fallback; the browser client now receives the canonical hosted public-schema types.
