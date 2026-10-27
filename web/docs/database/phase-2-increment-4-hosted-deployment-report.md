# Increment 4 hosted deployment checkpoint

Date: 2026-10-27, Africa/Lagos. **Deployed and verified.** Increment 5 was not started.

## GitHub checkpoint

Repository: https://github.com/Onitinnovations/Onit. Branch: main.

Implementation/release-preparation commit: **294538a76d00e258f4ac30933cf3b6dc4ff73b82**, successfully pushed without force. Canonical types and postdeployment evidence are recorded in the separate commit titled **chore: record verified Increment 4 Supabase deployment**. The final release response records its hash; Git history identifies the commit containing this report.

The unrelated logo remains untracked and untouched. No environment file, credential, backup, runtime state or sensitive live-data fixture was committed. The 22 previously deployed migration hashes and original reference seed remained unchanged.

## Verified target and predeployment gates

Project **OnIt**, reference **utoxjlsvqfmmzsjruzsm**, ACTIVE_HEALTHY, PostgreSQL **17.11**. Hosted baseline: exactly **22 migrations / 115 application tables**, all RLS-enabled. Actual hosted application definitions matched the verified Increment 3 baseline before migration. [Read-only baseline evidence](phase-2-orders-baseline.json).

Fresh disposable PostgreSQL 17.11 validation passed: all 26 migrations, **418 SQL assertions, 22 separate-connection concurrency checks across 53 connections, and 10 upgrade checks**. Existing provider/outbox rows and a live shared-human reservation survived upgrade rehearsal. Candidate source SHA-256 values matched the tested manifest. TypeScript, ESLint, dependency audit (zero vulnerabilities) and staged Git checks passed. [Tests](phase-2-orders-test-results.json), [exact hashes](phase-2-orders-candidate.sha256).

## Fresh backup and restore evidence

Archive: C:/Users/HP/OnIt Database Backups/increment4-20261027/pre-increment4-1793093807888.dump.

- Size: **1,320,359 bytes**.
- SHA-256: **8d4a41c7d4c8d67e34b0b3307012503392966985c8b13c07c93af161a1ce2b02**.
- Stored outside Git. Folder inheritance is disabled; folder/file access was verified as current user and SYSTEM only.
- Restored successfully to an isolated native PostgreSQL 17.11 database with ACLs retained and owners excluded. Only creation of the already-existing public schema was skipped in the restore TOC.
- Hosted/restored application definitions and all **115 baseline table counts/digests** matched. The restored copy upgraded through exactly the four candidate migrations to 126 RLS tables.

An initial raw-text comparison stopped the release because pg_dump/restore flattened one pure built-in weekday AND constraint. No hosted migration ran while that gate was failing. The comparison fix accepts only the two exact known equivalent strings; changed bounds and unrelated definitions remain rejected. **113 local truth-table cases and two negative guards passed**, followed by a new successful backup/restore/upgrade rehearsal. [Comparison evidence](phase-2-increment-4-recovery-comparison.json), [successful recovery verification](phase-2-increment-4-predeployment.json). Failed attempts are not counted as successful checks. Staged checks also caught two harmless trailing blank lines; they were fixed before the first commit.

Scope: public, private, app_private, auth, storage, extensions and supabase_migrations schemas/rows. This is a logical recovery artifact, not complete Supabase-managed recovery. It excludes Storage object binaries, global roles/cluster settings, Vault secrets, external integrations, platform settings and PITR. No Storage objects existed at inspection. The archive is protected by Windows access controls; encryption or a managed recovery guarantee is not claimed.

Recovery should first restore to a new isolated compatible environment using pg_restore --exit-on-error --no-owner and a reviewed TOC/role setup, then verify definitions and original-column row digests. Do not restore over or reset hosted data. Production recovery needs its own reviewed procedure and approval; prefer an additive forward fix with affected callers paused if a command fails.

## Exact hosted deployment

The official CLI dry run listed exactly these files, subsequently applied successfully in filename order:

1. [20261027000100_order_dispatch_foundation.sql](../../supabase/migrations/20261027000100_order_dispatch_foundation.sql)
2. [20261027000200_order_commands.sql](../../supabase/migrations/20261027000200_order_commands.sql)
3. [20261027000300_dispatch_commands.sql](../../supabase/migrations/20261027000300_dispatch_commands.sql)
4. [20261027000400_order_reads_integrity.sql](../../supabase/migrations/20261027000400_order_reads_integrity.sql)

The preceding 22 migrations were already recorded and were not reapplied. Commands:

```text
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --dry-run
node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --yes
```

No seed, role sync, synthetic fixture, real identity, policy, price, credit approval, payment or order was created. No operational permission was assigned to a real role. No background process, scheduler, notification sender or AWS deployment was activated. The final official dry run returned **upToDate=true**, with empty migration/seed/role lists.

## Hosted verification

[Actual hosted verification results](phase-2-increment-4-hosted-verification.json) record:

- **26 recorded migrations; 126 application tables: 51 public / 75 private; zero missing RLS**.
- Hosted columns/defaults, constraints, indexes, functions, policies and triggers match the tested candidate, with the narrowly documented known CHECK-format equivalence available to the comparison.
- All original rows across the 115 predeployment tables match their original-column counts/digests. New approved permission definitions/audit entries are excluded by the predeployment timestamp; original request/quote/pricing/provider/personnel/outbox records are preserved.
- Zero public SECURITY DEFINER functions, unsafe helper search paths, PUBLIC internal-function execution, client private-table grants or client transaction-write grants. Anonymous callers cannot execute order/dispatch commands. Ordinary clients cannot execute either operational_event_worker or expire_dispatch_offers.
- Zero role-permission assignments for the new orders/dispatch authorities. Private API schema access stays denied. Seven private Storage buckets and the separate public marketing bucket retain their exact prior settings and policies.
- Provider self-assignment, customer provider selection, commercial-evidence privacy and shared-capacity behaviour passed disposable role/concurrency tests; hosted definitions and grants match those implementations. These are not claims of signed-in hosted workflow execution.

HTTP results: Auth settings and public catalogue **200**; anonymous request/quote reads **401**; private/app_private profiles **406**; anonymous Storage listing **200 with an empty array**; anonymous order, dispatch and expiry RPC probes **401**. The denial probes produced no business transactions. The existing application's configured URL/anon key still connect to this verified project, without environment edits.

Canonical public-schema types were generated using the official CLI:

```text
node node_modules/supabase/dist/supabase.js gen types typescript --project-id utoxjlsvqfmmzsjruzsm --schema public
```

[database.generated.ts](../../types/database.generated.ts) includes the deployed RPC metadata and excludes private table schemas. Worker metadata in a type file does not grant execution. TypeScript and ESLint passed again after canonical generation. Native candidate types remain labelled as local catalog-derived artifacts.

## Remaining configuration and integration work

Hosted Auth users remain **zero**. Signed-in customer/corporate/provider workflow HTTP tests, authenticated Storage downloads and server-adapter HTTP integration could not be performed without approved test identities; no identities or synthetic business records were created. These tests remain explicitly outstanding. No full Supabase Docker or production-volume performance certification is claimed.

Before live operations, administrators need approved real identities/employment/memberships and least-privilege role grants; independently approved order/dispatch and provider eligibility policies; verified zones, qualifications, documents, contracts, availability and human/party capacity. Corporate terms and external payment evidence require their dedicated independent review. No accepted quotation implies payment success.

The expiry/outbox RPCs exist and are restricted, but worker/scheduler deployment and live notifications require a separate operational review. Consumers must handle typed provider/order events and preserve lease/idempotency semantics. Logical backup coverage and the missing authenticated HTTP tests remain operational limitations. No known critical dependency issue was reported by the current npm audit.

**Ready to commence Increment 5 development** on the verified deployed order/dispatch foundation. Increment 5 has not been started. No payment gateway, wallet, payout or settlement feature was introduced. Future implementation/deployment must follow its own scope and approval.
