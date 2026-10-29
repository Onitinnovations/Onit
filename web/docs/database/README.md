> Combined Increments 5–6 candidate (2026-10-29): 48 migrations / 180 RLS tables (51 public, 129 private), with 577 SQL assertions, 53 concurrency checks and 17 upgrade checks passed. Hosted release gates are pending. See [consolidated report](phase-2-increments-5-6-report.md). Earlier dated entries below are historical.

> Increment 5 local candidate (2026-10-27): six additive migrations, 16 private tables; 32 migrations / 142 RLS tables (51 public, 91 private). Hosted remains at Increment 4: 26 / 126. See [fulfilment report](phase-2-increment-5-report.md), [dictionary](phase-2-increment-5-dictionary.md) and [ERD](phase-2-increment-5-erd.md). No commit/push/deployment or Increment 6 work. Earlier status entries below are historical.

> Hosted checkpoint (2026-10-27): Increment 4 deployed and verified on OnIt, PostgreSQL 17.11: 26 migrations / 126 RLS tables (51 public, 75 private); canonical types updated. [Deployment report](phase-2-increment-4-hosted-deployment-report.md). Increment 5 was not started. Earlier local-only progress entries below are historical.

> Current hosted checkpoint (2026-10-27): Increment 3 deployed and verified on OnIt: 22 migrations, 115 RLS tables (51 public / 64 private), PostgreSQL 17.11. Canonical types updated. See [deployment report](phase-2-increment-3-hosted-deployment-report.md). Increments 4?6 remain unimplemented; earlier status entries below are historical.

# Database development

Start with the current [Phase 1 report](phase-1-report.md), [security guide](rls-policies.md), [deployment procedure](phase-1-deployment.md), root [database plan](../../DATABASE_PLAN.md), [inventory](schema-inventory.md), and generated [foundation dictionary](data-dictionary.md). Twelve migrations and public API types are implemented. No hosted database has been linked or modified.

## Runtime prerequisite

**Current limitation:** Supabase CLI 2.122.0 is installed, but the bounded Docker Server check times out; earlier checks reported HTTP 500/WSL virtualization failure. CLI management login is absent; remote public OpenAPI returned HTTP 401. Follow [Windows and access steps](windows-readiness.md). The latest task explicitly permits local SQL development despite these blockers, so fresh embedded PostgreSQL and incremental-upgrade tests have been executed successfully. Actual Supabase commands below still require a working Linux engine.

Docker Desktop was found in the Windows per-user installation. WSL was missing and has now been installed through an elevated `scripts/database/enable-wsl.ps1` run. Windows explicitly requires a **restart** before the virtualization changes take effect. No automatic restart was issued. Local setup logs are ignored under `.local-tools/`.

After saving work and restarting Windows, start Docker Desktop. Let its Linux engine become ready and complete any first-run agreement prompts. The Docker CLI may be under `%LOCALAPPDATA%\Programs\DockerDesktop\resources\bin`; the local SQL runner checks that path as well as PATH. No Docker Desktop upgrade was applied: winget found the existing package but offered no applicable per-user upgrade.

The setup follows the official [Docker Windows installation guide](https://docs.docker.com/desktop/setup/install/windows-install/), [WSL installation commands](https://learn.microsoft.com/windows/wsl/basic-commands), and [Supabase CLI setup](https://supabase.com/docs/guides/local-development/cli/getting-started). Docker licensing/account eligibility remains the owner's responsibility; this work configured no paid subscription.

## Commands

From the repository root in PowerShell:

```powershell
npm.cmd ci
npm.cmd run db:start
npm.cmd run db:migrate:local
npm.cmd run db:seed:local
npm.cmd run db:test:local
npm.cmd run db:test:api
npm.cmd run db:types
```

The pinned CLI uses `supabase/config.toml`, project `onit-foundation`, PostgreSQL 17, API port 54321 and database port 54322. Verify hosted PostgreSQL major version before considering any deployment. API exposure includes only `public`; automatic exposure of new tables is disabled. No live email/payment/wallet integration is enabled. Local Auth email confirmation is disabled for disposable testing; this is not a production Auth configuration.

`db:start` can download images and apply pending migrations/seeds to this isolated local project. No script links a hosted project, runs `db push`, reads `.env.local`, performs a reset or deletes a volume. SQL tests roll back all fixtures; API tests retain synthetic identities/files in the disposable local project so audit/financial retention need not be bypassed. Run tests on a fresh, reference-seeded disposable project, not on a development database whose reference services have been edited/published.

The local SQL runner targets only the fixed local container `supabase_db_onit-foundation`, checks migration history and refuses TCP remote Docker hosts. The API runner reads local CLI status in memory, accepts only the expected loopback endpoint and never prints credentials. Remote schema reconciliation is still mandatory before any hosted rollout.

When Docker cannot run, supplemental in-memory PostgreSQL checks remain available:

These commands are implemented and were executed in the latest request:

```powershell
npm.cmd run db:test:embedded
npm.cmd run db:test:upgrade
npm.cmd run db:dictionary
npm.cmd run db:types:embedded
```

The embedded bootstrap supplies **test-only** Auth/Storage SQL scaffolding on PostgreSQL 18.6. It is never a migration, never a second application identity system, and never substitutes for testing Supabase/PostgreSQL 17, Auth, Storage APIs, JWTs, Realtime or multiple connections. Dictionary generation runs migrations, reference seeds twice and security assertions before reading catalogs; it writes the physical FK graph. The labelled fallback type generator derives only public schema types from that tested catalog. The canonical `db:types` uses the actual local CLI, writes UTF-8 atomically and preserves an existing generated file on failure.

Reference seeds contain no services, packages, customers or operational zones. The labelled `supabase/fixtures/catalogue-development.sql` is injected only inside rollback-only SQL tests. Both SQL runners do that injection; running a raw test SQL file without its runner omits the required fixture preparation.

## Application integration

Existing `supabaseClient.js`, public environment variable names and the current customer web page are unchanged. New public RPCs are invoker wrappers around narrowly granted private implementations that validate `auth.uid()`:

- `ensure_individual_customer()` provisions one own individual account under a profile row lock; it never grants corporate/staff access.
- `add_customer_address(...)` checks own/approved corporate requester scope and geographic FKs.
- `prepare_customer_upload(...)` generates registry ownership and object path server-side. Uploaded files remain quarantined until an authorized scanner marks them clean; no scanner/live download endpoint is implemented here.

There is no generic staff administration or approval RPC yet. Private operational tables are available only to trusted server credentials; future OMS endpoints must enforce explicit permission checks before using a bypass role. Team/self role grants and department-only corporate members cannot acquire broader access through the currently implemented helpers.

See [validation and recovery](validation-and-recovery.md) for the full later-domain acceptance matrix, non-destructive remote baseline/rollout, backup/PITR and reversal procedures.
