begin;
-- Privileged implementations are outside exposed schemas. Public RPC wrappers
-- use invoker rights and explicit grants; implementations always authorize uid.
create function app_private.ensure_individual_customer() returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid=auth.uid(); v_account uuid; v_currency uuid;
begin
  if v_user is null then raise exception 'authentication required' using errcode='42501'; end if;
  perform 1 from public.profiles where id=v_user and status='active' for update;
  if not found then raise exception 'active profile required' using errcode='42501'; end if;
  select id into v_account from public.customer_profiles where individual_profile_id=v_user;
  if v_account is not null then return v_account; end if;
  select id into strict v_currency from public.currencies where code='NGN';
  insert into public.customer_profiles(individual_profile_id,status,currency_id,created_by)
    values(v_user,'approved',v_currency,v_user) returning id into v_account;
  insert into public.user_preferences(profile_id,created_by) values(v_user,v_user) on conflict(profile_id) do nothing;
  insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id)
    values(v_user,'provision_individual_customer','public','customer_profiles',v_account);
  return v_account;
end $$;
create function public.ensure_individual_customer() returns uuid
language sql set search_path = '' as $$ select app_private.ensure_individual_customer(); $$;
revoke all on function public.ensure_individual_customer() from public,anon,authenticated;
grant execute on function app_private.ensure_individual_customer(),public.ensure_individual_customer() to authenticated;

create function app_private.add_customer_address(p_account_id uuid,p_label text,p_address text,p_country_id uuid,p_state_id uuid,p_city_id uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not app_private.can_access_customer(p_account_id,true) then raise exception 'account access denied' using errcode='42501'; end if;
  if length(trim(p_label)) not between 1 and 120 or length(trim(p_address)) not between 1 and 1000 then
    raise exception 'invalid address' using errcode='23514';
  end if;
  insert into public.customer_addresses(customer_account_id,label,address_line_1,country_id,state_id,city_id,created_by)
    values(p_account_id,p_label,p_address,p_country_id,p_state_id,p_city_id,auth.uid()) returning id into v_id;
  return v_id;
end $$;
create function public.add_customer_address(p_account_id uuid,p_label text,p_address text,p_country_id uuid,p_state_id uuid,p_city_id uuid default null) returns uuid
language sql set search_path = '' as $$ select app_private.add_customer_address(p_account_id,p_label,p_address,p_country_id,p_state_id,p_city_id); $$;
revoke all on function public.add_customer_address(uuid,text,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.add_customer_address(uuid,text,text,uuid,uuid,uuid),public.add_customer_address(uuid,text,text,uuid,uuid,uuid) to authenticated;

create function app_private.prepare_customer_upload(p_account_id uuid,p_content_type text,p_byte_size bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid=gen_random_uuid(); v_name text;
begin
  if not app_private.can_access_customer(p_account_id,true) then raise exception 'account access denied' using errcode='42501'; end if;
  v_name=v_id::text||'/content';
  insert into private.document_objects(id,bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,created_by)
    values(v_id,'customer-documents',v_name,p_account_id,auth.uid(),'customer',p_content_type,p_byte_size,auth.uid());
  insert into public.customer_documents(customer_account_id,document_object_id,purpose,created_by)
    values(p_account_id,v_id,'customer_upload',auth.uid());
  return jsonb_build_object('document_id',v_id,'bucket','customer-documents','object_name',v_name);
end $$;
create function public.prepare_customer_upload(p_account_id uuid,p_content_type text,p_byte_size bigint) returns jsonb
language sql set search_path = '' as $$ select app_private.prepare_customer_upload(p_account_id,p_content_type,p_byte_size); $$;
revoke all on function public.prepare_customer_upload(uuid,text,bigint) from public,anon,authenticated;
grant execute on function app_private.prepare_customer_upload(uuid,text,bigint),public.prepare_customer_upload(uuid,text,bigint) to authenticated;

-- Validate configured rates against their rate card's currency; an independent FK
-- to currencies alone cannot prevent a currency mismatch.
alter table private.service_rate_cards add constraint service_rate_cards_currency_key unique(id,currency_id);
alter table private.service_pricing_rules add constraint pricing_rule_card_currency_fk
  foreign key(rate_card_id,currency_id) references private.service_rate_cards(id,currency_id) on delete restrict;

-- Never let TRUNCATE bypass row-level history/version guards.
do $$ declare t text; begin
  foreach t in array array['service_versions','service_variants','service_options','service_option_values',
    'service_requirements','service_booking_fields','service_booking_field_options','service_checklists',
    'service_checklist_items','service_exclusions','service_faqs','service_media'] loop
    execute format('create trigger onit_no_truncate before truncate on public.%I for each statement execute function app_private.reject_mutation()',t);
  end loop;
end $$;

-- Index referencing FK columns unless an existing index already has that prefix.
-- Restricted to tables created by these migrations via their onit_updated_at /
-- immutable/audit triggers; never adopt unrelated pre-existing application tables.
do $$ declare fk record; cols text; begin
  for fk in select con.oid,con.conrelid,con.conkey,con.conname,n.nspname,c.relname
    from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
    where con.contype='f' and n.nspname in ('public','private')
      and exists(select 1 from pg_trigger tr where tr.tgrelid=c.oid and not tr.tgisinternal
        and tr.tgname in ('onit_updated_at','onit_immutable','onit_audit_immutable','onit_activity_immutable'))
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
create index customer_addresses_account_time_idx on public.customer_addresses(customer_account_id,created_at desc) where archived_at is null;
create index support_tickets_account_status_idx on public.support_tickets(customer_account_id,status,created_at desc);
create index support_messages_ticket_time_idx on public.support_messages(ticket_id,created_at);
create index document_objects_pending_idx on private.document_objects(scan_status,created_at) where scan_status='pending';
create index user_roles_authorization_idx on private.user_role_assignments(profile_id,role_id) where revoked_at is null;
revoke create on schema public from public,anon,authenticated;
commit;
