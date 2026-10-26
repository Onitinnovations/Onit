begin;
create function pg_temp.assert_true(p_condition boolean,p_message text) returns text language plpgsql as $$begin if p_condition is distinct from true then raise exception 'ASSERTION FAILED: %',p_message;end if;return p_message;end$$;
create function pg_temp.expect_error(p_sql text,p_code text) returns boolean language plpgsql as $$begin execute p_sql;return false;exception when others then if sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm;end if;return true;end$$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to authenticated;
create temporary table personnel_ids(key text primary key,id uuid not null);grant select,insert,update on personnel_ids to authenticated;
insert into auth.users(id) select ('d1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,5) i;
insert into public.organisations(id,name,organisation_type,status) values
 ('d2000000-0000-0000-0000-000000000001','Synthetic resource employer','onit','active'),
 ('d2000000-0000-0000-0000-000000000002','Synthetic contractor one','provider','active'),
 ('d2000000-0000-0000-0000-000000000003','Synthetic contractor two','provider','active');
insert into private.employee_profiles(profile_id,organisation_id,employee_number,status) select ('d1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'d2000000-0000-0000-0000-000000000001','SYN-RESOURCE-'||i,'active' from generate_series(3,4) i;
insert into private.roles(code,name) values('synthetic_personnel_resources','Synthetic resource role');
insert into private.role_permissions(role_id,permission_id) select r.id,p.id from private.roles r cross join private.permissions p where r.code='synthetic_personnel_resources' and p.code like 'providers.%';
insert into private.user_role_assignments(profile_id,role_id,scope) select e.profile_id,r.id,'global' from private.employee_profiles e cross join private.roles r where e.employee_number like 'SYN-RESOURCE-%' and r.code='synthetic_personnel_resources';
insert into private.organisation_members(organisation_id,profile_id,status) select o.id,'d1000000-0000-0000-0000-000000000001','active' from public.organisations o where o.id in ('d2000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000003');
-- Approved fixture parties only in this disposable transaction. Actual onboarding is tested in 005.
insert into private.provider_profiles(id,organisation_id,provider_type,status,approved_by,approved_at,created_by) values
 ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','processing_partner','active','d1000000-0000-0000-0000-000000000004',now(),'d1000000-0000-0000-0000-000000000003'),
 ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000003','processing_partner','active','d1000000-0000-0000-0000-000000000004',now(),'d1000000-0000-0000-0000-000000000003');
insert into private.provider_personnel(provider_id,organisation_id,profile_id,personnel_role,valid_from,created_by) select id,organisation_id,'d1000000-0000-0000-0000-000000000001','executing_worker',now()-interval '1 day','d1000000-0000-0000-0000-000000000003' from private.provider_profiles where id in ('d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002');
insert into public.service_families(service_area_id,code,name,status) select id,'synthetic-personnel-work','Synthetic worker resource','published' from public.service_areas where code='home-utilities';
insert into public.services(service_family_id,code,name,slug,status) select id,'synthetic-personnel-work','Synthetic worker resource','synthetic-personnel-work','published' from public.service_families where code='synthetic-personnel-work';
insert into public.service_versions(service_id,version,description) select id,1,'Synthetic resource scope' from public.services where code='synthetic-personnel-work';
insert into personnel_ids select 'service',v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-personnel-work';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position) select id,'note','Note','text',0 from personnel_ids where key='service';
update public.service_booking_schemas set status='published',effective_from=now() where service_version_id=(select id from personnel_ids where key='service');
update public.service_areas set status='published' where code='home-utilities' and status='draft';
update public.service_versions set status='published',published_at=now() where id=(select id from personnel_ids where key='service');
insert into public.service_zones(state_id,code,name,status) select id,'synthetic-personnel-zone','Synthetic worker coverage','active' from public.states where code='LA';
insert into personnel_ids select 'zone',id from public.service_zones where code='synthetic-personnel-zone';
insert into private.zone_boundaries_or_coverage(zone_id,state_id,city_id,version,verified_at) select z.id,z.state_id,c.id,1,now() from public.service_zones z join public.cities c on c.state_id=z.state_id where z.code='synthetic-personnel-zone' and c.code='lagos-operations';
insert into private.provider_requirement_sets(service_version_id,provider_type,zone_id,version,valid_from,requirements,capacity_unit,engagement_required,status,approved_by,approved_at,created_by)
 select s.id,'processing_partner',z.id,1,now()-interval '1 day','[{"kind":"skill","code":"handling","scope":"worker","document_required":false}]','kg',false,'approved','d1000000-0000-0000-0000-000000000004',now(),'d1000000-0000-0000-0000-000000000003' from personnel_ids s cross join personnel_ids z where s.key='service' and z.key='zone';
insert into private.provider_qualifications(provider_id,kind,code,subject_profile_id,valid_from,status,decided_by,decided_at,created_by)
 select p.id,q.kind,q.code,q.subject,now()-interval '1 day','approved','d1000000-0000-0000-0000-000000000004',now(),'d1000000-0000-0000-0000-000000000003' from private.provider_profiles p cross join (values('verification','identity',null::uuid),('skill','handling','d1000000-0000-0000-0000-000000000001'::uuid)) q(kind,code,subject) where p.id in ('d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002');
insert into private.provider_capacity(provider_id,unit,units,created_by) select id,'kg',100,'d1000000-0000-0000-0000-000000000003' from private.provider_profiles where id in ('d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002');
insert into private.provider_coverage_areas(provider_id,service_version_id,zone_id,valid_from,created_by) select p.id,s.id,z.id,now()-interval '1 day','d1000000-0000-0000-0000-000000000003' from private.provider_profiles p cross join personnel_ids s cross join personnel_ids z where p.id in ('d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002') and s.key='service' and z.key='zone';
insert into private.provider_availability(provider_id,service_version_id,starts_at,ends_at,kind,created_by) select p.id,s.id,now(),now()+interval '3 days','working','d1000000-0000-0000-0000-000000000003' from private.provider_profiles p cross join personnel_ids s where p.id in ('d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002') and s.key='service';
create function pg_temp.resource_actor(p_n integer) returns void language plpgsql as $$begin perform set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-'||lpad(p_n::text,12,'0'),true);end$$;
create function pg_temp.resource_eligible(p_provider uuid default 'd3000000-0000-0000-0000-000000000001') returns jsonb language sql as $$select public.provider_eligibility(p_provider,(select id from personnel_ids where key='service'),(select id from personnel_ids where key='zone'),now()+interval '1 day',now()+interval '1 day 1 hour','10','d1000000-0000-0000-0000-000000000001')$$;
create function pg_temp.resource_cmd(p_action text,p_data jsonb,p_actor integer default 3) returns uuid language plpgsql as $$begin perform pg_temp.resource_actor(p_actor);return public.personnel_command(p_action,p_data||jsonb_build_object('reason','Synthetic personnel resource'),gen_random_uuid()::text);end$$;
grant execute on function pg_temp.resource_actor(integer),pg_temp.resource_eligible(uuid),pg_temp.resource_cmd(text,jsonb,integer) to authenticated;
set local role authenticated;
select pg_temp.resource_actor(3);
select pg_temp.assert_true(not (pg_temp.resource_eligible()->>'eligible')::boolean,'Organisation pool alone cannot establish human capacity or availability');
insert into personnel_ids values('resource',pg_temp.resource_cmd('capacity',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','version',1,'units','1','valid_from',now()-interval '1 day','valid_until',now()+interval '1 year')));
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.resource_cmd('approve_capacity',jsonb_build_object('id',(select id from personnel_ids where key='resource')))$q$,'42501'),'Human capacity maker cannot approve');
select pg_temp.resource_cmd('approve_capacity',jsonb_build_object('id',(select id from personnel_ids where key='resource')),4);
select pg_temp.assert_true(not (pg_temp.resource_eligible()->>'eligible')::boolean,'Approved human capacity does not imply availability');
insert into personnel_ids values('calendar',pg_temp.resource_cmd('availability',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','start',now(),'end',now()+interval '3 days','kind','working'),1));
select pg_temp.resource_actor(3);
select pg_temp.assert_true((pg_temp.resource_eligible()->>'eligible')::boolean,'Configured qualified scheduled worker becomes eligible');
select pg_temp.assert_true(pg_temp.resource_eligible()->>'worker_capacity_requested'='1','Processing kilograms do not become human workload units');
insert into personnel_ids values('blackout',pg_temp.resource_cmd('availability',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','start',now()+interval '1 day','end',now()+interval '2 days','kind','blackout'),1));
select pg_temp.resource_actor(3);
select pg_temp.assert_true(not (pg_temp.resource_eligible()->>'eligible')::boolean,'Personal blackout blocks work for every contracting business');
select pg_temp.resource_cmd('revoke_availability',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','id',(select id from personnel_ids where key='blackout')),1);
select pg_temp.resource_actor(5);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.read_personnel_resource('d1000000-0000-0000-0000-000000000001')$q$,'42501'),'Unrelated profile cannot inspect personal calendar');
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.resource_cmd('availability',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','start',now(),'end',now()+interval '1 day','kind','working'),5)$q$,'42501'),'Unrelated profile cannot alter calendar');
select pg_temp.resource_actor(1);
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.resource_cmd('capacity',jsonb_build_object('profile_id','d1000000-0000-0000-0000-000000000001','version',2,'units','99','valid_from',now()),1)$q$,'42501'),'Worker cannot increase their own authorised capacity');
select pg_temp.assert_true(jsonb_array_length(public.read_personnel_resource('d1000000-0000-0000-0000-000000000001')->'capacity')=1,'Worker can inspect own authorised resources');
select pg_temp.resource_actor(3);
select pg_temp.assert_true(pg_temp.expect_error($q$select app_private.provider_party_reservation('d3000000-0000-0000-0000-000000000001','reserve','{}','bypass-reservation')$q$,'42501'),'Legacy party-only helper cannot bypass human reservation');
insert into personnel_ids values('reservation',public.provider_reservation('d3000000-0000-0000-0000-000000000001','reserve',jsonb_build_object('service_version_id',(select id from personnel_ids where key='service'),'zone_id',(select id from personnel_ids where key='zone'),'worker_id','d1000000-0000-0000-0000-000000000001','start',now()+interval '1 day','end',now()+interval '1 day 1 hour','units','10','expires_at',now()+interval '1 hour','purpose_reference','SYNTHETIC-WORKER-RESERVATION','reason','Synthetic personnel check'),'synthetic-worker-reserve'));
select pg_temp.assert_true(not (pg_temp.resource_eligible('d3000000-0000-0000-0000-000000000002')->>'eligible')::boolean,'Worker cannot be allocated by a second business during first reservation');
select pg_temp.assert_true(pg_temp.resource_eligible('d3000000-0000-0000-0000-000000000002')->'reasons' @> '[{"code":"personnel_capacity_exceeded"}]','Human over-allocation has an explicit explainable reason');
select public.provider_reservation('d3000000-0000-0000-0000-000000000001','release',jsonb_build_object('id',(select id from personnel_ids where key='reservation'),'reason','Synthetic resource release'),'synthetic-worker-release');
select pg_temp.assert_true((pg_temp.resource_eligible('d3000000-0000-0000-0000-000000000002')->>'eligible')::boolean,'Release restores shared human capacity');
reset role;
select pg_temp.assert_true(pg_temp.expect_error($q$update private.provider_personnel_capacity set units=99 where id=(select id from personnel_ids where key='resource')$q$,'55000'),'Approved personal resource terms immutable');
select pg_temp.assert_true((select count(*)=2 from pg_tables where schemaname='private' and tablename in ('provider_personnel_capacity','provider_personnel_availability') and rowsecurity),'Personal resource tables have default-deny RLS');
insert into private.provider_capacity_reservations(pool_id,provider_id,starts_at,ends_at,units,expires_at,purpose_reference,worker_profile_id,worker_units,created_by)
 select c.id,c.provider_id,now()+interval '2 days'+make_interval(hours=>i),now()+interval '2 days'+make_interval(hours=>i+1),1,now()+interval '3 hours','SYNTHETIC-PEAK-'||i,'d1000000-0000-0000-0000-000000000001',1,'d1000000-0000-0000-0000-000000000003' from private.provider_capacity c cross join generate_series(0,1) i where c.provider_id='d3000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select app_private.provider_capacity_used(id,now()+interval '2 days',now()+interval '2 days 2 hours')=1 from private.provider_capacity where provider_id='d3000000-0000-0000-0000-000000000001'),'Adjacent half-open intervals consume peak one, not two');
select pg_temp.assert_true(app_private.personnel_used('d1000000-0000-0000-0000-000000000001',now()+interval '2 days',now()+interval '2 days 2 hours')=1,'Shared human peak respects simultaneous end and start');
insert into private.provider_capacity_reservations(pool_id,provider_id,starts_at,ends_at,units,expires_at,purpose_reference,worker_profile_id,worker_units,created_by)
 select c.id,c.provider_id,now()+interval '2 days 30 minutes',now()+interval '2 days 90 minutes',0.5,now()+interval '3 hours','SYNTHETIC-PEAK-OVERLAP','d1000000-0000-0000-0000-000000000001',0.5,'d1000000-0000-0000-0000-000000000003' from private.provider_capacity c where c.provider_id='d3000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select app_private.provider_capacity_used(id,now()+interval '2 days',now()+interval '2 days 2 hours')=1.5 from private.provider_capacity where provider_id='d3000000-0000-0000-0000-000000000001'),'Overlapping exact fractional provider units produce correct peak');
select pg_temp.assert_true(app_private.personnel_used('d1000000-0000-0000-0000-000000000001',now()+interval '2 days',now()+interval '2 days 2 hours')=1.5,'Overlapping exact human resource units produce correct peak');
update private.provider_capacity_reservations set status='released' where purpose_reference like 'SYNTHETIC-PEAK-%';
rollback;
