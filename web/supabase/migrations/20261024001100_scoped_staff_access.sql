begin;
create function app_private.can_staff_read_customer(p_account_id uuid,p_permission text default 'customers.read') returns boolean
language sql stable security definer set search_path = '' as $$
  select p_permission in ('customers.read','documents.read') and exists(
    select 1 from public.customer_profiles c where c.id=p_account_id
    and app_private.has_permission(p_permission,c.organisation_id));
$$;
create function app_private.has_team_permission(p_code text,p_team_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.teams t where t.id=p_team_id and t.archived_at is null
    and (app_private.has_permission(p_code,t.organisation_id) or exists(
      select 1 from private.user_role_assignments a
      join private.roles r on r.id=a.role_id and r.archived_at is null
      join private.role_permissions rp on rp.role_id=r.id
      join private.permissions p on p.id=rp.permission_id and p.code=p_code
      join private.team_members tm on tm.team_id=t.id and tm.profile_id=a.profile_id and tm.revoked_at is null
      join private.employee_profiles e on e.profile_id=a.profile_id and e.status='active'
      join public.organisations employer on employer.id=e.organisation_id and employer.organisation_type='onit' and employer.status='active'
      join public.profiles subject on subject.id=a.profile_id and subject.status='active'
      where a.profile_id=auth.uid() and a.scope='team' and a.team_id=t.id and a.organisation_id=t.organisation_id
        and a.revoked_at is null and (a.valid_until is null or a.valid_until>now())
        and app_private.is_active_member(t.organisation_id))));
$$;
grant execute on function app_private.can_staff_read_customer(uuid,text),app_private.has_team_permission(text,uuid) to authenticated;
create or replace function app_private.can_read_object(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.document_objects d where d.bucket_id=p_bucket and d.object_name=p_name
    and d.scan_status='clean' and d.archived_at is null
    and ((d.classification='public' and d.bucket_id='marketing-assets')
      or (d.classification='customer' and (app_private.can_access_customer(d.customer_account_id)
        or app_private.can_staff_read_customer(d.customer_account_id,'documents.read')))
      or (d.classification='identity' and d.owner_profile_id=auth.uid()
        and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active'))));
$$;
-- Contracts, employee files, field evidence and invoices require future typed
-- domain download commands. A generic document permission cannot expose HR files.
do $$ declare t text; begin
  foreach t in array array['customer_addresses','service_locations','customer_contacts','support_tickets','customer_feedback','customer_consents','communication_preferences'] loop
    execute format('drop policy customer_scoped_read on public.%I',t);
    execute format('create policy customer_scoped_read on public.%I for select to authenticated using(app_private.can_access_customer(customer_account_id) or app_private.can_staff_read_customer(customer_account_id))',t);
  end loop;
  foreach t in array array['roles','permissions','teams','team_members','departments'] loop
    execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
  end loop;
end $$;
drop policy support_messages_read on public.support_messages;
create policy support_messages_read on public.support_messages for select to authenticated
using((visibility='customer' and app_private.can_access_customer(customer_account_id)) or app_private.can_staff_read_customer(customer_account_id));
drop policy customer_document_read on public.customer_documents;
create policy customer_document_read on public.customer_documents for select to authenticated
using(app_private.can_access_customer(customer_account_id) or app_private.can_staff_read_customer(customer_account_id,'documents.read'));

create or replace function app_private.add_customer_address(p_account_id uuid,p_label text,p_address text,p_country_id uuid,p_state_id uuid,p_city_id uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not app_private.can_access_customer(p_account_id,true) then raise exception 'account access denied' using errcode='42501'; end if;
  if length(trim(p_label)) not between 1 and 120 or length(trim(p_address)) not between 1 and 1000 then
    raise exception 'invalid address' using errcode='23514';
  end if;
  if not exists(select 1 from public.states s join public.countries c on c.id=s.country_id
    where s.id=p_state_id and c.id=p_country_id and s.status='active' and c.status='active')
    or (p_city_id is not null and not exists(select 1 from public.cities c where c.id=p_city_id
      and c.state_id=p_state_id and app_private.is_city_active(c.id))) then
    raise exception 'active, consistent geography required' using errcode='23514';
  end if;
  insert into public.customer_addresses(customer_account_id,label,address_line_1,country_id,state_id,city_id,created_by)
    values(p_account_id,p_label,p_address,p_country_id,p_state_id,p_city_id,auth.uid()) returning id into v_id;
  return v_id;
end $$;
commit;
