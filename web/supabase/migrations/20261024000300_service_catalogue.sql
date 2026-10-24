begin;
create table public.service_areas (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null unique,
  status text not null default 'draft' check(status in ('draft','published','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table public.service_families (
  id uuid primary key default gen_random_uuid(), service_area_id uuid not null references public.service_areas(id) on delete restrict,
  code text not null, name text not null,
  status text not null default 'draft' check(status in ('draft','published','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_area_id,code)
);
create table public.services (
  id uuid primary key default gen_random_uuid(), service_family_id uuid not null references public.service_families(id) on delete restrict,
  code text not null unique, name text not null, slug text not null unique check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status text not null default 'draft' check(status in ('draft','published','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);
create table public.service_versions (
  id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete restrict,
  version integer not null check(version>0), description text not null,
  status text not null default 'draft' check(status in ('draft','published','retired')),
  assessment_required boolean not null default false,
  payment_gate text not null default 'completion' check(payment_gate in ('none','deposit','milestone','completion','credit_terms')),
  published_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(service_id,version), unique(id,service_id), check(status<>'published' or published_at is not null)
);
create table public.service_variants (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  code text not null, name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,code), unique(id,service_version_id)
);
create table public.service_options (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  code text not null, name text not null, required boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,code), unique(id,service_version_id)
);
create table public.service_option_values (
  id uuid primary key default gen_random_uuid(), option_id uuid not null, service_version_id uuid not null,
  code text not null, label text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(option_id,service_version_id) references public.service_options(id,service_version_id) on delete restrict,
  unique(option_id,code), unique(id,service_version_id)
);
create table public.service_requirements (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  code text not null, description text not null, required boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,code)
);
create table public.service_booking_fields (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  field_key text not null, label text not null,
  field_type text not null check(field_type in ('text','number','boolean','date','single_choice','multiple_choice','document')),
  required boolean not null default false, position integer not null check(position>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(service_version_id,field_key), unique(service_version_id,position), unique(id,service_version_id)
);
create table public.service_booking_field_options (
  id uuid primary key default gen_random_uuid(), field_id uuid not null, service_version_id uuid not null,
  code text not null, label text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(field_id,service_version_id) references public.service_booking_fields(id,service_version_id) on delete restrict,
  unique(field_id,code)
);
create table public.service_checklists (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  code text not null, checklist_type text not null check(checklist_type in ('assessment','execution','quality')),
  name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(service_version_id,code), unique(id,service_version_id)
);
create table public.service_checklist_items (
  id uuid primary key default gen_random_uuid(), checklist_id uuid not null, service_version_id uuid not null,
  item_key text not null, label text not null, required boolean not null default true,
  position integer not null check(position>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(checklist_id,service_version_id) references public.service_checklists(id,service_version_id) on delete restrict,
  unique(checklist_id,item_key), unique(checklist_id,position)
);
create table private.service_rate_cards (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  zone_id uuid references public.service_zones(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  code text not null, version integer not null check(version>0),
  status text not null default 'draft' check(status in ('draft','approved','retired')),
  valid_from timestamptz not null, valid_until timestamptz, approved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(valid_until is null or valid_until>valid_from), check(status<>'approved' or approved_at is not null),
  unique(code,version), unique(id,service_version_id)
);
create table private.service_pricing_rules (
  id uuid primary key default gen_random_uuid(), rate_card_id uuid not null, service_version_id uuid not null,
  code text not null, rule_type text not null check(rule_type in ('fixed','per_unit','assessment_quote')),
  unit_amount numeric(20,4) check(unit_amount>=0), currency_id uuid not null references public.currencies(id) on delete restrict,
  unit_name text, minimum_quantity numeric(16,4) check(minimum_quantity>0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(rate_card_id,service_version_id) references private.service_rate_cards(id,service_version_id) on delete restrict,
  check((rule_type='assessment_quote' and unit_amount is null) or (rule_type<>'assessment_quote' and unit_amount is not null)),
  unique(rate_card_id,code)
);
create table private.service_availability (
  id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete restrict,
  zone_id uuid not null references public.service_zones(id) on delete restrict,
  available_from timestamptz not null, available_until timestamptz, enabled boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(available_until is null or available_until>available_from), unique(service_id,zone_id,available_from)
);
create table public.city_service_availability (
  id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict, enabled boolean not null default false,
  effective_from timestamptz not null, effective_until timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(effective_until is null or effective_until>effective_from), unique(service_id,city_id,effective_from)
);
create table public.service_exclusions (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  code text not null, description text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,code)
);
create table public.service_faqs (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  question text not null, answer text not null, position integer not null check(position>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,position)
);
create table private.zone_transport_rates (
  id uuid primary key default gen_random_uuid(), zone_id uuid not null references public.service_zones(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  amount numeric(20,4) not null check(amount>=0), valid_from timestamptz not null, valid_until timestamptz,
  status text not null default 'draft' check(status in ('draft','approved','retired')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(valid_until is null or valid_until>valid_from), unique(zone_id,currency_id,valid_from)
);

create function app_private.is_service_published(p_service_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.services s
    join public.service_families f on f.id=s.service_family_id and f.status='published'
    join public.service_areas a on a.id=f.service_area_id and a.status='published'
    where s.id=p_service_id and s.status='published');
$$;
create function app_private.is_version_published(p_version_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.service_versions v where v.id=p_version_id
    and v.status='published' and v.published_at<=now() and app_private.is_service_published(v.service_id));
$$;
grant execute on function app_private.is_service_published(uuid),app_private.is_version_published(uuid) to anon,authenticated;

-- Published catalogue content is immutable, including child rows. Create a new
-- service version for content changes. Retirement may only change the status.
create function app_private.guard_service_version() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op='INSERT' then
    if new.status<>'draft' then raise exception 'create a draft before publishing' using errcode='23514'; end if;
    return new;
  end if;
  if tg_op='DELETE' then raise exception 'archive service versions instead' using errcode='55000'; end if;
  if old.status='retired' or (old.status='published' and
    (new.status<>'retired' or (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at'))) then
    raise exception 'published service version is immutable' using errcode='55000';
  end if;
  return new;
end $$;
create trigger onit_version_guard before insert or update or delete on public.service_versions
for each row execute function app_private.guard_service_version();
create function app_private.guard_version_child() returns trigger
language plpgsql set search_path = '' as $$
declare old_version uuid; new_version uuid; v_status text;
begin
  if tg_op<>'INSERT' then old_version=old.service_version_id; end if;
  if tg_op<>'DELETE' then new_version=new.service_version_id; end if;
  -- Lock parent before checking, serializing child edits against publication.
  for v_status in select status from public.service_versions
    where id in (old_version,new_version) order by id for update loop
    if v_status<>'draft' then raise exception 'versioned content is immutable' using errcode='55000'; end if;
  end loop;
  if tg_op='DELETE' then return old; end if; return new;
end $$;

do $$ declare t record; begin
  for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','private') and c.relname in (
    'service_areas','service_families','services','service_versions','service_variants','service_options','service_option_values',
    'service_requirements','service_booking_fields','service_booking_field_options','service_checklists','service_checklist_items',
    'service_rate_cards','service_pricing_rules','service_availability','city_service_availability','service_exclusions','service_faqs','zone_transport_rates') loop
    execute format('alter table %I.%I enable row level security',t.nspname,t.relname);
    execute format('revoke all on %I.%I from public, anon, authenticated',t.nspname,t.relname);
    execute format('grant all on %I.%I to service_role',t.nspname,t.relname);
    execute format('create trigger onit_updated_at before update on %I.%I for each row execute function app_private.touch_updated_at()',t.nspname,t.relname);
    if t.relname in ('service_variants','service_options','service_option_values','service_requirements','service_booking_fields',
      'service_booking_field_options','service_checklists','service_checklist_items','service_exclusions','service_faqs') then
      execute format('create trigger onit_version_child_guard before insert or update or delete on %I.%I for each row execute function app_private.guard_version_child()',t.nspname,t.relname);
    end if;
  end loop;
end $$;
grant select on public.service_areas,public.service_families,public.services,public.service_versions,public.service_variants,
  public.service_options,public.service_option_values,public.service_requirements,public.service_booking_fields,
  public.service_booking_field_options,public.service_exclusions,public.service_faqs,public.city_service_availability to anon,authenticated;
create policy areas_published on public.service_areas for select to anon,authenticated using(status='published');
create policy families_published on public.service_families for select to anon,authenticated using(status='published' and exists(
  select 1 from public.service_areas a where a.id=service_area_id and a.status='published'));
create policy services_published on public.services for select to anon,authenticated using(app_private.is_service_published(id));
create policy versions_published on public.service_versions for select to anon,authenticated using(app_private.is_version_published(id));
do $$ declare t text; begin
  foreach t in array array['service_variants','service_options','service_option_values','service_requirements',
    'service_booking_fields','service_booking_field_options','service_exclusions','service_faqs'] loop
    execute format('create policy version_published on public.%I for select to anon,authenticated using(app_private.is_version_published(service_version_id))',t);
  end loop;
end $$;
create policy city_availability_published on public.city_service_availability for select to anon,authenticated
using(enabled and effective_from<=now() and (effective_until is null or effective_until>now()) and app_private.is_service_published(service_id));
commit;
