# Conditional architecture approval — Phase 0 / Phase 1 refinements

Status: the latest implementation task supersedes the earlier runtime stop. Phase 1 refinements below are implemented in migrations 007–012 and validated in disposable embedded PostgreSQL. The sections remain the design rationale; [phase-1-report.md](phase-1-report.md) records exact delivered scope and limitations. Responsibility/custody and CMS sections are later-phase designs only. No hosted migration was applied; actual Supabase validation remains outstanding.

## A. Service pricing and versioned booking configuration

Add explicit `service_versions.pricing_mode`, CHECK-constrained to `fixed_price`, `starting_price`, `assessment_based`, `custom_quotation`. Keep customer pricing presentation separate from internal pricing calculation (`fixed`, `per_unit`, assessment rule). Published terms identify the approved rate-card/version and currency; rate cards/transaction snapshots preserve history.

- Fixed price requires an approved, effective fixed amount for the selected scope before commercial activation; no invented seed price.
- Starting price represents an explicitly labelled lower bound, never an accepted final charge; scope/quotation determines the approved payable amount.
- Assessment-based service requires assessment before a final approved quotation; assessment fees, if any, are separately configured and disclosed.
- Custom quotation has no automatic final price; approved quote/version is required before order creation.

Draft services may have unconfigured commercial terms. No representative service is activated solely because its seed record exists. `payment_gate` remains separate from pricing mode; none of these modes implies mandatory upfront payment.

Extend the existing version-owned field definitions without replacing them with unvalidated JSON:

| Proposed entity/change | Relationship and integrity |
| --- | --- |
| `service_booking_schemas` | Numbered schema belonging to an exact service version; published schemas immutable. Service publication pins the schema version. Existing fields are backfilled into a draft schema before NOT NULL/composite constraints are validated locally. |
| `service_booking_field_groups` | Schema-scoped stable group key, display ordering, repeatable flag and min/max occurrences with bounded counts; non-repeatable group permits one occurrence. |
| Existing `service_booking_fields` | Add schema/group composite FKs, customer-facing visibility (`visible`, `conditional`, `hidden`), field key, type, requiredness and safe display/help metadata. Unique keys/order within the correct schema/group. |
| `service_booking_field_dependencies` | Real FKs to source and target fields within the same schema, explicit condition operator and typed comparison value. Reject self-reference, dependency cycles and impossible type/operator combinations. Multiple-condition AND/OR grouping must be explicit. |
| `service_booking_field_validation_rules` | Allowlisted rules by field type: string length/pattern safety, numeric bounds, date bounds, choice cardinality, attachment class/size and required-when condition. No executable SQL/JavaScript or unrestricted expression strings. |
| Existing field options | Same-schema/field composite FKs, stable option codes and ordered labels; historical options immutable. |

Client visibility is presentation only. Server validation independently resolves conditions, rejects hidden/unknown/duplicate fields, validates types/choices, bounds group occurrences and prevents a hidden required field from bypassing an applicable requirement. An omitted field cannot be treated as an implicit approval. Future request answers identify exact schema/field/group occurrence; request/order tables remain outside Phase 1.

RLS must expose only published customer-facing definitions and safe rules. Internal staff fields, private pricing logic and qualification scoring remain in private definitions; do not expose them by returning an entire JSON booking schema. Customer display rules cannot reference private internal field values. Helpers check exact schema/version publication and audience. Add SQL tests for same-schema FKs, cycle rejection, conditional visibility and immutability; future intake validation tests wait for the booking phase.

## B. Responsibility and custody

Three roles are independent: **contractual service provider**, **assigned execution personnel**, and **approved processing/subcontracting partner**. An organisation's type or an individual's Auth role cannot stand in for these contractual relationships.

Phase 1 retains organisation/person identity anchors and documents this separation; it does not create provider network, dispatch, work orders or custody modules early. The later approved delivery design must include typed relationships:

- Contract/order responsibility snapshot -> contractual provider legal entity and exact signed agreement/version. OnIt's customer-facing management/accountability remains explicit.
- Assignment -> execution provider/personnel membership, qualification and work package. Several people or reassignment rounds do not silently transfer contractual responsibility.
- Approved partner allocation -> supplier/provider legal entity, qualification/approval record, subcontract terms and exact allocated work/batch/phase. Partner approval alone does not grant all customer account access.
- Custody transfer -> identified from/to custodian and authorised representatives, timestamp, location, item/bag/material scope, quantities, evidence and acknowledgement. Append-only corrections preserve predecessor events.

Laundry links bag/item reconciliation and processing batches to approved processing partners and shared custody records. Construction links phase/work-package subcontractors, accountable personnel and material custody without fixed universal stages. B2B client engagements retain responsibility and deliverable approval across campaigns/sites. Provider portal access is task-specific; no customer directly books a provider.

## C. Corporate branches, billing, credit and approvals

Reuse `organisation_locations` as the canonical physical branch/site record; do not duplicate addresses in an unrelated branch registry. Add a typed corporate branch extension to associate a location with one customer account and organisation, using composite FKs and stable scoped branch codes.

| Proposed entity/change | Boundary |
| --- | --- |
| `corporate_account_branches` | Account/organisation/location composite FKs; active/archived state; branch cost-centre/reference code. Referenced branches remain retained. |
| Existing `corporate_account_users` | Multiple approved requesters/approvers; no implied approval rights from organisation membership. Existing account/department restrictions remain valid and must not widen during backfill. |
| `corporate_account_user_branches` | Explicit allowed branch links with same account/organisation FKs. Account-wide grants are distinguished from branch-limited grants, not represented by an accidentally empty allowlist. |
| `corporate_billing_profiles` | Versioned account billing legal name/contact/address and centralised billing policy; no invoice/payment module in Phase 1. Branch cost attribution remains separate from bill-to account. |
| `corporate_credit_terms` | Immutable approved versions with currency, payment days, optional approved limit, effective interval, approver/policy reference and suspension/retirement. No commercial terms or limits seeded. |
| Shared approval policies and scoped thresholds | Versioned currency/amount thresholds, account/branch scope and independent approver requirements. Deterministic priority and no overlapping ambiguous active threshold bands. |

Orders later preserve requesting branch, requester, approval policy/version and billing-profile/credit-term snapshots. Centrally issued invoice lines still retain branch-level cost attribution. An account's boolean `credit_terms_approved` is insufficient evidence to allow credit: future commands require current approved, effective terms and limits. No live credit bypass or generic approval executor is introduced in Phase 1.

RLS requires an active organisation membership, approved corporate account/user grant, current subject status and allowed branch/department. Account-wide billing records require finance/account-wide permission; branch-only requesters must not enumerate other branches' costs. Approval authority and amount thresholds are checked independently of request permission, and makers cannot approve their own requests. Revoke/expiry tests must cover the same JWT after membership/grant changes.

## D. Geography and expansion

The existing country -> state -> city/LGA reference model and separate operational zones already support expansion without restructuring. Lagos stays the initial draft operational seed; no exhaustive geography, polygon, commercial rate or live coverage is invented.

Abuja and Port Harcourt are added later as approved reference records in their appropriate administrative geography, then connected to versioned operational zones and city service availability. Do not hardcode Lagos IDs/names, create one table per city, or treat a zone as an official LGA. All location/catalogue relationships use UUID FKs; country/state/city consistency is enforced. Currency and timezone remain explicit reference/configuration data. City publication/approval state is needed before CMS references may be published.

## E. Catalogue-linked CMS/SEO

Full content pages, blog posts and SEO remain in the later CMS phase. Prepare typed relationship design now; no CMS tables are created before Phase 1 passes:

- `content_page_services`, `blog_post_services`: FKs to real content and stable `services`, plus optional exact service version for version-specific claims.
- `content_page_locations`, `blog_post_locations`: FKs to approved `cities` and/or `service_zones` with exactly one typed location per link; avoid generic unvalidated location UUIDs.
- `seo_metadata`: exactly one real content/page/post/landing target, canonical URL, locale, validated structured data and optional typed service/location associations. Use typed bridges for multi-service/multi-location SEO.

Draft editorial content may reference draft records during preparation. Publication requires the content's editorial permission/workflow, current published service/version and approved operational location references; service/location withdrawal must prevent stale location-specific claims from remaining publicly served. Never use CMS text/slug matches as database relationship authority. Public SEO projections cannot expose unpublished service configuration, private customer sites or internal operations.

## Dependency and acceptance plan

Phase 0: repair/verify Docker Linux engine; obtain authenticated read-only hosted inventory/migration history; identify PostgreSQL version and existing equivalents. Do not apply SQL remotely. A management login alone is not proof that the actual database schema and history have been inspected.

Phase 1: audit existing six unsubmitted migrations; retain their identity/geography/customer/catalogue relationships; prepare small additional timestamped refinements once the local environment is ready. Because no migration is known to be deployed remotely, local clean-install and incremental tests must still both be rehearsed; never edit applied history after a verified deployment.

Run real local Supabase SQL and Auth/REST/Storage tests with synthetic fixtures, including the new conditional/schema/branch/credit/publication checks, before regenerating the physical dictionary/ERD and public TypeScript types. Existing embedded results remain labelled historical/supplemental. Do not proceed to bookings, dispatch, payments, wallet or other OMS modules in this request.
