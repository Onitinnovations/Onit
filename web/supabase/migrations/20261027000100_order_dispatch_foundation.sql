begin;
insert into private.permissions(code,description) values
 ('orders.read','Read scoped service orders'),('orders.manage','Manage scoped service orders'),
 ('orders.release','Independently release scoped orders'),('orders.payment.verify','Independently verify external payment evidence'),
 ('orders.credit.approve','Independently authorise order-specific corporate terms'),('orders.exception.approve','Independently authorise commercial exceptions'),
 ('dispatch.manage','Manage scoped dispatch and resource allocation'),('dispatch.override.approve','Independently approve dispatch preferences override'),
 ('orders.policy.manage','Prepare global order and dispatch policies'),('orders.policy.approve','Independently approve global order and dispatch policies') on conflict(code) do nothing;
create table private.order_policies (
 id uuid primary key default gen_random_uuid(),service_version_id uuid not null references public.service_versions(id) on delete restrict,
 version integer not null check(version>0),valid_from timestamptz not null,valid_until timestamptz,
 payment_gate text not null check(payment_gate in ('payment_required','payment_or_credit','no_upfront_payment')),
 offer_seconds integer not null check(offer_seconds between 30 and 86400),
 performance_weight numeric(8,4) not null check(performance_weight between 0 and 1000),workload_weight numeric(8,4) not null check(workload_weight between 0 and 1000),
 status text not null default 'draft' check(status in ('draft','approved','retired')),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 unique(service_version_id,version),check(valid_until is null or valid_until>valid_from),
 check(status='draft' or (approved_by is not null and approved_at is not null)),
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(approved_by is null or approved_by<>created_by)
);
create table private.service_orders (
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('ORD-'||upper(replace(gen_random_uuid()::text,'-',''))),
 request_id uuid not null,customer_account_id uuid not null,organisation_id uuid references public.organisations(id) on delete restrict,
 branch_id uuid,department_id uuid,service_version_id uuid not null references public.service_versions(id) on delete restrict,
 service_location_id uuid not null,zone_id uuid not null references public.service_zones(id) on delete restrict,
 policy_id uuid not null references private.order_policies(id) on delete restrict,
 classification text not null check(classification in ('individual','corporate')),
 status text not null default 'pending_authorization' check(status in ('pending_authorization','awaiting_dispatch','assigned','on_hold','cancelled')),
 revision integer not null default 1 check(revision>0),starts_at timestamptz not null,ends_at timestamptz not null,
 released_by uuid references public.profiles(id) on delete restrict,released_revision integer,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(request_id,customer_account_id) references public.service_requests(id,customer_account_id) on delete restrict,
 foreign key(service_location_id,customer_account_id) references public.service_locations(id,customer_account_id) on delete restrict,
 foreign key(branch_id,customer_account_id,organisation_id) references public.corporate_account_branches(id,customer_account_id,organisation_id) on delete restrict,
 foreign key(department_id,organisation_id) references private.departments(id,organisation_id) on delete restrict,
 check(ends_at>starts_at and ends_at-starts_at<=interval '31 days'),check(branch_id is null or organisation_id is not null),
 check(released_by is null or released_by<>created_by),unique(id,customer_account_id)
);
create table private.order_commercial_versions (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,
 quotation_version_id uuid not null unique references public.quotation_versions(id) on delete restrict,
 version integer not null check(version>0),snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 currency_id uuid not null references public.currencies(id) on delete restrict,total numeric(20,4) not null check(total>=0),minor_units integer not null check(minor_units between 0 and 4),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),unique(order_id,version)
);
create table private.order_authorizations (
 id uuid primary key default gen_random_uuid(),order_id uuid not null,customer_account_id uuid not null,order_revision integer not null,
 kind text not null check(kind in ('payment_evidence','corporate_credit','exception')),
 document_id uuid not null,reference text not null check(length(reference) between 1 and 160),
 currency_id uuid not null references public.currencies(id) on delete restrict,amount numeric(20,4) not null check(amount>=0),
 valid_until timestamptz not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),
 decided_by uuid references public.profiles(id) on delete restrict,decided_at timestamptz,
 reason text not null check(length(reason) between 1 and 2000),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 foreign key(document_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
 check(decided_by is null or decided_by<>created_by),check((status='pending')=(decided_by is null and decided_at is null))
);
create table private.order_changes (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,order_revision integer not null,
 kind text not null check(kind in ('reschedule','cancel','amend')),proposal jsonb not null check(jsonb_typeof(proposal)='object' and octet_length(proposal::text)<=8192),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 decided_by uuid references public.profiles(id) on delete restrict,reason text not null check(length(reason) between 1 and 2000),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(decided_by is null or decided_by<>created_by)
);
create table private.order_history (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,
 order_revision integer not null,action text not null,subject_id uuid not null,previous_state text,new_state text,order_snapshot jsonb not null,
 reason text not null check(length(reason) between 1 and 2000),permission_code text not null,
 actor_id uuid references public.profiles(id) on delete restrict,actor_type text not null default 'user' check(actor_type in ('user','system_worker')),
 correlation_id uuid not null default gen_random_uuid(),check((actor_id is null)=(actor_type='system_worker')),
 created_at timestamptz not null default clock_timestamp()
);
create table private.dispatch_candidates (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,order_revision integer not null,
 provider_id uuid not null references private.provider_profiles(id) on delete restrict,worker_id uuid not null references public.profiles(id) on delete restrict,
 units numeric(12,4) not null check(units>0),decision jsonb not null,score numeric not null,policy_id uuid not null references private.order_policies(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now()
);
create table private.dispatch_proposals (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,order_revision integer not null,
 status text not null default 'pending' check(status in ('pending','ready','confirmed','withdrawn','expired','rejected')),
 expires_at timestamptz not null,override_reason text,override_by uuid references public.profiles(id) on delete restrict,
 confirmed_by uuid references public.profiles(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(override_reason is null or length(override_reason) between 1 and 2000),check(override_by is null or override_by<>created_by)
);
create unique index dispatch_one_live on private.dispatch_proposals(order_id) where status in ('pending','ready','confirmed');
create table private.assignment_offers (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null references private.dispatch_proposals(id) on delete restrict,
 provider_id uuid not null references private.provider_profiles(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','accepted','rejected','withdrawn','expired')),
 responded_by uuid references public.profiles(id) on delete restrict,responded_at timestamptz,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(proposal_id,provider_id),unique(id,provider_id)
);
create table private.assignment_resources (
 id uuid primary key default gen_random_uuid(),offer_id uuid not null,provider_id uuid not null,
 worker_id uuid not null references public.profiles(id) on delete restrict,reservation_id uuid not null unique references private.provider_capacity_reservations(id) on delete restrict,
 candidate_id uuid not null references private.dispatch_candidates(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),
 foreign key(offer_id,provider_id) references private.assignment_offers(id,provider_id) on delete restrict,unique(offer_id,worker_id)
);
create table private.dispatch_escalations (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,
 reason text not null check(length(reason) between 1 and 2000),resolved_at timestamptz,resolved_by uuid references public.profiles(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
-- Extend the single durable outbox; keep provider events intact.
alter table private.operational_events alter column provider_id drop not null,add column order_id uuid references private.service_orders(id) on delete restrict,
 add constraint operational_event_domain check(provider_id is not null or order_id is not null);
create index order_event_lookup on private.operational_events(order_id,created_at,id);
do $$declare t text;begin
 foreach t in array array['order_policies','service_orders','order_commercial_versions','order_authorizations','order_changes','order_history','dispatch_candidates','dispatch_proposals','assignment_offers','assignment_resources','dispatch_escalations'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 execute format('grant all on private.%I to service_role',t);
 execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
 if t<>'order_history' then execute format('create index %I on private.%I(created_by)',t||'_creator',t);end if;
 end loop;
 foreach t in array array['order_policies','service_orders','order_authorizations','order_changes','dispatch_proposals','assignment_offers','dispatch_escalations'] loop
 execute format('create trigger onit_updated_at before update on private.%I for each row execute function app_private.touch_updated_at()',t);
 end loop;
 foreach t in array array['order_commercial_versions','order_history','dispatch_candidates','assignment_resources'] loop
 execute format('create trigger onit_immutable before update or delete on private.%I for each row execute function app_private.reject_mutation()',t);
 end loop;
end$$;
-- History uses actor_id, rather than created_by.
commit;
