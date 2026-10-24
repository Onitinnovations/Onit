begin;
create table public.countries (
  id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[A-Z]{2}$'), name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table public.currencies (
  id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[A-Z]{3}$'), name text not null,
  minor_units integer not null check(minor_units between 0 and 4),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table public.states (
  id uuid primary key default gen_random_uuid(), country_id uuid not null references public.countries(id) on delete restrict,
  code text not null, name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(country_id,code), unique(id,country_id)
);
create table public.cities (
  id uuid primary key default gen_random_uuid(), state_id uuid not null references public.states(id) on delete restrict,
  code text not null, name text not null, is_operational_label boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(state_id,code), unique(id,state_id)
);
create table public.local_government_areas (
  id uuid primary key default gen_random_uuid(), state_id uuid not null references public.states(id) on delete restrict,
  code text not null, name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(state_id,code), unique(id,state_id)
);
create table public.service_zones (
  id uuid primary key default gen_random_uuid(), state_id uuid not null references public.states(id) on delete restrict,
  code text not null unique, name text not null, timezone text not null default 'Africa/Lagos',
  status text not null default 'draft' check(status in ('draft','active','inactive','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(id,state_id)
);
create table private.zone_boundaries_or_coverage (
  id uuid primary key default gen_random_uuid(), zone_id uuid not null, state_id uuid not null,
  city_id uuid, local_government_area_id uuid,
  version integer not null check(version>0), verified_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(zone_id,state_id) references public.service_zones(id,state_id) on delete restrict,
  foreign key(city_id,state_id) references public.cities(id,state_id) on delete restrict,
  foreign key(local_government_area_id,state_id) references public.local_government_areas(id,state_id) on delete restrict,
  check(num_nonnulls(city_id,local_government_area_id)=1),
  unique(zone_id,version,city_id,local_government_area_id)
);
create unique index zone_city_coverage_key on private.zone_boundaries_or_coverage(zone_id,version,city_id) where city_id is not null;
create unique index zone_lga_coverage_key on private.zone_boundaries_or_coverage(zone_id,version,local_government_area_id) where local_government_area_id is not null;

create table public.customer_profiles (
  id uuid primary key default gen_random_uuid(),
  individual_profile_id uuid unique references public.profiles(id) on delete restrict,
  organisation_id uuid unique references public.organisations(id) on delete restrict,
  status text not null default 'pending' check(status in ('pending','approved','suspended','archived')),
  currency_id uuid not null references public.currencies(id) on delete restrict, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(num_nonnulls(individual_profile_id,organisation_id)=1), unique(id,organisation_id)
);
create table public.corporate_accounts (
  id uuid primary key, organisation_id uuid not null,
  approval_status text not null default 'pending' check(approval_status in ('pending','approved','suspended','rejected')),
  account_reference text not null unique, credit_terms_approved boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(id,organisation_id) references public.customer_profiles(id,organisation_id) on delete restrict,
  unique(id,organisation_id)
);
create table private.corporate_account_users (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null, organisation_id uuid not null,
  profile_id uuid not null, department_id uuid,
  access_scope text not null default 'account' check(access_scope in ('account','department')),
  can_request boolean not null default false, can_approve boolean not null default false,
  status text not null default 'pending' check(status in ('pending','approved','revoked')),
  valid_until timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(customer_account_id,organisation_id) references public.corporate_accounts(id,organisation_id) on delete restrict,
  foreign key(organisation_id,profile_id) references private.organisation_members(organisation_id,profile_id) on delete restrict,
  foreign key(department_id,organisation_id) references private.departments(id,organisation_id) on delete restrict,
  check((access_scope='account' and department_id is null) or (access_scope='department' and department_id is not null)),
  unique(customer_account_id,profile_id)
);
create function app_private.can_access_customer(p_account_id uuid, p_write boolean default false, p_department_id uuid default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.customer_profiles c
    join public.profiles p on p.id=auth.uid() and p.status='active'
    where c.id=p_account_id and c.status='approved' and c.archived_at is null
      and (c.individual_profile_id=auth.uid() or exists(
        select 1 from private.corporate_account_users u
        join public.corporate_accounts a on a.id=u.customer_account_id and a.approval_status='approved'
        where u.customer_account_id=c.id and u.profile_id=auth.uid()
          and u.status='approved' and u.revoked_at is null and (u.valid_until is null or u.valid_until>now())
          and app_private.is_active_member(u.organisation_id)
          and (not p_write or u.can_request)
          and (u.access_scope='account' or u.department_id=p_department_id)
      )));
$$;
-- Account-level records are intentionally hidden from department-only members;
-- task/order commands must pass the exact department and enforce a composite FK.
grant execute on function app_private.can_access_customer(uuid,boolean,uuid) to authenticated;

create table public.customer_addresses (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  label text not null, address_line_1 text not null, address_line_2 text,
  country_id uuid not null references public.countries(id) on delete restrict, state_id uuid not null,
  city_id uuid, local_government_area_id uuid, latitude numeric(9,6), longitude numeric(9,6),
  is_default boolean not null default false, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(state_id,country_id) references public.states(id,country_id) on delete restrict,
  foreign key(city_id,state_id) references public.cities(id,state_id) on delete restrict,
  foreign key(local_government_area_id,state_id) references public.local_government_areas(id,state_id) on delete restrict,
  check(latitude between -90 and 90), check(longitude between -180 and 180),
  check(num_nonnulls(latitude,longitude) in (0,2)), unique(id,customer_account_id)
);
create unique index customer_addresses_default_key on public.customer_addresses(customer_account_id) where is_default and archived_at is null;
create table public.service_locations (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  source_address_id uuid, address_snapshot text not null,
  country_id uuid not null references public.countries(id) on delete restrict, state_id uuid not null, city_id uuid,
  latitude numeric(9,6), longitude numeric(9,6),
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict,
  foreign key(source_address_id,customer_account_id) references public.customer_addresses(id,customer_account_id) on delete restrict,
  foreign key(state_id,country_id) references public.states(id,country_id) on delete restrict,
  foreign key(city_id,state_id) references public.cities(id,state_id) on delete restrict,
  check(latitude between -90 and 90), check(longitude between -180 and 180),
  check(num_nonnulls(latitude,longitude) in (0,2)), unique(id,customer_account_id)
);
create table public.organisation_locations (
  id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id) on delete restrict,
  code text not null, name text not null, address_text text not null, city_id uuid references public.cities(id) on delete restrict,
  archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(organisation_id,code)
);
create table public.customer_contacts (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  name text not null, email text, phone text, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(email is not null or phone is not null), unique(id,customer_account_id)
);
create table private.leads (
  id uuid primary key default gen_random_uuid(), owner_id uuid references public.profiles(id) on delete restrict,
  name text not null, contact_email text, contact_phone text,
  status text not null default 'new' check(status in ('new','qualified','converted','lost','archived')),
  converted_account_id uuid references public.customer_profiles(id) on delete restrict,
  source text, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(status<>'converted' or converted_account_id is not null)
);
create table private.lead_activities (
  id uuid primary key default gen_random_uuid(), lead_id uuid not null references private.leads(id) on delete restrict,
  activity_type text not null check(activity_type in ('call','email','meeting','note','conversion')),
  summary text not null, occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict
);
create table private.opportunities (
  id uuid primary key default gen_random_uuid(), lead_id uuid references private.leads(id) on delete restrict,
  customer_account_id uuid references public.customer_profiles(id) on delete restrict,
  name text not null, status text not null default 'open' check(status in ('open','won','lost','archived')),
  expected_value numeric(20,4) check(expected_value>=0), currency_id uuid references public.currencies(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(num_nonnulls(lead_id,customer_account_id)>=1), check(num_nonnulls(expected_value,currency_id) in (0,2))
);
create table private.customer_segments (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.customer_segment_assignments (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  segment_id uuid not null references private.customer_segments(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(customer_account_id,segment_id)
);
create table private.customer_notes (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  body text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.customer_tags (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.customer_tag_assignments (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  tag_id uuid not null references private.customer_tags(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(customer_account_id,tag_id)
);
create table public.support_tickets (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  subject text not null, status text not null default 'open' check(status in ('open','in_progress','resolved','closed')),
  closed_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(id,customer_account_id)
);
create table public.support_messages (
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null, customer_account_id uuid not null,
  visibility text not null default 'internal' check(visibility in ('internal','customer')),
  body text not null,
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict,
  foreign key(ticket_id,customer_account_id) references public.support_tickets(id,customer_account_id) on delete restrict
);
create table public.customer_feedback (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  rating integer not null check(rating between 1 and 5), comment text,
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict
);
create table public.customer_consents (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  purpose text not null, policy_version text not null, decision text not null check(decision in ('granted','withdrawn')),
  evidence_reference text not null,
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict
);
create table public.communication_preferences (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  channel text not null check(channel in ('email','sms','phone','push')), purpose text not null, enabled boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(customer_account_id,channel,purpose)
);

do $$ declare t record; begin
  for t in select n.nspname,c.relname,
    exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='updated_at' and not a.attisdropped) mutable
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','private') and c.relname in (
      'countries','currencies','states','cities','local_government_areas','service_zones','zone_boundaries_or_coverage',
      'customer_profiles','corporate_accounts','corporate_account_users','customer_addresses','service_locations',
      'organisation_locations','customer_contacts','leads','lead_activities','opportunities','customer_segments',
      'customer_segment_assignments','customer_notes','customer_tags','customer_tag_assignments','support_tickets',
      'support_messages','customer_feedback','customer_consents','communication_preferences') loop
    execute format('alter table %I.%I enable row level security',t.nspname,t.relname);
    execute format('revoke all on %I.%I from public, anon, authenticated',t.nspname,t.relname);
    execute format('grant all on %I.%I to service_role',t.nspname,t.relname);
    if t.mutable then
      execute format('create trigger onit_updated_at before update on %I.%I for each row execute function app_private.touch_updated_at()',t.nspname,t.relname);
    else
      execute format('create trigger onit_immutable before update or delete or truncate on %I.%I for each statement execute function app_private.reject_mutation()',t.nspname,t.relname);
    end if;
  end loop;
end $$;
grant select on public.countries,public.currencies,public.states,public.cities,public.local_government_areas to anon,authenticated;
create policy countries_reference on public.countries for select to anon,authenticated using(true);
create policy currencies_reference on public.currencies for select to anon,authenticated using(true);
create policy states_reference on public.states for select to anon,authenticated using(true);
create policy cities_reference on public.cities for select to anon,authenticated using(true);
create policy lgas_reference on public.local_government_areas for select to anon,authenticated using(true);
grant select on public.service_zones to anon,authenticated;
create policy zones_published on public.service_zones for select to anon,authenticated using(status='active');
grant select on public.customer_profiles,public.corporate_accounts,public.customer_addresses,public.service_locations,
  public.customer_contacts,public.support_tickets,public.support_messages,public.customer_feedback,
  public.customer_consents,public.communication_preferences,public.organisation_locations to authenticated;
create policy customer_account_read on public.customer_profiles for select to authenticated
  using(app_private.can_access_customer(id) or app_private.has_permission('customers.read',organisation_id));
create policy corporate_account_read on public.corporate_accounts for select to authenticated
  using(app_private.can_access_customer(id) or app_private.has_permission('customers.read',organisation_id));
create policy organisation_locations_read on public.organisation_locations for select to authenticated
  using(app_private.is_active_member(organisation_id) or app_private.has_permission('customers.read',organisation_id));
do $$ declare t text; begin
  foreach t in array array['customer_addresses','service_locations','customer_contacts','support_tickets','customer_feedback','customer_consents','communication_preferences'] loop
    execute format('create policy customer_scoped_read on public.%I for select to authenticated using(app_private.can_access_customer(customer_account_id) or app_private.has_permission(''customers.read''))',t);
  end loop;
end $$;
create policy support_messages_read on public.support_messages for select to authenticated
  using((visibility='customer' and app_private.can_access_customer(customer_account_id)) or app_private.has_permission('customers.read'));

-- The browser may edit address content but cannot reassign ownership or hard-delete history.
grant update(label,address_line_1,address_line_2,city_id,local_government_area_id,latitude,longitude,is_default,archived_at)
  on public.customer_addresses to authenticated;
create policy customer_address_edit on public.customer_addresses for update to authenticated
  using(app_private.can_access_customer(customer_account_id,true))
  with check(app_private.can_access_customer(customer_account_id,true));
grant update(enabled) on public.communication_preferences to authenticated;
create policy communication_edit on public.communication_preferences for update to authenticated
  using(app_private.can_access_customer(customer_account_id,true)) with check(app_private.can_access_customer(customer_account_id,true));
commit;
