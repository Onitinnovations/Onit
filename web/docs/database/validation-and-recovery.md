# Database validation, rollout and recovery plan

Status: twelve migrations pass fresh embedded PostgreSQL 18.6 installation, 124 SQL/security assertions, five reference-seed checks and four upgrade assertions. Real local Supabase/PostgreSQL 17 validation remains pending Docker engine readiness; see [current report](phase-1-report.md) for exact results. Do not point development fixtures, resets or test runners at a hosted project.

## Disposable environment and baseline

1. Obtain authorized read-only remote schema/history inspection. Record remote PostgreSQL/extensions versions, exposed schemas, grants, Auth hooks, Storage, publications and existing equivalents without committing secrets or customer data. Establish an approved non-destructive baseline and drift report.
2. Supabase CLI 2.122.0 is now pinned as development tooling. Docker Desktop was found outside PATH and WSL installation succeeded, pending reboot. Verify the Linux engine, Windows support and available extensions before local validation. Do not use unpinned `latest` in CI.
3. `supabase/config.toml` was initialized after approval with isolated project ID `onit-foundation`, explicit local ports and only `public` exposed. Start with `npm run db:start`; verify local status without logging credentials. Confirm every test target is loopback and the intended disposable database.
4. Apply each pending migration with the pinned CLI's local migration command (`supabase migration up --local`, subject to version verification), starting from an empty disposable instance. Never use `db reset` on a database containing real data. Separate fresh-install tests from incremental upgrade rehearsals on a synthetic prior schema.
5. Require phase 1 migrations, provisioning, RLS and Storage tests to pass before phase 2 SQL is generated. Repeat phase checks at each dependency gate, then run the entire suite from a fresh disposable instance. Keep logs sanitized.

## Fixtures and security acceptance matrix

Use synthetic Auth identities created by local Auth admin APIs, then invoke actual public APIs with their issued JWTs. Portable SQL fixtures use `SET LOCAL ROLE authenticated` plus JWT request claims and exception-based assertions; an owner/service-role connection alone cannot test RLS. The same SQL assertions run in embedded PostgreSQL and the actual local Supabase container. All synthetic commercial values live only in fixtures, never production seed. Use separate connections/processes for concurrency tests. The HTTP runner includes concurrent account provisioning; later dispatch/ledger races require their own multi-connection tests.

Fixture actors: anonymous; customers A/B; organisations A/B with active, expired and removed members; limited department member; provider A/B; supplier A/B; ordinary staff without finance access; scoped dispatcher; independent QA reviewer; finance maker/checker; HR maker/checker; editor/publisher; worker. Include a person holding customer/provider roles simultaneously and an organisation with customer/supplier relationships.

| Acceptance area | Required assertions |
| --- | --- |
| Provisioning | New Auth user gets exactly one neutral profile; retry/backfill is idempotent; malformed/untrusted metadata cannot grant roles/membership; provisioning failure behavior is defined and tested. |
| Customer isolation | A cannot SELECT/INSERT/UPDATE/DELETE B's records, attach B's address/files, change account owner, set approved prices, or enumerate staff. Test direct queries, nested joins, RPCs, views and Realtime exposure. |
| Corporate isolation | Active approved membership plus account grants required; removed/expired member loses access despite valid JWT; department scope enforced; mixed-tenant child FK writes fail. |
| Provider | Only own addressed offers and minimal active assignment DTO visible; cannot create offer, assign self, read candidate scores/bank checks, accept expired offer or submit QA approval. Ended assignments lose sensitive address access. |
| Supplier | Only addressed RFQs/own quotes/POs; cannot read comparison sheets/competing prices or alter accepted quote history. Organisation membership revoke takes effect. |
| Staff and HR | No automatic access from profile metadata; roles scoped to active employment/permissions. Customer/provider role cannot read HR, payroll, internal notes or privileged settings. Makers cannot approve own payroll/expenses/payouts. |
| State transitions | Valid request/assessment/quote/approval/order/QA/closure flow passes; invalid skipped state fails; unapproved quote and stale versions fail. Service with post-completion/credit gate works without prepaid requirement. |
| Dispatch races | Two concurrent accepts for one work package produce one active assignment; capacity cannot be exceeded; eligibility/restriction recheck wins over stale offer. Reassignment retains predecessor history. |
| Forms and versions | Prior orders/submissions retain service/price/checklist/form versions after publication changes; malformed answers and cross-campaign evidence fail. |
| Laundry | Pickup/intake/batch/delivery counts reconcile; double allocation and unresolved shortage closure fail; custody records cannot be rewritten. |
| BFS | Client A cannot read B campaign tasks/reports; agent only sees assigned tasks; submitter cannot verify own work; only approved verified deliverables count toward billing. |
| Procurement/inventory | Internal/customer purpose XOR enforced; accepted supplier quotes preserved; duplicate receipts/movements rejected; concurrent reservations/debits cannot create negative availability; projection equals movement totals. |
| Webhook replay | Same event twice and different events for same transaction post once; invalid signature/reference/account/amount/currency/status cause no credit; browser callback cannot mark paid; retry after transaction failure is safe. |
| Journal invariants | Unbalanced, empty, one-line, negative or both-side lines fail; foreign currencies cannot offset; closed periods reject; unauthorized balanced posting fails. Journal+lines+balances commit or roll back together. |
| Financial immutability | Posted header/line UPDATE/DELETE/TRUNCATE denied; audit mutation denied; reversal adds balanced entries and preserves original; duplicate reversal rejected; direct SQL grants cannot bypass posting. |
| Wallet races | Concurrent debits/holds cannot overspend; held funds unavailable; release/expiry idempotent; disabled funding/payout paths reject even if a feature flag is changed. |
| Storage | Cross-tenant object GET/list/upload/overwrite/delete denied; path spoofing/forged registry links fail; identity/HR docs never public; legal hold blocks delete; quarantine not downloadable; signed URLs expire. Test Storage API, not just registry RLS. |
| CMS/notifications | Draft/future scheduled/private content hidden; editor cannot self-publish without publish permission; marketing withdrawal suppresses intended channel; outbox retries deduplicate; no live sends. |
| Governance | Export/import jobs enforce tenant and requester scope on every access; no secrets in logs/config; malicious imported tenant IDs rejected; deletion cannot erase finance evidence or active legal holds. |

Catalog assertions: all intended base tables have RLS; expected immutable objects have mutation guards; no broad authenticated policies/default grants; security-definer functions have fixed search paths and least execution grants; indexes cover expected tenant/FK paths; exposed views use safe invoker semantics; private schemas absent from API exposure. Test authorization helpers for recursion and denied-path performance. Test service/privileged worker roles separately because RLS bypass must never be mistaken for end-user authorization.

## Seed, types and dictionary workflow

`supabase/seed.sql` is reference-data-only and idempotent by stable codes. Dedicated test fixtures are never configured as production seeds. Existing reference values must be reconciled, not overwritten by blind upserts. No production business prices, rates, identities or credentials.

After each accepted schema phase, generate types against the tested **local** database using the pinned CLI:

```powershell
npm.cmd run db:types
```

The canonical wrapper calls `supabase gen types typescript --local --schema public` without shell redirection, creates the directory, fails on generation errors and writes UTF-8 through a temporary file before replacing the result. While Docker is unavailable, `npm run db:types:embedded` generates explicitly labelled public API types from tested PostgreSQL catalogs. Those types are delivered and used by the existing client through JSDoc. Private schemas are excluded. Run the canonical generator and compare its output after actual Supabase validation; types do not confer database permissions.

The final data dictionary is built from approved migrations plus catalog introspection and reviewed policy descriptions. Verify its table/column/constraint/index/policy inventory matches the database, regenerate the physical ERD, and maintain requirement mapping alongside SQL. No documentation should describe planned enforcement as already tested enforcement.

## Non-destructive rollout

Deploy through reviewed migration artifacts with a non-browser, narrowly controlled database credential. Back up schema and data, verify backup restoration on an isolated target, record migration hashes and approvals, and establish recovery objectives before production rollout. PITR availability/retention must be confirmed for the actual Supabase plan; do not assume it exists. Storage object backup/restore is separate from relational backups.

Use expand/backfill/validate/contract: add compatible structures, backfill in resumable scoped batches, validate constraints and policies, switch consumers, then separately review removal of obsolete objects. Choose lock/statement timeouts and maintenance windows; measure operations on representative synthetic volume. No destructive drop, cascade, database reset or automatic remote `db push` is authorized by this plan.

On failure: stop the deployment, preserve migration/error evidence without PII, assess committed DDL, and prefer a forward corrective migration. Reverting application code is safe only while the expanded schema remains compatible. Never edit already-applied migration files or delete ledger entries to recover. Reverse financial/stock mistakes through authorized compensating postings. Reconcile payments, inventory projections and journal sums after recovery.

For serious corruption: isolate writes and external jobs, restore backup/PITR to a separate database, validate schema, RLS, Auth relationships, Storage registry/object consistency and journal/stock totals, then execute a reviewed cutover. Reconcile external payment/provider activity after the recovery point using permanent idempotency references before re-enabling jobs. Preserve audit/legal-hold evidence. Test recovery procedures and record achieved recovery time/data loss rather than promising untested RTO/RPO.

## Evidence for the next implementation report

Report every changed file; migration IDs generated/applied and exact target; CLI/PostgreSQL versions; fixture/test commands and pass/fail counts; RLS/Storage/API coverage; concurrency and immutability results; seed/type-generation results; drift and recovery rehearsal outcomes; assumptions and unresolved activation decisions. A blocked local environment or failed test is reported explicitly and does not authorize remote testing as a substitute.
