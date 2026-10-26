begin;
-- Provider parties are operational identities, never a second authentication system.
insert into private.permissions(code,description) values
 ('providers.read','Read provider operations within assigned scope'),
 ('providers.documents.read','Read exact scoped provider verification and contract files'),
 ('providers.manage','Manage provider recruitment and operational configuration'),
 ('providers.approve','Independently approve provider verification and activation'),
 ('providers.policy.manage','Prepare service eligibility configuration'),
 ('providers.policy.approve','Independently approve eligibility configuration'),
 ('providers.capacity.manage','Reserve and release provider capacity') on conflict(code) do nothing;
create table private.provider_profiles (
 id uuid primary key default gen_random_uuid(), individual_profile_id uuid unique references public.profiles(id) on delete restrict,
 organisation_id uuid unique references public.organisations(id) on delete restrict,
 provider_type text not null check(provider_type in ('service_associate','artisan','professional','field_agent','service_business','processing_partner','contractor')),
 status text not null default 'applicant' check(status in ('applicant','approved','active','suspended','offboarded')),
 revision integer not null default 1 check(revision>0), approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz, suspended_by uuid references public.profiles(id) on delete restrict,
 check(num_nonnulls(individual_profile_id,organisation_id)=1),
 check((provider_type in ('service_associate','artisan','professional','field_agent'))=(individual_profile_id is not null)),
 check(status in ('applicant','offboarded') or (approved_by is not null and approved_at is not null)), unique(id,organisation_id)
);
create table private.provider_personnel (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 organisation_id uuid not null,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 personnel_role text not null check(personnel_role in ('administrator','executing_worker','field_agent')),
 valid_from timestamptz not null, valid_until timestamptz,revoked_at timestamptz,
 check(valid_until is null or valid_until>valid_from),unique(provider_id,profile_id),
 foreign key(provider_id,organisation_id) references private.provider_profiles(id,organisation_id) on delete restrict,
 foreign key(organisation_id,profile_id) references private.organisation_members(organisation_id,profile_id) on delete restrict
);
create table private.provider_recruitment_campaigns (
 id uuid primary key default gen_random_uuid(),code text not null unique check(code ~ '^[a-z0-9_-]{1,80}$'),
 name text not null check(length(name) between 1 and 200),starts_at timestamptz not null,ends_at timestamptz,
 status text not null default 'active' check(status in ('active','closed')),check(ends_at is null or ends_at>starts_at)
);
create table private.provider_applications (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 revision integer not null check(revision>0),stage text not null default 'submitted' check(stage in ('submitted','screening','verification','training','approved','rejected','withdrawn')),
 source text not null check(source in ('online','referral','social','offline','internal')),
 campaign_id uuid references private.provider_recruitment_campaigns(id) on delete restrict,
 referrer_id uuid references public.profiles(id) on delete restrict,
 screening_passed boolean not null default false,reviewed_by uuid references public.profiles(id) on delete restrict,
 unique(provider_id,revision),check((source='referral')=(referrer_id is not null))
);
create unique index provider_open_application_key on private.provider_applications(provider_id) where stage not in ('approved','rejected','withdrawn');
create table private.provider_qualifications (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 subject_profile_id uuid references public.profiles(id) on delete restrict,
 kind text not null check(kind in ('verification','skill','credential','training')),
 code text not null check(code ~ '^[a-z0-9_-]{1,80}$'),valid_from timestamptz not null,valid_until timestamptz,
 document_id uuid references private.document_objects(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','approved','rejected','revoked')),
 decided_by uuid references public.profiles(id) on delete restrict,decided_at timestamptz,
 check(valid_until is null or valid_until>valid_from),
 check((status='pending')=(decided_by is null and decided_at is null)),unique(id,provider_id)
);
create index provider_qualification_lookup on private.provider_qualifications(provider_id,kind,code,status,valid_until);
create table private.provider_requirement_sets (
 id uuid primary key default gen_random_uuid(),service_version_id uuid not null references public.service_versions(id) on delete restrict,
 provider_type text not null check(provider_type in ('service_associate','artisan','professional','field_agent','service_business','processing_partner','contractor')),
 zone_id uuid not null references public.service_zones(id) on delete restrict,
 version integer not null check(version>0),valid_from timestamptz not null,valid_until timestamptz,
 requirements jsonb not null check(jsonb_typeof(requirements)='array' and jsonb_array_length(requirements) between 1 and 50),
 capacity_unit text not null check(capacity_unit ~ '^[a-z0-9_-]{1,40}$'),
 engagement_required boolean not null, maximum_travel_km numeric(10,2) check(maximum_travel_km>0),
 performance_metric text check(performance_metric in ('acceptance','completion','timeliness','quality','reliability')),
 minimum_performance numeric(8,6) check(minimum_performance between 0 and 1),
 performance_window_days integer check(performance_window_days between 1 and 3650),
 status text not null default 'draft' check(status in ('draft','approved','retired')),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 check((performance_metric is null)=(minimum_performance is null)),check((performance_metric is null)=(performance_window_days is null)),check(valid_until is null or valid_until>valid_from),
 check(status='draft' or (approved_by is not null and approved_at is not null)),unique(service_version_id,provider_type,zone_id,version)
);
create table private.provider_training_courses (
 id uuid primary key default gen_random_uuid(),code text not null check(code ~ '^[a-z0-9_-]{1,80}$'),version integer not null check(version>0),
 name text not null check(length(name) between 1 and 200),pass_mark numeric(5,2) not null check(pass_mark between 0 and 100),
 required_attendance numeric(5,2) not null check(required_attendance between 0 and 100),
 certificate_valid_days integer not null check(certificate_valid_days between 1 and 3650),
 status text not null default 'draft' check(status in ('draft','approved','retired')),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 unique(code,version),check(status='draft' or (approved_by is not null and approved_at is not null))
);
create table private.provider_training_sessions (
 id uuid primary key default gen_random_uuid(),course_id uuid not null references private.provider_training_courses(id) on delete restrict,
 trainer_id uuid not null references public.profiles(id) on delete restrict,
 starts_at timestamptz not null,ends_at timestamptz not null,check(ends_at>starts_at)
);
create table private.provider_training_enrolments (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 session_id uuid not null references private.provider_training_sessions(id) on delete restrict,
 subject_profile_id uuid references public.profiles(id) on delete restrict,
 attendance_percent numeric(5,2) check(attendance_percent between 0 and 100),score numeric(5,2) check(score between 0 and 100),
 status text not null default 'enrolled' check(status in ('enrolled','assessed','passed','failed')),
 qualification_id uuid unique,
 assessed_by uuid references public.profiles(id) on delete restrict,
 unique nulls not distinct(provider_id,session_id,subject_profile_id),
 check((status='enrolled')=(assessed_by is null)),check(status not in ('passed','failed') or (attendance_percent is not null and score is not null)),
 check((status='passed')=(qualification_id is not null)),
 foreign key(qualification_id,provider_id) references private.provider_qualifications(id,provider_id) on delete restrict
);
create table private.provider_coverage_areas (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 service_version_id uuid not null references public.service_versions(id) on delete restrict,
 zone_id uuid not null references public.service_zones(id) on delete restrict,
 travel_limit_km numeric(10,2) check(travel_limit_km>0),valid_from timestamptz not null,valid_until timestamptz,
 revoked_at timestamptz,check(valid_until is null or valid_until>valid_from),unique(provider_id,service_version_id,zone_id,valid_from)
);
-- Explicit confirmed windows, not inferred city-wide/24-hour availability.
create table private.provider_work_schedules (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 service_version_id uuid not null references public.service_versions(id) on delete restrict,
 zone_id uuid not null references public.service_zones(id) on delete restrict,timezone text not null,
 weekdays smallint[] not null check(cardinality(weekdays) between 1 and 7 and weekdays<@array[1,2,3,4,5,6,7]::smallint[]),
 local_start time not null,local_end time not null,valid_from date not null,valid_until date not null,revoked_at timestamptz,
 check(local_end>local_start),check(valid_until>=valid_from and valid_until-valid_from<=30),unique(id,provider_id,service_version_id)
);
create table private.provider_availability (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 service_version_id uuid not null references public.service_versions(id) on delete restrict,
 starts_at timestamptz not null,ends_at timestamptz not null,
 kind text not null check(kind in ('working','leave','blackout','temporary_unavailable')),revoked_at timestamptz,
 schedule_id uuid,
 foreign key(schedule_id,provider_id,service_version_id) references private.provider_work_schedules(id,provider_id,service_version_id) on delete restrict,
 check(ends_at>starts_at),check(ends_at-starts_at<=interval '31 days')
);
create table private.provider_capacity (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 unit text not null check(unit ~ '^[a-z0-9_-]{1,40}$'),units numeric(12,4) not null check(units>0),
 status text not null default 'active' check(status in ('active','inactive')),
 unique(provider_id,unit),unique(id,provider_id)
);
create table private.provider_capacity_reservations (
 id uuid primary key default gen_random_uuid(),pool_id uuid not null references private.provider_capacity(id) on delete restrict,
 provider_id uuid not null,starts_at timestamptz not null,ends_at timestamptz not null,
 units numeric(12,4) not null check(units>0),expires_at timestamptz not null,
 status text not null default 'reserved' check(status in ('reserved','assigned','released','expired')),
 purpose_reference text not null check(length(purpose_reference) between 1 and 120),
 foreign key(pool_id,provider_id) references private.provider_capacity(id,provider_id) on delete restrict,
 check(ends_at>starts_at)
);
create index provider_reservations_overlap on private.provider_capacity_reservations(pool_id,starts_at,ends_at) where status in ('reserved','assigned');
create table private.provider_engagements (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 service_version_id uuid not null references public.service_versions(id) on delete restrict,
 zone_id uuid not null references public.service_zones(id) on delete restrict,
 version integer not null check(version>0),contract_reference text not null check(length(contract_reference) between 1 and 160),
 currency_id uuid not null references public.currencies(id) on delete restrict,unit text not null check(unit ~ '^[a-z0-9_-]{1,40}$'),
 unit_rate numeric(20,4) not null check(unit_rate>=0),obligations text not null check(length(obligations) between 1 and 8000),
 valid_from timestamptz not null,valid_until timestamptz not null,
 document_id uuid not null references private.document_objects(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','approved','terminated')),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 check(valid_until>valid_from),check(status='draft' or (approved_by is not null and approved_at is not null)),
 unique(provider_id,service_version_id,zone_id,version)
);
create table private.provider_restrictions (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 service_version_id uuid references public.service_versions(id) on delete restrict,zone_id uuid references public.service_zones(id) on delete restrict,
 valid_from timestamptz not null,valid_until timestamptz,reason text not null check(length(reason) between 1 and 2000),
 revoked_at timestamptz,revoked_by uuid references public.profiles(id) on delete restrict,
 check(valid_until is null or valid_until>valid_from),check((revoked_at is null)=(revoked_by is null))
);
create table private.provider_performance_events (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 metric text not null check(metric in ('acceptance','completion','timeliness','quality','reliability')),
 successful integer not null check(successful>=0),observations integer not null check(observations>0 and observations>=successful),
 source_reference text not null check(length(source_reference) between 1 and 160),
 document_id uuid not null references private.document_objects(id) on delete restrict,occurred_at timestamptz not null,
 unique(provider_id,metric,source_reference)
);
create table private.provider_history (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 action text not null,subject_id uuid not null,previous_state text,new_state text,
 reason text not null check(length(reason) between 1 and 2000),correlation_id uuid not null default gen_random_uuid(),
 permission_code text not null,actor_id uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default clock_timestamp()
);
create table private.operational_events (
 id uuid primary key default gen_random_uuid(),provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 event_code text not null,subject_id uuid not null,correlation_id uuid not null,
 created_at timestamptz not null default clock_timestamp()
);
create table private.operational_event_deliveries (
 id uuid primary key default gen_random_uuid(),event_id uuid not null unique references private.operational_events(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','leased','processed','dead')),
 attempts integer not null default 0 check(attempts>=0),available_at timestamptz not null default now(),
 lease_until timestamptz,lease_token uuid,processed_at timestamptz,
 check((status='leased')=(lease_until is not null and lease_token is not null)),check((status='processed')=(processed_at is not null))
);
do $$ declare t text;begin
 foreach t in array array['provider_profiles','provider_personnel','provider_recruitment_campaigns','provider_applications','provider_qualifications','provider_requirement_sets','provider_training_courses','provider_training_sessions','provider_training_enrolments','provider_coverage_areas','provider_work_schedules','provider_availability','provider_capacity','provider_capacity_reservations','provider_engagements','provider_restrictions','provider_performance_events','operational_event_deliveries'] loop
  execute format('alter table private.%I add column created_at timestamptz not null default now(),add column updated_at timestamptz not null default now(),add column created_by uuid not null references public.profiles(id) on delete restrict',t);
  execute format('create trigger onit_updated_at before update on private.%I for each row execute function app_private.touch_updated_at()',t);
 end loop;
 foreach t in array array['provider_profiles','provider_personnel','provider_recruitment_campaigns','provider_applications','provider_qualifications','provider_requirement_sets','provider_training_courses','provider_training_sessions','provider_training_enrolments','provider_coverage_areas','provider_work_schedules','provider_availability','provider_capacity','provider_capacity_reservations','provider_engagements','provider_restrictions','provider_performance_events','provider_history','operational_events','operational_event_deliveries'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  execute format('grant all on private.%I to service_role',t);
  execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
 end loop;
 foreach t in array array['provider_history','provider_performance_events','operational_events'] loop
  execute format('create trigger onit_immutable before update or delete on private.%I for each row execute function app_private.reject_mutation()',t);
 end loop;
end $$;
alter table private.provider_profiles add constraint provider_approval_independent check(approved_by is null or approved_by<>created_by);
alter table private.provider_qualifications add constraint provider_qualification_independent check(decided_by is null or decided_by<>created_by);
alter table private.provider_requirement_sets add constraint provider_requirements_independent check(approved_by is null or approved_by<>created_by);
alter table private.provider_training_courses add constraint provider_course_independent check(approved_by is null or approved_by<>created_by);
alter table private.provider_engagements add constraint provider_engagement_independent check(approved_by is null or approved_by<>created_by);
create index provider_history_timeline on private.provider_history(provider_id,created_at desc,id);
create index provider_availability_lookup on private.provider_availability(provider_id,service_version_id,starts_at,ends_at) where revoked_at is null;
create index provider_coverage_lookup on private.provider_coverage_areas(provider_id,service_version_id,zone_id) where revoked_at is null;
create index provider_restriction_lookup on private.provider_restrictions(provider_id,valid_from,valid_until) where revoked_at is null;
create index operational_event_claim on private.operational_event_deliveries(status,available_at,lease_until);
commit;
