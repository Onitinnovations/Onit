# Windows readiness and Phase 0 access — current prerequisite report

Historical prerequisite check: the latest implementation task subsequently authorised local development despite unavailable remote/runtime access. See [current implementation report](phase-1-report.md). Windows repair instructions below remain applicable, but the prior instruction to stop all embedded/local development has been superseded. No additional Windows configuration change was made in the latest pass.

Date: 2026-10-24, Africa/Lagos. This report supersedes the assumption that WSL installation alone made Docker ready.

## Checks executed in this request

| Check | Result |
| --- | --- |
| Repository/package/migration review | Six existing foundation migrations; Supabase CLI pinned at 2.122.0. No new SQL generated or applied in this request. |
| Docker `version` | Client 29.9.2, context `desktop-linux`; server version request returned HTTP 500. Docker Desktop/backend processes exist, but the engine is not ready. |
| `wsl --status` | Default WSL version 2, but WSL explicitly reports it cannot start because virtualization/Virtual Machine Platform is not enabled/effective. A running Desktop UI is not evidence of a working Linux engine. |
| `supabase --version` | 2.122.0. |
| `supabase status --output json` | Failed with HTTP 500 inspecting `supabase_db_onit-foundation` through Docker's Linux engine. No local project credentials were emitted or recorded. |
| `.env.local` variable-name inspection | Only public URL and anon key. No values printed. No database connection or management token found in process configuration; no linked-project marker. |
| `supabase projects list --output json` | Failed: access token not provided; CLI login is required. No project/schema/history could be inspected. |

No start, migration, seed, database-test or type-generation command was run in this request. No hosted SQL, AWS deployment, database reset or Windows restart was performed. Earlier embedded SQL results remain historical; no current Supabase validation success is claimed.

Documentation validation checked all ten database Markdown documents for local links, fenced-block balance and trailing whitespace: passed. `git diff --check` passed (only existing Windows line-ending notices). No qualifying Next.js feedback candidate was observed in this request, so no Next.js feedback submission was made.

## Exact Windows prerequisite steps

Save work before restarting. Open **PowerShell as Administrator** and enable the prerequisite Windows components without automatically restarting:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```

If either command fails, stop and resolve its specific Windows error. Verify virtualization is enabled in Task Manager -> Performance -> CPU. If disabled, enable Intel VT-x/AMD-V in the machine's UEFI/BIOS. If Windows runs inside a VM, the host must allow nested virtualization.

If the features are enabled and the error persists, inspect the boot configuration from Administrator PowerShell:

```powershell
bcdedit.exe /enum '{current}'
```

Only if `hypervisorlaunchtype` is explicitly `Off`, enable it:

```powershell
bcdedit.exe /set hypervisorlaunchtype auto
```

**Restart Windows manually after saving work.** Then open PowerShell:

```powershell
wsl.exe --update
wsl.exe --set-default-version 2
wsl.exe --status
```

Start Docker Desktop and select its WSL 2 Linux engine. Complete any first-run prompts and wait for engine readiness. Verify both Client **and Server** information:

```powershell
& "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe" version
```

If using an all-users install instead, the executable is normally `C:\Program Files\Docker\Docker\resources\bin\docker.exe`. Do not proceed while the Server section errors. These steps follow Microsoft's [WSL troubleshooting](https://learn.microsoft.com/windows/wsl/troubleshooting), [WSL manual setup](https://learn.microsoft.com/windows/wsl/install-manual) and Docker's [WSL/virtualization troubleshooting](https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/).

From the repository root, confirm the pinned CLI:

```powershell
npx.cmd --no-install supabase --version
```

The CLI is already installed, so reinstalling it is unnecessary. If rebuilding dependencies on a clean checkout, use `npm.cmd ci`. A Docker-compatible runtime is required for [local Supabase development](https://supabase.com/docs/guides/local-development/cli-workflows).

## Authorised hosted read-only inspection

Authenticate interactively on this machine; do not paste credentials into chat or commit them:

```powershell
npx.cmd --no-install supabase login
npx.cmd --no-install supabase projects list --output json
```

Confirm the intended project against the existing app configuration. Authorise a read-only PostgreSQL connection or provide an authorised schema/migration-history export through the workspace. A public anon key cannot reveal a complete private schema, grants, functions, Storage policies or `supabase_migrations` history. A management login may establish project identity but does not itself certify complete database inventory.

The inspection must capture actual PostgreSQL version, existing public/private objects, constraints, functions, RLS/grants, Auth triggers, extensions, Storage buckets/policies, migration history and drift. Use read-only transactions/catalog queries or schema-only exports; do not run `db push`, `db reset`, migration repair, hosted DDL, or hosted seed/test fixtures. Do not automatically run `db pull`: it can generate baseline artifacts and may prompt to update hosted migration history. Record and reconcile equivalents before remote rollout is considered.

Only after the local engine is verified ready should the local-only sequence in [README.md](README.md) begin. Keep generated schema types pending until migrations and security tests pass. The latest user explicitly requires this readiness gate; no embedded fallback is used to bypass it.
