begin;
alter table private.audit_logs add column correlation_id uuid not null default gen_random_uuid();
alter table private.audit_logs add column changed_columns text[] not null default array[]::text[];
create or replace function app_private.audit_access_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_columns text[]=array[]::text[];
begin
  if tg_op='UPDATE' then
    select coalesce(array_agg(j.key order by j.key),array[]::text[]) into v_columns
      from jsonb_each(to_jsonb(new)) j where j.value is distinct from to_jsonb(old)->j.key;
  end if;
  insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id,changed_columns)
  values(auth.uid(),tg_op,tg_table_schema,tg_table_name,case when tg_op='DELETE' then old.id else new.id end,v_columns);
  if tg_op='DELETE' then return old; end if; return new;
end $$;
-- Context is column names, never row values, tokens, raw Auth metadata or secrets.
alter table private.document_objects add column visibility text generated always as
 (case classification when 'public' then 'public' when 'customer' then 'account' when 'identity' then 'owner' else 'restricted' end) stored;
create index audit_correlation_idx on private.audit_logs(correlation_id);

-- Harden condition publication against dependencies that cannot be client-resolved.
create function app_private.guard_booking_publication() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status='published' and old.status='draft' then
    if exists(select 1 from public.service_booking_field_dependencies d
      join public.service_booking_fields source on source.id=d.depends_on_field_id
      join public.service_booking_fields target on target.id=d.field_id
      where d.schema_id=new.id and source.visibility='hidden' and target.visibility<>'hidden')
      or exists(select 1 from public.service_booking_fields f where f.schema_id=new.id and f.visibility='hidden' and f.required) then
      raise exception 'public form cannot depend on hidden required inputs' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger onit_publication_rules before update on public.service_booking_schemas
for each row execute function app_private.guard_booking_publication();

create function app_private.guard_booking_field_type() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.field_type<>old.field_type and (exists(select 1 from public.service_booking_field_dependencies d
    where d.field_id=old.id or d.depends_on_field_id=old.id)
    or exists(select 1 from public.service_booking_field_validation_rules r where r.field_id=old.id)
    or exists(select 1 from public.service_booking_field_options o where o.field_id=old.id)) then
    raise exception 'remove draft field rules/options before changing its type' using errcode='23514';
  end if;
  return new;
end $$;
create trigger onit_field_type before update on public.service_booking_fields
for each row execute function app_private.guard_booking_field_type();

-- Same-version options must belong to a selectable question, not a text/number.
create function app_private.validate_booking_option() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists(select 1 from public.service_booking_fields f where f.id=new.field_id
    and f.field_type in ('single_choice','multiple_choice')) then
    raise exception 'options require a selectable field' using errcode='23514';
  end if;
  return new;
end $$;
create trigger onit_option_type before insert or update on public.service_booking_field_options
for each row execute function app_private.validate_booking_option();
create function app_private.guard_referenced_choice() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (tg_op='DELETE' or new.code<>old.code or new.field_id<>old.field_id) and exists(
    select 1 from public.service_booking_field_dependencies d where d.depends_on_field_id=old.field_id
      and d.operator<>'is_present' and d.comparison_value#>>'{}'=old.code) then
    raise exception 'choice is referenced by a condition' using errcode='23514';
  end if;
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger onit_choice_reference before update or delete on public.service_booking_field_options
for each row execute function app_private.guard_referenced_choice();
create function app_private.guard_booking_option_schema() returns trigger
language plpgsql set search_path = '' as $$
declare v_old uuid; v_new uuid; v_status text;
begin
  if tg_op<>'INSERT' then v_old=old.field_id; end if;
  if tg_op<>'DELETE' then v_new=new.field_id; end if;
  perform 1 from public.service_versions where id in(select f.service_version_id
    from public.service_booking_fields f where f.id in(v_old,v_new)) order by id for update;
  for v_status in select s.status from public.service_booking_schemas s
    where s.id in (select f.schema_id from public.service_booking_fields f where f.id in(v_old,v_new))
    order by s.id for update loop
    if v_status<>'draft' then raise exception 'published form options immutable' using errcode='55000'; end if;
  end loop;
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger onit_option_schema before insert or update or delete on public.service_booking_field_options
for each row execute function app_private.guard_booking_option_schema();

do $$ declare fk record; cols text; begin
  for fk in select con.conrelid,con.conkey,con.conname,n.nspname,c.relname
    from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
    where con.contype='f' and n.nspname in ('public','private')
      and c.relname in ('service_booking_forms','service_booking_schemas','service_booking_field_groups',
        'service_booking_fields','service_booking_field_dependencies','service_booking_field_validation_rules',
        'corporate_account_branches','corporate_account_user_branches','corporate_billing_profiles','corporate_credit_terms')
      and not exists(select 1 from pg_index i where i.indrelid=c.oid and i.indisvalid and i.indpred is null
        and array(select k from unnest(i.indkey::smallint[]) with ordinality x(k,pos)
          where pos<=cardinality(con.conkey) order by pos)=con.conkey)
  loop
    select string_agg(quote_ident(a.attname),',' order by u.position) into cols
      from unnest(fk.conkey) with ordinality u(attnum,position)
      join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=u.attnum;
    execute format('create index %I on %I.%I(%s)','onit_fk_'||substr(md5(fk.nspname||'.'||fk.relname||'.'||fk.conname),1,24),fk.nspname,fk.relname,cols);
  end loop;
end $$;
commit;
