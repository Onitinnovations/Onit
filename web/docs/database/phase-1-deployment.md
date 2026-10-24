> **Current hosted status (2026-10-24): Phase 1 deployed and verified on OnIt, PostgreSQL 17.11. All 12 migrations applied; 79 tables have RLS. Native backup restore and 126 SQL assertions passed. Official hosted types and app checks passed. See [hosted deployment report](hosted-deployment-report.md). Earlier blocked-readiness statements below are historical and superseded.

# Phase 1 deployment procedure — approval required

**Current status: founder authorisation retained; login and target inspection succeeded; recovery gate blocked.** The configured **OnIt** project is verified on PostgreSQL 17.11, with no application schema/data/history found. No usable backup has been verified, Docker remains unavailable and logical backup creation failed. See the [current hosted report](hosted-deployment-report.md). Read-only hosted SQL has run; no application migration or seed has been applied. Recovery and sufficient compatibility/security validation must pass before application. This procedure does not authorise resets, destructive reconciliation or deployment to an unverified project.

## 1. Read-only hosted reconciliation

Authenticate locally without sharing secrets in chat or committing them:

```powershell
npx.cmd --no-install supabase login
npx.cmd --no-install supabase projects list --output json
```

The configured app project is identified in `remote-public-inventory.json`; match it to the project shown by authenticated management access. Do not infer an empty database from an empty public API schema. Determine whether data is production/test with the owner and authorised evidence; row estimates alone cannot classify it.

Use a separately authorised read-only PostgreSQL role, configuring `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and an external `PGPASSFILE` in your secure environment. Do not put passwords/DSNs in command-line arguments, repository files or logs. Run:

```powershell
psql.exe -X -v ON_ERROR_STOP=1 -f supabase/inspection/remote_inventory.sql
```

The script opens a read-only transaction, sets a statement timeout, identifies schema objects/indexes/constraints/functions/triggers/RLS/grants/extensions/Storage/migration versions, and rolls back. It reads no customer row values. Keep output in an ignored, restricted local location; review pre-existing expressions for sensitive literals before sharing. Function bodies are deliberately not dumped. Inspect any relevant existing bodies through a controlled read-only review before trusting compatibility.

Compare every candidate name/definition against this inventory. Pay special attention to `profiles`, Auth provisioning triggers, all public/private tables, RPC overloads, published service fields, existing Storage bucket IDs/policies, function owners/default privileges and migration versions. Existing permissive Storage policies can combine with new ones via OR; never assume adding restrictive policies neutralises an old broad policy. Existing object conflicts intentionally fail rather than silently overwrite/adopt objects. Do not automatically run `db pull` or repair migration history, since those paths may prompt to update hosted metadata.

## 2. Complete disposable local verification

Fix WSL/Virtual Machine Platform using [Windows readiness instructions](windows-readiness.md), start Docker Desktop's Linux engine and verify a working Server section from Docker. The local config uses PostgreSQL 17; confirm the actual hosted major version, then match and rerun validation.

On the isolated local project only:

```powershell
npm.cmd ci
npm.cmd run db:start
npm.cmd run db:migrate:local
npm.cmd run db:seed:local
npm.cmd run db:test:local
npm.cmd run db:test:api
npm.cmd run db:types
node node_modules/typescript/bin/tsc --noEmit
npm.cmd run lint
```

Starting a fresh local stack may already apply pending migrations and seeds; `migration up --local` then reports nothing pending. No command above is a remote reset. Use a separate disposable project/volume for a clean-install rehearsal; never reset or delete a database containing real data. Run the incremental upgrade rehearsal too. Review canonical CLI type differences against the delivered embedded-generated public types.

Existing supplemental commands are executable without Docker:

```powershell
npm.cmd run db:test:embedded
npm.cmd run db:test:upgrade
npm.cmd run db:dictionary
npm.cmd run db:types:embedded
```

These execute PostgreSQL 18.6 through a test-only Auth/Storage SQL scaffold. They are useful SQL/RLS checks, not Supabase/17/JWT/HTTP certification.

## 3. Prepare a reviewed hosted candidate

Reconcile naming conflicts and equivalent existing structures with additive compatibility migrations, not destructive drops. Preserve existing IDs, data, Auth relationships and published history. If existing history differs, prepare a reviewed baseline/mapping before linking anything for deployment. Confirm Storage buckets and API schema exposure separately; local `config.toml` is not proof of hosted dashboard settings.

Take and verify a restorable backup, confirm PITR capability for the actual plan, back up Storage objects separately, choose lock/statement timeouts and record rollback/forward-repair steps. Rehearse on an isolated restored or sanitised staging copy. The broader [recovery plan](validation-and-recovery.md) applies. Never undo a released migration by editing it or deleting audit history.

## 4. Approval and exact future apply commands

The founder's latest instruction supplies conditional hosted approval. Retain that authorisation and proceed when target, inventory, recovery, compatibility and security checks pass for the approved Phase 1 scope. Record candidate hashes, remote diff and backup/restore evidence. Stop for further approval if destructive reconciliation, unrelated object changes or an unverified target would be required; do not ask for the same routine deployment permission again.

Then, using the confirmed project reference (not a pasted secret):

```powershell
npx.cmd --no-install supabase link --project-ref <CONFIRMED_PROJECT_REF>
npx.cmd --no-install supabase migration list --linked
npx.cmd --no-install supabase db push --linked --dry-run
```

Review the dry-run output against the approved candidate. If it differs, stop. Only with approval for that exact candidate:

```powershell
npx.cmd --no-install supabase db push --linked
```

Do not use `--include-all`, migration-history repair, hosted seed execution or any reset to force a mismatched baseline. Verify grants/RLS, Auth provisioning, private bucket settings and approved public reads after application; production checks must not insert synthetic customer fixtures into real data. No AWS operation is involved.
