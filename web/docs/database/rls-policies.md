> Increments 5–6 current security evidence: [consolidated report](phase-2-increments-5-6-report.md). All 180 candidate tables have RLS; 38 specialised private tables use deny-by-default ordinary grants, independent approvals and scoped projections. Supplier portal access is organisation-bound, field reports are branch-filtered, and Storage access is limited to exact current linked references. Signed-in HTTP integration remains outstanding. Earlier sections describe their original checkpoints.

# Increment 5 local security extension

The local candidate has 142 RLS tables; hosted remains at the verified 126-table Increment 4 baseline. The sixteen new tables are in unexposed `private`, with no ordinary client table access. See the [fulfilment report](phase-2-increment-5-report.md) and [catalog dictionary](phase-2-increment-5-dictionary.md). The Phase 1 guide below remains the historical foundation.

| Actor | Fulfilment boundary |
| --- | --- |
| Customer/current corporate member | Account, branch and department-scoped customer projection; internal work staffing, commercial calculations and investigations omitted. |
| Customer approver | Current scoped `can_approve` authority for plan-specific confirmation/dispute and completed-work feedback. Requester authority alone does not confer sign-off. |
| Executing personnel | Exact current task, active profile/personnel/membership and assigned reservation; acceptance, approved progress, declared attendance, checklist submission and private evidence preparation. No self-supervision, QA or closure. |
| Contracting-provider administrator | Addressed active-party work projection; exact execution remains tied to assigned humans. Unrelated businesses and confidential commercial/case data remain hidden. |
| Scoped operations staff | Active OnIt employment plus the relevant `fulfilment.*` permission; expected revisions and command-specific lifecycle rules still apply. |
| Supervisor | Scoped supervision; actual supervisor identity and independence required to verify completion. Reviews cannot rewrite submitted/final content. |
| QA inspector/checker | Assigned independent inspector; a different scoped checker approves. Current/historical executing-party affiliation, completer, supervisor and inspection maker checks prevent self-approval. |
| Sensitive-case investigator | Separate sensitive-case authority plus scope and independence. Reporter projections contain customer-visible communication only. |
| Exception/closure authority | Independent current-plan decisions, explicit policy and all closure gates; no provider declaration or customer silence releases capacity. |
| Configuration makers/checkers | Global active OnIt configuration authority, independent publication, immutable versions and inspectable draft definitions. No automatic real-role grants. |
| System worker | `process_execution_slas` requires service-role execution and trusted worker JWT context. Ordinary clients cannot execute it or the existing outbox/dispatch-expiry worker. No worker is deployed. |

Public RPC wrappers use invoker rights; internal definers use pinned empty search paths and current database authority. Existing order/dispatch wrappers are rebound to execution-aware guards; direct execution of renamed bypass helpers is revoked. Storage paths remain private, account-consistent, scan-gated and linked to current work authority or reviewed customer visibility. Native SQL/concurrency tests passed; authenticated Supabase HTTP/Storage integration remains outstanding.

# Phase 1 RLS, grants and privileged-function review

All 79 application tables have RLS. Exact per-table policy expressions, constraints, indexes and grants are generated from PostgreSQL catalogs in [data-dictionary.md](data-dictionary.md). This guide explains intent; it does not claim that embedded tests replace real Supabase validation.

| Surface | Anonymous | Authenticated subject | Privileged path |
| --- | --- | --- | --- |
| Profiles | None | Own neutral identity; own display-name update only | Explicit `identity.read` staff permission for other identities; provisioning trigger/backfill never reads roles from editable metadata. |
| Organisations | None | Active member of the same active organisation | Explicit organisation/global identity permission and active OnIt employment. |
| Memberships, roles, permissions, employees | None | No direct schema/table access; no self-grant RPC | Trusted server/admin writes; audited grants/revocations. `private` is not API-exposed. |
| Customer accounts | None | Own approved individual account or approved current corporate account grant plus active membership | `customers.read` scoped to that client's organisation, or explicit global staff grant. |
| Account-owned contacts, addresses, preferences | None | Same approved account; column-limited preference/address content updates | Scoped staff helper propagates client organisation scope to child tables. No browser owner reassignment or hard deletion. |
| Corporate branches/sites | None | Explicit active branch grant or approved all-branch account grant; independent requester/approver flags | Scoped customer-read staff; branch/organisation composite FKs prevent attaching another client's location. |
| Billing and credit-term configuration | None | No direct access, including branch-only requesters | Trusted server configuration only. Activated versions immutable; credit approval requires independent decision evidence. No credit execution or ledger. |
| Country/currency/state/city/LGA references | Active approved reference subset | Same safe public subset | Server-maintained reference data; ancestor geography checks and new-address command require active consistent geography. |
| Catalogue | Published hierarchy and effective versions only | Same published projection | Drafts and pricing/checklists require trusted server operations. No generic client publishing/price mutation. |
| Dynamic forms | Published effective schema on a published service version; hidden fields excluded | Same customer-facing definition | Same-version/schema/group FKs, acyclic typed dependencies, safe choices and validation bounds; drafts/published history are guarded. |
| Audit, approval, private CRM | None | No direct write/read; redacted subject activity only where granted | Server operations; immutable audit/decision rows. Audit changes retain column names, not row values or Auth metadata. |
| Documents and Storage | Reviewed public marketing only | Own account's clean customer files, own clean identity file; registry-backed pending uploads on own account only | Scoped customer-document readers. Other sensitive buckets require future typed server download commands; a generic document permission cannot reveal HR files. |

Public reference/catalogue policies are intentional public content, not broad authenticated access to business records. Tenant data always has an ownership/membership/permission predicate. New application objects receive no automatic browser grants; API exposure is only `public` in local config. All private application tables also have RLS as defense in depth, but the server service role intentionally bypasses RLS and must never enter browser/mobile bundles.

## Function boundaries

Public RPCs are invoker wrappers: `ensure_individual_customer`, `add_customer_address`, `prepare_customer_upload`. Their narrowly granted implementations live in unexposed `app_private` and validate `auth.uid()` internally. Only neutral own-account provisioning is automatic; corporate approval, role assignment, staff employment, publishing, scans and commercial configuration cannot come from untrusted metadata or caller-provided owner IDs.

Security-definer helpers have empty fixed search paths and schema-qualified objects. Their trusted migration/table owner bypasses owner RLS to avoid recursion; FORCE RLS is deliberately not enabled. No extra superuser/independent auth system is introduced. Never grant this owner to application roles. PostgreSQL's global default PUBLIC function execution is explicitly revoked for the migration owner, because schema-local revocation alone cannot subtract it. Helpers are executable only by the roles that need them; boolean visibility helpers cannot return hidden records.

`has_permission` requires an active profile, active OnIt employee, active employer, unrevoked/unexpired role and permission. Organisation-scoped grants also require active membership. Team grants use `has_team_permission` with active exact team membership and never widen into organisation/global access. Branch-only users cannot use account-wide customer helpers. Revocation is read from database state on each operation rather than trusted as a stale JWT role claim.

## Integrity and mutation controls

Versioned form changes lock the service version and schema; dependency/rule changes are serialized and cycles/type inconsistencies rejected. Published service/form/configuration content cannot be rewritten or truncated. Form backfill migration 008 briefly suspends only the existing field-version guard inside its DDL transaction to populate new FKs, then re-enables it; tests assert no disabled guard remains and published legacy content survives. No data, service identity or historical field text is deleted.

Document ownership/path/classification is immutable. Upload paths are generated server-side; registry fields are private and cannot be forged by a client. A pending upload is quarantined until trusted scanning; the future scanner must verify actual MIME/size/hash before marking it clean. File deletion/overwrite is not granted to end users; retention/legal-hold workers and typed domain access remain future server responsibilities. Public marketing is intentionally public and must contain only reviewed non-sensitive assets.

## Verified and pending coverage

Executed embedded SQL checks cover individual/corporate/branch isolation, staff organisation/team scope, ordinary-role escalation denial, neutral provider/supplier subjects, Auth-trigger provisioning, published-form visibility, immutability, Storage policy predicates and private HR document denial. See [current report](phase-1-report.md) for counts and exact commands.

Pending: actual Supabase JWT/Auth-trigger and Storage HTTP behavior, service deployment grants, PostgreSQL 17 compatibility, Realtime/publication review, separate-connection races and recovery rehearsal. Provider offers/supplier quotes do not exist in Phase 1; their eventual access workflows are not claimed tested by the neutral-subject denial fixtures.
