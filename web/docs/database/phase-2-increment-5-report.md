# Increment 5 — service fulfilment, quality and issue resolution

Date: 2026-10-27, Africa/Lagos. **Local candidate only. No commit, push, hosted migration, hosted fixture, environment edit, worker deployment or AWS action. Increment 6 was not started.** Canonical hosted types and the unrelated logo are unchanged.

## Baseline and implementation

Read-only inspection verified the existing `main` repository and OnIt project `utoxjlsvqfmmzsjruzsm`, ACTIVE_HEALTHY, PostgreSQL 17.11, 26 migration versions and 126 RLS tables (51 public / 75 private). Hosted application definitions matched the verified Increment 4 replay. All 26 deployed migration SHA-256 values and the original seed remain unchanged. See [baseline evidence](phase-2-fulfilment-baseline.json). Installed Next.js data-security guidance was reviewed before adding the server adapter.

Six additive migrations implement shared work planning/execution, attendance, evidence, supervision, independent quality/rework, customer decisions, confidential cases, SLAs and closure on the existing order/provider/resource foundation. The candidate contains **32 migrations and 142 RLS tables (51 public / 91 private)**. There is no service-specific parallel fulfilment system, new identity system, duplicate capacity ledger or second event outbox.

## Exact migration inventory

| File under `supabase/migrations/` | Purpose |
| --- | --- |
| `20261028000100_fulfilment_foundation.sql` | Ten permission definitions; sixteen private tables; existing checklist version/type extensions; order-linked feedback and verified performance references; constraints, audit, RLS and retention. |
| `20261028000200_execution_configuration_access.sql` | Effective independently approved workflow/SLA policies; independently published existing checklist versions; bounded typed answer validation; scoped staff/worker/independence predicates and atomic history/outbox events. |
| `20261028000300_execution_commands.sql` | Work/task creation, dependencies, acceptance, progress, attendance, checklist responses, quarantined uploads, evidence review, supervision, suspension/resumption and operational exceptions. |
| `20261028000400_quality_closure_cases.sql` | Exact assignment revalidation, independently checked QA, retained findings/rework, customer confirmation/feedback, approved substitution/retirement and final capacity-aware closure. |
| `20261028000500_cases_sla_integrations.sql` | Confidential case lifecycle and investigation; SLA breach worker; existing order/dispatch compatibility boundaries; verified source-event performance integration. |
| `20261028000600_execution_reads_storage_integrity.sql` | Scoped work/case/OMS projections, private Storage reference controls, retained-record guards, worker/client grants and operational/FK indexes. |

No production reference data was added. No authority is automatically assigned to a real role. Local synthetic services, policies, amounts, people and schedules appear exclusively in disposable tests.

## Tables and relationships

| New private tables | Responsibility |
| --- | --- |
| `fulfilment_policies` | Numbered service-version/account/contract workflow, checklist and explicit SLA configuration; independent publication and non-overlapping effective windows. |
| `work_orders`, `work_tasks`, `task_dependencies` | Exact order/account/bundle linkage, immutable technical scope, operational ownership/supervision, task hierarchy, exact resource assignments and acyclic prerequisites. |
| `execution_history`, `execution_attendance` | Append-only transitions/snapshots and separately recorded declared attendance/independent acknowledgements. |
| `execution_evidence`, `execution_submissions` | Same-account registry evidence and versioned responses using existing checklist definitions; execution rounds retain prior evidence. |
| `quality_inspections`, `quality_findings`, `rework_requests` | Assigned inspections, independent decisions, immutable defects and corrective tasks linked to original work. |
| `service_cases`, `service_case_entries` | Customer/operational reports, confidential investigations, communication, corrective requirements, independent resolution and reopening. |
| `customer_confirmations`, `operational_exceptions`, `sla_tracks` | Current-plan sign-off/dispute, independently authorised operational alternatives, explicit due times, pauses and retained breach events. |

Reused: service orders, accepted quotation snapshots, corporate branch/department authority, provider parties/personnel/eligibility, shared human and party reservations, registry/private Storage, employee/RBAC authority, existing checklist registry, customer feedback, audit/idempotency receipts, provider performance observations and the existing operational outbox/lease worker. The [catalog-derived dictionary](phase-2-increment-5-dictionary.md) and [physical FK graph](phase-2-increment-5-erd.md) cover new and extended relationships.

## Planning and execution

Work generation requires a released commercial gate, a current confirmed bundle and an approved effective fulfilment policy. The accepted quotation's real pricing-contract relationship determines contract scope; a caller cannot invent or omit a contract to select weaker policy. Work snapshots contain technical descriptions/quantities/location references, without customer prices or provider compensation. Unique order/work codes and actor/key/payload receipts prevent duplicate creation.

Multiple work orders and personnel tasks may share a confirmed bundle. Non-container task schedules fit the assigned resource window and cannot overlap another task for the same worker in that order. Hierarchy parents must be same-work containers; dependencies must be same-work and acyclic. Required dependencies need quality approval before dependent execution. Containers finish only after children are approved.

Task progress follows explicitly approved edges, bounded to mobilisation, en route, arrival/access, start/in-progress, pauses/materials/customer decisions and completion declaration. Acceptance, actual execution window, check-in, current commercial gate and eligibility are rechecked. One human cannot execute competing tasks simultaneously. Database timestamps record actual start/finish; declared attendance is distinct. Staff can retain operational notes, revise active instructions/priority/ownership, assign a scoped supervisor, suspend and independently revalidate before resume. Every mutation requires expected work/task revisions and emits history/outbox records atomically.

Provider completion, supervisor verification, QA approval, customer acknowledgement and administrative closure are separate commands and events. There is no arbitrary status setter or provider completion-to-closure shortcut. Work/order projections aggregate task state; supervision and quality queues inspect outstanding tasks, so partially completed teams remain visible.

## Attendance, checklists and evidence

Attendance supports mobilisation/departure/arrival/check-in/out, no-show/late/missed appointment/access/interruption/discrepancy and supervisor acknowledgement. Coordinates are **declared only**; no GPS or journey verification is claimed. Acknowledgement names an earlier same-task/current-round record, requires an independent supervisor and cannot be duplicated. Verified arrival can produce a sourced timeliness observation.

Execution/quality/handover phases pin independently published versions in the existing checklist registry. Boolean, text, numeric, single/multiple choice, requiredness, bounds, conditional visibility and classified evidence requirements are validated in PostgreSQL. Conditional sources must be defined and unconditional; no executable expressions are accepted. Responses progress through draft/submitted/approved/rejected; corrections append a version. Submission freezes answers; approval/rejection is immutable. Supervision and closure inspect the latest applicable response.

Uploads generate opaque account-owned `work-evidence` registry paths, initially quarantined. Supported images/PDF/text/video are bounded by the existing 20 MiB limit. No binary data or public URL is stored. A trusted scanning process must mark registry objects clean before independent evidence acceptance. Same-account composite links, classification, uploader, server timestamps, task revision/round, review identity and existing retention metadata remain available. Providers lose execution file access when authority/assignment is lost or work closes; reviewed customer-visible evidence remains available through current tenant permissions. A supplied pre-existing customer document retains its original account visibility.

## Quality and rework

Only supervisor-verified work with mandatory accepted clean evidence enters QA. A scoped independent inspector is explicitly scheduled and submits the pinned quality checklist/findings. A separate checker cannot be the inspector, requester, completing worker, supervisor or a current/historical provider party/personnel subject. Conditional acceptance requires explicit policy and no blocking defect. Rejected inspections and findings are never rewritten.

Each unresolved finding has at most one active corrective record. Rework uses a new mandatory task and new evidence/checklists/QA; original work and failed outcomes remain. Within the assigned window it consumes the existing reservation, retaining capacity through correction. Outside the window it becomes `awaiting_capacity`; it cannot execute on expired capacity. Operations must independently retire the old execution arrangement, reschedule/redispatch through existing commands, create a new valid task and approve `transfer_rework`. Transfer preserves the defect and moves its still-running deadline to the actual corrective task. It does not manufacture extra capacity.

Worker substitution requires an independently approved current-plan exception, canonical shared-human/provider locks and the existing eligibility/reservation engine. The old resource is retained; a new resource version is created and affected tasks start a fresh execution round. Late failure rolls back all resource changes. Substitution of a resource shared with another active work order fails safely until those arrangements are retired; it never silently changes another supervisor's plan. Task reassignment uses an already assigned valid resource and rejects overlapping work.

## Customer, complaints and SLA control

Current account/branch/department approvers confirm or dispute the exact work plan. A dispute creates a blocking case and prevents closure. Resolution needs a different authorised person; the customer must acknowledge the revised plan after investigation. Customer silence never implies acceptance. Feedback corrections append linked revisions; original ratings/comments remain.

Case classifications are approved configuration, with severity/priority, owner, related order/work/task/provider, evidence, investigation/findings/corrective actions/customer communication, proposed resolution, independent decision, closure and reopening. Sensitive cases require separate authority. Providers and provider-affiliated staff cannot decide their own conduct; reporter projections exclude internal investigation and staffing data. Reopening retains prior entries and creates a new deadline cycle. Financial remediation requirements may be recorded; no refund/compensation transaction exists.

All nine SLA targets require explicit positive configured durations: mobilisation, arrival, start, task completion, quality review, rework, case acknowledgement/resolution and customer response. There are no invented universal durations. Authorised policy pauses retain remaining time; resume revalidates assignment. Revision-bound independently approved extensions retain exception/history evidence. `process_execution_slas` is service-role-only, bounded and retry-safe, using order-first locking and `SKIP LOCKED`. It records exact breach time, target, system provenance, escalation and existing outbox delivery receipts. **No scheduler or live notification sender is deployed.**

## Closure and resources

Closure requires independent authority, all active tasks quality-approved or explicitly cancelled under an approved partial-work policy, no unresolved rework, latest accepted handover checklists, mandatory clean accepted evidence, no blocking unresolved case and current-plan customer confirmation. An alternative needs an independently approved unexpired exception and an explicit policy; a customer dispute cannot be overridden by silence. Every allocated resource must have accounted work.

Capacity remains assigned through provider completion, QA and customer confirmation. Only authorised final closure of the last work order, or independently approved cancellation/retirement of the entire active arrangement, releases the existing dispatch bundle. Order and dispatch legacy commands are rebound and inaccessible bypass helpers are revoked, preventing reassignment/hold/release under active execution. Rescheduling preserves history and requires fresh commercial release/redispatch; no old provider availability is promised.

## API, OMS and security

`lib/fulfilment/server.ts` exposes typed caller-JWT/anon-key create/configure/change/quality/case/read/document/list operations, Auth `getUser` validation and safe error mapping. There is no service-role ordinary-user client, new route or frontend. The service-only SLA worker has no user adapter. Public wrappers are invokers; internal definers use pinned empty search paths and deliberate execution grants.

Ordinary authenticated RPC entry points (each performs its own current authority checks): `fulfilment_configuration`, `read_fulfilment_configuration`, `create_work_order`, `fulfilment_command`, `quality_command`, `execution_case_command`, `read_work_order`, `read_service_case`, `execution_dashboard`, `execution_document_reference`. `process_execution_slas` is exclusively service-role executable. Configuration approvers can inspect draft policy terms and pinned checklist standards before deciding; customers/providers cannot read that configuration.

All sixteen new tables are unexposed `private`, RLS-enabled and denied ordinary table clients. Work access checks current employee scope, corporate branch/department permissions and exact provider/personnel assignment. Historical provider participation prevents self-checking. Customer/provider DTOs omit commercial calculations, staffing investigations and confidential decisions. Registry/Storage policies extend existing helpers while preserving identity, HR and unrelated-account boundaries. Privileged maintenance remains a trusted database-owner boundary.

Keyset OMS pages support date/city/zone filtering and scheduled/active work, supervision, QA, rework, customer confirmation, completed/closed jobs, delays/breaches, complaints/incidents and verified provider observations. Detail projections include task schedules/attendance/resources, supervision and bounded history. These compose with existing provider/order read models; they are not a full OMS frontend or an unlimited archival analytics export.

Quality decisions, independently verified arrival, verified completed work and independently resolved provider-responsible cases feed the existing performance table. Each observation has a unique source event/provider/metric, numerator/denominator and actual event time; retries cannot duplicate it. No historical score is seeded. Derived analytics must distinguish work-order observations from order/assignment totals.

## Validation record

The final **serial PostgreSQL 17.11 run passed**, completing at `10/27/2026 16:16:01`. [Machine evidence](phase-2-fulfilment-test-results.json) records `passed: true`; [candidate manifest](phase-2-fulfilment-candidate.sha256) records the exact SQL hashes.

| Executed check | Final result |
| --- | --- |
| Fresh migration replay and seed integrity | All 32 migrations applied; original reference seed replayed twice; all 26 deployed migration hashes and seed unchanged. |
| SQL regression/scenario assertions | **493 passed**: 418 historical + 30 fulfilment + 18 confidential-case/SLA + 23 configuration/immutability + 4 corporate projection assertions. |
| Actual separate-connection checks | **35 passed across 79 connections**: 4 request/quotation + 7 provider/personnel + 11 order/dispatch + 13 fulfilment checks. Includes successful reassignment, former-worker denial, failed allocation rollback, independent SLA extension, suspension/resume and cancellation release. |
| Upgrade rehearsals | **13 checks passed**: six accepted-commercial checks, four provider/outbox/live-reservation checks and three Increment 4 upgrade checks. Original-column row multisets across **all 126 baseline tables / 1,777 synthetic rows** were preserved. |
| Security catalog | All 142 application tables have RLS; no public definers, unsafe definer paths, PUBLIC internal execution, browser private-schema usage, ordinary transaction writes or client event/expiry worker execution. New SLA worker and legacy bypass denial assertions passed. |
| Candidate types and documentation | Native catalog-derived public types generated to `types/database.fulfilment.generated.ts`; private schemas excluded; 16 new/six reused table dictionary and FK graph generated. Canonical hosted types untouched. |
| Application checks | TypeScript and repository-wide ESLint completed with exit code 0, including negative fulfilment type contracts. |
| Dependencies | `npm audit` completed with zero vulnerabilities; no dependency changes. |
| Query plans | Five actual local `EXPLAIN (ANALYZE, BUFFERS)` plans inspected; [plan evidence](phase-2-fulfilment-query-plans.json). Small fixtures, not production-volume certification. |

Normal SQL suites roll back. Only explicitly labelled synthetic fixtures in a newly created loopback database are retained for separate connections. The historical order runner is bounded to its 26-migration/seven-suite baseline; the new runner includes all prior checks. No hosted fixture or transaction was created.

Commands: `npm run db:test:fulfilment`; `npm run db:types:fulfilment`; `node scripts/database/fulfilment-query-plans.mjs`; `node node_modules/typescript/bin/tsc --noEmit`; `node node_modules/eslint/bin/eslint.js .`; `npm.cmd audit --json`; `git diff --check`. Migration integrity checks compare all deployed SQL and the original seed against prior manifests. The current dependency audit returned zero vulnerabilities after retrying the registry request with network access; no dependency/lockfile change was needed.

Development tests caught ambiguous PL/pgSQL names, missing temporary assertion privileges and a fixture extraction that included an old assertion. These were corrected and rerun. Source changes during an earlier run deliberately caused the SHA gate to fail; those runs are not counted as successful final validation.

A reassignment branch also referenced a non-existent optional release timestamp; it now updates the existing reservation status. Overlapping full replay/upgrade processes hit local process deadlines; validation was rerun serially with bounded, longer local-tool timeouts. Failed/time-limited attempts do not certify the candidate.

Required scenario mapping (all fixtures are disposable and synthetic):

| Scenario | Executable coverage |
| --- | --- |
| A: complete cleaning workflow | `008_service_fulfilment.sql`: real request/accepted quote/confirmed bundle, two workers, execution, evidence, QA, customer sign-off and closure. |
| B: partial team completion | `008`: closure denied after only the first worker passes QA. |
| C: incomplete evidence | `008`: supervision/QA entry blocked until mandatory clean accepted evidence and checklist review. |
| D: QA failure/rework | `008`: retained rejection, defect/corrective task, new evidence, separate reinspection and independent approval. |
| E: customer dispute | `008`: blocking dispute, independent investigation resolution and new-plan acknowledgement. |
| F: authority loss | Execution concurrency: former worker loses work access after approved task reassignment; historical provider/personnel revocation regressions also run. |
| G: reassignment/history/capacity | Execution concurrency: new round/resource, unused capacity release and independent cancellation. Historical order rescheduling regressions remain included. |
| H: competing staff/provider actions | Real concurrent progress/suspension transactions; exactly one revision wins. |
| I: corporate branch isolation | `011_execution_corporate_isolation.sql`: owner-created unreleased security projection fixture, current branch grant, other-branch denial and unrelated-account denial. This is not a claim of an authenticated corporate dispatch HTTP workflow. |
| J: sensitive cases | `009_execution_security_sla.sql`: restricted investigation, independent resolution, customer-safe entries and reopening preservation. |
| K: SLA processing | `009`: real one-second configured deadlines, bounded breach/escalation and retry; execution concurrency tests independent extension and suspend/resume clocks. |
| L: sourced performance | `008`: exact quality/completion observation counts, verified source FK and unique source/provider/metric constraint; command receipts prevent replaying the producer. |
| M: release timing | `008` retains both resources through QA/customer acknowledgement and releases at final closure; concurrency tests failed-substitution rollback, reassignment and authorised cancellation. |
| N: prior modules | All seven historical SQL suites, historical concurrency and accepted-commercial/provider/order upgrade rehearsals. |

## Limits, integration and release readiness

- Real Supabase Auth JWT/REST/Storage and server-adapter HTTP integration are unexecuted. Hosted Auth users remain absent; no test identities were created. Native PostgreSQL roles and restored managed schemas do not replace HTTP tests or managed-DDL review.
- No external scanner, location verifier, live sender, deployed SLA/outbox consumer or scheduler is activated. Registry scan status requires trusted integration. No GPS/travel success is inferred.
- Local query plans use small synthetic fixtures, not production-volume certification. Detail collections are intended for operational work units; large historical exports/analytics require separate bounded reporting APIs.
- Personnel substitution across multiple active work orders deliberately fails safely; retire/replan affected arrangements before changing the shared resource. Overtime/new-window rework requires approved new dispatch capacity, not a fabricated reservation extension.
- Independent real identities, employment, scoped grants, verified provider resources and approved service-specific workflow/checklist/SLA policies are prerequisites for operations. No universal policy is activated by migrations.

This is a local review checkpoint, **not permission to deploy**. Before a separate release: review the exact six migrations, refresh hosted drift/history, complete approved authenticated HTTP/Storage testing, create/restore-test a fresh external backup, inspect a CLI dry run restricted to these files, review operational grants and generate canonical types only after approved deployment. Recovery is a reviewed additive forward fix preserving execution/commercial/QA/case history; never reset or destructively roll back real data.

Changed-file groups: the six migrations and SQL suites `008`–`011`; `lib/fulfilment/server.ts` and candidate types/type contracts; native baseline/replay/concurrency/upgrade/generation/query-plan tooling; this report/dictionary/ERD/evidence/hash manifest and navigation banners. Existing order projection types gain the new execution states; historical test helpers accept an explicit cutoff. Package changes add only local fulfilment test/type scripts. No deployed migration, original seed, hosted type, browser client, environment value or logo changed.

Increment 6 can extend these exact order/work/task/evidence/quality/case/resource IDs for Laundry custody, Construction milestones/change orders, Procurement delivery and Business Field Services campaigns. It must reuse the shared workflow and outbox, preserve confidentiality and obtain its own implementation/release review. **Increment 6 has not started.**
