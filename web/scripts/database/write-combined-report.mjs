import { readFileSync, existsSync, writeFileSync, readdirSync } from 'node:fs';
const read = file => JSON.parse(readFileSync('docs/database/' + file, 'utf8'));
const tests = read('phase-2-specialized-test-results.json');
if (!tests.passed) throw Error('Passing integrated candidate required before publishing its report');
const before = existsSync('docs/database/phase-2-increments-5-6-predeployment.json') ? read('phase-2-increments-5-6-predeployment.json') : null;
const after = existsSync('docs/database/phase-2-increments-5-6-hosted-verification.json') ? read('phase-2-increments-5-6-hosted-verification.json') : null;
const deployed = after?.passed === true;
const implementation = process.argv[2] ?? 'Not committed at report generation.';
const checks = value => Array.isArray(value?.checks) ? value.checks.length : value?.checks ?? 0;
const concurrency = ['concurrency', 'providerConcurrency', 'orderConcurrency', 'fulfilmentConcurrency', 'laundryConcurrency', 'specializedConcurrency'];
const upgrades = ['upgrade', 'providerUpgrade', 'orderUpgrade', 'fulfilmentUpgrade'];
const inventory = readdirSync('supabase/migrations').filter(file => file.endsWith('.sql') && file >= '20261028000000').sort();
const migrationRows = inventory.map(file => `| ${file.startsWith('20261028') ? '5' : '6'} | [${file}](../../supabase/migrations/${file}) |`).join('\n');
const assertions = tests.tests.reduce((sum, test) => sum + test.assertions, 0);
const stageRows = tests.tests.filter(test => test.file.startsWith('specialized/')).map(test => `| ${test.file} | ${test.assertions} passed |`).join('\n');
const backup = before?.backup;
const report = `# Increments 5–6 — fulfilment and specialised operations

Report date: **2026-10-29, Africa/Lagos**. **${deployed ? 'Combined release deployed and verified.' : 'Complete local candidate validated; combined GitHub/hosted release gates remain pending.'}** This replaces the earlier incomplete draft checkpoint. No frontend, AWS, payment gateway, wallet, payout, settlement, live sender, worker or scheduler was implemented/deployed.

## Baseline and Increment 5 preservation

Repository: https://github.com/Onitinnovations/Onit, existing main. Baseline HEAD was cdee0fd6f14f05d067c9358359bdc636f6dac51a. Read-only inspection verified OnIt project utoxjlsvqfmmzsjruzsm, PostgreSQL 17.11, 26 migrations and 126 RLS tables. All 26 deployed migrations, six preserved Increment 5 migrations and original reference seed retain their verified SHA-256 values. Environment values and the unrelated logo were preserved.

Increment 5's separate evidence remains **493 SQL assertions, 35 concurrent checks and 13 upgrade checks**, with its original report, types and six migrations retained. The integrated suite re-executes those historical assertions and races against the final candidate. Historical runners have explicit cutoffs rather than silently assuming their old table counts against new files.

## Exact combined migration inventory

**48 migrations; 180 application tables: 51 public / 129 private, all RLS-enabled.** Increment 5 adds 16 tables; Increment 6 adds 38 private tables. The combined release contains exactly six Increment 5 and sixteen Increment 6 migrations after the deployed 26:

| Increment | File |
| --- | --- |
${migrationRows}

The former 35-table draft was reviewed, extended and replaced by operational commands and tests before promotion. Its DDL-only evidence is historical, not certification of this release. The [final manifest](phase-2-specialized-candidate.sha256) identifies the executed candidate. [Dictionary](phase-2-increment-6-dictionary.md) and [physical ERD](phase-2-increment-6-erd.md) are generated from the passing catalog; the [Increment 5 dictionary](phase-2-increment-5-dictionary.md) remains separate.

## Shared fulfilment and extension architecture

Increment 5 supplies work orders/tasks/dependencies, attendance, typed versioned checklists, quarantined evidence, independent supervision/QA/rework, customer decisions, confidential cases, explicit SLAs, verified performance and capacity-aware closure. See its [preserved implementation report](phase-2-increment-5-report.md).

Increment 6 adds specialised_service_policies, service_operations, operation_orders, operation_tasks and operation_documents. Each operation pins an approved service-category policy and existing accepted commercial/order/work/task references. Commands use actor/key/payload receipts, order-first locks and expected revisions. They append existing execution history and the single operational outbox in the same transaction. No new customer, provider, order, capacity, form, complaint or outbox system exists.

An approved specialised capability cannot be skipped by executing common tasks without its operation. Shared execution requires an active typed operation and task link (or actual shared corrective ancestry); shared closure requires specialised reconciliation. Field supervision requires a reviewed location submission. Procurement receiving/handover supervision requires actual receipts/reconciled purchasing. Existing commercial release, assignments, current membership, eligibility and shared human/party capacity remain mandatory.

## Laundry

New structures: bags, immutable tagged items, processing batches/allocations, independently approved allocation corrections, physical custody positions, addressed transfers/lines and immutable custody events. These record physical accountability, not inventory ownership or financial balances.

Staff plan pickup/intake and record categories, condition, handling/treatment and counts under approved configuration. Current customers acknowledge counted intake. Actual assigned workers receive pickup, sort, allocate and acknowledge processing batches. Processing partners reuse existing verified provider capabilities, assigned resource units and capacity. Multiple businesses can process separate batches without mixing custody.

Sending reserves the proposed quantity but does not move custody. A different actual authorised receiver acknowledges explicit counts. Partial receipt moves missing units into same-order case accountability; sums remain equal to original intake. Damage retains actual counts and a blocking case. Rejected handovers do not become receipts. Lost units require independent case resolution, explicit customer acknowledgement and approved allocation correction; they are never fabricated as delivered.

Shared completion, clean evidence and independent QA gate packaging. Failed QA creates actual shared rework with new evidence and independent reinspection; original defects and outcomes remain. Item-level configuration requires one tagged garment/dedicated inspection task per batch; batch-level QA must be explicitly approved. Packaging, returned processing custody, delivery acknowledgement, customer confirmation and shared closure precede final operation closure and resource release.

## Construction

Projects use the order's immutable service site, technical scope, access and registry drawings/specifications. Milestones link trade tasks and measurement snapshots; material requirements have independent approval, with evidenced receipt/use/return/waste conservation. Shared supervision, defects, corrective work and independent QA precede milestone inspection and customer handover.

Variations preserve their original commercial version, evidence, exact cost/currency/time impact and scope. Customer acceptance and independent OnIt commercial authority are separate. Nonzero impact requires an accepted same-tenant/site revised quote with the exact difference. It cannot execute until the order actually adopts that accepted version. Existing independently approved retirement, rescheduling, commercial release and redispatch establish new capacity. Explicit predecessor/successor milestone links retain replaced work; field progress cannot implement an unapproved variation. Zero-cost clarification pins the unchanged accepted commercial version.

## Procurement

New structures: supplier eligibility versions, customer-approved RFQs/items/invitations, confidential supplier quote versions/lines, independent selections, POs/immutable versions/lines, actual receipts/lines, returns, verified supplier observations and supplier document links.

Suppliers reuse organisations, Auth profiles, membership and explicitly scoped supplier.portal grants. They can access only addressed invitations, their own quotes/POs and receipt outcomes; internal buyers compare authorised proposals. Customers do not receive supplier cost quotes or margins. Supplier affiliations and the original quote actor cannot act as their own independent checker, including after membership revocation.

Approved customer specifications drive sourcing. PostgreSQL performs exact quantity/unit price/discount/tax calculations at the configured currency scale. Effective country tax references are optional according to actual treatment; no operational rates are seeded. Independently selected, effective supplier terms must fit released customer authorisation. Reselection cannot create a second live purchase commitment for the same RFQ. Unreceived PO amendments append independently approved terms and require a new supplier acknowledgement.

Supplier notices are not goods receipts. Independent actual inspection records accepted/rejected/missing quantities; accepted totals cannot exceed approved demand. Excess can be recorded physically and rejected without increasing purchases or fictional stock ownership. Rejected/returned quantities, supplier acknowledgements, replacements and independently resolved cases must reconcile before PO closure. Receiving/handover tasks still require shared QA and customer confirmation. Supplier performance uses unique receipt/metric sources and evidenced numerators/denominators.

Supplier verification, response and shipping uploads use existing private registry/buckets, opaque bounded paths, current authority and quarantine. Trusted scanning is required before use. Another supplier cannot discover/upload the file. No public or signed bypass URL is returned; Storage RLS remains authoritative.

## Business Field Services

Campaigns pin corporate scope, milestones/deliverables and a published existing execution form. Locations link actual order/work/task/resource identities and retain declared target details with tenant-consistent order/site/zone keys. Each linked campaign order needs actual target locations before readiness.

Named current agents reuse eligibility, capacity, attendance, check-in, private evidence and versioned checklist submissions. Duplicate source submissions/content are rejected. Supervisor rejection retains the original and requires correction; shared independent QA precedes location approval. Actual shared corrective tasks can be linked without replacing old submissions. Current branch/department approvers accept only their own deliverables. Mandatory locations cannot be silently omitted; optional omission requires the configured shared partial-work policy, independent cancellation and explicit client acknowledgement.

Customer reporting filters locations/submissions by actual order authority. A branch-only user cannot receive global scope spanning inaccessible branches, another branch's targets or inaccessible primary-site geography. Coordinates and location provenance remain declared; no GPS or third-party verification success is inferred.

## Application operations and OMS

Server-only adapters: lib/fulfilment/server.ts and lib/specialized/{laundry,construction,procurement,field,queries}.ts. They validate Auth getUser, use the caller JWT with the anon key, bound inputs and map errors safely. They perform no financial arithmetic or token/payload logging and use no service-role ordinary-user client.

Public invoker RPCs include operation_policy_command, read_operation_policy, service_operation_command, read_service_operation, list_service_operations and specialized_document_reference, alongside the preserved fulfilment RPCs. Domain actions are explicit discriminated commands, not arbitrary status setters. Service-only SLA/outbox/expiry workers retain their restricted boundaries.

Keyset OMS queues cover laundry pickup/processing/exception/delivery; construction progress/changes; supplier sourcing/receiving; field review/progress and scoped cases/exceptions. Existing fulfilment queues cover execution, supervision, QA, rework, SLA and confirmation. Candidate public-schema types are separate from canonical hosted types. There is no OMS frontend in this assignment.

## Security and integrity

All new operational tables are private, RLS-enabled and denied ordinary table clients. Invoker wrappers delegate to explicit pinned-empty-search-path definers with current employment/membership/tenant/branch/assignment checks. Private schemas remain outside REST exposure; internal kernels and legacy bypass helpers have no ordinary execution grants. Accepted commercial snapshots, submitted evidence, decisions and physical history remain retained/guarded.

Composite FKs bind operations, orders, accounts, service versions, tasks, sites, suppliers, quote selections, PO versions, receipt lines and cases. Deterministically ordered FK indexes make fresh and upgrade definitions identical. Capacity remains the existing dispatch reservation system. Provider completion, supervision, QA, customer acceptance and administrative closure remain separate events; no specialised action fabricates payment or releases capacity early.

## Executed validation

Primary evidence: [integrated tests](phase-2-specialized-test-results.json), [preserved Increment 5 tests](phase-2-fulfilment-test-results.json), [hashes](phase-2-specialized-candidate.sha256), [query plans](phase-2-specialized-query-plans.json).

| Check | Actual result |
| --- | --- |
| Fresh PostgreSQL replay | ${tests.postgres}; all ${tests.migrations.length} migrations; unchanged reference seed twice. |
| Historical SQL | 493 passed. |
${stageRows}
| Total SQL | **${assertions} passed**. |
| Actual concurrency | **${concurrency.reduce((sum, key) => sum + checks(tests[key]), 0)} checks**, ${concurrency.reduce((sum, key) => sum + (tests[key]?.connections ?? 0), 0)} actor connections; independent disposable fixtures. |
| Upgrade preservation | **${upgrades.reduce((sum, key) => sum + checks(tests[key]), 0)} checks**; original 126-table and 142-table row multisets retained; fresh/upgrade definitions match. |
| Catalog | 180 RLS tables; safe definer paths, no PUBLIC internal execution, client private-table writes or client worker access. |

Scenarios A–C exercise actual laundry pickup/two partners/partial and rejected custody/damage/loss/QA failure/rework/delivery/closure. D–F exercise trade milestones/materials, rejected variations and accepted priced commercial replanning. G–I exercise competing supplier confidentiality, amendments, partial/missing/damaged/excess receipts, returns and replacements. J–L exercise multiple field agents, rejected corrections, optional cancellation and client/branch reporting. M–O add real concurrent acknowledgements/receipts/milestones/submissions, shared closure/capacity/outbox/performance and every historical regression.

Development failures are not passing evidence: SQL name/alias errors, too-short synthetic execution windows, fixture capacity overlap and nondeterministic redundant FK indexes were corrected. The priced variation now explicitly reschedules before re-release. Independent race fixtures use isolated clones. The final manifest/report comes from the successful complete candidate, not earlier DDL-only/focused attempts. Normal SQL suites roll back; retained synthetic race fixtures exist only in labelled loopback databases.

TypeScript, ESLint, dependency audit, migration integrity, text/credential scans and git diff checks are release gates recorded in the release checkpoint. Query plans are actual local EXPLAIN ANALYZE/BUFFERS on small fixtures, not production-volume certification.

## GitHub, recovery and hosted release

Implementation/checkpoint commit: **${implementation}**. ${deployed ? 'Pushed to existing main without force; postdeployment canonical types and this report are committed separately. The final response records that checkpoint hash.' : 'No hosted release success is claimed until the recovery, exact CLI dry run and postdeployment gates pass.'}

${backup ? `Fresh external archive: ${backup.archive}. Size: **${backup.bytes} bytes**; SHA-256: **${backup.sha256}**. Restore verified: **${backup.restoreVerified === true}**; complete restored upgrade definitions match: **${before.upgradedDefinitionMatch === true}**. Folder protection: ${before.backupDirectoryAcl}. Hosted/restored baseline schema and all 126 baseline row counts/digests were compared. [Recovery evidence](phase-2-increments-5-6-predeployment.json).` : 'Final fresh backup, restore/combined upgrade and official dry-run gates are pending. The earlier recovery preflight covers Increment 5 only and is not substituted for this gate.'}

Logical recovery scope is public/private/app_private/auth/storage/extensions/supabase_migrations schemas/rows. It excludes Storage object binaries, cluster roles/globals, Vault secrets, external integrations, platform settings and managed PITR. Access controls do not imply encryption. Restore first into an isolated compatible environment with reviewed managed roles/TOC and pg_restore --exit-on-error --no-owner, then compare definitions and original-column row digests. Never reset or overwrite hosted data as rollback; prefer reviewed additive forward fixes with affected callers paused.

${deployed ? `Hosted verification: **48 migrations / 180 RLS tables**, exact tested application definitions and preserved original rows. Protected function grants, unchanged Storage configuration and zero unintended operational role assignments passed. Anonymous API/Auth/Storage denial checks passed and canonical public-schema types were generated with the official CLI. [Hosted evidence](phase-2-increments-5-6-hosted-verification.json).` : 'Hosted remains at the verified 26-migration baseline until the separately recorded combined application succeeds. Canonical hosted types are preserved until actual deployment.'}

## Limits and operational prerequisites

- Authenticated Supabase JWT/REST/Storage workflows and server-adapter HTTP integration remain unexecuted without approved existing test identities; none were created hosted. SQL role tests do not replace those tests or a full managed-runtime/production-load certification.
- Real identities, employment/membership, least-privilege grants and independently approved category/workflow/form/SLA/provider/supplier/commercial configuration are required. No operational price, tax, provider, customer, supplier, campaign, order or credit record is seeded or activated.
- Scanning, external verification/location services, senders, schedules and live workers are not deployed. Upload preparation is working metadata/Storage authorisation; trusted scanning and actual HTTP/object-binary integration remain operational integrations.
- Physical work and corrective execution must fit validated assigned windows. New-window work requires authorised retirement/replanning/redispatch; capacity is never invented or silently extended. Cross-work personnel substitution fails safely until affected plans are retired. New commercial/specification scope outside approved demand requires the accepted-order change/new-order process, not editing a PO/task price in place.
- Detail projections are intended for operational units; large historical exports and production-scale benchmarks require separate bounded reporting. Currency conversion, supplier payments, financial stock ownership/refunds and third-party authenticity guarantees are not implemented.

${deployed ? '**Ready for frontend and OMS application development on this deployed backend**, subject to the outstanding authenticated integration tests and deliberate operational configuration before live use.' : '**Ready for the remaining controlled release gates after successful local validation.** Frontend development has not started.'}
`;
writeFileSync('docs/database/phase-2-increments-5-6-report.md', report);
console.log('Wrote consolidated report from actual passing evidence; hosted status:', deployed ? 'verified' : 'pending');
