begin;
create function pg_temp.assert_true(p_condition boolean,p_message text) returns text language plpgsql as $$
begin if p_condition is distinct from true then raise exception 'ASSERTION FAILED: %',p_message; end if; return p_message; end $$;
create function pg_temp.expect_error(p_sql text,p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false; exception when others then if sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm; end if; return true; end $$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to authenticated,anon;
create temporary table tx_ids(key text primary key,id uuid not null);
grant select,insert,update on tx_ids to authenticated;
insert into auth.users(id) values
 ('a1000000-0000-0000-0000-000000000001'),('a1000000-0000-0000-0000-000000000002'),
 ('a1000000-0000-0000-0000-000000000003'),('a1000000-0000-0000-0000-000000000004'),
 ('a1000000-0000-0000-0000-000000000005'),('a1000000-0000-0000-0000-000000000006');
insert into tx_ids select 'currency',id from public.currencies where code='NGN';
insert into public.customer_profiles(id,individual_profile_id,currency_id,status)
 select 'a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',id,'approved' from tx_ids where key='currency';
insert into public.customer_profiles(id,individual_profile_id,currency_id,status)
 select 'a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002',id,'approved' from tx_ids where key='currency';
insert into public.customer_addresses(id,customer_account_id,label,address_line_1,country_id,state_id)
 select 'a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Test','Synthetic location',c.id,s.id
 from public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA';
insert into tx_ids select 'version',v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='home-cleaning';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,required,position)
 select id,'bedrooms','Bedrooms','number',true,0 from tx_ids where key='version';
insert into tx_ids select 'schema',schema_id from public.service_booking_fields where field_key='bedrooms';
insert into public.service_booking_field_validation_rules(schema_id,service_version_id,field_id,rule_type,rule_value,error_message)
 select schema_id,service_version_id,id,'minimum',0,'Nonnegative bedrooms' from public.service_booking_fields where field_key='bedrooms';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,required,position)
 select id,'property','Property','single_choice',true,1 from tx_ids where key='version';
insert into public.service_booking_field_options(field_id,service_version_id,code,label)
 select id,service_version_id,'flat','Flat' from public.service_booking_fields where field_key='property';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position,visibility)
 select id,'secret','Internal','text',2,'hidden' from tx_ids where key='version';
insert into public.service_booking_fields(service_version_id,field_key,label,field_type,required,position,visibility)
 select id,'parking','Parking','boolean',true,3,'conditional' from tx_ids where key='version';
insert into public.service_booking_field_dependencies(schema_id,service_version_id,field_id,depends_on_field_id,operator,comparison_value)
 select f.schema_id,f.service_version_id,f.id,src.id,'greater_than','2' from public.service_booking_fields f
 join public.service_booking_fields src on src.field_key='bedrooms' and src.service_version_id=f.service_version_id where f.field_key='parking';
update public.service_booking_schemas set status='published',effective_from=now() where id=(select id from tx_ids where key='schema');
update public.service_areas set status='published' where code='home-utilities';
update public.service_families set status='published' where code='cleaning';
update public.services set status='published' where code='home-cleaning';
update public.service_versions set status='published',published_at=now() where id=(select id from tx_ids where key='version');

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
insert into tx_ids select 'request',public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{}','synthetic-create-1');
select pg_temp.assert_true((select status='draft' from public.service_requests),'Incomplete draft allowed');
select pg_temp.assert_true(public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{}','synthetic-create-1')=(select id from tx_ids where key='request'),'Duplicate creation returns same request');
select pg_temp.assert_true((select count(*)=1 from public.service_requests),'Duplicate creates no extra rows');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{"details":[]}','synthetic-create-1')$q$,'23505'),'Changed idempotency payload rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.create_service_request('a2000000-0000-0000-0000-000000000002',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{}','synthetic-cross-1')$q$,'42501'),'Cross-account creation denied');
select pg_temp.assert_true(pg_temp.expect_error('update public.service_requests set status=''reviewed''','42501'),'Direct status writes denied');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.request_revisions','42501'),'Private answer history denied');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),1,'submit')$q$,'23514'),'Missing required group rejected');
select public.change_service_request((select id from tx_ids where key='request'),1,'amend','{"details":[{"bedrooms":"two","property":"flat"}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),2,'submit')$q$,'23514'),'Answer type checked server side');
select public.change_service_request((select id from tx_ids where key='request'),2,'amend','{"details":[{"bedrooms":-1,"property":"flat"}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),3,'submit')$q$,'23514'),'Numeric validation enforced');
select public.change_service_request((select id from tx_ids where key='request'),3,'amend','{"details":[{"bedrooms":1,"property":"unknown"}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),4,'submit')$q$,'23514'),'Unknown selectable option rejected');
select public.change_service_request((select id from tx_ids where key='request'),4,'amend','{"details":[{"bedrooms":1,"property":"flat","secret":"injected"}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),5,'submit')$q$,'23514'),'Hidden field injection rejected');
select public.change_service_request((select id from tx_ids where key='request'),5,'amend','{"details":[{"bedrooms":3,"property":"flat"}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),6,'submit')$q$,'23514'),'Conditionally required field enforced');
select public.change_service_request((select id from tx_ids where key='request'),6,'amend','{"details":[{"bedrooms":1,"property":"flat","parking":true}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),7,'submit')$q$,'23514'),'Invisible conditional answer rejected');
select public.change_service_request((select id from tx_ids where key='request'),7,'amend','{"details":[{"bedrooms":3,"property":"flat","parking":false}]}');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),7,'submit')$q$,'40001'),'Stale optimistic revision rejected');
select pg_temp.assert_true(public.change_service_request((select id from tx_ids where key='request'),8,'submit')=9,'Valid submission succeeds');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),9,'submit')$q$,'23514'),'Duplicate state transition rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.review_service_request((select id from tx_ids where key='request'),9)$q$,'42501'),'Customer cannot review own request as staff');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.service_requests),'Other individual cannot read request');
select pg_temp.assert_true((select count(*)=0 from public.request_history),'Other individual cannot read history');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),9,'cancel')$q$,'42501'),'Other individual cannot cancel request');
reset role;

-- Real trusted staff roles require active OnIt employment, never user metadata.
insert into public.organisations(id,name,organisation_type,status) values('a4000000-0000-0000-0000-000000000001','Synthetic employer','onit','active');
insert into private.employee_profiles(profile_id,organisation_id,employee_number,status) values
 ('a1000000-0000-0000-0000-000000000003','a4000000-0000-0000-0000-000000000001','SYN-MAKER','active'),
 ('a1000000-0000-0000-0000-000000000004','a4000000-0000-0000-0000-000000000001','SYN-APPROVER','active');
insert into private.roles(code,name) values('synthetic_quote_staff','Synthetic quote staff');
insert into private.role_permissions(role_id,permission_id) select r.id,p.id from private.roles r cross join private.permissions p
 where r.code='synthetic_quote_staff' and p.code in ('requests.read','requests.review','quotes.manage','quotes.approve');
insert into private.user_role_assignments(profile_id,role_id,scope) select u.id,r.id,'global' from public.profiles u cross join private.roles r
 where r.code='synthetic_quote_staff' and u.id in ('a1000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000004');
-- Synthetic tax test configuration, not an assertion of the legal VAT rate.
insert into private.quotation_tax_rules(id,code,version,country_id,rate,valid_from,status)
 select 'a5000000-0000-0000-0000-000000000001','SYNTHETIC_TEST_TAX',1,id,7.5,now(),'active' from public.countries where code='NG';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(public.review_service_request((select id from tx_ids where key='request'),9)=10,'Authorised staff review succeeds');
insert into tx_ids select 'quote',public.prepare_quotation((select id from tx_ids where key='request'),(select id from tx_ids where key='currency'),now()+interval '1 day','Synthetic terms',
 '[{"description":"Synthetic labour","kind":"labour","quantity":"2","unit_price":"100.0050","discount":"10.00","tax_rule_id":"a5000000-0000-0000-0000-000000000001"}]','synthetic-quote-1');
select pg_temp.assert_true((select subtotal=200.01 and discount_total=10 and tax_total=14.25 and total=204.26 from public.quotation_versions),'Exact numeric rounding, discount and configured tax calculation');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from tx_ids where key='quote'),'approve')$q$,'42501'),'Maker cannot approve own quotation');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.prepare_quotation((select id from tx_ids where key='request'),(select id from tx_ids where key='currency'),now()+interval '1 day','Synthetic','[{"description":"bad","kind":"labour","quantity":1,"unit_price":"5"}]','synthetic-quote-bad')$q$,'23514'),'Floating point JSON financial inputs rejected');
insert into tx_ids select 'old_quote',id from tx_ids where key='quote';
update tx_ids set id=public.prepare_quotation((select id from tx_ids where key='request'),(select id from tx_ids where key='currency'),now()+interval '1 day','Revised synthetic terms',
 '[{"description":"Synthetic labour","kind":"labour","quantity":"2","unit_price":"100.0050","discount":"10.00","tax_rule_id":"a5000000-0000-0000-0000-000000000001"}]','synthetic-quote-2') where key='quote';
select pg_temp.assert_true((select status='superseded' from public.quotation_versions where id=(select id from tx_ids where key='old_quote')),'Revision supersedes prior proposal');
select pg_temp.assert_true((select version=2 from public.quotation_versions where id=(select id from tx_ids where key='quote')),'Quotation version increases without overwriting lines');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from public.quotation_versions),'Unapproved quotation hidden from customer');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from tx_ids where key='quote'),'accept')$q$,'23514'),'Unapproved quote cannot be accepted');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000004',true);
select public.decide_quotation((select id from tx_ids where key='quote'),'approve');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.quotation_versions),'Other customer cannot see released quote');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from tx_ids where key='quote'),'accept')$q$,'42501'),'Other customer cannot accept quote');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.quotation_line_items),'Customer sees approved customer-facing line items');
select public.decide_quotation((select id from tx_ids where key='quote'),'accept');
select pg_temp.assert_true(public.decide_quotation((select id from tx_ids where key='quote'),'accept')=(select id from tx_ids where key='quote'),'Acceptance retry is idempotent');
select pg_temp.assert_true((select status='accepted' from public.quotation_versions),'Customer acceptance recorded');
select pg_temp.assert_true(jsonb_typeof(public.read_quotation((select id from tx_ids where key='quote'))->'total')='string','Quotation money RPC returns exact decimal strings');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='request'),10,'cancel')$q$,'23514'),'Accepted scope cannot be cancelled through request command');
select pg_temp.assert_true(pg_temp.expect_error('update public.quotation_versions set total=0','42501'),'Client financial mutation denied');
reset role;
select pg_temp.assert_true(pg_temp.expect_error('update public.quotation_versions set terms=''Changed''','55000'),'Accepted quotation immutable even for migration owner');
select pg_temp.assert_true(pg_temp.expect_error('delete from public.quotation_line_items','55000'),'Quote lines append-only');
select pg_temp.assert_true(pg_temp.expect_error('truncate private.request_revisions','55000'),'Request history truncate blocked');
select pg_temp.assert_true((select count(*)=10 from public.request_history),'Every committed request revision has one history event');
select pg_temp.assert_true((select count(*)=0 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity),'All tables have RLS');

-- Document registry links reuse account ownership and quarantine boundaries.
insert into private.document_objects(id,bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,scan_status) values
 ('a6000000-0000-0000-0000-000000000001','customer-documents','synthetic-clean/content','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','customer','application/pdf',10,'clean'),
 ('a6000000-0000-0000-0000-000000000002','customer-documents','synthetic-pending/content','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','customer','application/pdf',10,'pending'),
 ('a6000000-0000-0000-0000-000000000003','customer-documents','synthetic-foreign/content','a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002','customer','application/pdf',10,'clean');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
insert into tx_ids select 'draft',public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{}','synthetic-draft-2');
select pg_temp.assert_true(public.attach_request_document((select id from tx_ids where key='draft'),'a6000000-0000-0000-0000-000000000001') is not null,'Clean own attachment accepted');
select pg_temp.assert_true(public.attach_request_document((select id from tx_ids where key='draft'),'a6000000-0000-0000-0000-000000000001')=(select id from public.request_attachments where request_id=(select id from tx_ids where key='draft')),'Attachment retry is idempotent');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{}','synthetic-bad-window',p_start=>now()+interval '1 day')$q$,'23514'),'Incomplete scheduling window rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.attach_request_document((select id from tx_ids where key='draft'),'a6000000-0000-0000-0000-000000000002')$q$,'23514'),'Quarantined attachment rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.attach_request_document((select id from tx_ids where key='draft'),'a6000000-0000-0000-0000-000000000003')$q$,'23514'),'Foreign attachment rejected');
select pg_temp.assert_true(public.change_service_request((select id from tx_ids where key='draft'),1,'cancel')=2,'Draft cancellation succeeds');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='draft'),2,'amend','{}')$q$,'23514'),'Cancelled request cannot be amended');
reset role;
insert into public.quotations(id,request_id,created_by)
 select 'ac000000-0000-0000-0000-000000000001',id,'a1000000-0000-0000-0000-000000000003' from tx_ids where key='draft';
insert into public.quotation_versions(id,quotation_id,version,request_revision,currency_id,pricing_mode,status,valid_until,terms,subtotal,discount_total,tax_total,total,approved_by,approved_at,created_by)
 select 'ac000000-0000-0000-0000-000000000002','ac000000-0000-0000-0000-000000000001',1,2,id,'custom_quotation','offered',now()-interval '1 second','Synthetic expired fixture',0,0,0,0,
 'a1000000-0000-0000-0000-000000000004',now()-interval '1 hour','a1000000-0000-0000-0000-000000000003' from tx_ids where key='currency';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation('ac000000-0000-0000-0000-000000000002','accept')$q$,'23514'),'Expired proposal cannot be accepted');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
select public.decide_quotation('ac000000-0000-0000-0000-000000000002','expire');
select pg_temp.assert_true((select status='expired' from public.quotation_versions where id='ac000000-0000-0000-0000-000000000002'),'Authorised expiry records terminal status');
reset role;

-- Corporate branches must retain strict requester and approver boundaries.
insert into public.organisations(id,name,organisation_type,status) values
 ('a7000000-0000-0000-0000-000000000001','Synthetic client A','customer','active'),
 ('a7000000-0000-0000-0000-000000000002','Synthetic client B','customer','active');
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select 'a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001',id,'approved' from tx_ids where key='currency';
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select 'a8000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000002',id,'approved' from tx_ids where key='currency';
insert into public.corporate_accounts(id,organisation_id,account_reference,approval_status) values
 ('a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001','SYN-CORP-1','approved'),
 ('a8000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000002','SYN-CORP-2','approved');
insert into private.organisation_members(organisation_id,profile_id,status) values
 ('a7000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000005','active'),
 ('a7000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000006','active');
insert into private.corporate_account_users(customer_account_id,organisation_id,profile_id,can_request,can_approve,status,branch_access) values
 ('a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000005',true,true,'approved','assigned'),
 ('a8000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000006',true,true,'approved','all');
insert into public.organisation_locations(id,organisation_id,code,name,address_text) values
 ('a9000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001','branch-1','Synthetic branch','Synthetic first address'),
 ('a9000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000001','branch-2','Synthetic second branch','Synthetic second address');
insert into public.corporate_account_branches(id,customer_account_id,organisation_id,organisation_location_id,code) values
 ('aa000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001','a9000000-0000-0000-0000-000000000001','one'),
 ('aa000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001','a9000000-0000-0000-0000-000000000002','two');
insert into private.corporate_account_user_branches(account_user_id,customer_account_id,organisation_id,branch_id)
 select id,customer_account_id,organisation_id,'aa000000-0000-0000-0000-000000000001' from private.corporate_account_users where profile_id='a1000000-0000-0000-0000-000000000005';
insert into public.customer_addresses(id,customer_account_id,label,address_line_1,country_id,state_id)
 select 'ab000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','Branch','Synthetic corporate address',c.id,s.id
 from public.countries c join public.states s on s.country_id=c.id where c.code='NG' and s.code='LA';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
insert into tx_ids select 'corp_request',public.create_service_request('a8000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'ab000000-0000-0000-0000-000000000001','{}','synthetic-corp-1','aa000000-0000-0000-0000-000000000001');
select pg_temp.assert_true((select count(*)=1 from public.service_requests),'Branch requester sees only corporate branch request');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.create_service_request('a8000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'ab000000-0000-0000-0000-000000000001','{}','synthetic-corp-2','aa000000-0000-0000-0000-000000000002')$q$,'42501'),'Unassigned corporate branch request rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.create_service_request('a8000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'ab000000-0000-0000-0000-000000000001','{}','synthetic-corp-3')$q$,'42501'),'Branch requester cannot omit branch to widen access');
reset role;
insert into private.document_objects(id,bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,scan_status) values
 ('ad000000-0000-0000-0000-000000000001','customer-documents','synthetic-branch/content','a8000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000005','customer','application/pdf',10,'clean');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
select public.attach_request_document((select id from tx_ids where key='corp_request'),'ad000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(app_private.can_read_object('customer-documents','synthetic-branch/content'),'Assigned branch member can read linked clean evidence');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000006',true);
select pg_temp.assert_true(not app_private.can_read_object('customer-documents','synthetic-branch/content'),'Other corporation cannot download linked evidence');
select pg_temp.assert_true((select count(*)=0 from public.service_requests),'Unrelated corporation cannot read request');
select pg_temp.assert_true(not app_private.request_access((select id from tx_ids where key='corp_request'),'approve'),'Unrelated corporate approver denied');
reset role;
update private.corporate_account_users set can_request=false where profile_id='a1000000-0000-0000-0000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
select pg_temp.assert_true(app_private.request_access((select id from tx_ids where key='corp_request'),'approve'),'Approver-only branch membership can approve');
select pg_temp.assert_true(not app_private.request_access((select id from tx_ids where key='corp_request'),'request'),'Approver-only membership cannot request');
reset role;
update private.corporate_account_users set branch_access='all' where profile_id='a1000000-0000-0000-0000-000000000005';
update public.service_requests set branch_id=null where id=(select id from tx_ids where key='corp_request');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
select pg_temp.assert_true(app_private.request_access((select id from tx_ids where key='corp_request'),'approve'),'Account-wide approver without requester authority can approve');
select pg_temp.assert_true(not app_private.request_access((select id from tx_ids where key='corp_request'),'request'),'Account-wide approver cannot silently gain requester authority');
reset role;
savepoint final_submission_checks;
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
insert into tx_ids select 'pending_submit',public.create_service_request('a2000000-0000-0000-0000-000000000001',(select id from tx_ids where key='version'),'a3000000-0000-0000-0000-000000000001','{"details":[{"bedrooms":1,"property":"flat"}]}','synthetic-submit-final');
select public.attach_request_document((select id from tx_ids where key='pending_submit'),'a6000000-0000-0000-0000-000000000001');
reset role;
update private.document_objects set scan_status='rejected' where id='a6000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='pending_submit'),1,'submit')$q$,'23514'),'Submission rechecks a previously clean attachment');
reset role;
update private.document_objects set scan_status='clean' where id='a6000000-0000-0000-0000-000000000001';
update public.service_versions set status='retired' where id=(select id from tx_ids where key='version');
set local role authenticated;
select pg_temp.assert_true(pg_temp.expect_error($q$select public.change_service_request((select id from tx_ids where key='pending_submit'),1,'submit')$q$,'23514'),'Submission rechecks service publication after draft creation');
reset role;
rollback to final_submission_checks;
rollback;
