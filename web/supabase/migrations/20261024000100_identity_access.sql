-- Foundation only. Reconcile any existing remote schema before remote deployment.
begin;
create schema if not exists private;
create schema if not exists app_private;
revoke all on schema private, app_private from public, anon, authenticated;
grant usage on schema app_private to anon, authenticated, service_role;
grant usage on schema private to service_role;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema private revoke all on tables from public, anon, authenticated;
-- PostgreSQL's built-in PUBLIC execute default is global; a schema-local REVOKE
-- cannot subtract that global grant. Revoke globally for this migration owner.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;
alter default privileges in schema app_private revoke execute on functions from public;

create function app_private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = clock_timestamp(); return new; end $$;

create function app_private.reject_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'append-only record: %', tg_table_name using errcode = '55000'; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null default '' check (length(display_name) <= 120),
  status text not null default 'active' check (status in ('active','suspended','archived')),
  archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create function app_private.provision_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'display_name',''),120))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger onit_auth_profile after insert on auth.users
for each row execute function app_private.provision_profile();
insert into public.profiles(id, display_name)
select id, left(coalesce(raw_user_meta_data ->> 'display_name',''),120) from auth.users
on conflict (id) do nothing;

create table public.organisations (
  id uuid primary key default gen_random_uuid(), name text not null check (length(name) between 1 and 240),
  organisation_type text not null check (organisation_type in ('customer','provider','supplier','onit','mixed')),
  status text not null default 'pending' check (status in ('pending','active','suspended','archived')),
  registration_reference text, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.organisation_members (
  id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'invited' check (status in ('invited','active','suspended','revoked')),
  valid_until timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(organisation_id,profile_id)
);
create index organisation_members_profile_idx on private.organisation_members(profile_id,status);
create table private.departments (
  id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id) on delete restrict,
  code text not null, name text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(organisation_id,code), unique(id,organisation_id)
);
create table private.teams (
  id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id) on delete restrict,
  department_id uuid, code text not null, name text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(department_id,organisation_id) references private.departments(id,organisation_id) on delete restrict,
  unique(organisation_id,code), unique(id,organisation_id)
);
create table private.team_members (
  id uuid primary key default gen_random_uuid(), team_id uuid not null, organisation_id uuid not null,
  profile_id uuid not null, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(team_id,organisation_id) references private.teams(id,organisation_id) on delete restrict,
  foreign key(organisation_id,profile_id) references private.organisation_members(organisation_id,profile_id) on delete restrict,
  unique(team_id,profile_id)
);
-- Early minimal HR identity anchor; later HR migrations extend this same table.
create table private.employee_profiles (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null unique references public.profiles(id) on delete restrict,
  organisation_id uuid not null references public.organisations(id) on delete restrict,
  employee_number text not null unique,
  status text not null default 'pending' check(status in ('pending','active','suspended','exited')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.roles (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.permissions (
  id uuid primary key default gen_random_uuid(), code text not null unique, description text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.role_permissions (
  id uuid primary key default gen_random_uuid(), role_id uuid not null references private.roles(id) on delete restrict,
  permission_id uuid not null references private.permissions(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(role_id,permission_id)
);
create table private.user_role_assignments (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete restrict,
  role_id uuid not null references private.roles(id) on delete restrict,
  scope text not null check(scope in ('global','organisation','team','self')),
  organisation_id uuid references public.organisations(id) on delete restrict, team_id uuid,
  valid_until timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(team_id,organisation_id) references private.teams(id,organisation_id) on delete restrict,
  check ((scope in ('global','self') and organisation_id is null and team_id is null)
    or (scope = 'organisation' and organisation_id is not null and team_id is null)
    or (scope = 'team' and organisation_id is not null and team_id is not null))
);
create unique index user_role_assignments_active_key on private.user_role_assignments
 (profile_id,role_id,scope,coalesce(organisation_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(team_id,'00000000-0000-0000-0000-000000000000'::uuid)) where revoked_at is null;

create function app_private.is_active_member(p_organisation_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.organisation_members m
    join public.organisations o on o.id=m.organisation_id
    join public.profiles p on p.id=m.profile_id
    where m.organisation_id=p_organisation_id and m.profile_id=auth.uid()
    and m.status='active' and m.revoked_at is null and (m.valid_until is null or m.valid_until>now())
    and o.status='active' and p.status='active');
$$;
create function app_private.has_permission(p_code text, p_organisation_id uuid default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.user_role_assignments a
    join private.roles r on r.id=a.role_id and r.archived_at is null
    join private.role_permissions rp on rp.role_id=r.id
    join private.permissions pm on pm.id=rp.permission_id and pm.code=p_code
    join private.employee_profiles e on e.profile_id=a.profile_id and e.status='active'
    join public.organisations employer on employer.id=e.organisation_id
      and employer.status='active' and employer.organisation_type='onit'
    join public.profiles p on p.id=a.profile_id and p.status='active'
    where a.profile_id=auth.uid() and a.revoked_at is null and (a.valid_until is null or a.valid_until>now())
      and (a.scope='global' or (a.scope='organisation' and a.organisation_id=p_organisation_id
        and app_private.is_active_member(a.organisation_id))));
$$;
-- Team and self roles never silently widen into global permissions; future commands
-- must explicitly authorize their team/subject and current membership.
grant execute on function app_private.is_active_member(uuid), app_private.has_permission(text,uuid) to authenticated;

create table public.user_preferences (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null unique references public.profiles(id) on delete restrict,
  timezone text not null default 'Africa/Lagos', locale text not null default 'en-NG',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table private.user_devices (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete restrict,
  installation_id uuid not null, platform text not null check(platform in ('web','ios','android')),
  push_token_secret_reference text, last_seen_at timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(profile_id,installation_id)
);
create table private.user_sessions_metadata (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete restrict,
  auth_session_id uuid not null unique, device_id uuid references private.user_devices(id) on delete restrict,
  last_seen_at timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table public.notification_preferences (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete restrict,
  channel text not null check(channel in ('email','sms','push','in_app')), event_code text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(profile_id,channel,event_code)
);
create table private.audit_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id) on delete restrict,
  action text not null, subject_schema text not null, subject_table text not null, subject_id uuid,
  organisation_id uuid references public.organisations(id) on delete restrict,
  details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
  created_at timestamptz not null default now()
);
create index audit_logs_subject_idx on private.audit_logs(subject_schema,subject_table,subject_id,created_at desc);
create index audit_logs_actor_idx on private.audit_logs(actor_id,created_at desc);
create table public.activity_events (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id) on delete restrict,
  event_code text not null, summary text not null check(length(summary)<=500),
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict
);

create function app_private.audit_access_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id)
  values(auth.uid(),tg_op,tg_table_schema,tg_table_name,case when tg_op='DELETE' then old.id else new.id end);
  if tg_op='DELETE' then return old; end if; return new;
end $$;

-- The migration role owns helpers/tables so helper reads do not recurse through RLS.
-- It is never granted to application users. FORCE RLS is intentionally not used.
do $$ declare t record; begin
  for t in select schemaname,tablename from pg_tables where schemaname in ('public','private')
    and tablename in ('profiles','organisations','organisation_members','departments','teams','team_members',
    'employee_profiles','roles','permissions','role_permissions','user_role_assignments','user_preferences',
    'user_devices','user_sessions_metadata','notification_preferences','audit_logs','activity_events') loop
    execute format('alter table %I.%I enable row level security',t.schemaname,t.tablename);
    execute format('revoke all on %I.%I from public, anon, authenticated',t.schemaname,t.tablename);
    execute format('grant all on %I.%I to service_role',t.schemaname,t.tablename);
    if t.tablename not in ('audit_logs','activity_events') then
      execute format('create trigger onit_updated_at before update on %I.%I for each row execute function app_private.touch_updated_at()',t.schemaname,t.tablename);
    end if;
    if t.tablename in ('organisation_members','user_role_assignments','role_permissions','employee_profiles','profiles','organisations') then
      execute format('create trigger onit_audit after insert or update or delete on %I.%I for each row execute function app_private.audit_access_change()',t.schemaname,t.tablename);
    end if;
  end loop;
end $$;
create trigger onit_audit_immutable before update or delete or truncate on private.audit_logs
for each statement execute function app_private.reject_mutation();
create trigger onit_activity_immutable before update or delete or truncate on public.activity_events
for each statement execute function app_private.reject_mutation();

grant select on public.profiles, public.organisations, public.user_preferences, public.notification_preferences, public.activity_events to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant update(timezone,locale) on public.user_preferences to authenticated;
grant update(enabled) on public.notification_preferences to authenticated;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or app_private.has_permission('identity.read'));
create policy profile_edit on public.profiles for update to authenticated using(id=auth.uid() and status='active') with check(id=auth.uid() and status='active');
create policy organisation_read on public.organisations for select to authenticated using(app_private.is_active_member(id) or app_private.has_permission('identity.read',id));
create policy preferences_read on public.user_preferences for select to authenticated using(profile_id=auth.uid());
create policy preferences_edit on public.user_preferences for update to authenticated using(profile_id=auth.uid()) with check(profile_id=auth.uid());
create policy notification_preferences_read on public.notification_preferences for select to authenticated using(profile_id=auth.uid());
create policy notification_preferences_edit on public.notification_preferences for update to authenticated using(profile_id=auth.uid()) with check(profile_id=auth.uid());
create policy activity_read on public.activity_events for select to authenticated using(profile_id=auth.uid());
commit;
