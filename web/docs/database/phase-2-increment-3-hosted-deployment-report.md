# Increment 3 hosted deployment checkpoint

Date: 2026-10-27, Africa/Lagos. **Deployed and verified.** Increment 4 was not started.

## GitHub and target

Existing repository https://github.com/Onitinnovations/Onit, branch main. Implementation commit: 42edf960db6eb4886eb4fc56d55205febff0cc4c, successfully pushed without force. The final checkpoint separately records canonical types and this deployment evidence. The unrelated logo remains untracked and untouched. No credentials, environment files, dumps or local runtime state were committed.

Verified project: OnIt, utoxjlsvqfmmzsjruzsm, ACTIVE_HEALTHY, PostgreSQL 17.11. Before deployment: exactly 17 migrations and 93 RLS tables, with no application-definition drift against native replay. All 17 deployed migration hashes and the original reference seed matched their manifests.

## Recovery gate

Fresh custom-format logical backup: C:/Users/HP/OnIt Database Backups/increment3-20261027/pre-increment3-1793057412442.dump, outside the Git repository, with inheritance disabled and explicit current-user/SYSTEM access. Size: 1,042,517 bytes. SHA-256: 876507816f3c1e3a57c35031da85941be148f3429788e14da9fbe924782a4745.

Restored successfully into an isolated loopback PostgreSQL 17.11 database. Hosted/restored application definitions and all 93 table row counts/digests matched. The restored copy upgraded through all five migrations to 115 RLS tables. Recovery evidence: [predeployment verification](phase-2-increment-3-predeployment.json).

Scope: public, private, app_private, auth, storage, extensions and supabase_migrations schemas/rows. This is logical recovery evidence, not certification of Supabase-managed recovery. It excludes Storage object binaries, cluster roles/globals, Vault secrets, external integrations, platform settings and PITR. No Storage objects existed at inspection. Restore recovery first into an isolated compatible environment using pg_restore --exit-on-error --no-owner, retaining ACLs and reviewing managed-role prerequisites; the rehearsal skips only creation of the already-existing public schema. Compare definitions/row digests before planning any separately authorised production recovery. Never reset or overwrite the hosted database as a rollback. Prefer a reviewed forward fix and pause affected callers if needed.

## Exact deployment

The official CLI dry run returned exactly these files; they were then applied successfully in this order:

1. 20261026000100_provider_network.sql
2. 20261026000200_provider_commands.sql
3. 20261026000300_provider_eligibility.sql
4. 20261026000400_provider_reads_events.sql
5. 20261026000500_personnel_resources.sql

The prior 17 were already present and were not reapplied. Commands used the existing linked target explicitly:

```text
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --dry-run
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --yes
```

No seed, role sync, synthetic fixtures, providers, qualifications, commercial rates or user permission assignments were applied. A final dry run reported upToDate=true, with empty migrations/seeds/roles lists.

## Verification results

- Disposable native PostgreSQL 17.11: all 22 migrations, 363 SQL assertions, 11 separate-connection concurrency checks and six upgrade-preservation checks passed. Includes party capacity and shared-worker races, provider isolation, qualifications, document boundaries, immutable histories and worker lease security. [Executed test evidence](phase-2-operations-test-results.json), [exact migration hashes](phase-2-operations-candidate.sha256).
- Hosted: 22 recorded migrations; 115 application tables (51 public, 64 private); zero missing RLS. Full application definitions match the tested local candidate, including constraints, indexes, functions, triggers and Storage policies. All pre-existing rows match the predeployment digests using their original columns.
- No public SECURITY DEFINER functions, unsafe helper search paths, PUBLIC internal-function execution, browser private-schema USAGE, client private-table grants or client transaction-write grants. Anonymous/authenticated roles cannot execute the operational event worker. Seven private Storage buckets and the public marketing bucket retain their original configuration.
- HTTP: Auth settings and public catalogue returned 200; anonymous request/quotation reads returned 401; private/app_private API profiles returned 406; anonymous Storage bucket listing returned an empty array. The application URL/anon-key configuration still connects to the verified project. No environment changes.
- Canonical public-schema types generated with the official CLI from the hosted project; private schemas excluded. TypeScript and ESLint passed after generation. Dependency audit returned zero vulnerabilities. Migration integrity and text/credential-pattern checks passed.

[Hosted verification evidence](phase-2-increment-3-hosted-verification.json) records the actual catalog and HTTP results.

## Outstanding integration limits and next boundary

Hosted Auth user count is zero. Authenticated provider/customer/corporate workflow HTTP, signed-in Storage downloads and server-adapter HTTP tests were not run; no test identities or transactions were created. SQL/concurrency tests ran only against disposable local fixtures and do not replace those integration tests. No full Docker Supabase runtime test or production-volume benchmark is claimed.

New permission definitions have no automatic user/role assignment. Real onboarding, approved eligibility/capacity configuration, document verification, worker deployment and downstream notification delivery require deliberate administration/integration. There is no external verification service, deployed scheduler or live sender. Quote acceptance still has no order/payment side effect.

Ready to commence Increment 4 development on the deployed provider/personnel foundation. Orders, matching/dispatch, multi-person atomic assignment conversion, fulfilment and specialised operations remain future work. No AWS, payment, wallet or settlement work was performed. Future migrations require their own deployment approval.
