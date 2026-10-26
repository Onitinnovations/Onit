begin;
create function app_private.provider_configuration(p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;v private.provider_requirement_sets;c private.provider_training_courses;r record;permission text;
 receipt private.transaction_commands;payload jsonb;item jsonb;reason text=p_data->>'reason';
begin
 permission=case when p_action in ('approve_requirements','retire_requirements','approve_course','retire_course') then 'providers.policy.approve' else 'providers.policy.manage' end;
 if not app_private.has_permission(permission) then raise exception 'global provider configuration permission required' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 or p_key is null or length(p_key) not between 8 and 128 or reason is null or length(trim(reason)) not between 1 and 2000 then raise exception 'bounded configuration, reason and key required' using errcode='23514';end if;
 payload=jsonb_build_object('action',p_action,'data',p_data);
 perform pg_advisory_xact_lock(hashtextextended('provider-config:'||auth.uid()::text||':'||p_key,0));
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='provider_config' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505';end if;return receipt.result_id;end if;
 case p_action
 when 'requirements' then
  if jsonb_typeof(p_data->'requirements') is distinct from 'array' or jsonb_array_length(p_data->'requirements') not between 1 and 50 then raise exception 'requirements array required' using errcode='23514';end if;
  for item in select value from jsonb_array_elements(p_data->'requirements') loop
   if jsonb_typeof(item) is distinct from 'object' or item->>'kind' is null or item->>'kind' not in ('verification','skill','credential','training')
   or item->>'code' is null or (item->>'code') !~ '^[a-z0-9_-]{1,80}$' or item->>'scope' is null or item->>'scope' not in ('provider','worker')
   or jsonb_typeof(item->'document_required') is distinct from 'boolean' or exists(select 1 from jsonb_object_keys(item) k where k not in ('kind','code','scope','document_required')) then raise exception 'invalid typed requirement' using errcode='23514';end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_data->'requirements') e group by e->>'kind',e->>'code',e->>'scope' having count(*)>1) then raise exception 'duplicate requirement' using errcode='23514';end if;
  if p_data->>'provider_type' in ('service_associate','artisan','professional','field_agent') and p_data->>'capacity_unit' is distinct from 'concurrent_jobs' then raise exception 'individual policies require shared concurrent_jobs capacity' using errcode='23514';end if;
  insert into private.provider_requirement_sets(service_version_id,provider_type,zone_id,version,valid_from,valid_until,requirements,capacity_unit,engagement_required,maximum_travel_km,performance_metric,minimum_performance,performance_window_days,created_by)
  values((p_data->>'service_version_id')::uuid,p_data->>'provider_type',(p_data->>'zone_id')::uuid,(p_data->>'version')::integer,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,p_data->'requirements',p_data->>'capacity_unit',(p_data->>'engagement_required')::boolean,(p_data->>'maximum_travel_km')::numeric,p_data->>'performance_metric',(p_data->>'minimum_performance')::numeric,(p_data->>'performance_window_days')::integer,auth.uid()) returning id into result;
 when 'approve_requirements','retire_requirements' then
  select * into v from private.provider_requirement_sets where id=(p_data->>'id')::uuid for update;
  if not found or v.created_by=auth.uid() or (p_action='approve_requirements' and v.status<>'draft') or (p_action='retire_requirements' and v.status<>'approved') then raise exception 'independent configuration decision required' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended('provider-policy:'||v.service_version_id::text,0));
  if p_action='approve_requirements' then
   if not exists(select 1 from public.service_zones where id=v.zone_id and status='active') then raise exception 'active zone required' using errcode='23514';end if;
   if exists(select 1 from private.provider_requirement_sets x where x.service_version_id=v.service_version_id and x.provider_type=v.provider_type and x.zone_id=v.zone_id and x.status='approved' and tstzrange(x.valid_from,x.valid_until,'[)')&&tstzrange(v.valid_from,v.valid_until,'[)')) then raise exception 'overlapping approved requirements' using errcode='23514';end if;
   update private.provider_requirement_sets set status='approved',approved_by=auth.uid(),approved_at=now() where id=v.id;
  else update private.provider_requirement_sets set status='retired' where id=v.id;end if;result=v.id;
 when 'course' then
  insert into private.provider_training_courses(code,version,name,pass_mark,required_attendance,certificate_valid_days,created_by)
  values(p_data->>'code',(p_data->>'version')::integer,p_data->>'name',(p_data->>'pass_mark')::numeric,(p_data->>'required_attendance')::numeric,(p_data->>'certificate_valid_days')::integer,auth.uid()) returning id into result;
 when 'approve_course','retire_course' then
  select * into c from private.provider_training_courses where id=(p_data->>'id')::uuid for update;
  if not found or c.created_by=auth.uid() or (p_action='approve_course' and c.status<>'draft') or (p_action='retire_course' and c.status<>'approved') then raise exception 'independent course decision required' using errcode='42501';end if;
  if p_action='approve_course' then update private.provider_training_courses set status='approved',approved_by=auth.uid(),approved_at=now() where id=c.id;
  else update private.provider_training_courses set status='retired' where id=c.id;end if;result=c.id;
 when 'session' then
  if not exists(select 1 from private.provider_training_courses where id=(p_data->>'course_id')::uuid and status='approved')
   or not exists(select 1 from private.employee_profiles e join public.profiles p on p.id=e.profile_id and p.status='active' join public.organisations o on o.id=e.organisation_id and o.organisation_type='onit' and o.status='active' where e.profile_id=(p_data->>'trainer_id')::uuid and e.status='active') then raise exception 'approved course and active internal trainer required' using errcode='23514';end if;
  insert into private.provider_training_sessions(course_id,trainer_id,starts_at,ends_at,created_by) values((p_data->>'course_id')::uuid,(p_data->>'trainer_id')::uuid,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,auth.uid()) returning id into result;
 when 'campaign' then
  insert into private.provider_recruitment_campaigns(code,name,starts_at,ends_at,created_by) values(p_data->>'code',p_data->>'name',(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,auth.uid()) returning id into result;
 when 'close_campaign' then
  update private.provider_recruitment_campaigns set status='closed' where id=(p_data->>'id')::uuid and status='active' returning id into result;
  if not found then raise exception 'campaign not active' using errcode='55000';end if;
 else raise exception 'unsupported configuration action' using errcode='23514';
 end case;
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id,details)
 values(auth.uid(),'provider_config.'||p_action,'private',case when p_action like '%requirements' then 'provider_requirement_sets' when p_action like '%course' then 'provider_training_courses' when p_action='session' then 'provider_training_sessions' else 'provider_recruitment_campaigns' end,result,jsonb_build_object('permission',permission,'reason',reason));
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'provider_config',p_key,payload,result);
 return result;
end $$;
-- Half-open intervals; compute the actual peak, not sum of all overlapping jobs.
create function app_private.provider_capacity_used(p_pool uuid,p_start timestamptz,p_end timestamptz) returns numeric
language sql stable security definer set search_path='' as $$
 with live as (select * from private.provider_capacity_reservations where pool_id=p_pool and starts_at<p_end and ends_at>p_start
 and (status='assigned' or (status='reserved' and expires_at>now()))),
 events as (select greatest(starts_at,p_start) t,units delta from live union all select least(ends_at,p_end),-units from live),
 grouped as (select t,sum(delta) delta from events group by t),
 levels as (select t,sum(delta) over(order by t rows unbounded preceding) used from grouped)
 select coalesce(max(used),0) from levels where t<p_end
$$;
create function app_private.provider_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p private.provider_profiles;policy private.provider_requirement_sets;pool private.provider_capacity;reasons jsonb='[]';requirement jsonb;
 amount numeric;used numeric=0;score numeric;identity_valid boolean;
begin
 select * into p from private.provider_profiles where id=p_provider;
 if p.id is null or not (app_private.provider_self(p.id) or app_private.has_permission('providers.read',p.organisation_id) or app_private.has_permission('providers.capacity.manage',p.organisation_id)) then raise exception 'provider eligibility access denied' using errcode='42501';end if;
 if p_start is null or p_end is null or p_end<=p_start or p_end-p_start>interval '31 days' or p_units is null or p_units !~ '^[0-9]+(\.[0-9]{1,4})?$' or p_units::numeric<=0 or p_units::numeric>99999999 then raise exception 'valid window and exact positive capacity required' using errcode='23514';end if;
 amount=p_units::numeric;
 if p.status<>'active' then reasons=reasons||jsonb_build_array(jsonb_build_object('code','provider_inactive'));end if;
 if p.individual_profile_id is not null and not exists(select 1 from public.profiles where id=p.individual_profile_id and status='active') or p.organisation_id is not null and not exists(select 1 from public.organisations where id=p.organisation_id and status='active' and organisation_type in ('provider','mixed')) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','identity_inactive'));end if;
 if p_worker is not null and (p.individual_profile_id=p_worker or exists(select 1 from private.provider_personnel w join public.profiles pr on pr.id=w.profile_id and pr.status='active' join private.organisation_members m on m.profile_id=w.profile_id and m.organisation_id=p.organisation_id and m.status='active' and m.revoked_at is null and (m.valid_until is null or m.valid_until>=p_end) where w.provider_id=p.id and w.profile_id=p_worker and w.personnel_role in ('executing_worker','field_agent') and w.revoked_at is null and w.valid_from<=p_start and (w.valid_until is null or w.valid_until>=p_end))) is distinct from true then reasons=reasons||jsonb_build_array(jsonb_build_object('code','worker_not_authorised'));end if;
 if not exists(select 1 from public.service_versions v join public.services s on s.id=v.service_id join public.service_families f on f.id=s.service_family_id join public.service_areas a on a.id=f.service_area_id where v.id=p_service and v.status='published' and s.status='published' and f.status='published' and a.status='published') then reasons=reasons||jsonb_build_array(jsonb_build_object('code','service_unavailable'));end if;
 if not exists(select 1 from public.service_zones z join public.states st on st.id=z.state_id and st.status='active' where z.id=p_zone and z.status='active' and exists(select 1 from private.zone_boundaries_or_coverage c where c.zone_id=z.id and c.verified_at is not null and c.version=(select max(version) from private.zone_boundaries_or_coverage where zone_id=z.id))) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','zone_unverified'));end if;
 select * into policy from private.provider_requirement_sets where service_version_id=p_service and provider_type=p.provider_type and zone_id=p_zone and status='approved' and valid_from<=least(now(),p_start) and (valid_until is null or valid_until>=p_end);
 if not found then reasons=reasons||jsonb_build_array(jsonb_build_object('code','approved_requirements_missing'));end if;
 identity_valid=exists(select 1 from private.provider_qualifications q where q.provider_id=p.id and q.kind='verification' and q.code='identity' and q.status='approved' and q.valid_from<=least(now(),p_start) and (q.valid_until is null or q.valid_until>=p_end) and (q.document_id is null or app_private.provider_document(p.id,q.document_id)));
 if not identity_valid then reasons=reasons||jsonb_build_array(jsonb_build_object('code','identity_verification_missing_or_expired'));end if;
 for requirement in select value from jsonb_array_elements(coalesce(policy.requirements,'[]')) loop
  if not exists(select 1 from private.provider_qualifications q where q.provider_id=p.id and q.kind=requirement->>'kind' and q.code=requirement->>'code' and q.status='approved'
  and ((requirement->>'scope'='provider' and q.subject_profile_id is null) or (requirement->>'scope'='worker' and q.subject_profile_id=coalesce(p_worker,p.individual_profile_id)))
  and q.valid_from<=least(now(),p_start) and (q.valid_until is null or q.valid_until>=p_end)
  and (not (requirement->>'document_required')::boolean or q.document_id is not null)
  and (q.document_id is null or app_private.provider_document(p.id,q.document_id))) then
   reasons=reasons||jsonb_build_array(jsonb_build_object('code','requirement_not_met','kind',requirement->>'kind','requirement',requirement->>'code','scope',requirement->>'scope'));
  end if;
 end loop;
 if not exists(select 1 from private.provider_coverage_areas c where c.provider_id=p.id and c.service_version_id=p_service and c.zone_id=p_zone and c.revoked_at is null and c.valid_from<=p_start and (c.valid_until is null or c.valid_until>=p_end)) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','zone_coverage_missing'));end if;
 if policy.maximum_travel_km is not null or exists(select 1 from private.provider_coverage_areas where provider_id=p.id and service_version_id=p_service and zone_id=p_zone and revoked_at is null and travel_limit_km is not null) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','trusted_travel_evidence_required'));end if;
 if not exists(select 1 from private.provider_availability a where a.provider_id=p.id and a.service_version_id=p_service and a.kind='working' and a.revoked_at is null and a.starts_at<=p_start and a.ends_at>=p_end)
 or exists(select 1 from private.provider_availability a where a.provider_id=p.id and a.service_version_id=p_service and a.kind<>'working' and a.revoked_at is null and a.starts_at<p_end and a.ends_at>p_start) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','unavailable'));end if;
 if exists(select 1 from private.provider_restrictions r where r.provider_id=p.id and r.revoked_at is null and (r.service_version_id is null or r.service_version_id=p_service) and (r.zone_id is null or r.zone_id=p_zone) and r.valid_from<p_end and (r.valid_until is null or r.valid_until>least(now(),p_start))) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','restricted'));end if;
 if policy.engagement_required and not exists(select 1 from private.provider_engagements e where e.provider_id=p.id and e.service_version_id=p_service and e.zone_id=p_zone and e.status='approved' and e.valid_from<=least(now(),p_start) and e.valid_until>=p_end and app_private.provider_document(p.id,e.document_id)) then reasons=reasons||jsonb_build_array(jsonb_build_object('code','approved_engagement_missing'));end if;
 if policy.performance_metric is not null then
  select sum(successful)::numeric/nullif(sum(observations),0) into score from private.provider_performance_events where provider_id=p.id and metric=policy.performance_metric and occurred_at<=now() and occurred_at>=now()-make_interval(days=>policy.performance_window_days) and app_private.provider_document(p.id,document_id);
  if score is null or score<policy.minimum_performance then reasons=reasons||jsonb_build_array(jsonb_build_object('code','performance_requirement_not_met'));end if;
 end if;
 select * into pool from private.provider_capacity where provider_id=p.id and unit=policy.capacity_unit and status='active';
 if pool.id is null then reasons=reasons||jsonb_build_array(jsonb_build_object('code','capacity_configuration_missing'));
 else used=app_private.provider_capacity_used(pool.id,p_start,p_end);if used+amount>pool.units then reasons=reasons||jsonb_build_array(jsonb_build_object('code','capacity_exceeded'));end if;end if;
 return jsonb_build_object('eligible',jsonb_array_length(reasons)=0,'reasons',reasons,'provider_id',p.id,'provider_revision',p.revision,'policy_id',policy.id,'pool_id',pool.id,'capacity_unit',policy.capacity_unit,'capacity_used',used::text,'capacity_requested',amount::text,'capacity_limit',pool.units::text,'performance_ratio',score::text);
end $$;
create function app_private.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare p private.provider_profiles;pool private.provider_capacity;r private.provider_capacity_reservations;decision jsonb;result uuid;payload jsonb;receipt private.transaction_commands;
begin
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192 or p_data->>'reason' is null or length(trim(p_data->>'reason')) not between 1 and 2000 then raise exception 'bounded reservation input required' using errcode='23514';end if;
 if p_action='reserve' then perform pg_advisory_xact_lock(hashtextextended('provider-policy:'||(p_data->>'service_version_id'),0));end if;
 select * into p from private.provider_profiles where id=p_provider for update;
 if not found or not app_private.has_permission('providers.capacity.manage',p.organisation_id) then raise exception 'capacity manager required' using errcode='42501';end if;
 payload=jsonb_build_object('provider',p_provider,'action',p_action,'data',p_data);
 perform pg_advisory_xact_lock(hashtextextended('provider-reserve:'||auth.uid()::text||':'||p_key,0));
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='provider_reservation' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action='reserve' then
  if (p_data->>'start')::timestamptz<now() or (p_data->>'expires_at')::timestamptz<=now() or (p_data->>'expires_at')::timestamptz>(p_data->>'end')::timestamptz then raise exception 'future window and bounded reservation expiry required' using errcode='23514';end if;
  decision=app_private.provider_eligibility(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,p_data->>'units',(p_data->>'worker_id')::uuid);
  if not (decision->>'eligible')::boolean then raise exception 'provider not eligible: %',decision->'reasons' using errcode='23514';end if;
  select * into pool from private.provider_capacity where id=(decision->>'pool_id')::uuid for update;
  insert into private.provider_capacity_reservations(pool_id,provider_id,starts_at,ends_at,units,expires_at,purpose_reference,created_by)
  values(pool.id,p.id,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,(p_data->>'units')::numeric,(p_data->>'expires_at')::timestamptz,p_data->>'purpose_reference',auth.uid()) returning id into result;
 elsif p_action in ('release','expire') then
  select * into r from private.provider_capacity_reservations where id=(p_data->>'id')::uuid and provider_id=p.id for update;
  if not found then raise exception 'reservation access denied' using errcode='42501';end if;
  if r.status not in ('reserved','released','expired') then raise exception 'assigned capacity requires assignment cancellation' using errcode='55000';end if;
  if r.status='reserved' then
   if p_action='expire' and r.expires_at>now() then raise exception 'reservation has not expired' using errcode='55000';end if;
   update private.provider_capacity_reservations set status=case p_action when 'release' then 'released' else 'expired' end where id=r.id;
  end if;result=r.id;
 else raise exception 'unsupported reservation action' using errcode='23514';end if;
 perform app_private.provider_receipt(p.id,'capacity_'||p_action,result,null,null,p_data->>'reason','providers.capacity.manage');
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'provider_reservation',p_key,payload,result);
 return result;
end $$;
create function public.provider_configuration(p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.provider_configuration(p_action,p_data,p_key)$$;
create function public.provider_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb language sql stable set search_path='' as $$select app_private.provider_eligibility(p_provider,p_service,p_zone,p_start,p_end,p_units,p_worker)$$;
create function public.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.provider_reservation(p_provider,p_action,p_data,p_key)$$;
create function app_private.read_provider(p_provider uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p private.provider_profiles;staff boolean;
begin
 select * into p from private.provider_profiles where id=p_provider;
 staff=app_private.has_permission('providers.read',p.organisation_id);
 if p.id is null or not (staff or app_private.provider_self(p.id)) then raise exception 'provider access denied' using errcode='42501';end if;
 return jsonb_build_object('id',p.id,'type',p.provider_type,'status',p.status,'revision',p.revision,
 'display_name',case when p.individual_profile_id is not null then (select display_name from public.profiles where id=p.individual_profile_id) else (select name from public.organisations where id=p.organisation_id) end,
 'personnel',(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'profile_id',w.profile_id,'role',w.personnel_role,'valid_until',w.valid_until)),'[]') from private.provider_personnel w where w.provider_id=p.id and w.revoked_at is null and (staff or app_private.provider_self(p.id,true) or w.profile_id=auth.uid())),
 'applications',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'revision',a.revision,'stage',a.stage) order by a.revision),'[]') from private.provider_applications a where a.provider_id=p.id),
 'qualifications',(select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'kind',q.kind,'code',q.code,'status',q.status,'subject_profile_id',q.subject_profile_id,'valid_until',q.valid_until,'document_id',q.document_id)),'[]') from (select * from private.provider_qualifications where provider_id=p.id and (staff or subject_profile_id is null or subject_profile_id=auth.uid() or app_private.provider_self(p.id,true)) order by created_at desc,id limit 100) q),
 'availability',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'service_version_id',a.service_version_id,'start',a.starts_at,'end',a.ends_at,'kind',a.kind,'schedule_id',a.schedule_id)),'[]') from (select * from private.provider_availability where provider_id=p.id and revoked_at is null and ends_at>now() order by starts_at,id limit 100) a),
 'capacity',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'unit',c.unit,'units',c.units::text,'status',c.status)),'[]') from private.provider_capacity c where c.provider_id=p.id),
 'training',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
  select e.id,e.status,e.subject_profile_id,e.attendance_percent::text,e.score::text,e.qualification_id,s.id session_id,s.starts_at,s.ends_at,c.code,c.version,c.name
  from private.provider_training_enrolments e join private.provider_training_sessions s on s.id=e.session_id join private.provider_training_courses c on c.id=s.course_id
  where e.provider_id=p.id and (staff or e.subject_profile_id=auth.uid() or app_private.provider_self(p.id,true)) order by s.starts_at desc,e.id limit 100) t),
 'engagements',case when staff then (select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'status',e.status,'unit',e.unit,'unit_rate',e.unit_rate::text,'currency_id',e.currency_id,'valid_from',e.valid_from,'valid_until',e.valid_until)),'[]') from private.provider_engagements e where e.provider_id=p.id) else null end);
end $$;
create function public.read_provider(p_provider uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_provider(p_provider)$$;
-- Private schema stays unexposed; invoker wrappers can execute only authorised helpers.
grant execute on function public.provider_configuration(text,jsonb,text),app_private.provider_configuration(text,jsonb,text),
 public.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),app_private.provider_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),
 public.provider_reservation(uuid,text,jsonb,text),app_private.provider_reservation(uuid,text,jsonb,text),public.read_provider(uuid),app_private.read_provider(uuid) to authenticated;
-- Add indexes for every new FK not already covered by a leading btree prefix.
do $$declare f record;begin
 for f in select c.conrelid,c.conname,c.conkey,n.nspname,t.relname from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where c.contype='f' and n.nspname='private' and (t.relname like 'provider_%' or t.relname in ('operational_events','operational_event_deliveries')) loop
  if not exists(select 1 from pg_index i where i.indrelid=f.conrelid and i.indisvalid and i.indpred is null and array(select x from unnest(i.indkey::smallint[]) with ordinality v(x,ord) where ord<=cardinality(f.conkey) order by ord)=f.conkey) then
   execute format('create index %I on %I.%I (%s)',left(f.relname,30)||'_'||substr(md5(f.conname),1,10)||'_fk',f.nspname,f.relname,(select string_agg(quote_ident(attname),',' order by ord) from unnest(f.conkey) with ordinality a(num,ord) join pg_attribute pa on pa.attrelid=f.conrelid and pa.attnum=a.num));
  end if;
 end loop;
end $$;
commit;
