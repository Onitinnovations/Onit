-- Portable PostgreSQL assertions; run in a disposable local database only.
-- Entire fixture transaction is rolled back. These identities are never seeds.
begin;
create function pg_temp.assert_true(p_condition boolean,p_message text) returns text
language plpgsql as $$ begin
  if p_condition is distinct from true then raise exception 'ASSERTION FAILED: %',p_message; end if;
  return p_message;
end $$;
create function pg_temp.expect_error(p_sql text,p_code text) returns boolean
language plpgsql as $$ begin
  execute p_sql; return false;
exception when others then
  if sqlstate<>p_code then raise exception 'Expected SQLSTATE %, got %: %',p_code,sqlstate,sqlerrm; end if;
  return true;
end $$;

grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to anon,authenticated;
insert into auth.users(id,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000001','{"display_name":"Customer A","role":"admin"}'),
 ('10000000-0000-0000-0000-000000000002','{"display_name":"Customer B"}'),
 ('10000000-0000-0000-0000-000000000003','{"display_name":"Corporate A"}'),
 ('10000000-0000-0000-0000-000000000004','{"display_name":"Corporate B"}'),
 ('10000000-0000-0000-0000-000000000005','{"display_name":"Provider fixture"}'),
 ('10000000-0000-0000-0000-000000000006','{"display_name":"Supplier fixture"}'),
 ('10000000-0000-0000-0000-000000000007','{"role":"staff"}'),
 ('10000000-0000-0000-0000-000000000008','{"display_name":"OnIt staff"}');
select pg_temp.assert_true((select count(*)=8 from public.profiles where id between '10000000-0000-0000-0000-000000000001' and '10000000-0000-0000-0000-000000000008'),'Auth inserts provision profiles');
insert into public.profiles(id) select id from auth.users on conflict(id) do nothing;
select pg_temp.assert_true((select count(*)=8 from public.profiles where id between '10000000-0000-0000-0000-000000000001' and '10000000-0000-0000-0000-000000000008'),'Profile backfill is idempotent');
select pg_temp.assert_true((select count(*)=0 from private.user_role_assignments),'Auth metadata cannot grant roles');
insert into public.organisations(id,name,organisation_type,status) values
 ('20000000-0000-0000-0000-000000000001','Corporate fixture A','customer','active'),
 ('20000000-0000-0000-0000-000000000002','Corporate fixture B','customer','active'),
 ('20000000-0000-0000-0000-000000000003','OnIt fixture employer','onit','active');
insert into public.customer_profiles(id,individual_profile_id,currency_id,status)
 select '30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,individual_profile_id,currency_id,status)
 select '30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select '30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select '30000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000002',id,'approved' from public.currencies where code='NGN';
insert into public.corporate_accounts(id,organisation_id,account_reference,approval_status) values
 ('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','TEST-CORP-A','approved'),
 ('30000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000002','TEST-CORP-B','approved');
insert into private.organisation_members(organisation_id,profile_id,status) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','active'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000004','active');
insert into private.corporate_account_users(customer_account_id,organisation_id,profile_id,status,can_request) values
 ('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','approved',true),
 ('30000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000004','approved',false);
insert into public.customer_addresses(id,customer_account_id,label,address_line_1,country_id,state_id)
 select '40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Home','Synthetic address A',c.id,s.id
 from public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA';
insert into public.customer_addresses(id,customer_account_id,label,address_line_1,country_id,state_id)
 select '40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','Home','Synthetic address B',c.id,s.id
 from public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA';

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.profiles),'Customer cannot enumerate other profiles');
select pg_temp.assert_true((select count(*)=1 from public.customer_profiles),'Customer account isolation');
select pg_temp.assert_true((select count(*)=1 from public.customer_addresses),'Customer address isolation');
select pg_temp.assert_true(public.ensure_individual_customer()='30000000-0000-0000-0000-000000000001','Existing customer provisioning is idempotent');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.profiles set status='active' $q$,'42501'),'Customers cannot edit privilege/lifecycle columns');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.customer_addresses set customer_account_id='30000000-0000-0000-0000-000000000002' $q$,'42501'),'Customers cannot reassign address owners');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.employee_profiles','42501'),'HR table inaccessible to customers');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.user_role_assignments','42501'),'Role assignments inaccessible to customers');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.customer_notes','42501'),'Internal CRM notes inaccessible to customers');
select pg_temp.assert_true(not app_private.has_permission('identity.read'),'Customer metadata admin role ignored');
select pg_temp.assert_true(pg_temp.expect_error($q$ select public.prepare_customer_upload('30000000-0000-0000-0000-000000000002','application/pdf',10) $q$,'42501'),'Cross-account upload rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$ select public.prepare_customer_upload('30000000-0000-0000-0000-000000000001','text/html',10) $q$,'23514'),'Unsafe upload content type rejected');
select pg_temp.assert_true((public.prepare_customer_upload('30000000-0000-0000-0000-000000000001','application/pdf',10)->>'bucket')='customer-documents','Owned upload preparation succeeds');
select pg_temp.assert_true((select count(*)=1 from public.customer_documents),'Customer sees own document links');
update public.customer_addresses set label='Updated own label' where id='40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select label='Updated own label' from public.customer_addresses where id='40000000-0000-0000-0000-000000000001'),'Owned address content update allowed');
update public.customer_addresses set label='Attempted cross-tenant change' where id='40000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select count(*)=0 from public.customer_addresses where id='40000000-0000-0000-0000-000000000002'),'Cross-customer update sees zero rows');
select pg_temp.assert_true(pg_temp.expect_error('delete from public.customer_addresses','42501'),'Historical addresses cannot be hard deleted');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true((select count(*)=1 from public.customer_profiles),'Corporate account isolation');
select pg_temp.assert_true((select count(*)=1 from public.corporate_accounts),'Corporate extension isolation');
select pg_temp.assert_true(app_private.can_access_customer('30000000-0000-0000-0000-000000000003',true),'Approved corporate requester allowed');
select pg_temp.assert_true(not app_private.can_access_customer('30000000-0000-0000-0000-000000000004'),'Corporate user cannot read another client');
reset role;
update private.organisation_members set status='revoked',revoked_at=now() where profile_id='10000000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.customer_profiles),'Revoked corporate membership takes effect with same claims');
reset role;
update private.organisation_members set status='active',revoked_at=null,valid_until=now()-interval '1 second' where profile_id='10000000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.customer_profiles),'Expired corporate membership denied');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select pg_temp.assert_true(not app_private.can_access_customer('30000000-0000-0000-0000-000000000004',true),'Read-only corporate user cannot request/write');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
select pg_temp.assert_true((select count(*)=0 from public.customer_profiles),'Provider subject cannot read customer accounts before assignment');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.document_objects','42501'),'Provider cannot enumerate private document registry');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
select pg_temp.assert_true((select count(*)=0 from public.customer_addresses),'Supplier subject cannot read customer addresses');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.service_rate_cards','42501'),'Supplier cannot read private OnIt rate cards');
select pg_temp.assert_true(public.ensure_individual_customer()=public.ensure_individual_customer(),'Multi-role subject can create one own individual account');
reset role;

-- A role assignment without active OnIt employment never grants staff access.
insert into private.roles(id,code,name) values('50000000-0000-0000-0000-000000000001','test-staff','Synthetic identity reader');
insert into private.role_permissions(role_id,permission_id)
 select '50000000-0000-0000-0000-000000000001',id from private.permissions where code='identity.read';
insert into private.user_role_assignments(profile_id,role_id,scope) values
 ('10000000-0000-0000-0000-000000000007','50000000-0000-0000-0000-000000000001','global'),
 ('10000000-0000-0000-0000-000000000008','50000000-0000-0000-0000-000000000001','global');
insert into private.employee_profiles(profile_id,organisation_id,employee_number,status) values
 ('10000000-0000-0000-0000-000000000008','20000000-0000-0000-0000-000000000003','TEST-STAFF-8','active');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000007',true);
select pg_temp.assert_true(not app_private.has_permission('identity.read'),'Role alone cannot grant staff access');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000008',true);
select pg_temp.assert_true(app_private.has_permission('identity.read'),'Active staff with explicit permission allowed');
select pg_temp.assert_true(not app_private.has_permission('documents.read'),'Staff permissions do not widen to document access');
reset role;
update private.employee_profiles set status='exited' where profile_id='10000000-0000-0000-0000-000000000008';
set local role authenticated;
select pg_temp.assert_true(not app_private.has_permission('identity.read'),'Employment exit revokes staff access immediately');
reset role;

-- Structural isolation and geographic constraints are enforced even for workers.
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_locations(customer_account_id,source_address_id,address_snapshot,country_id,state_id)
 select '30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','Forged cross-account source',c.id,s.id
 from public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA'
$q$,'23503'),'Composite location/account FK blocks cross-client source');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.customer_addresses set latitude=95,longitude=1 $q$,'23514'),'Invalid geographic coordinates rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.customer_profiles(individual_profile_id,organisation_id,currency_id)
 select '10000000-0000-0000-0000-000000000007','20000000-0000-0000-0000-000000000003',id from public.currencies where code='NGN'
$q$,'23514'),'Individual and corporate owner XOR enforced');

-- Publication gate and historical immutability; fixtures never seed live services.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true((select count(*)=0 from public.services),'Anonymous cannot read draft services');
select pg_temp.assert_true((select count(*)=0 from public.service_zones),'Anonymous cannot read unverified pilot zone');
select pg_temp.assert_true(pg_temp.expect_error('select * from public.customer_profiles','42501'),'Anonymous has no customer-table grant');
select pg_temp.assert_true(pg_temp.expect_error('select public.ensure_individual_customer()','42501'),'Anonymous cannot provision customer account');
reset role;
update public.service_areas set status='published' where code='home-utilities';
update public.service_families set status='published' where code='laundry';
update public.services set status='published' where code='laundry';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position)
 select v.id,'instructions','Instructions','text',0 from public.service_versions v join public.services s on s.id=v.service_id where s.code='laundry';
update public.service_booking_schemas set status='published',effective_from=now() where service_id=(select id from public.services where code='laundry');
update public.service_versions set status='published',published_at=now() where service_id=(select id from public.services where code='laundry');
set local role anon;
select pg_temp.assert_true((select count(*)=1 from public.services),'Anonymous sees published service hierarchy');
select pg_temp.assert_true((select count(*)=1 from public.service_versions),'Anonymous sees only published current versions');
select pg_temp.assert_true((select count(*)=1 from public.service_booking_fields),'Published form field visible');
reset role;
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_versions set description='Rewrite history' where status='published' $q$,'55000'),'Published service version cannot change');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_fields set label='Rewrite historical form' $q$,'55000'),'Published booking field cannot change');
select pg_temp.assert_true(pg_temp.expect_error($q$ insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position)
 select id,'late','Late field','text',1 from public.service_versions where status='published' $q$,'55000'),'New child cannot alter a published version');
select pg_temp.assert_true(pg_temp.expect_error('truncate public.service_versions cascade','55000'),'Truncate cannot erase historical versions');

insert into private.service_rate_cards(id,service_version_id,currency_id,code,version,valid_from)
 select '80000000-0000-0000-0000-000000000001',v.id,c.id,'TEST-RATE',1,now()
 from public.service_versions v join public.services s on s.id=v.service_id
 cross join public.currencies c where s.code='laundry' and c.code='NGN';
insert into private.service_pricing_rules(rate_card_id,service_version_id,code,rule_type,unit_amount,currency_id)
 select id,service_version_id,'TEST-LINE','fixed',1.23,currency_id from private.service_rate_cards where code='TEST-RATE';
update private.service_rate_cards set status='approved',approved_at=now() where code='TEST-RATE';
select pg_temp.assert_true(pg_temp.expect_error($q$ update private.service_pricing_rules set unit_amount=2 where code='TEST-LINE' $q$,'55000'),'Approved rate card price history cannot be rewritten');
select pg_temp.assert_true(pg_temp.expect_error($q$ update private.service_rate_cards set valid_from=now()+interval '1 day' where code='TEST-RATE' $q$,'55000'),'Approved rate card terms cannot be rewritten');

select pg_temp.assert_true(pg_temp.expect_error('update private.audit_logs set action=''forged''','55000'),'Audit updates rejected');
select pg_temp.assert_true(pg_temp.expect_error('delete from private.audit_logs','55000'),'Audit deletes rejected');
select pg_temp.assert_true(pg_temp.expect_error('truncate private.audit_logs','55000'),'Audit truncate rejected');
select pg_temp.assert_true((select count(*)>0 from private.audit_logs),'Access changes leave audit evidence');
select pg_temp.assert_true(pg_temp.expect_error($q$ update private.system_configurations set value='true'::jsonb where key='wallet.live_funding' and status='active' $q$,'55000'),'Live funding default cannot be silently rewritten');

-- Approval decision rows are independently authored and immutable.
insert into private.approval_policies(id,code,version,approval_type,status)
 values('60000000-0000-0000-0000-000000000001','TEST-EXPENSE',1,'expense','active');
insert into private.approval_requests(id,policy_id,requested_by)
 values('60000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000007');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into private.approval_steps(request_id,requested_by,sequence,decided_by,decision,reason)
 values('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000007',1,'10000000-0000-0000-0000-000000000007','approved','self')
$q$,'23514'),'Maker cannot approve own request');

-- Registry-backed storage policy assertions (SQL only, not Storage HTTP tests).
insert into private.document_objects(id,bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,scan_status) values
 ('70000000-0000-0000-0000-000000000001','customer-documents','fixture-a/clean','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','customer','application/pdf',10,'clean'),
 ('70000000-0000-0000-0000-000000000002','customer-documents','fixture-b/pending','30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','customer','application/pdf',10,'pending'),
 ('70000000-0000-0000-0000-000000000003','customer-documents','fixture-a/pending','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','customer','application/pdf',10,'pending');
insert into storage.objects(bucket_id,name) values('customer-documents','fixture-a/clean');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from storage.objects),'Customer sees own clean stored object');
select pg_temp.assert_true(not app_private.can_read_object('customer-documents','fixture-a/pending'),'Quarantined upload is not downloadable');
select pg_temp.assert_true(not app_private.can_upload_object('customer-documents','fixture-b/pending'),'Other tenant upload authorization denied');
select pg_temp.assert_true(not app_private.can_upload_object('customer-documents','path-forgery'),'Unregistered upload path denied');
insert into storage.objects(bucket_id,name) values('customer-documents','fixture-a/pending');
select pg_temp.assert_true(pg_temp.expect_error($q$ insert into storage.objects(bucket_id,name) values('customer-documents','fixture-b/pending') $q$,'42501'),'Storage policy rejects cross-account upload');
select pg_temp.assert_true(pg_temp.expect_error($q$ insert into storage.objects(bucket_id,name) values('customer-documents','forged') $q$,'42501'),'Storage policy rejects path forgery');
select pg_temp.assert_true((select count(*)=1 from storage.objects),'Pending uploaded object stays quarantined');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects),'Other customer cannot read clean file');
reset role;
select pg_temp.assert_true(pg_temp.expect_error($q$ update private.document_objects set customer_account_id='30000000-0000-0000-0000-000000000002'
 where id='70000000-0000-0000-0000-000000000001' $q$,'55000'),'File registry ownership cannot be reassigned');
select pg_temp.assert_true((select count(*)=7 from storage.buckets where not public),'All seven sensitive buckets are private');
select pg_temp.assert_true((select count(*)=1 from storage.buckets where public and id='marketing-assets'),'Only marketing assets bucket is public');

-- Catalog-level coverage checks are evaluated as the migration owner.
select pg_temp.assert_true(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity),'Every foundation table has RLS');
select pg_temp.assert_true(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private','app_private') and p.prosecdef and not coalesce(p.proconfig @> array['search_path=""'],false)),
 'All definer functions pin an empty search path');
select pg_temp.assert_true(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosecdef),'No exposed security-definer RPCs');
select pg_temp.assert_true(not has_schema_privilege('authenticated','private','USAGE'),'Private schema not directly available to authenticated users');
select pg_temp.assert_true(not has_schema_privilege('anon','public','CREATE'),'Anonymous cannot create public schema objects');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.customer_profiles','INSERT'),'Browser cannot directly create arbitrary customer ownership');
select pg_temp.assert_true(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace,
 lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 where n.nspname='app_private' and a.grantee=0 and a.privilege_type='EXECUTE'),'Internal helpers do not grant PUBLIC execution');
rollback;
