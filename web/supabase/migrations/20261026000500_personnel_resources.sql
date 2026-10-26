begin;
-- A worker is a resource linked to an existing profile, not another contracting provider.
create table private.provider_personnel_capacity (
 id uuid primary key default gen_random_uuid(),profile_id uuid not null references public.profiles(id) on delete restrict,
 version integer not null check(version>0),units numeric(12,4) not null check(units>0),
 valid_from timestamptz not null,valid_until timestamptz,
 status text not null default 'draft' check(status in ('draft','approved','retired')),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(valid_until is null or valid_until>valid_from),check(status='draft' or (approved_by is not null and approved_at is not null)),
 check(approved_by is null or (approved_by<>created_by and approved_by<>profile_id)),unique(profile_id,version)
);
create table private.provider_personnel_availability (
 id uuid primary key default gen_random_uuid(),profile_id uuid not null references public.profiles(id) on delete restrict,
 starts_at timestamptz not null,ends_at timestamptz not null,
 kind text not null check(kind in ('working','leave','blackout','temporary_unavailable')),revoked_at timestamptz,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(ends_at>starts_at and ends_at-starts_at<=interval '31 days')
);
alter table private.provider_capacity_reservations add column worker_profile_id uuid references public.profiles(id) on delete restrict,
 add column worker_units numeric(12,4),add constraint reservation_worker_units check((worker_profile_id is null and worker_units is null) or (worker_profile_id is not null and worker_units is not null and worker_units>0));
-- Preserve any earlier local candidate reservations when rehearsing an upgrade.
update private.provider_capacity_reservations r set worker_profile_id=p.individual_profile_id,worker_units=r.units
 from private.provider_profiles p where p.id=r.provider_id and p.individual_profile_id is not null;
update private.provider_capacity_reservations r set worker_profile_id=(c.payload->'data'->>'worker_id')::uuid,worker_units=1
 from private.transaction_commands c where c.command='provider_reservation' and c.result_id=r.id and r.worker_profile_id is null and c.payload->>'action'='reserve' and c.payload->'data'->>'worker_id' is not null;
create index personnel_capacity_effective on private.provider_personnel_capacity(profile_id,valid_from,valid_until) where status='approved';
create index personnel_calendar_overlap on private.provider_personnel_availability(profile_id,starts_at,ends_at) where revoked_at is null;
create index personnel_reservation_overlap on private.provider_capacity_reservations(worker_profile_id,starts_at,ends_at) where status in ('reserved','assigned');
create function app_private.guard_personnel_capacity() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or (old.status<>'draft' and ((to_jsonb(new)-array['status','updated_at']) is distinct from (to_jsonb(old)-array['status','updated_at']) or not (old.status='approved' and new.status='retired'))) then raise exception 'approved personnel capacity is immutable' using errcode='55000';end if;return new;
end$$;
create trigger onit_personnel_terms before update or delete on private.provider_personnel_capacity for each row execute function app_private.guard_personnel_capacity();
do $$declare t text;begin foreach t in array array['provider_personnel_capacity','provider_personnel_availability'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 execute format('grant all on private.%I to service_role',t);
 execute format('create trigger onit_updated_at before update on private.%I for each row execute function app_private.touch_updated_at()',t);
 execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
 execute format('create index %I on private.%I(created_by)',t||'_creator_idx',t);
end loop;end$$;
create index personnel_capacity_approver on private.provider_personnel_capacity(approved_by);
create index personnel_reservation_profile on private.provider_capacity_reservations(worker_profile_id);
create function app_private.personnel_command(p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare profile uuid=(p_data->>'profile_id')::uuid;result uuid;r private.provider_personnel_capacity;receipt private.transaction_commands;payload jsonb;related record;reason text=p_data->>'reason';permission text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192 or p_key is null or length(p_key) not between 8 and 128 or reason is null or length(trim(reason)) not between 1 and 2000 then raise exception 'bounded personnel command required' using errcode='23514';end if;
 permission=case when p_action in ('approve_capacity','retire_capacity') then 'providers.approve' when p_action='capacity' then 'providers.capacity.manage' else 'providers.manage' end;
 if p_action in ('availability','revoke_availability') then
  if profile is null or not (profile=auth.uid() or app_private.has_permission(permission)) then raise exception 'personal calendar access denied' using errcode='42501';end if;
 elsif not app_private.has_permission(permission) then raise exception 'global personnel resource permission required' using errcode='42501';end if;
 if p_action in ('approve_capacity','retire_capacity') then
  select * into r from private.provider_personnel_capacity where id=(p_data->>'id')::uuid;
  if not found then raise exception 'resource record unavailable' using errcode='42501';end if;profile=r.profile_id;
 end if;
 perform 1 from public.profiles where id=profile and status='active' for no key update;
 if not found then raise exception 'active resource profile required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('personnel-command:'||auth.uid()::text||':'||p_key,0));
 payload=jsonb_build_object('action',p_action,'data',p_data);
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='personnel_resource' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'personnel idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 case p_action
 when 'capacity' then
  if p_data->>'units' is null or (p_data->>'units') !~ '^[0-9]+(\.[0-9]{1,4})?$' then raise exception 'exact positive resource capacity required' using errcode='23514';end if;
  if not exists(select 1 from private.provider_personnel where profile_id=profile and revoked_at is null) and not exists(select 1 from private.provider_profiles where individual_profile_id=profile) then raise exception 'existing executing personnel or individual provider required' using errcode='23514';end if;
  insert into private.provider_personnel_capacity(profile_id,version,units,valid_from,valid_until,created_by) values(profile,(p_data->>'version')::integer,(p_data->>'units')::numeric,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,auth.uid()) returning id into result;
 when 'approve_capacity','retire_capacity' then
  select * into r from private.provider_personnel_capacity where id=r.id for update;
  if r.created_by=auth.uid() or r.profile_id=auth.uid() or (p_action='approve_capacity' and r.status<>'draft') or (p_action='retire_capacity' and r.status<>'approved') then raise exception 'independent resource approval required' using errcode='42501';end if;
  if p_action='approve_capacity' then
   if exists(select 1 from private.provider_personnel_capacity c where c.profile_id=profile and c.status='approved' and tstzrange(c.valid_from,c.valid_until,'[)')&&tstzrange(r.valid_from,r.valid_until,'[)')) then raise exception 'overlapping personnel capacity terms' using errcode='23514';end if;
   if r.units<app_private.personnel_used(profile,greatest(now(),r.valid_from),coalesce(r.valid_until,(select max(ends_at) from private.provider_capacity_reservations where worker_profile_id=profile and (status='assigned' or (status='reserved' and expires_at>now()))),now())) then raise exception 'resource capacity below reserved workload' using errcode='23514';end if;
   update private.provider_personnel_capacity set status='approved',approved_by=auth.uid(),approved_at=now() where id=r.id;
  else update private.provider_personnel_capacity set status='retired' where id=r.id;end if;result=r.id;
 when 'availability' then
  insert into private.provider_personnel_availability(profile_id,starts_at,ends_at,kind,created_by) values(profile,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,p_data->>'kind',auth.uid()) returning id into result;
 when 'revoke_availability' then
  update private.provider_personnel_availability set revoked_at=now() where id=(p_data->>'id')::uuid and profile_id=profile and revoked_at is null returning id into result;if not found then raise exception 'calendar record unavailable' using errcode='42501';end if;
 else raise exception 'unsupported personnel command' using errcode='23514';end case;
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id,details) values(auth.uid(),'personnel.'||p_action,'private',case when p_action like '%capacity' then 'provider_personnel_capacity' else 'provider_personnel_availability' end,result,jsonb_build_object('permission',case when profile=auth.uid() and p_action in ('availability','revoke_availability') then 'self.calendar' else permission end,'reason',reason));
 for related in select p.id from private.provider_profiles p where p.individual_profile_id=profile or exists(select 1 from private.provider_personnel w where w.provider_id=p.id and w.profile_id=profile and w.revoked_at is null) loop
  perform app_private.provider_receipt(related.id,'personnel_'||p_action,result,null,null,reason,permission);
 end loop;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'personnel_resource',p_key,payload,result);
 return result;
end$$;
create function app_private.personnel_used(p_profile uuid,p_start timestamptz,p_end timestamptz) returns numeric
language sql stable security definer set search_path='' as $$
 with live as(select starts_at,ends_at,worker_units from private.provider_capacity_reservations where worker_profile_id=p_profile and starts_at<p_end and ends_at>p_start and (status='assigned' or (status='reserved' and expires_at>now()))),
 events as(select greatest(starts_at,p_start) t,worker_units delta from live union all select least(ends_at,p_end),-worker_units from live),
 grouped as(select t,sum(delta) delta from events group by t),
 levels as(select t,sum(delta) over(order by t rows unbounded preceding) used from grouped)
 select coalesce(max(used),0) from levels where t<p_end
$$;
alter function app_private.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid) rename to provider_party_eligibility;
revoke all on function app_private.provider_party_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid) from public,anon,authenticated;
create function app_private.provider_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare decision jsonb;p private.provider_profiles;worker uuid;capacity numeric;used numeric;demand numeric;calendar boolean;individual uuid;
begin
 decision=app_private.provider_party_eligibility(p_provider,p_service,p_zone,p_start,p_end,p_units,p_worker);
 select * into p from private.provider_profiles where id=p_provider;
 worker=coalesce(p_worker,p.individual_profile_id);
 if worker is null then return decision||jsonb_build_object('personnel_checked',false,'worker_id',null);end if;
 if p_worker is not null and decision->'reasons' @> '[{"code":"worker_not_authorised"}]' then return decision||jsonb_build_object('personnel_checked',false);end if;
 if not (worker=auth.uid() or app_private.provider_self(p.id,true) or app_private.has_permission('providers.read',p.organisation_id) or app_private.has_permission('providers.capacity.manage',p.organisation_id)) then raise exception 'worker resource access denied' using errcode='42501';end if;
 demand=case when p.individual_profile_id=worker then p_units::numeric else 1 end;
 select id into individual from private.provider_profiles where individual_profile_id=worker and status='active';
 select units into capacity from private.provider_personnel_capacity where profile_id=worker and status='approved' and valid_from<=least(now(),p_start) and (valid_until is null or valid_until>=p_end);
 -- Reuse an individual provider's configured human pool, never processing units.
 -- Explicit personnel terms take precedence; draft/retired terms block fallback.
 if capacity is null and not exists(select 1 from private.provider_personnel_capacity where profile_id=worker) then select units into capacity from private.provider_capacity where provider_id=individual and unit='concurrent_jobs' and status='active';end if;
 used=app_private.personnel_used(worker,p_start,p_end);
 calendar=(exists(select 1 from private.provider_personnel_availability where profile_id=worker and kind='working' and revoked_at is null and starts_at<=p_start and ends_at>=p_end)
  or exists(select 1 from private.provider_availability where provider_id=individual and service_version_id=p_service and kind='working' and revoked_at is null and starts_at<=p_start and ends_at>=p_end))
  and not exists(select 1 from private.provider_personnel_availability where profile_id=worker and kind<>'working' and revoked_at is null and starts_at<p_end and ends_at>p_start)
  and not exists(select 1 from private.provider_availability where provider_id=individual and service_version_id=p_service and kind<>'working' and revoked_at is null and starts_at<p_end and ends_at>p_start);
 if capacity is null then decision=jsonb_set(decision,'{reasons}',decision->'reasons'||'[{"code":"personnel_capacity_missing"}]');
 elsif used+demand>capacity then decision=jsonb_set(decision,'{reasons}',decision->'reasons'||'[{"code":"personnel_capacity_exceeded"}]');end if;
 if not calendar then decision=jsonb_set(decision,'{reasons}',decision->'reasons'||'[{"code":"personnel_unavailable"}]');end if;
 return decision||jsonb_build_object('eligible',jsonb_array_length(decision->'reasons')=0,'personnel_checked',true,'worker_id',worker,'worker_capacity_used',used::text,'worker_capacity_requested',demand::text,'worker_capacity_limit',capacity::text);
end$$;
alter function app_private.provider_reservation(uuid,text,jsonb,text) rename to provider_party_reservation;
revoke all on function app_private.provider_party_reservation(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare p private.provider_profiles;worker uuid;result uuid;decision jsonb;receipt private.transaction_commands;payload jsonb;
begin
 select * into p from private.provider_profiles where id=p_provider;
 if not found or not app_private.has_permission('providers.capacity.manage',p.organisation_id) then raise exception 'capacity manager required' using errcode='42501';end if;
 if p_action='reserve' then
  perform pg_advisory_xact_lock(hashtextextended('provider-policy:'||(p_data->>'service_version_id'),0));
  worker=coalesce((p_data->>'worker_id')::uuid,p.individual_profile_id);
 else select worker_profile_id into worker from private.provider_capacity_reservations where id=(p_data->>'id')::uuid and provider_id=p.id;end if;
 -- Canonical lock order: policy -> human profile -> contracting provider -> receipt/pool.
 -- NO KEY UPDATE allows FK key-share checks without a provider/profile lock cycle.
 if worker is not null then perform 1 from public.profiles where id=worker for no key update;end if;
 perform 1 from private.provider_profiles where id=p.id for update;
 payload=jsonb_build_object('provider',p_provider,'action',p_action,'data',p_data);
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='provider_reservation' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action='reserve' then
  decision=app_private.provider_eligibility(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,p_data->>'units',(p_data->>'worker_id')::uuid);
  if not (decision->>'eligible')::boolean then raise exception 'provider/personnel eligibility failed: %',decision->'reasons' using errcode='23514';end if;
 end if;
 result=app_private.provider_party_reservation(p_provider,p_action,p_data,p_key);
 if p_action='reserve' and worker is not null then update private.provider_capacity_reservations set worker_profile_id=worker,worker_units=case when p.individual_profile_id=worker then (p_data->>'units')::numeric else 1 end where id=result;end if;
 return result;
end$$;
-- Rebind wrappers: existing cached SQL bodies must not retain the earlier helper OIDs.
create or replace function public.provider_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb language sql stable set search_path='' as $$select app_private.provider_eligibility(p_provider,p_service,p_zone,p_start,p_end,p_units,p_worker)$$;
create or replace function public.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.provider_reservation(p_provider,p_action,p_data,p_key)$$;
create function public.personnel_command(p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.personnel_command(p_action,p_data,p_key)$$;
create function app_private.read_personnel_resource(p_profile uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if ((p_profile=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and status='active')) or app_private.has_permission('providers.read')) is distinct from true or p_profile is null then raise exception 'personnel resource access denied' using errcode='42501';end if;
 return jsonb_build_object('profile_id',p_profile,'capacity',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'version',version,'units',units::text,'valid_from',valid_from,'valid_until',valid_until,'status',status) order by version),'[]') from private.provider_personnel_capacity where profile_id=p_profile),
 'availability',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (select id,starts_at,ends_at,kind from private.provider_personnel_availability where profile_id=p_profile and revoked_at is null and ends_at>now() order by starts_at,id limit 100) q));
end$$;
create function public.read_personnel_resource(p_profile uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_personnel_resource(p_profile)$$;
revoke all on function public.personnel_command(text,jsonb,text),public.read_personnel_resource(uuid) from public,anon;
grant execute on function public.personnel_command(text,jsonb,text),app_private.personnel_command(text,jsonb,text),public.read_personnel_resource(uuid),app_private.read_personnel_resource(uuid),app_private.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),app_private.provider_reservation(uuid,text,jsonb,text) to authenticated;
commit;
