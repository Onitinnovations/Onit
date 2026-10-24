begin;
-- Additive upgrade: no existing data or migration history is removed.
do $$ declare t text; begin
  foreach t in array array['countries','currencies','states','cities','local_government_areas'] loop
    execute format('alter table public.%I add column status text not null default ''active'' check(status in (''active'',''inactive'',''archived''))',t);
  end loop;
end $$;
alter table public.service_versions add column pricing_mode text not null default 'custom_quotation'
  check(pricing_mode in ('fixed_price','starting_price','quantity_based','assessment_based','custom_quotation'));
alter table public.service_versions add constraint assessment_pricing_requires_assessment
  check(pricing_mode<>'assessment_based' or assessment_required);
alter table public.organisation_locations add constraint organisation_locations_tenant_key unique(id,organisation_id);
alter table private.corporate_account_users add constraint corporate_account_users_tenant_key unique(id,customer_account_id,organisation_id);

create function app_private.is_city_active(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.cities c join public.states s on s.id=c.state_id
    join public.countries co on co.id=s.country_id where c.id=p_id
    and c.status='active' and s.status='active' and co.status='active');
$$;
grant execute on function app_private.is_city_active(uuid) to anon,authenticated;
drop policy countries_reference on public.countries;
create policy countries_reference on public.countries for select to anon,authenticated using(status='active');
drop policy currencies_reference on public.currencies;
create policy currencies_reference on public.currencies for select to anon,authenticated using(status='active');
drop policy states_reference on public.states;
create policy states_reference on public.states for select to anon,authenticated using(status='active' and exists(
  select 1 from public.countries c where c.id=country_id and c.status='active'));
drop policy cities_reference on public.cities;
create policy cities_reference on public.cities for select to anon,authenticated using(app_private.is_city_active(id));
drop policy lgas_reference on public.local_government_areas;
create policy lgas_reference on public.local_government_areas for select to anon,authenticated using(status='active' and exists(
  select 1 from public.states s where s.id=state_id and s.status='active'));
drop policy city_availability_published on public.city_service_availability;
create policy city_availability_published on public.city_service_availability for select to anon,authenticated
using(enabled and effective_from<=now() and (effective_until is null or effective_until>now())
  and app_private.is_city_active(city_id) and app_private.is_service_published(service_id));
commit;
