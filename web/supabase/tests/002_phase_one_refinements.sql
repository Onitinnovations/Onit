begin;
create function pg_temp.assert_true(p_condition boolean,p_message text) returns text language plpgsql as $$
begin if p_condition is distinct from true then raise exception 'ASSERTION FAILED: %',p_message; end if; return p_message; end $$;
create function pg_temp.expect_error(p_sql text,p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then if sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm; end if; return true; end $$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to anon,authenticated;
create temporary table phase_ids(key text primary key,id uuid not null);
grant select on phase_ids to anon,authenticated;
insert into phase_ids select 'version',v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='home-cleaning';
insert into phase_ids select 'other_version',v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='laundry';

-- Real field/group/schema configuration, no customer booking submissions.
insert into public.service_booking_fields(id,service_version_id,field_key,label,field_type,position)
 select '91000000-0000-0000-0000-000000000001',id,'property_type','Property type','single_choice',0 from phase_ids where key='version';
insert into phase_ids select 'schema',schema_id from public.service_booking_fields where id='91000000-0000-0000-0000-000000000001';
insert into public.service_booking_fields(id,service_version_id,field_key,label,field_type,position,visibility)
 select '91000000-0000-0000-0000-000000000002',id,'bedrooms','Bedrooms','number',1,'conditional' from phase_ids where key='version';
insert into public.service_booking_fields(id,service_version_id,field_key,label,field_type,position,visibility)
 select '91000000-0000-0000-0000-000000000003',id,'internal_note','Internal note','text',2,'hidden' from phase_ids where key='version';
insert into public.service_booking_field_options(field_id,service_version_id,code,label)
 select '91000000-0000-0000-0000-000000000001',id,'flat','Flat' from phase_ids where key='version';
insert into public.service_booking_field_dependencies(schema_id,service_version_id,field_id,depends_on_field_id,operator,comparison_value)
 select f.schema_id,f.service_version_id,'91000000-0000-0000-0000-000000000002',f.id,'equals',to_jsonb('flat'::text)
 from public.service_booking_fields f where f.id='91000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=1 from public.service_booking_forms f where f.service_id=
 (select service_id from public.service_versions where id=(select id from phase_ids where key='version'))),'Form identity automatically bound to service');
select pg_temp.assert_true((select count(*)=1 from public.service_booking_schemas where id=(select id from phase_ids where key='schema')),'Fields bind to one exact versioned schema');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_booking_field_dependencies(schema_id,service_version_id,field_id,depends_on_field_id,operator)
 select schema_id,service_version_id,'91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002','is_present'
 from public.service_booking_fields where id='91000000-0000-0000-0000-000000000001'
$q$,'23514'),'Condition dependency cycles rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_booking_field_dependencies(schema_id,service_version_id,field_id,depends_on_field_id,operator,comparison_value)
 select schema_id,service_version_id,'91000000-0000-0000-0000-000000000002',id,'equals',to_jsonb('unknown-option'::text)
 from public.service_booking_fields where id='91000000-0000-0000-0000-000000000001'
$q$,'23514'),'Unknown conditional choice rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_booking_field_dependencies(schema_id,service_version_id,field_id,depends_on_field_id,operator,comparison_value)
 select schema_id,service_version_id,'91000000-0000-0000-0000-000000000002',id,'greater_than','1'::jsonb
 from public.service_booking_fields where id='91000000-0000-0000-0000-000000000001'
$q$,'23514'),'Numeric comparison on choice field rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$ delete from public.service_booking_field_options where code='flat' $q$,'23514'),'Referenced choice cannot disappear from draft rules');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_fields set field_type='text' where id='91000000-0000-0000-0000-000000000001' $q$,'23514'),'Changing referenced question type rejected');
insert into public.service_booking_field_validation_rules(schema_id,service_version_id,field_id,rule_type,rule_value,error_message)
 select schema_id,service_version_id,id,'minimum',0,'Bedrooms must be nonnegative' from public.service_booking_fields where id='91000000-0000-0000-0000-000000000002';
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_booking_field_validation_rules(schema_id,service_version_id,field_id,rule_type,rule_value,error_message)
 select schema_id,service_version_id,id,'maximum',-1,'Invalid test upper bound' from public.service_booking_fields where id='91000000-0000-0000-0000-000000000002'
$q$,'23514'),'Inconsistent validation bounds rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.service_booking_field_validation_rules(schema_id,service_version_id,field_id,rule_type,rule_value,error_message)
 select schema_id,service_version_id,id,'min_length',1,'Invalid text rule' from public.service_booking_fields where id='91000000-0000-0000-0000-000000000002'
$q$,'23514'),'Incompatible validation rule rejected');
insert into public.service_booking_field_groups(schema_id,service_version_id,group_key,label,position,repeatable,minimum_occurrences,maximum_occurrences)
 select schema_id,service_version_id,'rooms','Rooms',1,true,0,20 from public.service_booking_fields where id='91000000-0000-0000-0000-000000000001';
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_field_groups set maximum_occurrences=101 where group_key='rooms' $q$,'23514'),'Repeatable groups are bounded');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_fields set service_version_id=(select id from phase_ids where key='other_version')
 where id='91000000-0000-0000-0000-000000000003' $q$,'23503'),'Cross-version field/group foreign key rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_versions set pricing_mode='marketplace_bid' where id=(select id from phase_ids where key='version') $q$,'23514'),'Unsupported pricing mode rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_versions set pricing_mode='assessment_based',assessment_required=false where id=(select id from phase_ids where key='version') $q$,'23514'),'Assessment pricing requires assessment');
update public.service_versions set pricing_mode='fixed_price' where id=(select id from phase_ids where key='version');
update public.service_versions set pricing_mode='starting_price' where id=(select id from phase_ids where key='version');
update public.service_versions set pricing_mode='quantity_based' where id=(select id from phase_ids where key='version');
select pg_temp.assert_true((select pricing_mode='quantity_based' from public.service_versions where id=(select id from phase_ids where key='version')),'Multiple pricing modes configurable without prices');

set local role anon;
select pg_temp.assert_true((select count(*)=0 from public.service_booking_fields),'Draft form fields hidden anonymously');
select pg_temp.assert_true((select count(*)=0 from public.service_booking_schemas),'Draft schemas hidden anonymously');
reset role;
update public.service_booking_schemas set status='published',effective_from=now() where id=(select id from phase_ids where key='schema');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_field_options set label='Changed' where code='flat' $q$,'55000'),'Published schema freezes choices while service is still draft');
select pg_temp.assert_true(pg_temp.expect_error($q$ update public.service_booking_field_groups set label='Changed' where group_key='rooms' $q$,'55000'),'Published schema freezes repeatable groups');
update public.service_areas set status='published' where code='home-utilities';
update public.service_families set status='published' where code='cleaning';
update public.services set status='published' where code='home-cleaning';
update public.service_versions set status='published',published_at=now() where id=(select id from phase_ids where key='version');
set local role anon;
select pg_temp.assert_true((select count(*)=1 from public.service_booking_forms),'Published service form identity visible');
select pg_temp.assert_true((select count(*)=1 from public.service_booking_schemas),'Published effective schema visible');
select pg_temp.assert_true((select count(*)=2 from public.service_booking_fields),'Hidden fields excluded from published schema');
select pg_temp.assert_true((select count(*)=1 from public.service_booking_field_dependencies),'Safe published condition visible');
select pg_temp.assert_true((select count(*)=1 from public.service_booking_field_validation_rules),'Published typed validation rule visible');
reset role;

-- Branch-limited corporate users must not acquire account-wide read access.
insert into auth.users(id,raw_user_meta_data) values
 ('92000000-0000-0000-0000-000000000001','{"display_name":"Branch requester"}'),
 ('92000000-0000-0000-0000-000000000002','{"display_name":"Other corporation"}');
insert into public.organisations(id,name,organisation_type,status) values
 ('93000000-0000-0000-0000-000000000001','Synthetic corporate A','customer','active'),
 ('93000000-0000-0000-0000-000000000002','Synthetic corporate B','customer','active');
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select '94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select '94000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002',id,'approved' from public.currencies where code='NGN';
insert into public.corporate_accounts(id,organisation_id,account_reference,approval_status) values
 ('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','TEST-BRANCH-A','approved'),
 ('94000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002','TEST-BRANCH-B','approved');
insert into private.organisation_members(organisation_id,profile_id,status) values
 ('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','active'),
 ('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','active');
insert into public.organisation_locations(id,organisation_id,code,name,address_text) values
 ('95000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','HQ','Central branch','Synthetic HQ'),
 ('95000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000001','WEST','Second branch','Synthetic west'),
 ('95000000-0000-0000-0000-000000000003','93000000-0000-0000-0000-000000000002','HQ','Other HQ','Synthetic other');
insert into public.corporate_account_branches(id,customer_account_id,organisation_id,organisation_location_id,code) values
 ('96000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','HQ'),
 ('96000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000002','WEST'),
 ('96000000-0000-0000-0000-000000000003','94000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000003','HQ');
insert into private.corporate_account_users(id,customer_account_id,organisation_id,profile_id,status,can_request,branch_access) values
 ('97000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','approved',true,'assigned');
insert into private.corporate_account_user_branches(account_user_id,customer_account_id,organisation_id,branch_id) values
 ('97000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into public.corporate_account_branches(customer_account_id,organisation_id,organisation_location_id,code)
 values('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000003','FORGED')
$q$,'23503'),'Corporate branch cannot attach another organisation location');
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.corporate_account_branches),'Requester sees only assigned branch');
select pg_temp.assert_true((select count(*)=1 from public.organisation_locations),'Membership cannot enumerate other corporate locations');
select pg_temp.assert_true((select count(*)=0 from public.customer_profiles),'Branch-only grant does not expose account-wide customer data');
select pg_temp.assert_true(app_private.can_access_branch('96000000-0000-0000-0000-000000000001','request'),'Assigned requester permission allowed');
select pg_temp.assert_true(not app_private.can_access_branch('96000000-0000-0000-0000-000000000001','approve'),'Requester is not implicitly an approver');
select pg_temp.assert_true(not app_private.can_access_branch('96000000-0000-0000-0000-000000000002'),'Unassigned branch denied');
select pg_temp.assert_true(not app_private.can_access_branch('96000000-0000-0000-0000-000000000003'),'Cross-corporate branch denied');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.corporate_billing_profiles','42501'),'Branch requester cannot read centralized billing details');
select pg_temp.assert_true(pg_temp.expect_error('update private.corporate_account_users set can_approve=true','42501'),'Requester cannot self-promote to approver');
reset role;
update private.corporate_account_user_branches set revoked_at=now() where account_user_id='97000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.corporate_account_branches),'Branch revocation applies immediately with same claims');
reset role;
select pg_temp.assert_true((select exists(select 1 from private.audit_logs where subject_table='corporate_account_user_branches'
 and changed_columns @> array['revoked_at'])),'Privileged branch grant change recorded by column name');
select pg_temp.assert_true(not exists(select 1 from private.audit_logs where details::text like '%Synthetic HQ%'),'Audit does not copy sensitive address payloads');

-- Explicit staff organisation scope and team scope never widen to other clients.
insert into public.organisations(id,name,organisation_type,status)
 values('93000000-0000-0000-0000-000000000003','Synthetic OnIt employer','onit','active');
insert into private.employee_profiles(profile_id,organisation_id,employee_number,status)
 values('92000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000003','TEST-SCOPED-STAFF','active');
insert into private.organisation_members(organisation_id,profile_id,status)
 values('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002','active');
insert into private.user_role_assignments(id,profile_id,role_id,scope,organisation_id)
 select '98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002',id,'organisation','93000000-0000-0000-0000-000000000001'
 from private.roles where code='operations_reader';
insert into public.customer_addresses(customer_account_id,label,address_line_1,country_id,state_id)
 select a.id,'Synthetic office','Fixture only',c.id,s.id from public.customer_profiles a
 cross join public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA';
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true(app_private.can_staff_read_customer('94000000-0000-0000-0000-000000000001'),'Scoped staff can read assigned client');
select pg_temp.assert_true(not app_private.can_staff_read_customer('94000000-0000-0000-0000-000000000002'),'Scoped staff cannot read other client');
select pg_temp.assert_true((select count(*)=1 from public.customer_addresses),'Staff child-table RLS follows client organisation scope');
reset role;
update private.user_role_assignments set revoked_at=now() where id='98000000-0000-0000-0000-000000000001';
insert into private.teams(id,organisation_id,code,name) values
 ('99000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','OPS','Operations'),
 ('99000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000001','OTHER','Other team');
insert into private.team_members(team_id,organisation_id,profile_id)
 values('99000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002');
insert into private.user_role_assignments(profile_id,role_id,scope,organisation_id,team_id)
 select '92000000-0000-0000-0000-000000000002',id,'team','93000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000001'
 from private.roles where code='operations_reader';
set local role authenticated;
select pg_temp.assert_true(app_private.has_team_permission('customers.read','99000000-0000-0000-0000-000000000001'),'Staff team permission requires exact active team');
select pg_temp.assert_true(not app_private.has_team_permission('customers.read','99000000-0000-0000-0000-000000000002'),'Team grant does not extend to a sibling team');
select pg_temp.assert_true(not app_private.has_permission('customers.read','93000000-0000-0000-0000-000000000001'),'Team grant cannot become organisation-wide read');
reset role;
update private.team_members set revoked_at=now() where team_id='99000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not app_private.has_team_permission('customers.read','99000000-0000-0000-0000-000000000001'),'Team membership revocation takes effect immediately');
reset role;
insert into private.approval_policies(id,code,version,approval_type,status)
 values('9a000000-0000-0000-0000-000000000001','TEST-CREDIT',1,'credit_terms','active');
insert into private.approval_requests(id,policy_id,requested_by,status)
 values('9a000000-0000-0000-0000-000000000002','9a000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','approved');
select pg_temp.assert_true(pg_temp.expect_error($q$
 insert into private.corporate_credit_terms(customer_account_id,version,payment_days,currency_id,valid_from,status,approval_request_id,created_by,approved_by)
 select '94000000-0000-0000-0000-000000000001',1,7,id,now(),'approved','9a000000-0000-0000-0000-000000000002',
 '92000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002' from public.currencies where code='NGN'
$q$,'23514'),'Credit terms cannot rely on status without independent decision evidence');
insert into private.approval_steps(request_id,requested_by,sequence,decided_by,decision,reason)
 values('9a000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001',1,'92000000-0000-0000-0000-000000000002','approved','Synthetic config review');
insert into private.corporate_credit_terms(customer_account_id,version,payment_days,currency_id,valid_from,status,approval_request_id,created_by,approved_by)
 select '94000000-0000-0000-0000-000000000001',1,7,id,now(),'approved','9a000000-0000-0000-0000-000000000002',
 '92000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002' from public.currencies where code='NGN';
select pg_temp.assert_true(pg_temp.expect_error('update private.corporate_credit_terms set payment_days=14','55000'),'Approved credit terms remain immutable configuration');
insert into private.document_objects(bucket_id,object_name,owner_profile_id,uploaded_by,classification,content_type,byte_size,scan_status)
 values('employee-documents','synthetic-hr/restricted','92000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002','employee','application/pdf',10,'clean');
insert into private.role_permissions(role_id,permission_id)
 select r.id,p.id from private.roles r cross join private.permissions p where r.code='operations_reader' and p.code='documents.read';
insert into private.user_role_assignments(profile_id,role_id,scope)
 select '92000000-0000-0000-0000-000000000002',id,'global' from private.roles where code='operations_reader';
set local role authenticated;
select pg_temp.assert_true(app_private.has_permission('documents.read'),'Synthetic staff has explicit general document permission');
select pg_temp.assert_true(not app_private.can_read_object('employee-documents','synthetic-hr/restricted'),'General document permission cannot expose private HR files');
reset role;
select pg_temp.assert_true((select count(*)=0 from public.service_zones where status='active'),'Synthetic development coverage never becomes operational');
select pg_temp.assert_true(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity),'RLS enabled on all added foundation tables');
select pg_temp.assert_true(not exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
 join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not t.tgisinternal and t.tgenabled='D'),'Migration backfill leaves no disabled guards');
rollback;
