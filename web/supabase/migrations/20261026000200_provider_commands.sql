begin;
create function app_private.provider_self(p_id uuid,p_administrator boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.provider_profiles p join public.profiles me on me.id=auth.uid() and me.status='active'
 where p.id=p_id and (p.individual_profile_id=me.id or (p.organisation_id is not null and app_private.is_active_member(p.organisation_id)
 and ((not p_administrator and p.created_by=me.id) or exists(select 1 from private.provider_personnel w where w.provider_id=p.id and w.profile_id=me.id
 and w.revoked_at is null and w.valid_from<=now() and (w.valid_until is null or w.valid_until>now())
 and (not p_administrator or w.personnel_role='administrator'))))))
$$;
create function app_private.provider_document(p_provider uuid,p_document uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.document_objects d join private.provider_profiles p on p.id=p_provider
 where d.id=p_document and d.scan_status='clean' and d.archived_at is null
 and d.classification in ('identity','contract','work') and d.customer_account_id is null
 and (d.owner_profile_id=p.individual_profile_id or d.organisation_id=p.organisation_id
 or exists(select 1 from private.provider_personnel w where w.provider_id=p.id and w.profile_id=d.owner_profile_id
 and w.revoked_at is null and w.valid_from<=now() and (w.valid_until is null or w.valid_until>now()))))
$$;
create function app_private.provider_receipt(p_provider uuid,p_action text,p_subject uuid,p_previous text,p_new text,p_reason text,p_permission text) returns void
language plpgsql security definer set search_path='' as $$
declare correlation uuid=gen_random_uuid();event_id uuid;
begin
 insert into private.provider_history(provider_id,action,subject_id,previous_state,new_state,reason,permission_code,actor_id,correlation_id)
 values(p_provider,p_action,p_subject,p_previous,p_new,p_reason,p_permission,auth.uid(),correlation);
 insert into private.operational_events(provider_id,event_code,subject_id,correlation_id) values(p_provider,'provider.'||p_action,p_subject,correlation) returning id into event_id;
 insert into private.operational_event_deliveries(event_id,created_by) values(event_id,auth.uid());
end $$;
create function app_private.guard_provider_configuration() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'provider history must be retained' using errcode='55000';end if;
 if tg_table_name in ('provider_requirement_sets','provider_training_courses','provider_engagements') and old.status<>'draft'
 and ((to_jsonb(new)-array['status','updated_at']) is distinct from (to_jsonb(old)-array['status','updated_at'])
 or not ((old.status='approved' and new.status in ('retired','terminated')) or new.status=old.status)) then
 raise exception 'approved configuration is immutable; prepare a new version' using errcode='55000';end if;
 if tg_table_name='provider_qualifications' and old.status<>'pending' and
 ((to_jsonb(new)-array['status','updated_at']) is distinct from (to_jsonb(old)-array['status','updated_at']) or not (old.status='approved' and new.status='revoked')) then
 raise exception 'decided qualification is immutable' using errcode='55000';end if;
 return new;
end $$;
do $$ declare t text;begin foreach t in array array['provider_requirement_sets','provider_training_courses','provider_engagements','provider_qualifications'] loop
 execute format('create trigger onit_configuration_guard before update or delete on private.%I for each row execute function app_private.guard_provider_configuration()',t);
end loop;end $$;
create function app_private.provider_command(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare p private.provider_profiles;a private.provider_applications;q private.provider_qualifications;e private.provider_engagements;
 course private.provider_training_courses;session private.provider_training_sessions;enrol private.provider_training_enrolments;
 result uuid;subject uuid;old_state text;new_state text;permission text='providers.manage';reason text;
 receipt private.transaction_commands;payload jsonb;owner_id uuid;org_id uuid;can_manage boolean;day_item date;work private.provider_work_schedules;days smallint[];tz text;pool private.provider_capacity;peak numeric;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 or length(p_key) not between 8 and 128 or p_key is null then raise exception 'bounded command and key required' using errcode='23514';end if;
 reason=p_data->>'reason';if length(trim(reason)) not between 1 and 2000 or reason is null then raise exception 'reason required' using errcode='23514';end if;
 payload=jsonb_build_object('provider',p_provider,'action',p_action,'data',p_data);
 perform pg_advisory_xact_lock(hashtextextended('provider-command:'||auth.uid()::text||':'||p_key,0));
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='provider' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action='apply' then
  if p_provider is not null then raise exception 'application identity is selected server-side' using errcode='23514';end if;
  org_id=(p_data->>'organisation_id')::uuid;
  if p_data->>'source'='internal' and not app_private.has_permission('providers.manage',org_id) then raise exception 'internal sourcing requires an authorised recruiter' using errcode='42501';end if;
  owner_id=case when org_id is null then coalesce((p_data->>'profile_id')::uuid,auth.uid()) end;
  if org_id is not null then
   perform 1 from public.organisations where id=org_id and status='active' and organisation_type in ('provider','mixed') for update;
   if not found or not (app_private.is_active_member(org_id) or app_private.has_permission('providers.manage',org_id)) then raise exception 'provider organisation access denied' using errcode='42501';end if;
  else
   perform 1 from public.profiles where id=owner_id and status='active' for update;
   if not found or not (owner_id=auth.uid() or app_private.has_permission('providers.manage')) then raise exception 'applicant access denied' using errcode='42501';end if;
  end if;
  select * into p from private.provider_profiles where individual_profile_id=owner_id or organisation_id=org_id for update;
  if p.id is null then
   insert into private.provider_profiles(individual_profile_id,organisation_id,provider_type,created_by)
   values(owner_id,org_id,p_data->>'provider_type',auth.uid()) returning * into p;
  elsif p.status<>'applicant' or p.provider_type is distinct from p_data->>'provider_type' then raise exception 'provider identity already established' using errcode='55000';end if;
  insert into private.provider_applications(provider_id,revision,source,campaign_id,referrer_id,created_by)
  select p.id,coalesce(max(revision),0)+1,p_data->>'source',(p_data->>'campaign_id')::uuid,(p_data->>'referrer_id')::uuid,auth.uid() from private.provider_applications where provider_id=p.id returning id into result;
  if (p_data->>'campaign_id') is not null and not exists(select 1 from private.provider_recruitment_campaigns c where c.id=(p_data->>'campaign_id')::uuid and c.status='active' and c.starts_at<=now() and (c.ends_at is null or c.ends_at>now())) then raise exception 'campaign not open' using errcode='23514';end if;
  permission='provider.application.self_or_manager';new_state='submitted';
 else
  select * into p from private.provider_profiles where id=p_provider for update;
  if not found then raise exception 'provider access denied' using errcode='42501';end if;
  can_manage=app_private.has_permission('providers.manage',p.organisation_id);
  if p_action in ('approve_application','activate','reactivate','approve_qualification','reject_qualification','approve_engagement','confirm_training','revoke_qualification','revoke_restriction') then
   permission='providers.approve';
   if not app_private.has_permission(permission,p.organisation_id) or app_private.provider_self(p.id) or p.created_by=auth.uid() or p.individual_profile_id=auth.uid()
    or exists(select 1 from private.provider_personnel w where w.provider_id=p.id and w.profile_id=auth.uid()) then raise exception 'independent provider approver required' using errcode='42501';end if;
  elsif not can_manage and not ((p_action in ('availability','weekly_schedule','revoke_schedule','revoke_availability','withdraw') and app_private.provider_self(p.id,true)) or (p_action='withdraw' and p.created_by=auth.uid() and app_private.provider_self(p.id))) then raise exception 'provider manager required' using errcode='42501';end if;
  if p_data->>'expected_revision' is null or (p_data->>'expected_revision')::integer<>p.revision then raise exception 'stale provider revision' using errcode='40001';end if;
  if p.status='offboarded' then raise exception 'provider offboarded' using errcode='55000';end if;
  select * into a from private.provider_applications where provider_id=p.id order by revision desc limit 1 for update;
  subject=(p_data->>'id')::uuid;result=p.id;old_state=p.status;
  case p_action
  when 'screen','interview','reject_application','withdraw','advance_training','approve_application' then
   if a.id is null or a.stage in ('approved','rejected','withdrawn') then raise exception 'no open application' using errcode='55000';end if;
   old_state=a.stage;result=a.id;
   if p_action='screen' then
    if a.stage not in ('submitted','screening') then raise exception 'screening stage closed' using errcode='55000';end if;
    update private.provider_applications set screening_passed=(p_data->>'passed')::boolean,stage=case when (p_data->>'passed')::boolean then 'verification' else 'rejected' end,reviewed_by=auth.uid() where id=a.id;
   elsif p_action='interview' then
    if p_data->>'outcome' not in ('passed','failed','follow_up') or p_data->>'outcome' is null then raise exception 'interview outcome required' using errcode='23514';end if;
    update private.provider_applications set reviewed_by=auth.uid() where id=a.id;
   elsif p_action='advance_training' then
    if a.stage<>'verification' then raise exception 'verification stage required' using errcode='55000';end if;
    update private.provider_applications set stage='training',reviewed_by=auth.uid() where id=a.id;
   elsif p_action='approve_application' then
    if a.stage not in ('verification','training') or not a.screening_passed or a.created_by=auth.uid() or p.created_by=auth.uid() or a.reviewed_by=auth.uid()
    or not exists(select 1 from private.provider_qualifications v where v.provider_id=p.id and v.kind='verification' and v.code='identity' and v.status='approved' and v.valid_from<=now() and (v.valid_until is null or v.valid_until>now()) and (v.document_id is null or app_private.provider_document(p.id,v.document_id))) then raise exception 'screening, identity and independent approval required' using errcode='42501';end if;
    update private.provider_applications set stage='approved',reviewed_by=auth.uid() where id=a.id;
    update private.provider_profiles set status='approved',approved_by=auth.uid(),approved_at=now() where id=p.id;
   else update private.provider_applications set stage=case p_action when 'withdraw' then 'withdrawn' else 'rejected' end,reviewed_by=auth.uid() where id=a.id;
   end if;
   select stage into new_state from private.provider_applications where id=a.id;
  when 'activate','reactivate' then
   if not ((p_action='activate' and p.status='approved') or (p_action='reactivate' and p.status='suspended'))
    or auth.uid()=p.created_by or auth.uid()=p.suspended_by or not exists(select 1 from private.provider_qualifications v where v.provider_id=p.id and v.kind='verification' and v.code='identity' and v.status='approved' and v.valid_from<=now() and (v.valid_until is null or v.valid_until>now()) and (v.document_id is null or app_private.provider_document(p.id,v.document_id))) then raise exception 'independent activation and valid identity required' using errcode='42501';end if;
   update private.provider_profiles set status='active' where id=p.id;new_state='active';
  when 'suspend' then
   if p.status not in ('active','approved') then raise exception 'cannot suspend this state' using errcode='55000';end if;
   update private.provider_profiles set status='suspended',suspended_by=auth.uid() where id=p.id;new_state='suspended';
  when 'offboard' then update private.provider_profiles set status='offboarded' where id=p.id;new_state='offboarded';
  when 'personnel' then
   if p.organisation_id is null or not exists(select 1 from private.organisation_members m join public.profiles pr on pr.id=m.profile_id where m.organisation_id=p.organisation_id and m.profile_id=(p_data->>'profile_id')::uuid and m.status='active' and m.revoked_at is null and (m.valid_until is null or m.valid_until>now()) and pr.status='active') then raise exception 'active organisation personnel required' using errcode='23514';end if;
   insert into private.provider_personnel(provider_id,organisation_id,profile_id,personnel_role,valid_from,valid_until,created_by) values(p.id,p.organisation_id,(p_data->>'profile_id')::uuid,p_data->>'role',(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,auth.uid()) returning id into result;
  when 'revoke_personnel' then
   update private.provider_personnel set revoked_at=now() where id=subject and provider_id=p.id and revoked_at is null returning id into result;if not found then raise exception 'personnel not active' using errcode='55000';end if;
  when 'qualification' then
   if p_data->>'kind'='training' then raise exception 'training requires the enrolment workflow' using errcode='23514';end if;
   if p_data->>'document_id' is not null and not app_private.provider_document(p.id,(p_data->>'document_id')::uuid) then raise exception 'clean provider-owned evidence required' using errcode='42501';end if;
   if p_data->>'subject_profile_id' is not null and (p.individual_profile_id=(p_data->>'subject_profile_id')::uuid or exists(select 1 from private.provider_personnel w where w.provider_id=p.id and w.profile_id=(p_data->>'subject_profile_id')::uuid and w.revoked_at is null)) is distinct from true then raise exception 'foreign execution personnel' using errcode='23514';end if;
   insert into private.provider_qualifications(provider_id,subject_profile_id,kind,code,valid_from,valid_until,document_id,created_by)
   values(p.id,(p_data->>'subject_profile_id')::uuid,p_data->>'kind',p_data->>'code',(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,(p_data->>'document_id')::uuid,auth.uid()) returning id into result;
  when 'approve_qualification','reject_qualification','revoke_qualification' then
   select * into q from private.provider_qualifications where id=subject and provider_id=p.id for update;
   if not found or q.created_by=auth.uid() or q.subject_profile_id=auth.uid() or (p_action='revoke_qualification' and q.status<>'approved') or (p_action<>'revoke_qualification' and q.status<>'pending') then raise exception 'independent qualification decision required' using errcode='42501';end if;
   if q.document_id is not null and not app_private.provider_document(p.id,q.document_id) then raise exception 'clean qualification evidence required' using errcode='42501';end if;
   old_state=q.status;new_state=case p_action when 'approve_qualification' then 'approved' when 'reject_qualification' then 'rejected' else 'revoked' end;
   update private.provider_qualifications set status=new_state,decided_by=case when p_action='revoke_qualification' then decided_by else auth.uid() end,decided_at=case when p_action='revoke_qualification' then decided_at else now() end where id=q.id;result=q.id;
  when 'coverage' then
   if not exists(select 1 from public.service_zones z where z.id=(p_data->>'zone_id')::uuid and z.status='active' and exists(select 1 from private.zone_boundaries_or_coverage c where c.zone_id=z.id and c.verified_at is not null and c.version=(select max(version) from private.zone_boundaries_or_coverage where zone_id=z.id))) then raise exception 'verified active zone required' using errcode='23514';end if;
   insert into private.provider_coverage_areas(provider_id,service_version_id,zone_id,travel_limit_km,valid_from,valid_until,created_by)
   values(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,(p_data->>'travel_limit_km')::numeric,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,auth.uid()) returning id into result;
  when 'availability' then
   insert into private.provider_availability(provider_id,service_version_id,starts_at,ends_at,kind,created_by)
   values(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,p_data->>'kind',auth.uid()) returning id into result;
  when 'revoke_coverage' then
   update private.provider_coverage_areas set revoked_at=now() where id=subject and provider_id=p.id and revoked_at is null returning id into result;
   if not found then raise exception 'coverage not active' using errcode='55000';end if;
  when 'revoke_availability' then
   update private.provider_availability set revoked_at=now() where id=subject and provider_id=p.id and revoked_at is null returning id into result;if not found then raise exception 'availability not active' using errcode='55000';end if;
  when 'weekly_schedule' then
   select z.timezone into tz from public.service_zones z join pg_timezone_names t on t.name=z.timezone where z.id=(p_data->>'zone_id')::uuid and z.status='active';
   if tz is null or jsonb_typeof(p_data->'weekdays') is distinct from 'array' then raise exception 'active zone timezone and weekdays required' using errcode='23514';end if;
   select array_agg(value::smallint) into days from jsonb_array_elements_text(p_data->'weekdays');
   insert into private.provider_work_schedules(provider_id,service_version_id,zone_id,timezone,weekdays,local_start,local_end,valid_from,valid_until,created_by)
   values(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,tz,days,(p_data->>'local_start')::time,(p_data->>'local_end')::time,(p_data->>'valid_from')::date,(p_data->>'valid_until')::date,auth.uid()) returning * into work;
   day_item=work.valid_from;
   while day_item<=work.valid_until loop
    if extract(isodow from day_item)::smallint=any(work.weekdays) then
     insert into private.provider_availability(provider_id,service_version_id,starts_at,ends_at,kind,schedule_id,created_by)
     values(p.id,work.service_version_id,(day_item+work.local_start) at time zone work.timezone,(day_item+work.local_end) at time zone work.timezone,'working',work.id,auth.uid());
    end if;day_item=day_item+1;
   end loop;result=work.id;
  when 'revoke_schedule' then
   update private.provider_work_schedules set revoked_at=now() where id=subject and provider_id=p.id and revoked_at is null returning id into result;
   if not found then raise exception 'schedule not active' using errcode='55000';end if;
   update private.provider_availability set revoked_at=now() where schedule_id=result and provider_id=p.id and revoked_at is null;
  when 'capacity' then
   if (p_data->>'units') !~ '^[0-9]+(\.[0-9]{1,4})?$' then raise exception 'exact positive capacity required' using errcode='23514';end if;
   if p.individual_profile_id is not null and p_data->>'unit' is distinct from 'concurrent_jobs' then raise exception 'individual capacity uses one shared concurrent_jobs pool' using errcode='23514';end if;
   insert into private.provider_capacity(provider_id,unit,units,created_by) values(p.id,p_data->>'unit',(p_data->>'units')::numeric,auth.uid()) returning id into result;
  when 'restriction' then
   insert into private.provider_restrictions(provider_id,service_version_id,zone_id,valid_from,valid_until,reason,created_by) values(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,reason,auth.uid()) returning id into result;
  when 'capacity_change' then
   select * into pool from private.provider_capacity where id=subject and provider_id=p.id for update;
   if not found or p_data->>'units' is null or (p_data->>'units') !~ '^[0-9]+(\.[0-9]{1,4})?$' or p_data->>'status' is null or p_data->>'status' not in ('active','inactive') then raise exception 'valid pool configuration required' using errcode='23514';end if;
   peak=app_private.provider_capacity_used(pool.id,now(),coalesce((select max(ends_at) from private.provider_capacity_reservations where pool_id=pool.id and (status='assigned' or (status='reserved' and expires_at>now()))),now()));
   if (p_data->>'units')::numeric<peak or (p_data->>'status'='inactive' and peak>0) then raise exception 'capacity is still reserved or assigned' using errcode='23514';end if;
   update private.provider_capacity set units=(p_data->>'units')::numeric,status=p_data->>'status' where id=pool.id;result=pool.id;
  when 'revoke_restriction' then
   update private.provider_restrictions set revoked_at=now(),revoked_by=auth.uid() where id=subject and provider_id=p.id and revoked_at is null and created_by<>auth.uid() returning id into result;if not found then raise exception 'independent restriction revocation required' using errcode='42501';end if;
  when 'engagement' then
   if not app_private.provider_document(p.id,(p_data->>'document_id')::uuid) or not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and classification='contract') then raise exception 'clean owned contract required' using errcode='42501';end if;
   if p_data->>'unit_rate' is null or (p_data->>'unit_rate') !~ '^[0-9]+(\.[0-9]{1,4})?$' or not exists(select 1 from public.currencies where id=(p_data->>'currency_id')::uuid and round((p_data->>'unit_rate')::numeric,minor_units)=(p_data->>'unit_rate')::numeric) then raise exception 'currency-precision rate required' using errcode='23514';end if;
   insert into private.provider_engagements(provider_id,service_version_id,zone_id,version,contract_reference,currency_id,unit,unit_rate,obligations,valid_from,valid_until,document_id,created_by)
   values(p.id,(p_data->>'service_version_id')::uuid,(p_data->>'zone_id')::uuid,(p_data->>'version')::integer,p_data->>'contract_reference',(p_data->>'currency_id')::uuid,p_data->>'unit',(p_data->>'unit_rate')::numeric,p_data->>'obligations',(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,(p_data->>'document_id')::uuid,auth.uid()) returning id into result;
  when 'approve_engagement' then
   select * into e from private.provider_engagements where id=subject and provider_id=p.id for update;
   if not found or e.status<>'draft' or e.created_by=auth.uid() or not app_private.provider_document(p.id,e.document_id) then raise exception 'independent engagement approval required' using errcode='42501';end if;
   if exists(select 1 from private.provider_engagements x where x.provider_id=p.id and x.service_version_id=e.service_version_id and x.zone_id=e.zone_id and x.status='approved' and tstzrange(x.valid_from,x.valid_until,'[)')&&tstzrange(e.valid_from,e.valid_until,'[)')) then raise exception 'overlapping engagement' using errcode='23514';end if;
   update private.provider_engagements set status='approved',approved_by=auth.uid(),approved_at=now() where id=e.id;result=e.id;old_state=e.status;new_state='approved';
  when 'terminate_engagement' then
   update private.provider_engagements set status='terminated' where id=subject and provider_id=p.id and status='approved' returning id into result;if not found then raise exception 'approved engagement required' using errcode='55000';end if;
  when 'enrol' then
   select * into session from private.provider_training_sessions where id=(p_data->>'session_id')::uuid;
   if not found or not exists(select 1 from private.provider_training_courses where id=session.course_id and status='approved') then raise exception 'approved training session required' using errcode='23514';end if;
   if p_data->>'subject_profile_id' is not null and (p.individual_profile_id=(p_data->>'subject_profile_id')::uuid or exists(select 1 from private.provider_personnel where provider_id=p.id and profile_id=(p_data->>'subject_profile_id')::uuid and revoked_at is null)) is distinct from true then raise exception 'own personnel required' using errcode='23514';end if;
   insert into private.provider_training_enrolments(provider_id,session_id,subject_profile_id,created_by) values(p.id,session.id,(p_data->>'subject_profile_id')::uuid,auth.uid()) returning id into result;
  when 'assess_training','confirm_training' then
   select * into enrol from private.provider_training_enrolments where id=subject and provider_id=p.id for update;
   if not found then raise exception 'enrolment unavailable' using errcode='42501';end if;
   select * into session from private.provider_training_sessions where id=enrol.session_id;
   select * into course from private.provider_training_courses where id=session.course_id;
   if course.status<>'approved' or session.ends_at>now() then raise exception 'completed approved session required' using errcode='55000';end if;
   if p_action='assess_training' then
    if enrol.status<>'enrolled' or auth.uid()<>session.trainer_id then raise exception 'assigned trainer required' using errcode='42501';end if;
    update private.provider_training_enrolments set attendance_percent=(p_data->>'attendance_percent')::numeric,score=(p_data->>'score')::numeric,assessed_by=auth.uid(),status='assessed' where id=enrol.id;
   else
    if enrol.status<>'assessed' or auth.uid() in (enrol.created_by,enrol.assessed_by) then raise exception 'independent training decision required' using errcode='42501';end if;
    if enrol.score>=course.pass_mark and enrol.attendance_percent>=course.required_attendance then
     if p_data->>'document_id' is not null and not app_private.provider_document(p.id,(p_data->>'document_id')::uuid) then raise exception 'clean owned certificate evidence required' using errcode='42501';end if;
     insert into private.provider_qualifications(provider_id,subject_profile_id,kind,code,valid_from,valid_until,status,decided_by,decided_at,created_by,document_id)
     values(p.id,enrol.subject_profile_id,'training',course.code,session.ends_at,session.ends_at+make_interval(days=>course.certificate_valid_days),'approved',auth.uid(),now(),enrol.assessed_by,(p_data->>'document_id')::uuid) returning id into result;
     update private.provider_training_enrolments set status='passed',qualification_id=result where id=enrol.id;
    else update private.provider_training_enrolments set status='failed' where id=enrol.id;end if;
   end if;result=enrol.id;
  when 'performance' then
   if not app_private.provider_document(p.id,(p_data->>'document_id')::uuid) or (p_data->>'occurred_at')::timestamptz>now() then raise exception 'dated performance evidence required' using errcode='23514';end if;
   insert into private.provider_performance_events(provider_id,metric,successful,observations,source_reference,document_id,occurred_at,created_by)
   values(p.id,p_data->>'metric',(p_data->>'successful')::integer,(p_data->>'observations')::integer,p_data->>'source_reference',(p_data->>'document_id')::uuid,(p_data->>'occurred_at')::timestamptz,auth.uid()) returning id into result;
  else raise exception 'unsupported provider action' using errcode='23514';
  end case;
 end if;
 update private.provider_profiles set revision=revision+1 where id=p.id;
 perform app_private.provider_receipt(p.id,p_action,result,old_state,new_state,reason,permission);
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'provider',p_key,payload,result);
 return result;
end $$;
create function public.provider_command(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid
language sql set search_path='' as $$select app_private.provider_command(p_provider,p_action,p_data,p_key)$$;
revoke all on function public.provider_command(uuid,text,jsonb,text) from public,anon;
grant execute on function app_private.provider_command(uuid,text,jsonb,text),public.provider_command(uuid,text,jsonb,text) to authenticated;
commit;
