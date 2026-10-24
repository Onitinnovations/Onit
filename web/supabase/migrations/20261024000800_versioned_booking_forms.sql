begin;
create table public.service_booking_forms (
  id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete restrict,
  code text not null, name text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique(service_id,code), unique(id,service_id)
);
create table public.service_booking_schemas (
  id uuid primary key default gen_random_uuid(), form_id uuid not null, service_id uuid not null,
  service_version_id uuid not null, version integer not null check(version>0),
  status text not null default 'draft' check(status in ('draft','published','retired')),
  effective_from timestamptz, effective_until timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(form_id,service_id) references public.service_booking_forms(id,service_id) on delete restrict,
  foreign key(service_version_id,service_id) references public.service_versions(id,service_id) on delete restrict,
  check(effective_until is null or (effective_from is not null and effective_until>effective_from)),
  check(status<>'published' or effective_from is not null),
  unique(form_id,version), unique(service_version_id), unique(id,service_version_id)
);
create table public.service_booking_field_groups (
  id uuid primary key default gen_random_uuid(), schema_id uuid not null, service_version_id uuid not null,
  group_key text not null, label text not null, position integer not null check(position>=0),
  repeatable boolean not null default false, minimum_occurrences integer not null default 1,
  maximum_occurrences integer not null default 1,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(schema_id,service_version_id) references public.service_booking_schemas(id,service_version_id) on delete restrict,
  check(minimum_occurrences>=0 and maximum_occurrences between 1 and 100 and minimum_occurrences<=maximum_occurrences),
  check(repeatable or maximum_occurrences=1),
  unique(schema_id,group_key), unique(schema_id,position), unique(id,schema_id,service_version_id)
);
alter table public.service_booking_fields add column schema_id uuid;
alter table public.service_booking_fields add column group_id uuid;
alter table public.service_booking_fields add column visibility text not null default 'visible' check(visibility in ('visible','conditional','hidden'));

-- Upgrade legacy version-owned fields additively. Trigger suspension is limited
-- to this transaction/backfill; only new FK columns are populated, not content.
insert into public.service_booking_forms(service_id,code,name)
  select distinct service_id,'booking','Service booking form' from public.service_versions;
insert into public.service_booking_schemas(form_id,service_id,service_version_id,version,status,effective_from)
  select f.id,v.service_id,v.id,v.version,v.status,v.published_at from public.service_versions v
  join public.service_booking_forms f on f.service_id=v.service_id and f.code='booking';
insert into public.service_booking_field_groups(schema_id,service_version_id,group_key,label,position)
  select id,service_version_id,'details','Service details',0 from public.service_booking_schemas;
alter table public.service_booking_fields disable trigger onit_version_child_guard;
update public.service_booking_fields b set schema_id=g.schema_id,group_id=g.id
  from public.service_booking_field_groups g where g.service_version_id=b.service_version_id;
alter table public.service_booking_fields enable trigger onit_version_child_guard;
alter table public.service_booking_fields alter column schema_id set not null;
alter table public.service_booking_fields alter column group_id set not null;
alter table public.service_booking_fields add constraint booking_fields_group_fk
  foreign key(group_id,schema_id,service_version_id) references public.service_booking_field_groups(id,schema_id,service_version_id) on delete restrict;
alter table public.service_booking_fields add constraint booking_fields_schema_key unique(id,schema_id,service_version_id);

create table public.service_booking_field_dependencies (
  id uuid primary key default gen_random_uuid(), schema_id uuid not null, service_version_id uuid not null,
  field_id uuid not null, depends_on_field_id uuid not null,
  condition_group integer not null default 1 check(condition_group>0),
  operator text not null check(operator in ('equals','not_equals','greater_than','less_than','contains','is_present')),
  comparison_value jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(field_id,schema_id,service_version_id) references public.service_booking_fields(id,schema_id,service_version_id) on delete restrict,
  foreign key(depends_on_field_id,schema_id,service_version_id) references public.service_booking_fields(id,schema_id,service_version_id) on delete restrict,
  check(field_id<>depends_on_field_id),
  check((operator='is_present' and comparison_value is null) or (operator<>'is_present' and comparison_value is not null)),
  unique(field_id,depends_on_field_id,condition_group,operator)
);
-- AND within a condition_group, OR across groups. Typed literals only, no code.
create table public.service_booking_field_validation_rules (
  id uuid primary key default gen_random_uuid(), schema_id uuid not null, service_version_id uuid not null, field_id uuid not null,
  rule_type text not null check(rule_type in ('min_length','max_length','minimum','maximum','min_choices','max_choices','max_bytes')),
  rule_value numeric(20,4) not null, error_message text not null check(length(error_message) between 1 and 240),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(field_id,schema_id,service_version_id) references public.service_booking_fields(id,schema_id,service_version_id) on delete restrict,
  check(rule_type in ('minimum','maximum') or (rule_value>=0 and trunc(rule_value)=rule_value)), unique(field_id,rule_type)
);

create function app_private.prepare_booking_field() returns trigger
language plpgsql set search_path = '' as $$
declare v_form uuid; v_schema uuid; v_group uuid; v_service uuid; v_version integer;
begin
  select service_id,version into v_service,v_version from public.service_versions where id=new.service_version_id for update;
  if new.schema_id is null or new.group_id is null then
    insert into public.service_booking_forms(service_id,code,name) values(v_service,'booking','Service booking form')
      on conflict(service_id,code) do nothing;
    select id into v_form from public.service_booking_forms where service_id=v_service and code='booking';
    insert into public.service_booking_schemas(form_id,service_id,service_version_id,version)
      values(v_form,v_service,new.service_version_id,v_version) on conflict(service_version_id) do nothing;
    select id into v_schema from public.service_booking_schemas where service_version_id=new.service_version_id;
    insert into public.service_booking_field_groups(schema_id,service_version_id,group_key,label,position)
      values(v_schema,new.service_version_id,'details','Service details',0) on conflict(schema_id,group_key) do nothing;
    select id into v_group from public.service_booking_field_groups where schema_id=v_schema and group_key='details';
    new.schema_id=coalesce(new.schema_id,v_schema); new.group_id=coalesce(new.group_id,v_group);
  end if;
  return new;
end $$;
create trigger onit_a_prepare_field before insert on public.service_booking_fields
for each row execute function app_private.prepare_booking_field();

create function app_private.guard_booking_configuration() returns trigger
language plpgsql set search_path = '' as $$
declare v_old uuid; v_new uuid; v_status text;
begin
  if tg_op<>'INSERT' then v_old=old.schema_id; end if;
  if tg_op<>'DELETE' then v_new=new.schema_id; end if;
  perform 1 from public.service_versions where id in(select service_version_id from public.service_booking_schemas
    where id in(v_old,v_new)) order by id for update;
  for v_status in select status from public.service_booking_schemas where id in(v_old,v_new) order by id for update loop
    if v_status<>'draft' then raise exception 'published form content is immutable' using errcode='55000'; end if;
  end loop;
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create function app_private.validate_booking_dependency() returns trigger
language plpgsql set search_path = '' as $$
declare v_type text;
begin
  perform 1 from public.service_versions where id=new.service_version_id for update;
  perform 1 from public.service_booking_schemas where id=new.schema_id for update;
  select field_type into v_type from public.service_booking_fields where id=new.depends_on_field_id;
  if (new.operator in ('greater_than','less_than') and (v_type<>'number' or jsonb_typeof(new.comparison_value)<>'number'))
    or (new.operator='contains' and (v_type<>'multiple_choice' or jsonb_typeof(new.comparison_value)<>'string'))
    or (new.operator in ('equals','not_equals') and
      ((v_type='number' and jsonb_typeof(new.comparison_value)<>'number')
      or (v_type='boolean' and jsonb_typeof(new.comparison_value)<>'boolean')
      or (v_type in ('text','date','single_choice') and jsonb_typeof(new.comparison_value)<>'string')
      or v_type in ('document','multiple_choice'))) then
    raise exception 'condition operator/value incompatible with source field' using errcode='23514';
  end if;
  if v_type in ('single_choice','multiple_choice') and new.operator<>'is_present' and not exists(
    select 1 from public.service_booking_field_options o where o.field_id=new.depends_on_field_id
      and o.code=new.comparison_value#>>'{}') then
    raise exception 'condition must reference an existing choice code' using errcode='23514';
  end if;
  if exists(with recursive path(field_id) as (
    select new.depends_on_field_id union
    select d.depends_on_field_id from public.service_booking_field_dependencies d join path p on d.field_id=p.field_id
      where d.schema_id=new.schema_id and d.id<>new.id)
    select 1 from path where field_id=new.field_id) then
    raise exception 'cyclic booking dependency' using errcode='23514';
  end if;
  return new;
end $$;
create trigger onit_dependency_validate before insert or update on public.service_booking_field_dependencies
for each row execute function app_private.validate_booking_dependency();
create function app_private.validate_booking_rule() returns trigger
language plpgsql set search_path = '' as $$
declare v_type text; v_other numeric;
begin
  perform 1 from public.service_versions where id=new.service_version_id for update;
  perform 1 from public.service_booking_schemas where id=new.schema_id for update;
  select field_type into v_type from public.service_booking_fields where id=new.field_id;
  if not ((v_type='text' and new.rule_type in ('min_length','max_length'))
    or (v_type='number' and new.rule_type in ('minimum','maximum'))
    or (v_type='multiple_choice' and new.rule_type in ('min_choices','max_choices'))
    or (v_type='document' and new.rule_type='max_bytes')) then
    raise exception 'validation rule incompatible with field type' using errcode='23514';
  end if;
  select rule_value into v_other from public.service_booking_field_validation_rules
    where field_id=new.field_id and id<>new.id and rule_type=case new.rule_type
      when 'min_length' then 'max_length' when 'max_length' then 'min_length'
      when 'minimum' then 'maximum' when 'maximum' then 'minimum'
      when 'min_choices' then 'max_choices' when 'max_choices' then 'min_choices' end;
  if (new.rule_type in ('min_length','minimum','min_choices') and new.rule_value>v_other)
    or (new.rule_type in ('max_length','maximum','max_choices') and new.rule_value<v_other) then
    raise exception 'inconsistent validation bounds' using errcode='23514';
  end if;
  return new;
end $$;
create trigger onit_rule_validate before insert or update on public.service_booking_field_validation_rules
for each row execute function app_private.validate_booking_rule();

create function app_private.guard_booking_schema() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op='DELETE' then raise exception 'retain form versions' using errcode='55000'; end if;
  if tg_op='INSERT' then
    if new.status<>'draft' then raise exception 'create draft form first' using errcode='23514'; end if;
    return new;
  end if;
  if old.status='retired' or (old.status='published' and (new.status<>'retired'
    or (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at'))) then
    raise exception 'published form version immutable' using errcode='55000';
  end if;
  if new.status='published' and old.status='draft' and exists(select 1 from public.service_booking_fields f
    where f.schema_id=new.id and f.visibility='conditional' and not exists(
      select 1 from public.service_booking_field_dependencies d where d.field_id=f.id)) then
    raise exception 'conditional field requires a dependency' using errcode='23514';
  end if;
  return new;
end $$;
create trigger onit_schema_guard before insert or update or delete on public.service_booking_schemas
for each row execute function app_private.guard_booking_schema();

create function app_private.is_booking_schema_published(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.service_booking_schemas b
    join public.service_booking_forms f on f.id=b.form_id and f.archived_at is null
    where b.id=p_id and b.status='published' and b.effective_from<=now()
    and (b.effective_until is null or b.effective_until>now()) and app_private.is_version_published(b.service_version_id));
$$;
create function app_private.is_booking_field_visible(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.service_booking_fields f where f.id=p_id and f.visibility<>'hidden'
    and app_private.is_booking_schema_published(f.schema_id));
$$;
grant execute on function app_private.is_booking_schema_published(uuid),app_private.is_booking_field_visible(uuid) to anon,authenticated;
do $$ declare t text; begin
  foreach t in array array['service_booking_forms','service_booking_schemas','service_booking_field_groups',
    'service_booking_field_dependencies','service_booking_field_validation_rules'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to anon,authenticated',t);
    execute format('grant all on public.%I to service_role',t);
    execute format('create trigger onit_updated_at before update on public.%I for each row execute function app_private.touch_updated_at()',t);
    execute format('create trigger onit_no_truncate before truncate on public.%I for each statement execute function app_private.reject_mutation()',t);
    if t<>'service_booking_forms' then
      execute format('create trigger onit_parent_version before insert or update or delete on public.%I for each row execute function app_private.guard_version_child()',t);
    end if;
  end loop;
  foreach t in array array['service_booking_fields','service_booking_field_groups','service_booking_field_dependencies','service_booking_field_validation_rules'] loop
    execute format('create trigger onit_form_content before insert or update or delete on public.%I for each row execute function app_private.guard_booking_configuration()',t);
  end loop;
end $$;
create policy forms_published on public.service_booking_forms for select to anon,authenticated using(archived_at is null and exists(
  select 1 from public.service_booking_schemas s where s.form_id=service_booking_forms.id and app_private.is_booking_schema_published(s.id)));
create policy schemas_published on public.service_booking_schemas for select to anon,authenticated using(app_private.is_booking_schema_published(id));
create policy groups_published on public.service_booking_field_groups for select to anon,authenticated using(app_private.is_booking_schema_published(schema_id));
create policy dependencies_published on public.service_booking_field_dependencies for select to anon,authenticated
using(app_private.is_booking_field_visible(field_id) and app_private.is_booking_field_visible(depends_on_field_id));
create policy rules_published on public.service_booking_field_validation_rules for select to anon,authenticated using(app_private.is_booking_field_visible(field_id));
drop policy version_published on public.service_booking_fields;
create policy fields_published on public.service_booking_fields for select to anon,authenticated using(app_private.is_booking_field_visible(id));
drop policy version_published on public.service_booking_field_options;
create policy field_options_published on public.service_booking_field_options for select to anon,authenticated using(app_private.is_booking_field_visible(field_id));
commit;
