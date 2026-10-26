# Increment 3 provider dictionary — local candidate

Generated from the successfully replayed PostgreSQL 17 catalog. All 22 tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increment-3-report.md). No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.

## private.provider_profiles

Contracting provider party, linked to exactly one existing individual or organisation; never an Auth authority.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| individual_profile_id | uuid | no |  |
| organisation_id | uuid | no |  |
| provider_type | text | yes |  |
| status | text | yes | 'applicant'::text |
| revision | integer | yes | 1 |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| suspended_by | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_approval_independent: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- provider_profiles_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_profiles_check: CHECK ((num_nonnulls(individual_profile_id, organisation_id) = 1))
- provider_profiles_check1: CHECK (((provider_type = ANY (ARRAY['service_associate'::text, 'artisan'::text, 'professional'::text, 'field_agent'::text])) = (individual_profile_id IS NOT NULL)))
- provider_profiles_check2: CHECK (((status = ANY (ARRAY['applicant'::text, 'offboarded'::text])) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- provider_profiles_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_profiles_id_organisation_id_key: UNIQUE (id, organisation_id)
- provider_profiles_individual_profile_id_fkey: FOREIGN KEY (individual_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_profiles_individual_profile_id_key: UNIQUE (individual_profile_id)
- provider_profiles_organisation_id_fkey: FOREIGN KEY (organisation_id) REFERENCES organisations(id) ON DELETE RESTRICT
- provider_profiles_organisation_id_key: UNIQUE (organisation_id)
- provider_profiles_pkey: PRIMARY KEY (id)
- provider_profiles_provider_type_check: CHECK ((provider_type = ANY (ARRAY['service_associate'::text, 'artisan'::text, 'professional'::text, 'field_agent'::text, 'service_business'::text, 'processing_partner'::text, 'contractor'::text])))
- provider_profiles_revision_check: CHECK ((revision > 0))
- provider_profiles_status_check: CHECK ((status = ANY (ARRAY['applicant'::text, 'approved'::text, 'active'::text, 'suspended'::text, 'offboarded'::text])))
- provider_profiles_suspended_by_fkey: FOREIGN KEY (suspended_by) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_profiles_2e127dbf50_fk ON private.provider_profiles USING btree (suspended_by)
- CREATE INDEX provider_profiles_5ae94c6fb6_fk ON private.provider_profiles USING btree (approved_by)
- CREATE INDEX provider_profiles_81628b818e_fk ON private.provider_profiles USING btree (created_by)
- CREATE UNIQUE INDEX provider_profiles_id_organisation_id_key ON private.provider_profiles USING btree (id, organisation_id)
- CREATE UNIQUE INDEX provider_profiles_individual_profile_id_key ON private.provider_profiles USING btree (individual_profile_id)
- CREATE UNIQUE INDEX provider_profiles_organisation_id_key ON private.provider_profiles USING btree (organisation_id)
- CREATE UNIQUE INDEX provider_profiles_pkey ON private.provider_profiles USING btree (id)

## private.provider_personnel

Explicit executing worker, field-agent or administrator membership; does not grant employee status.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| organisation_id | uuid | yes |  |
| profile_id | uuid | yes |  |
| personnel_role | text | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| revoked_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_personnel_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_personnel_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_organisation_id_profile_id_fkey: FOREIGN KEY (organisation_id, profile_id) REFERENCES private.organisation_members(organisation_id, profile_id) ON DELETE RESTRICT
- provider_personnel_personnel_role_check: CHECK ((personnel_role = ANY (ARRAY['administrator'::text, 'executing_worker'::text, 'field_agent'::text])))
- provider_personnel_pkey: PRIMARY KEY (id)
- provider_personnel_profile_id_fkey: FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_personnel_provider_id_organisation_id_fkey: FOREIGN KEY (provider_id, organisation_id) REFERENCES private.provider_profiles(id, organisation_id) ON DELETE RESTRICT
- provider_personnel_provider_id_profile_id_key: UNIQUE (provider_id, profile_id)

Indexes:

- CREATE INDEX provider_personnel_2626d894ce_fk ON private.provider_personnel USING btree (created_by)
- CREATE INDEX provider_personnel_8532cb5777_fk ON private.provider_personnel USING btree (provider_id, organisation_id)
- CREATE INDEX provider_personnel_8660c8a796_fk ON private.provider_personnel USING btree (profile_id)
- CREATE INDEX provider_personnel_cd1531a748_fk ON private.provider_personnel USING btree (organisation_id, profile_id)
- CREATE UNIQUE INDEX provider_personnel_pkey ON private.provider_personnel USING btree (id)
- CREATE UNIQUE INDEX provider_personnel_provider_id_profile_id_key ON private.provider_personnel USING btree (provider_id, profile_id)

## private.provider_recruitment_campaigns

Recruitment source campaign and finite active/closed operating window.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| code | text | yes |  |
| name | text | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | no |  |
| status | text | yes | 'active'::text |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_recruitment_campaigns_check: CHECK (((ends_at IS NULL) OR (ends_at > starts_at)))
- provider_recruitment_campaigns_code_check: CHECK ((code ~ '^[a-z0-9_-]{1,80}$'::text))
- provider_recruitment_campaigns_code_key: UNIQUE (code)
- provider_recruitment_campaigns_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_recruitment_campaigns_name_check: CHECK (((length(name) >= 1) AND (length(name) <= 200)))
- provider_recruitment_campaigns_pkey: PRIMARY KEY (id)
- provider_recruitment_campaigns_status_check: CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text])))

Indexes:

- CREATE INDEX provider_recruitment_campaigns_3014d6451f_fk ON private.provider_recruitment_campaigns USING btree (created_by)
- CREATE UNIQUE INDEX provider_recruitment_campaigns_code_key ON private.provider_recruitment_campaigns USING btree (code)
- CREATE UNIQUE INDEX provider_recruitment_campaigns_pkey ON private.provider_recruitment_campaigns USING btree (id)

## private.provider_applications

Numbered sourced/referral application and current screening/onboarding stage; one open application per party.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| revision | integer | yes |  |
| stage | text | yes | 'submitted'::text |
| source | text | yes |  |
| campaign_id | uuid | no |  |
| referrer_id | uuid | no |  |
| screening_passed | boolean | yes | false |
| reviewed_by | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_applications_campaign_id_fkey: FOREIGN KEY (campaign_id) REFERENCES private.provider_recruitment_campaigns(id) ON DELETE RESTRICT
- provider_applications_check: CHECK (((source = 'referral'::text) = (referrer_id IS NOT NULL)))
- provider_applications_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_applications_pkey: PRIMARY KEY (id)
- provider_applications_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_applications_provider_id_revision_key: UNIQUE (provider_id, revision)
- provider_applications_referrer_id_fkey: FOREIGN KEY (referrer_id) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_applications_reviewed_by_fkey: FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_applications_revision_check: CHECK ((revision > 0))
- provider_applications_source_check: CHECK ((source = ANY (ARRAY['online'::text, 'referral'::text, 'social'::text, 'offline'::text, 'internal'::text])))
- provider_applications_stage_check: CHECK ((stage = ANY (ARRAY['submitted'::text, 'screening'::text, 'verification'::text, 'training'::text, 'approved'::text, 'rejected'::text, 'withdrawn'::text])))

Indexes:

- CREATE INDEX provider_applications_3d827b8eb7_fk ON private.provider_applications USING btree (reviewed_by)
- CREATE INDEX provider_applications_56a2252b8e_fk ON private.provider_applications USING btree (created_by)
- CREATE INDEX provider_applications_81e29768fe_fk ON private.provider_applications USING btree (campaign_id)
- CREATE INDEX provider_applications_8b33a71943_fk ON private.provider_applications USING btree (referrer_id)
- CREATE UNIQUE INDEX provider_applications_pkey ON private.provider_applications USING btree (id)
- CREATE UNIQUE INDEX provider_applications_provider_id_revision_key ON private.provider_applications USING btree (provider_id, revision)
- CREATE UNIQUE INDEX provider_open_application_key ON private.provider_applications USING btree (provider_id) WHERE (stage <> ALL (ARRAY['approved'::text, 'rejected'::text, 'withdrawn'::text]))

## private.provider_qualifications

Independently decided verification, skill, credential or training evidence, expiry and subject identity.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| subject_profile_id | uuid | no |  |
| kind | text | yes |  |
| code | text | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| document_id | uuid | no |  |
| status | text | yes | 'pending'::text |
| decided_by | uuid | no |  |
| decided_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_qualification_independent: CHECK (((decided_by IS NULL) OR (decided_by <> created_by)))
- provider_qualifications_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_qualifications_check1: CHECK (((status = 'pending'::text) = ((decided_by IS NULL) AND (decided_at IS NULL))))
- provider_qualifications_code_check: CHECK ((code ~ '^[a-z0-9_-]{1,80}$'::text))
- provider_qualifications_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_qualifications_decided_by_fkey: FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_qualifications_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- provider_qualifications_id_provider_id_key: UNIQUE (id, provider_id)
- provider_qualifications_kind_check: CHECK ((kind = ANY (ARRAY['verification'::text, 'skill'::text, 'credential'::text, 'training'::text])))
- provider_qualifications_pkey: PRIMARY KEY (id)
- provider_qualifications_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_qualifications_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'revoked'::text])))
- provider_qualifications_subject_profile_id_fkey: FOREIGN KEY (subject_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_qualification_lookup ON private.provider_qualifications USING btree (provider_id, kind, code, status, valid_until)
- CREATE INDEX provider_qualifications_0dd413165c_fk ON private.provider_qualifications USING btree (subject_profile_id)
- CREATE INDEX provider_qualifications_11b524ce00_fk ON private.provider_qualifications USING btree (document_id)
- CREATE INDEX provider_qualifications_7e51a821c8_fk ON private.provider_qualifications USING btree (created_by)
- CREATE INDEX provider_qualifications_97dc80df6e_fk ON private.provider_qualifications USING btree (decided_by)
- CREATE UNIQUE INDEX provider_qualifications_id_provider_id_key ON private.provider_qualifications USING btree (id, provider_id)
- CREATE UNIQUE INDEX provider_qualifications_pkey ON private.provider_qualifications USING btree (id)

## private.provider_requirement_sets

Independently approved versioned service/type/zone requirements, capacity unit and optional performance/travel/engagement gates.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| service_version_id | uuid | yes |  |
| provider_type | text | yes |  |
| zone_id | uuid | yes |  |
| version | integer | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| requirements | jsonb | yes |  |
| capacity_unit | text | yes |  |
| engagement_required | boolean | yes |  |
| maximum_travel_km | numeric(10,2) | no |  |
| performance_metric | text | no |  |
| minimum_performance | numeric(8,6) | no |  |
| performance_window_days | integer | no |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_requirement_sets_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_requirement_sets_capacity_unit_check: CHECK ((capacity_unit ~ '^[a-z0-9_-]{1,40}$'::text))
- provider_requirement_sets_check: CHECK (((performance_metric IS NULL) = (minimum_performance IS NULL)))
- provider_requirement_sets_check1: CHECK (((performance_metric IS NULL) = (performance_window_days IS NULL)))
- provider_requirement_sets_check2: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_requirement_sets_check3: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- provider_requirement_sets_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_requirement_sets_maximum_travel_km_check: CHECK ((maximum_travel_km > (0)::numeric))
- provider_requirement_sets_minimum_performance_check: CHECK (((minimum_performance >= (0)::numeric) AND (minimum_performance <= (1)::numeric)))
- provider_requirement_sets_performance_metric_check: CHECK ((performance_metric = ANY (ARRAY['acceptance'::text, 'completion'::text, 'timeliness'::text, 'quality'::text, 'reliability'::text])))
- provider_requirement_sets_performance_window_days_check: CHECK (((performance_window_days >= 1) AND (performance_window_days <= 3650)))
- provider_requirement_sets_pkey: PRIMARY KEY (id)
- provider_requirement_sets_provider_type_check: CHECK ((provider_type = ANY (ARRAY['service_associate'::text, 'artisan'::text, 'professional'::text, 'field_agent'::text, 'service_business'::text, 'processing_partner'::text, 'contractor'::text])))
- provider_requirement_sets_requirements_check: CHECK (((jsonb_typeof(requirements) = 'array'::text) AND ((jsonb_array_length(requirements) >= 1) AND (jsonb_array_length(requirements) <= 50))))
- provider_requirement_sets_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- provider_requirement_sets_service_version_id_provider_type__key: UNIQUE (service_version_id, provider_type, zone_id, version)
- provider_requirement_sets_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- provider_requirement_sets_version_check: CHECK ((version > 0))
- provider_requirement_sets_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT
- provider_requirements_independent: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))

Indexes:

- CREATE INDEX provider_requirement_sets_6f53dc9d5b_fk ON private.provider_requirement_sets USING btree (approved_by)
- CREATE INDEX provider_requirement_sets_b5f88d9825_fk ON private.provider_requirement_sets USING btree (zone_id)
- CREATE INDEX provider_requirement_sets_daefb8ecaa_fk ON private.provider_requirement_sets USING btree (created_by)
- CREATE UNIQUE INDEX provider_requirement_sets_pkey ON private.provider_requirement_sets USING btree (id)
- CREATE UNIQUE INDEX provider_requirement_sets_service_version_id_provider_type__key ON private.provider_requirement_sets USING btree (service_version_id, provider_type, zone_id, version)

## private.provider_training_courses

Versioned independently approved training standard, explicit pass/attendance requirements and certificate validity.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| code | text | yes |  |
| version | integer | yes |  |
| name | text | yes |  |
| pass_mark | numeric(5,2) | yes |  |
| required_attendance | numeric(5,2) | yes |  |
| certificate_valid_days | integer | yes |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_course_independent: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- provider_training_courses_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_training_courses_certificate_valid_days_check: CHECK (((certificate_valid_days >= 1) AND (certificate_valid_days <= 3650)))
- provider_training_courses_check: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- provider_training_courses_code_check: CHECK ((code ~ '^[a-z0-9_-]{1,80}$'::text))
- provider_training_courses_code_version_key: UNIQUE (code, version)
- provider_training_courses_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_training_courses_name_check: CHECK (((length(name) >= 1) AND (length(name) <= 200)))
- provider_training_courses_pass_mark_check: CHECK (((pass_mark >= (0)::numeric) AND (pass_mark <= (100)::numeric)))
- provider_training_courses_pkey: PRIMARY KEY (id)
- provider_training_courses_required_attendance_check: CHECK (((required_attendance >= (0)::numeric) AND (required_attendance <= (100)::numeric)))
- provider_training_courses_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- provider_training_courses_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX provider_training_courses_1d1d42fad8_fk ON private.provider_training_courses USING btree (created_by)
- CREATE UNIQUE INDEX provider_training_courses_code_version_key ON private.provider_training_courses USING btree (code, version)
- CREATE INDEX provider_training_courses_df74675533_fk ON private.provider_training_courses USING btree (approved_by)
- CREATE UNIQUE INDEX provider_training_courses_pkey ON private.provider_training_courses USING btree (id)

## private.provider_training_sessions

Internal trainer and exact session timing pinned to a course version.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| course_id | uuid | yes |  |
| trainer_id | uuid | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_training_sessions_check: CHECK ((ends_at > starts_at))
- provider_training_sessions_course_id_fkey: FOREIGN KEY (course_id) REFERENCES private.provider_training_courses(id) ON DELETE RESTRICT
- provider_training_sessions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_training_sessions_pkey: PRIMARY KEY (id)
- provider_training_sessions_trainer_id_fkey: FOREIGN KEY (trainer_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_training_sessions_a628afea99_fk ON private.provider_training_sessions USING btree (created_by)
- CREATE INDEX provider_training_sessions_add7a1fe91_fk ON private.provider_training_sessions USING btree (trainer_id)
- CREATE INDEX provider_training_sessions_be1c731a51_fk ON private.provider_training_sessions USING btree (course_id)
- CREATE UNIQUE INDEX provider_training_sessions_pkey ON private.provider_training_sessions USING btree (id)

## private.provider_training_enrolments

Per-party/person session attendance, trainer assessment and independent certificate decision.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| session_id | uuid | yes |  |
| subject_profile_id | uuid | no |  |
| attendance_percent | numeric(5,2) | no |  |
| score | numeric(5,2) | no |  |
| status | text | yes | 'enrolled'::text |
| qualification_id | uuid | no |  |
| assessed_by | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_training_enrolments_assessed_by_fkey: FOREIGN KEY (assessed_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_training_enrolments_attendance_percent_check: CHECK (((attendance_percent >= (0)::numeric) AND (attendance_percent <= (100)::numeric)))
- provider_training_enrolments_check: CHECK (((status = 'enrolled'::text) = (assessed_by IS NULL)))
- provider_training_enrolments_check1: CHECK (((status <> ALL (ARRAY['passed'::text, 'failed'::text])) OR ((attendance_percent IS NOT NULL) AND (score IS NOT NULL))))
- provider_training_enrolments_check2: CHECK (((status = 'passed'::text) = (qualification_id IS NOT NULL)))
- provider_training_enrolments_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_training_enrolments_pkey: PRIMARY KEY (id)
- provider_training_enrolments_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_training_enrolments_provider_id_session_id_subject_key: UNIQUE NULLS NOT DISTINCT (provider_id, session_id, subject_profile_id)
- provider_training_enrolments_qualification_id_key: UNIQUE (qualification_id)
- provider_training_enrolments_qualification_id_provider_id_fkey: FOREIGN KEY (qualification_id, provider_id) REFERENCES private.provider_qualifications(id, provider_id) ON DELETE RESTRICT
- provider_training_enrolments_score_check: CHECK (((score >= (0)::numeric) AND (score <= (100)::numeric)))
- provider_training_enrolments_session_id_fkey: FOREIGN KEY (session_id) REFERENCES private.provider_training_sessions(id) ON DELETE RESTRICT
- provider_training_enrolments_status_check: CHECK ((status = ANY (ARRAY['enrolled'::text, 'assessed'::text, 'passed'::text, 'failed'::text])))
- provider_training_enrolments_subject_profile_id_fkey: FOREIGN KEY (subject_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_training_enrolments_3c20c991e0_fk ON private.provider_training_enrolments USING btree (qualification_id, provider_id)
- CREATE INDEX provider_training_enrolments_421fe184cf_fk ON private.provider_training_enrolments USING btree (subject_profile_id)
- CREATE INDEX provider_training_enrolments_947d0346ed_fk ON private.provider_training_enrolments USING btree (assessed_by)
- CREATE INDEX provider_training_enrolments_bd7e3741db_fk ON private.provider_training_enrolments USING btree (created_by)
- CREATE INDEX provider_training_enrolments_cd4966686c_fk ON private.provider_training_enrolments USING btree (session_id)
- CREATE UNIQUE INDEX provider_training_enrolments_pkey ON private.provider_training_enrolments USING btree (id)
- CREATE UNIQUE INDEX provider_training_enrolments_provider_id_session_id_subject_key ON private.provider_training_enrolments USING btree (provider_id, session_id, subject_profile_id) NULLS NOT DISTINCT
- CREATE UNIQUE INDEX provider_training_enrolments_qualification_id_key ON private.provider_training_enrolments USING btree (qualification_id)

## private.provider_coverage_areas

Explicit exact-service/zone operating coverage; no inferred city or polygon coverage.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| travel_limit_km | numeric(10,2) | no |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| revoked_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_coverage_areas_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_coverage_areas_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_coverage_areas_pkey: PRIMARY KEY (id)
- provider_coverage_areas_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_coverage_areas_provider_id_service_version_id_zone_key: UNIQUE (provider_id, service_version_id, zone_id, valid_from)
- provider_coverage_areas_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- provider_coverage_areas_travel_limit_km_check: CHECK ((travel_limit_km > (0)::numeric))
- provider_coverage_areas_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_coverage_areas_3b9cd9cdf9_fk ON private.provider_coverage_areas USING btree (service_version_id)
- CREATE INDEX provider_coverage_areas_79186bfc2d_fk ON private.provider_coverage_areas USING btree (zone_id)
- CREATE INDEX provider_coverage_areas_c05c8ec1c1_fk ON private.provider_coverage_areas USING btree (created_by)
- CREATE UNIQUE INDEX provider_coverage_areas_pkey ON private.provider_coverage_areas USING btree (id)
- CREATE UNIQUE INDEX provider_coverage_areas_provider_id_service_version_id_zone_key ON private.provider_coverage_areas USING btree (provider_id, service_version_id, zone_id, valid_from)
- CREATE INDEX provider_coverage_lookup ON private.provider_coverage_areas USING btree (provider_id, service_version_id, zone_id) WHERE (revoked_at IS NULL)

## private.provider_work_schedules

Zone-timezone weekday declarations, materialised within a bounded date horizon.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| timezone | text | yes |  |
| weekdays | smallint[] | yes |  |
| local_start | time without time zone | yes |  |
| local_end | time without time zone | yes |  |
| valid_from | date | yes |  |
| valid_until | date | yes |  |
| revoked_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_work_schedules_check: CHECK ((local_end > local_start))
- provider_work_schedules_check1: CHECK (((valid_until >= valid_from) AND ((valid_until - valid_from) <= 30)))
- provider_work_schedules_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_work_schedules_id_provider_id_service_version_id_key: UNIQUE (id, provider_id, service_version_id)
- provider_work_schedules_pkey: PRIMARY KEY (id)
- provider_work_schedules_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_work_schedules_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- provider_work_schedules_weekdays_check: CHECK ((((cardinality(weekdays) >= 1) AND (cardinality(weekdays) <= 7)) AND (weekdays <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint])))
- provider_work_schedules_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_work_schedules_16d2307fed_fk ON private.provider_work_schedules USING btree (provider_id)
- CREATE INDEX provider_work_schedules_7c86e0b7b3_fk ON private.provider_work_schedules USING btree (service_version_id)
- CREATE INDEX provider_work_schedules_a880e0de24_fk ON private.provider_work_schedules USING btree (created_by)
- CREATE INDEX provider_work_schedules_bfa18a60cc_fk ON private.provider_work_schedules USING btree (zone_id)
- CREATE UNIQUE INDEX provider_work_schedules_id_provider_id_service_version_id_key ON private.provider_work_schedules USING btree (id, provider_id, service_version_id)
- CREATE UNIQUE INDEX provider_work_schedules_pkey ON private.provider_work_schedules USING btree (id)

## private.provider_availability

Confirmed working windows and overriding leave/blackout/unavailable intervals.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| kind | text | yes |  |
| revoked_at | timestamp with time zone | no |  |
| schedule_id | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_availability_check: CHECK ((ends_at > starts_at))
- provider_availability_check1: CHECK (((ends_at - starts_at) <= '31 days'::interval))
- provider_availability_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_availability_kind_check: CHECK ((kind = ANY (ARRAY['working'::text, 'leave'::text, 'blackout'::text, 'temporary_unavailable'::text])))
- provider_availability_pkey: PRIMARY KEY (id)
- provider_availability_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_availability_schedule_id_provider_id_service_vers_fkey: FOREIGN KEY (schedule_id, provider_id, service_version_id) REFERENCES private.provider_work_schedules(id, provider_id, service_version_id) ON DELETE RESTRICT
- provider_availability_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_availability_5b250eaf5c_fk ON private.provider_availability USING btree (provider_id)
- CREATE INDEX provider_availability_6d71ddb219_fk ON private.provider_availability USING btree (created_by)
- CREATE INDEX provider_availability_9837e07f38_fk ON private.provider_availability USING btree (schedule_id, provider_id, service_version_id)
- CREATE INDEX provider_availability_d8c544e1bd_fk ON private.provider_availability USING btree (service_version_id)
- CREATE INDEX provider_availability_lookup ON private.provider_availability USING btree (provider_id, service_version_id, starts_at, ends_at) WHERE (revoked_at IS NULL)
- CREATE UNIQUE INDEX provider_availability_pkey ON private.provider_availability USING btree (id)

## private.provider_capacity

Shared provider/unit resource pool across service versions; individual pools use concurrent_jobs.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| unit | text | yes |  |
| units | numeric(12,4) | yes |  |
| status | text | yes | 'active'::text |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_capacity_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_capacity_id_provider_id_key: UNIQUE (id, provider_id)
- provider_capacity_pkey: PRIMARY KEY (id)
- provider_capacity_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_capacity_provider_id_unit_key: UNIQUE (provider_id, unit)
- provider_capacity_status_check: CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
- provider_capacity_unit_check: CHECK ((unit ~ '^[a-z0-9_-]{1,40}$'::text))
- provider_capacity_units_check: CHECK ((units > (0)::numeric))

Indexes:

- CREATE INDEX provider_capacity_54ab9526f1_fk ON private.provider_capacity USING btree (created_by)
- CREATE UNIQUE INDEX provider_capacity_id_provider_id_key ON private.provider_capacity USING btree (id, provider_id)
- CREATE UNIQUE INDEX provider_capacity_pkey ON private.provider_capacity USING btree (id)
- CREATE UNIQUE INDEX provider_capacity_provider_id_unit_key ON private.provider_capacity USING btree (provider_id, unit)

## private.provider_capacity_reservations

Time-bounded idempotent reservation/release receipt; assignment conversion belongs to Increment 4.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| pool_id | uuid | yes |  |
| provider_id | uuid | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| units | numeric(12,4) | yes |  |
| expires_at | timestamp with time zone | yes |  |
| status | text | yes | 'reserved'::text |
| purpose_reference | text | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |
| worker_profile_id | uuid | no |  |
| worker_units | numeric(12,4) | no |  |

Constraints (including FKs, unique and CHECK):

- provider_capacity_reservations_check: CHECK ((ends_at > starts_at))
- provider_capacity_reservations_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_capacity_reservations_pkey: PRIMARY KEY (id)
- provider_capacity_reservations_pool_id_fkey: FOREIGN KEY (pool_id) REFERENCES private.provider_capacity(id) ON DELETE RESTRICT
- provider_capacity_reservations_pool_id_provider_id_fkey: FOREIGN KEY (pool_id, provider_id) REFERENCES private.provider_capacity(id, provider_id) ON DELETE RESTRICT
- provider_capacity_reservations_purpose_reference_check: CHECK (((length(purpose_reference) >= 1) AND (length(purpose_reference) <= 120)))
- provider_capacity_reservations_status_check: CHECK ((status = ANY (ARRAY['reserved'::text, 'assigned'::text, 'released'::text, 'expired'::text])))
- provider_capacity_reservations_units_check: CHECK ((units > (0)::numeric))
- provider_capacity_reservations_worker_profile_id_fkey: FOREIGN KEY (worker_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT
- reservation_worker_units: CHECK ((((worker_profile_id IS NULL) AND (worker_units IS NULL)) OR ((worker_profile_id IS NOT NULL) AND (worker_units IS NOT NULL) AND (worker_units > (0)::numeric))))

Indexes:

- CREATE INDEX personnel_reservation_overlap ON private.provider_capacity_reservations USING btree (worker_profile_id, starts_at, ends_at) WHERE (status = ANY (ARRAY['reserved'::text, 'assigned'::text]))
- CREATE INDEX personnel_reservation_profile ON private.provider_capacity_reservations USING btree (worker_profile_id)
- CREATE INDEX provider_capacity_reservations_00c65eb964_fk ON private.provider_capacity_reservations USING btree (created_by)
- CREATE INDEX provider_capacity_reservations_3e6c78fb52_fk ON private.provider_capacity_reservations USING btree (pool_id)
- CREATE INDEX provider_capacity_reservations_8023a6cc86_fk ON private.provider_capacity_reservations USING btree (pool_id, provider_id)
- CREATE UNIQUE INDEX provider_capacity_reservations_pkey ON private.provider_capacity_reservations USING btree (id)
- CREATE INDEX provider_reservations_overlap ON private.provider_capacity_reservations USING btree (pool_id, starts_at, ends_at) WHERE (status = ANY (ARRAY['reserved'::text, 'assigned'::text]))

## private.provider_engagements

Private versioned contract, explicit currency/rate unit and service/zone obligations; independently approved.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| service_version_id | uuid | yes |  |
| zone_id | uuid | yes |  |
| version | integer | yes |  |
| contract_reference | text | yes |  |
| currency_id | uuid | yes |  |
| unit | text | yes |  |
| unit_rate | numeric(20,4) | yes |  |
| obligations | text | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | yes |  |
| document_id | uuid | yes |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_engagement_independent: CHECK (((approved_by IS NULL) OR (approved_by <> created_by)))
- provider_engagements_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_engagements_check: CHECK ((valid_until > valid_from))
- provider_engagements_check1: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- provider_engagements_contract_reference_check: CHECK (((length(contract_reference) >= 1) AND (length(contract_reference) <= 160)))
- provider_engagements_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_engagements_currency_id_fkey: FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE RESTRICT
- provider_engagements_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- provider_engagements_obligations_check: CHECK (((length(obligations) >= 1) AND (length(obligations) <= 8000)))
- provider_engagements_pkey: PRIMARY KEY (id)
- provider_engagements_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_engagements_provider_id_service_version_id_zone_id_key: UNIQUE (provider_id, service_version_id, zone_id, version)
- provider_engagements_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- provider_engagements_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'terminated'::text])))
- provider_engagements_unit_check: CHECK ((unit ~ '^[a-z0-9_-]{1,40}$'::text))
- provider_engagements_unit_rate_check: CHECK ((unit_rate >= (0)::numeric))
- provider_engagements_version_check: CHECK ((version > 0))
- provider_engagements_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_engagements_5eea932ece_fk ON private.provider_engagements USING btree (document_id)
- CREATE INDEX provider_engagements_7663ce0b79_fk ON private.provider_engagements USING btree (service_version_id)
- CREATE INDEX provider_engagements_84e3eab3ef_fk ON private.provider_engagements USING btree (zone_id)
- CREATE INDEX provider_engagements_8bcd4c0f21_fk ON private.provider_engagements USING btree (approved_by)
- CREATE INDEX provider_engagements_e8375534e7_fk ON private.provider_engagements USING btree (created_by)
- CREATE INDEX provider_engagements_e99c810b88_fk ON private.provider_engagements USING btree (currency_id)
- CREATE UNIQUE INDEX provider_engagements_pkey ON private.provider_engagements USING btree (id)
- CREATE UNIQUE INDEX provider_engagements_provider_id_service_version_id_zone_id_key ON private.provider_engagements USING btree (provider_id, service_version_id, zone_id, version)

## private.provider_restrictions

Current/future provider/service/zone restriction with independently authorised revocation.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| service_version_id | uuid | no |  |
| zone_id | uuid | no |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| reason | text | yes |  |
| revoked_at | timestamp with time zone | no |  |
| revoked_by | uuid | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_restrictions_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_restrictions_check1: CHECK (((revoked_at IS NULL) = (revoked_by IS NULL)))
- provider_restrictions_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_restrictions_pkey: PRIMARY KEY (id)
- provider_restrictions_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_restrictions_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))
- provider_restrictions_revoked_by_fkey: FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_restrictions_service_version_id_fkey: FOREIGN KEY (service_version_id) REFERENCES service_versions(id) ON DELETE RESTRICT
- provider_restrictions_zone_id_fkey: FOREIGN KEY (zone_id) REFERENCES service_zones(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX provider_restriction_lookup ON private.provider_restrictions USING btree (provider_id, valid_from, valid_until) WHERE (revoked_at IS NULL)
- CREATE INDEX provider_restrictions_24b51e58cc_fk ON private.provider_restrictions USING btree (zone_id)
- CREATE INDEX provider_restrictions_4019e24462_fk ON private.provider_restrictions USING btree (revoked_by)
- CREATE INDEX provider_restrictions_6633ea947e_fk ON private.provider_restrictions USING btree (provider_id)
- CREATE INDEX provider_restrictions_869cc28421_fk ON private.provider_restrictions USING btree (service_version_id)
- CREATE INDEX provider_restrictions_c9ed997637_fk ON private.provider_restrictions USING btree (created_by)
- CREATE UNIQUE INDEX provider_restrictions_pkey ON private.provider_restrictions USING btree (id)

## private.provider_performance_events

Append-only evidenced numerator/denominator observations, not fabricated scores.

Owner: OnIt provider network operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| metric | text | yes |  |
| successful | integer | yes |  |
| observations | integer | yes |  |
| source_reference | text | yes |  |
| document_id | uuid | yes |  |
| occurred_at | timestamp with time zone | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |

Constraints (including FKs, unique and CHECK):

- provider_performance_events_check: CHECK (((observations > 0) AND (observations >= successful)))
- provider_performance_events_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_performance_events_document_id_fkey: FOREIGN KEY (document_id) REFERENCES private.document_objects(id) ON DELETE RESTRICT
- provider_performance_events_metric_check: CHECK ((metric = ANY (ARRAY['acceptance'::text, 'completion'::text, 'timeliness'::text, 'quality'::text, 'reliability'::text])))
- provider_performance_events_pkey: PRIMARY KEY (id)
- provider_performance_events_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_performance_events_provider_id_metric_source_refer_key: UNIQUE (provider_id, metric, source_reference)
- provider_performance_events_source_reference_check: CHECK (((length(source_reference) >= 1) AND (length(source_reference) <= 160)))
- provider_performance_events_successful_check: CHECK ((successful >= 0))

Indexes:

- CREATE INDEX provider_performance_events_12103c561d_fk ON private.provider_performance_events USING btree (document_id)
- CREATE INDEX provider_performance_events_d070d2c7ef_fk ON private.provider_performance_events USING btree (created_by)
- CREATE UNIQUE INDEX provider_performance_events_pkey ON private.provider_performance_events USING btree (id)
- CREATE UNIQUE INDEX provider_performance_events_provider_id_metric_source_refer_key ON private.provider_performance_events USING btree (provider_id, metric, source_reference)

## private.provider_history

Append-only internal actor, transition, reason, permission and correlation history.

Owner: OnIt provider network operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| action | text | yes |  |
| subject_id | uuid | yes |  |
| previous_state | text | no |  |
| new_state | text | no |  |
| reason | text | yes |  |
| correlation_id | uuid | yes | gen_random_uuid() |
| permission_code | text | yes |  |
| actor_id | uuid | yes |  |
| created_at | timestamp with time zone | yes | clock_timestamp() |

Constraints (including FKs, unique and CHECK):

- provider_history_actor_id_fkey: FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_history_pkey: PRIMARY KEY (id)
- provider_history_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT
- provider_history_reason_check: CHECK (((length(reason) >= 1) AND (length(reason) <= 2000)))

Indexes:

- CREATE INDEX provider_history_9f16aca242_fk ON private.provider_history USING btree (actor_id)
- CREATE UNIQUE INDEX provider_history_pkey ON private.provider_history USING btree (id)
- CREATE INDEX provider_history_timeline ON private.provider_history USING btree (provider_id, created_at DESC, id)

## private.operational_events

Append-only transactional provider event outbox; no claim of external delivery.

Owner: OnIt platform operations. Lifecycle: append-only; mutation/deletion rejected by trigger. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| provider_id | uuid | yes |  |
| event_code | text | yes |  |
| subject_id | uuid | yes |  |
| correlation_id | uuid | yes |  |
| created_at | timestamp with time zone | yes | clock_timestamp() |

Constraints (including FKs, unique and CHECK):

- operational_events_pkey: PRIMARY KEY (id)
- operational_events_provider_id_fkey: FOREIGN KEY (provider_id) REFERENCES private.provider_profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX operational_events_cc1d9398d1_fk ON private.operational_events USING btree (provider_id)
- CREATE UNIQUE INDEX operational_events_pkey ON private.operational_events USING btree (id)

## private.operational_event_deliveries

Mutable lease/retry/ack/dead receipt; worker tokens are restricted runtime metadata.

Owner: OnIt platform operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| event_id | uuid | yes |  |
| status | text | yes | 'pending'::text |
| attempts | integer | yes | 0 |
| available_at | timestamp with time zone | yes | now() |
| lease_until | timestamp with time zone | no |  |
| lease_token | uuid | no |  |
| processed_at | timestamp with time zone | no |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |
| created_by | uuid | yes |  |
| last_failure_code | text | no |  |
| last_receipt_token | uuid | no |  |
| last_receipt_action | text | no |  |
| last_receipt_hash | text | no |  |

Constraints (including FKs, unique and CHECK):

- operational_event_deliveries_attempts_check: CHECK ((attempts >= 0))
- operational_event_deliveries_check: CHECK (((status = 'leased'::text) = ((lease_until IS NOT NULL) AND (lease_token IS NOT NULL))))
- operational_event_deliveries_check1: CHECK (((status = 'processed'::text) = (processed_at IS NOT NULL)))
- operational_event_deliveries_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- operational_event_deliveries_event_id_fkey: FOREIGN KEY (event_id) REFERENCES private.operational_events(id) ON DELETE RESTRICT
- operational_event_deliveries_event_id_key: UNIQUE (event_id)
- operational_event_deliveries_last_failure_code_check: CHECK ((last_failure_code ~ '^[A-Z0-9_]{1,80}$'::text))
- operational_event_deliveries_last_receipt_action_check: CHECK ((last_receipt_action = ANY (ARRAY['ack'::text, 'retry'::text])))
- operational_event_deliveries_pkey: PRIMARY KEY (id)
- operational_event_deliveries_status_check: CHECK ((status = ANY (ARRAY['pending'::text, 'leased'::text, 'processed'::text, 'dead'::text])))

Indexes:

- CREATE INDEX operational_event_claim ON private.operational_event_deliveries USING btree (status, available_at, lease_until)
- CREATE INDEX operational_event_deliveries_1743c77633_fk ON private.operational_event_deliveries USING btree (created_by)
- CREATE UNIQUE INDEX operational_event_deliveries_event_id_key ON private.operational_event_deliveries USING btree (event_id)
- CREATE UNIQUE INDEX operational_event_deliveries_pkey ON private.operational_event_deliveries USING btree (id)

## private.provider_personnel_capacity

Versioned independently approved human capacity shared across contracting businesses; does not grant provider identity.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| profile_id | uuid | yes |  |
| version | integer | yes |  |
| units | numeric(12,4) | yes |  |
| valid_from | timestamp with time zone | yes |  |
| valid_until | timestamp with time zone | no |  |
| status | text | yes | 'draft'::text |
| approved_by | uuid | no |  |
| approved_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- provider_personnel_capacity_approved_by_fkey: FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_capacity_check: CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
- provider_personnel_capacity_check1: CHECK (((status = 'draft'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))))
- provider_personnel_capacity_check2: CHECK (((approved_by IS NULL) OR ((approved_by <> created_by) AND (approved_by <> profile_id))))
- provider_personnel_capacity_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_capacity_pkey: PRIMARY KEY (id)
- provider_personnel_capacity_profile_id_fkey: FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_capacity_profile_id_version_key: UNIQUE (profile_id, version)
- provider_personnel_capacity_status_check: CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'retired'::text])))
- provider_personnel_capacity_units_check: CHECK ((units > (0)::numeric))
- provider_personnel_capacity_version_check: CHECK ((version > 0))

Indexes:

- CREATE INDEX personnel_capacity_approver ON private.provider_personnel_capacity USING btree (approved_by)
- CREATE INDEX personnel_capacity_effective ON private.provider_personnel_capacity USING btree (profile_id, valid_from, valid_until) WHERE (status = 'approved'::text)
- CREATE INDEX provider_personnel_capacity_creator_idx ON private.provider_personnel_capacity USING btree (created_by)
- CREATE UNIQUE INDEX provider_personnel_capacity_pkey ON private.provider_personnel_capacity USING btree (id)
- CREATE UNIQUE INDEX provider_personnel_capacity_profile_id_version_key ON private.provider_personnel_capacity USING btree (profile_id, version)

## private.provider_personnel_availability

Personal working/leave/blackout windows shared across engagements.

Owner: OnIt provider network operations. Lifecycle: retained; command-controlled lifecycle and audit; no ordinary client writes. RLS: enabled, default deny; privileged server maintenance remains trusted.

| Column | Type | Required | Default |
| --- | --- | --- | --- |
| id | uuid | yes | gen_random_uuid() |
| profile_id | uuid | yes |  |
| starts_at | timestamp with time zone | yes |  |
| ends_at | timestamp with time zone | yes |  |
| kind | text | yes |  |
| revoked_at | timestamp with time zone | no |  |
| created_by | uuid | yes |  |
| created_at | timestamp with time zone | yes | now() |
| updated_at | timestamp with time zone | yes | now() |

Constraints (including FKs, unique and CHECK):

- provider_personnel_availability_check: CHECK (((ends_at > starts_at) AND ((ends_at - starts_at) <= '31 days'::interval)))
- provider_personnel_availability_created_by_fkey: FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT
- provider_personnel_availability_kind_check: CHECK ((kind = ANY (ARRAY['working'::text, 'leave'::text, 'blackout'::text, 'temporary_unavailable'::text])))
- provider_personnel_availability_pkey: PRIMARY KEY (id)
- provider_personnel_availability_profile_id_fkey: FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT

Indexes:

- CREATE INDEX personnel_calendar_overlap ON private.provider_personnel_availability USING btree (profile_id, starts_at, ends_at) WHERE (revoked_at IS NULL)
- CREATE INDEX provider_personnel_availability_creator_idx ON private.provider_personnel_availability USING btree (created_by)
- CREATE UNIQUE INDEX provider_personnel_availability_pkey ON private.provider_personnel_availability USING btree (id)

