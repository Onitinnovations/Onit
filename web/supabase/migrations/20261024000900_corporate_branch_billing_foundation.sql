begin;
create table public.corporate_account_branches (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null, organisation_id uuid not null,
  organisation_location_id uuid not null, code text not null, cost_reference text,
  status text not null default 'active' check(status in ('active','inactive','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(customer_account_id,organisation_id) references public.corporate_accounts(id,organisation_id) on delete restrict,
  foreign key(organisation_location_id,organisation_id) references public.organisation_locations(id,organisation_id) on delete restrict,
  unique(customer_account_id,code), unique(customer_account_id,organisation_location_id), unique(id,customer_account_id,organisation_id)
);
alter table private.corporate_account_users add column branch_access text not null default 'all' check(branch_access in ('all','assigned'));
create table private.corporate_account_user_branches (
  id uuid primary key default gen_random_uuid(), account_user_id uuid not null, customer_account_id uuid not null, organisation_id uuid not null,
  branch_id uuid not null, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(account_user_id,customer_account_id,organisation_id) references private.corporate_account_users(id,customer_account_id,organisation_id) on delete restrict,
  foreign key(branch_id,customer_account_id,organisation_id) references public.corporate_account_branches(id,customer_account_id,organisation_id) on delete restrict,
  unique(account_user_id,branch_id)
);
create table private.corporate_billing_profiles (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.corporate_accounts(id) on delete restrict,
  version integer not null check(version>0), bill_to_name text not null, billing_address text not null,
  billing_contact_id uuid, consolidated_billing boolean not null default true,
  status text not null default 'draft' check(status in ('draft','active','retired')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(billing_contact_id,customer_account_id) references public.customer_contacts(id,customer_account_id) on delete restrict,
  unique(customer_account_id,version)
);
create unique index corporate_billing_active_key on private.corporate_billing_profiles(customer_account_id) where status='active';
-- Configuration only, not a credit line, balance, invoice or credit authorizer.
create table private.corporate_credit_terms (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.corporate_accounts(id) on delete restrict,
  version integer not null check(version>0), payment_days integer not null check(payment_days between 0 and 365),
  currency_id uuid not null references public.currencies(id) on delete restrict,
  valid_from timestamptz not null, valid_until timestamptz,
  status text not null default 'draft' check(status in ('draft','approved','retired')),
  approval_request_id uuid references private.approval_requests(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(valid_until is null or valid_until>valid_from),
  check(status<>'approved' or (approval_request_id is not null and approved_by is not null and created_by is not null and approved_by<>created_by)),
  unique(customer_account_id,version)
);
create unique index corporate_credit_approved_key on private.corporate_credit_terms(customer_account_id) where status='approved';

create or replace function app_private.can_access_customer(p_account_id uuid,p_write boolean default false,p_department_id uuid default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.customer_profiles c join public.profiles p on p.id=auth.uid() and p.status='active'
    where c.id=p_account_id and c.status='approved' and c.archived_at is null
      and (c.individual_profile_id=auth.uid() or exists(select 1 from private.corporate_account_users u
        join public.corporate_accounts a on a.id=u.customer_account_id and a.approval_status='approved'
        where u.customer_account_id=c.id and u.profile_id=auth.uid() and u.status='approved'
          and u.revoked_at is null and (u.valid_until is null or u.valid_until>now())
          and app_private.is_active_member(u.organisation_id) and (not p_write or u.can_request)
          and u.branch_access='all' and (u.access_scope='account' or u.department_id=p_department_id))));
$$;
create function app_private.can_access_branch(p_branch_id uuid,p_action text default 'read',p_department_id uuid default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_action in ('read','request','approve') and exists(
    select 1 from public.corporate_account_branches b join public.customer_profiles c on c.id=b.customer_account_id
    join public.corporate_accounts a on a.id=c.id
    join public.organisation_locations l on l.id=b.organisation_location_id and l.archived_at is null
    join private.corporate_account_users u on u.customer_account_id=b.customer_account_id
    join public.profiles p on p.id=u.profile_id and p.status='active'
    where b.id=p_branch_id and b.status='active' and c.status='approved' and c.archived_at is null and a.approval_status='approved'
      and u.profile_id=auth.uid() and u.status='approved' and u.revoked_at is null and (u.valid_until is null or u.valid_until>now())
      and app_private.is_active_member(u.organisation_id)
      and (u.access_scope='account' or u.department_id=p_department_id)
      and (p_action='read' or (p_action='request' and u.can_request) or (p_action='approve' and u.can_approve))
      and (u.branch_access='all' or exists(select 1 from private.corporate_account_user_branches ub
        where ub.account_user_id=u.id and ub.branch_id=b.id and ub.revoked_at is null)));
$$;
create function app_private.can_access_organisation_location(p_location_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.corporate_account_branches b where b.organisation_location_id=p_location_id
    and app_private.can_access_branch(b.id)) or exists(select 1 from public.organisation_locations l
    where l.id=p_location_id and app_private.has_permission('customers.read',l.organisation_id));
$$;
grant execute on function app_private.can_access_branch(uuid,text,uuid),app_private.can_access_organisation_location(uuid) to authenticated;
-- Broad organisation membership does not expose all corporate operating locations.
drop policy organisation_locations_read on public.organisation_locations;
create policy organisation_locations_read on public.organisation_locations for select to authenticated
using(app_private.can_access_organisation_location(id));

do $$ declare t text; v_schema text; begin
  foreach t in array array['corporate_account_branches','corporate_account_user_branches','corporate_billing_profiles','corporate_credit_terms'] loop
    v_schema=case when t='corporate_account_branches' then 'public' else 'private' end;
    execute format('alter table %I.%I enable row level security',v_schema,t);
    execute format('revoke all on %I.%I from public,anon,authenticated',v_schema,t);
    execute format('grant all on %I.%I to service_role',v_schema,t);
    execute format('create trigger onit_updated_at before update on %I.%I for each row execute function app_private.touch_updated_at()',v_schema,t);
    execute format('create trigger onit_audit after insert or update or delete on %I.%I for each row execute function app_private.audit_access_change()',v_schema,t);
    if t in ('corporate_billing_profiles','corporate_credit_terms') then
      execute format('create trigger onit_configuration_guard before update or delete on %I.%I for each row execute function app_private.guard_released_configuration()',v_schema,t);
      execute format('create trigger onit_no_truncate before truncate on %I.%I for each statement execute function app_private.reject_mutation()',v_schema,t);
    end if;
  end loop;
end $$;
grant select on public.corporate_account_branches to authenticated;
create policy corporate_branch_read on public.corporate_account_branches for select to authenticated
using(app_private.can_access_branch(id) or app_private.has_permission('customers.read',organisation_id));
commit;
