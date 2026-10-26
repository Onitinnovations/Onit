begin;
create function pg_temp.assert_true(p_condition boolean,p_message text) returns text language plpgsql as $$ begin if p_condition is distinct from true then raise exception 'ASSERTION FAILED: %',p_message; end if;return p_message;end $$;
create function pg_temp.expect_error(p_sql text,p_code text) returns boolean language plpgsql as $$ begin execute p_sql;return false;exception when others then if sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm;end if;return true;end $$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to authenticated;
create temporary table price_ids(key text primary key,id uuid not null);
grant select,insert,update on price_ids to authenticated;
insert into auth.users(id) select ('b1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,10) i;
insert into public.organisations(id,name,organisation_type,status) values('b2000000-0000-0000-0000-000000000001','Synthetic pricing employer','onit','active');
insert into public.customer_profiles(id,individual_profile_id,currency_id,status) select 'b3000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,individual_profile_id,currency_id,status) select 'b3000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002',id,'approved' from public.currencies where code='NGN';
insert into private.document_objects(id,bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,scan_status) values
 ('bb000000-0000-0000-0000-000000000001','work-evidence','synthetic-assessment/clean','b3000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000006','work','image/jpeg',10,'clean'),
 ('bb000000-0000-0000-0000-000000000002','work-evidence','synthetic-assessment/foreign','b3000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000006','work','image/jpeg',10,'clean'),
 ('bb000000-0000-0000-0000-000000000003','work-evidence','synthetic-assessment/pending','b3000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000006','work','image/jpeg',10,'pending');
insert into private.employee_profiles(profile_id,organisation_id,employee_number,status)
 select ('b1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'b2000000-0000-0000-0000-000000000001','SYN-PRICE-'||i,'active' from generate_series(3,6) i;
insert into private.roles(code,name) values('synthetic_pricing','Synthetic pricing test role');
insert into private.role_permissions(role_id,permission_id) select r.id,p.id from private.roles r cross join private.permissions p where r.code='synthetic_pricing' and p.code in
 ('requests.read','requests.review','quotes.manage','quotes.approve','pricing.manage','pricing.approve','assessments.manage','assessments.perform','assessments.approve','quotes.override.request','quotes.override.approve');
insert into private.user_role_assignments(profile_id,role_id,scope) select e.profile_id,r.id,'global' from private.employee_profiles e cross join private.roles r where e.employee_number like 'SYN-PRICE-%' and r.code='synthetic_pricing';
update public.service_areas set status='published' where code='home-utilities';
insert into public.service_families(service_area_id,code,name,status) select id,'synthetic-pricing','Synthetic pricing test','published' from public.service_areas where code='home-utilities';
insert into private.quotation_tax_rules(id,code,version,country_id,rate,valid_from,status) select 'b4000000-0000-0000-0000-000000000001','SYNTHETIC_PERCENT',1,id,7.5,now()-interval '1 day','active' from public.countries where code='NG';
insert into private.quotation_tax_rules(id,code,version,country_id,rate,valid_from,status) select 'b4000000-0000-0000-0000-000000000002','SYNTHETIC_FUTURE',1,id,7.5,now()+interval '1 day','active' from public.countries where code='NG';
create function pg_temp.price_request(p_mode text,p_account uuid default 'b3000000-0000-0000-0000-000000000001',p_branch uuid default null) returns uuid language plpgsql as $$
declare s uuid;v uuid;schema_id uuid;loc uuid;req uuid;cu public.customer_profiles;cl uuid;
begin
 select * into strict cu from public.customer_profiles where id=p_account;
 insert into public.services(service_family_id,code,name,slug) select id,gen_random_uuid()::text,'Synthetic priced service',gen_random_uuid()::text from public.service_families where code='synthetic-pricing' returning id into s;
 insert into public.service_versions(service_id,version,description,pricing_mode,assessment_required) values(s,1,'Synthetic pricing fixture',p_mode,p_mode='assessment_based') returning id into v;
 insert into public.service_variants(service_version_id,code,name) values(v,'basic','Synthetic basic package');
 insert into public.service_options(service_version_id,code,name) values(v,'extra','Synthetic optional extra') returning id into cl;
 insert into public.service_option_values(option_id,service_version_id,code,label) values(cl,v,'extra','Synthetic extra');
 insert into public.service_checklists(service_version_id,code,checklist_type,name) values(v,'inspection','assessment','Synthetic inspection') returning id into cl;
 insert into public.service_checklist_items(checklist_id,service_version_id,item_key,label,position) values(cl,v,'measure','Measurement inspected',0);
 insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position) values(v,'notes','Notes','text',0) returning service_booking_fields.schema_id into schema_id;
 update public.service_booking_schemas set status='published',effective_from=now() where id=schema_id;
 update public.services set status='published' where id=s;
 update public.service_versions set status='published',published_at=now() where id=v;
 insert into public.service_locations(customer_account_id,address_snapshot,country_id,state_id,city_id,created_by)
 select p_account,'Synthetic test site',c.id,st.id,ci.id,'b1000000-0000-0000-0000-000000000001' from public.countries c join public.states st on st.country_id=c.id join public.cities ci on ci.state_id=st.id where c.code='NG' and st.code='LA' and ci.code='lagos-operations' returning id into loc;
 insert into public.service_requests(customer_account_id,organisation_id,branch_id,service_id,service_version_id,booking_schema_id,service_location_id,status,created_by)
 values(p_account,cu.organisation_id,p_branch,s,v,schema_id,loc,'reviewed',coalesce(cu.individual_profile_id,'b1000000-0000-0000-0000-000000000007')) returning id into req;
 return req;
end $$;
create function pg_temp.price_card(p_request uuid,p_config jsonb,p_rules jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.service_requests;currency uuid;
begin
 select * into r from public.service_requests where id=p_request;
 select currency_id into currency from public.customer_profiles where id=r.customer_account_id;
 return public.create_pricing_card(jsonb_build_object('service_version_id',r.service_version_id,'currency_id',currency,'code',gen_random_uuid(),'version',1,'valid_from',now()-interval '1 day','valid_until',now()+interval '10 days')||p_config,p_rules);
end $$;
grant execute on function pg_temp.price_card(uuid,jsonb,jsonb) to authenticated;
insert into price_ids values('fixed',pg_temp.price_request('fixed_price')),('quantity',pg_temp.price_request('quantity_based')),('starting',pg_temp.price_request('starting_price')),('assessment',pg_temp.price_request('assessment_based')),('custom',pg_temp.price_request('custom_quotation'));
insert into price_ids select 'package',v.id from public.service_variants v join public.service_requests r on r.service_version_id=v.service_version_id where r.id=(select id from price_ids where key='fixed');
insert into price_ids select 'option',o.id from public.service_option_values o join public.service_requests r on r.service_version_id=o.service_version_id where r.id=(select id from price_ids where key='fixed');
insert into price_ids select 'assessment_check',i.id from public.service_checklist_items i join public.service_requests r on r.service_version_id=i.service_version_id where r.id=(select id from price_ids where key='assessment');
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.price_card((select id from price_ids where key='fixed'),'{}','[]')$q$,'23514'),'Configuration input bounded before authority checks');
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.price_card((select id from price_ids where key='fixed'),'{}','[{"code":"base","rule_type":"fixed","unit_amount":"1","description":"Test"}]')$q$,'42501'),'Customer cannot create prices');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'fixed_card',pg_temp.price_card((select id from price_ids where key='fixed'),jsonb_build_object('variant_id',(select id from price_ids where key='package')),
 jsonb_build_array(jsonb_build_object('code','base','rule_type','fixed','unit_amount','100','description','Synthetic fixed package','internal_unit_cost','60','tax_rule_id','b4000000-0000-0000-0000-000000000001'),
 jsonb_build_object('code','extra','rule_type','fixed','unit_amount','5','description','Synthetic option','option_value_id',(select id from price_ids where key='option'))));
select pg_temp.assert_true(pg_temp.expect_error($q$select public.approve_pricing_card((select id from price_ids where key='fixed_card'))$q$,'42501'),'Price maker cannot approve own card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.approve_pricing_card((select id from price_ids where key='fixed_card'));
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='fixed'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Synthetic'),'missing-package')$q$,'23514'),'Required package selection cannot be omitted');
insert into price_ids select 'fixed_quote',public.generate_quotation((select id from price_ids where key='fixed'),jsonb_build_object('variant_id',(select id from price_ids where key='package'),'option_values',jsonb_build_array((select id from price_ids where key='option')::text),'valid_until',now()+interval '1 day','terms','Synthetic'),'fixed-quote-key');
select pg_temp.assert_true((select total=112.5 from public.quotation_versions where id=(select id from price_ids where key='fixed_quote')),'Fixed package plus optional charge and selective tax');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.prepare_quotation((select id from price_ids where key='fixed'),(select id from public.currencies where code='NGN'),now()+interval '1 day','Bypass','[{"description":"Bypass","kind":"service","quantity":"1","unit_price":"1"}]','manual-bypass-key')$q$,'23514'),'Manual API cannot bypass fixed pricing');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='fixed'),jsonb_build_object('variant_id',(select id from price_ids where key='package'),'overrides','{"base":"80"}'::jsonb,'valid_until',now()+interval '1 day','terms','Test'),'override-no-reason')$q$,'42501'),'Override needs permission and reason');
insert into price_ids select 'override_quote',public.generate_quotation((select id from price_ids where key='fixed'),jsonb_build_object('variant_id',(select id from price_ids where key='package'),'overrides','{"base":"80"}'::jsonb,'override_reason','Synthetic approved deviation','valid_until',now()+interval '1 day','terms','Test'),'override-reason-key');
select pg_temp.assert_true((select total=86 from public.quotation_versions where id=(select id from price_ids where key='override_quote')),'Override price is calculated exactly');
reset role;
select pg_temp.assert_true((select internal_cost_estimate=60 and override_requested from private.quotation_commercial_context where id=(select id from price_ids where key='override_quote')),'Internal costs and override evidence stored privately');
select pg_temp.assert_true(pg_temp.expect_error($q$update private.service_pricing_rules set unit_amount=0 where rate_card_id=(select id from price_ids where key='fixed_card')$q$,'55000'),'Approved pricing rules are immutable');
delete from private.role_permissions where role_id=(select id from private.roles where code='synthetic_pricing') and permission_id=(select id from private.permissions where code='quotes.override.approve');
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='override_quote'),'approve')$q$,'42501'),'Ordinary quote approval cannot approve an override');
reset role;
insert into private.role_permissions(role_id,permission_id) select r.id,p.id from private.roles r cross join private.permissions p where r.code='synthetic_pricing' and p.code='quotes.override.approve';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.decide_quotation((select id from price_ids where key='override_quote'),'approve');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(not (public.read_quotation((select id from price_ids where key='override_quote')) ? 'internal_cost_estimate'),'Customer DTO excludes costs');
select pg_temp.assert_true(pg_temp.expect_error('select * from private.quotation_commercial_context','42501'),'Customer cannot access commercial context');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'quantity_card',pg_temp.price_card((select id from price_ids where key='quantity'),'{"minimum_service_charge":"350","discount_percent":"10"}',
 '[{"code":"units","rule_type":"per_unit","unit_amount":"100","minimum_quantity":"2","minimum_charge":"300","description":"Synthetic quantity","charge_kind":"labour"}]');
insert into price_ids select 'starting_card',pg_temp.price_card((select id from price_ids where key='starting'),'{}','[{"code":"base","rule_type":"fixed","unit_amount":"40","description":"Synthetic starting charge"}]');
insert into price_ids select 'assessment_card',pg_temp.price_card((select id from price_ids where key='assessment'),'{}','[{"code":"units","rule_type":"per_unit","unit_amount":"10","description":"Measured labour"}]');
insert into price_ids select 'assessment_draft',public.prepare_quotation((select id from price_ids where key='assessment'),(select id from public.currencies where code='NGN'),now()+interval '1 day','Draft only','[{"description":"Uninspected","kind":"service","quantity":"1","unit_price":"10"}]','assessment-draft-key');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.approve_pricing_card(id) from price_ids where key in ('quantity_card','starting_card','assessment_card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='quantity'),jsonb_build_object('quantities','{"units":"1"}'::jsonb,'valid_until',now()+interval '1 day','terms','Test'),'quantity-too-low')$q$,'23514'),'Configured minimum quantity enforced');
insert into price_ids select 'quantity_quote',public.generate_quotation((select id from price_ids where key='quantity'),jsonb_build_object('quantities','{"units":"2"}'::jsonb,'valid_until',now()+interval '1 day','terms','Test'),'quantity-good-key');
select pg_temp.assert_true((select total=350 and discount_total=20 from public.quotation_versions where id=(select id from price_ids where key='quantity_quote')),'Quantity, discount, line minimum and service minimum combine exactly');
insert into price_ids select 'starting_quote',public.generate_quotation((select id from price_ids where key='starting'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Scoped starting price'),'starting-good-key');
select pg_temp.assert_true((select total=40 and pricing_mode='starting_price' from public.quotation_versions where id=(select id from price_ids where key='starting_quote')),'Starting-price method retained in quote');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='assessment'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Test'),'assessment-gate-key')$q$,'23514'),'Assessment-based generation requires approved assessment');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.prepare_quotation((select id from price_ids where key='assessment'),(select id from public.currencies where code='NGN'),now()+interval '1 day','Bypass','[{"description":"Uninspected","kind":"service","quantity":"1","unit_price":"1"}]','assessment-manual-bypass')$q$,'23514'),'Manual assessment pricing cannot bypass an approved rate card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='assessment_draft'),'approve')$q$,'23514'),'Legacy manual release cannot bypass assessment gate');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'assessment_id',public.assessment_command((select id from price_ids where key='assessment'),'create','{"mode":"remote","idempotency_key":"assessment-first-key"}');
select pg_temp.assert_true(public.assessment_command((select id from price_ids where key='assessment'),'create','{"mode":"remote","idempotency_key":"assessment-first-key"}')=(select id from price_ids where key='assessment_id'),'Assessment create retry is idempotent');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'create','{"mode":"physical","idempotency_key":"assessment-first-key"}')$q$,'23505'),'Assessment idempotency rejects changed intent');
select public.assessment_command((select id from price_ids where key='assessment'),'schedule',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'assessor_id','b1000000-0000-0000-0000-000000000006','start',now()+interval '1 hour','end',now()+interval '2 hours'));
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'complete',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'measurements','{"units":"5"}'::jsonb,'checklist_answers','{}'::jsonb,'findings','Test'))$q$,'42501'),'Unassigned staff cannot complete assessment');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000006',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'evidence',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'document_id','bb000000-0000-0000-0000-000000000002'))$q$,'23514'),'Cross-client assessment evidence rejected');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'evidence',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'document_id','bb000000-0000-0000-0000-000000000003'))$q$,'23514'),'Quarantined assessment evidence rejected');
select public.assessment_command((select id from price_ids where key='assessment'),'evidence',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'document_id','bb000000-0000-0000-0000-000000000001'));
select pg_temp.assert_true(app_private.can_read_object('work-evidence','synthetic-assessment/clean'),'Assigned internal assessor can read linked clean evidence');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'complete',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'measurements','{"units":"5"}'::jsonb,'checklist_answers','{}'::jsonb,'findings','Test'))$q$,'23514'),'Required inspection checklist enforced');
select public.assessment_command((select id from price_ids where key='assessment'),'complete',jsonb_build_object('id',(select id from price_ids where key='assessment_id'),'measurements','{"units":"5"}'::jsonb,'checklist_answers',
 jsonb_build_object((select id from price_ids where key='assessment_check')::text,true),'findings','Synthetic measured scope'));
select pg_temp.assert_true(pg_temp.expect_error($q$select public.assessment_command((select id from price_ids where key='assessment'),'approve',jsonb_build_object('id',(select id from price_ids where key='assessment_id')))$q$,'42501'),'Assessor cannot self-approve findings');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.assessment_command((select id from price_ids where key='assessment'),'approve',jsonb_build_object('id',(select id from price_ids where key='assessment_id')));
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='assessment'),jsonb_build_object('quantities','{"units":"1"}'::jsonb,'valid_until',now()+interval '1 day','terms','Test'),'measurement-forgery')$q$,'23514'),'Quote cannot substitute approved measurements');
insert into price_ids select 'assessment_quote',public.generate_quotation((select id from price_ids where key='assessment'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Measured scope'),'assessment-good-key');
select pg_temp.assert_true((select total=50 from public.quotation_versions where id=(select id from price_ids where key='assessment_quote')),'Assessment measurements generate exact quotation');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.decide_quotation((select id from price_ids where key='assessment_quote'),'approve');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select public.assessment_command((select id from price_ids where key='assessment'),'create','{"mode":"physical","idempotency_key":"assessment-revision-key"}');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='assessment_quote'),'accept')$q$,'23514'),'New assessment revision invalidates unaccepted quotation');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.read_assessment((select id from price_ids where key='assessment_id'))$q$,'42501'),'Customer cannot read private assessment calculations');
reset role;
select pg_temp.assert_true(pg_temp.expect_error($q$update private.site_assessments set findings='forged' where id=(select id from price_ids where key='assessment_id')$q$,'55000'),'Approved assessment immutable');

-- Multiple independent approvals use the existing versioned policy registry.
insert into private.approval_policies(id,code,version,approval_type,status,minimum_approvers,threshold_amount,currency_id)
 select 'b5000000-0000-0000-0000-000000000001','SYN-TWO-APPROVERS',1,'quotation','active',2,100,id from public.currencies where code='NGN';
insert into price_ids values('threshold',pg_temp.price_request('fixed_price')),('future',pg_temp.price_request('fixed_price'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'threshold_card',pg_temp.price_card((select id from price_ids where key='threshold'),'{"approval_policy_id":"b5000000-0000-0000-0000-000000000001"}','[{"code":"base","rule_type":"fixed","unit_amount":"150","description":"Threshold test"}]');
insert into price_ids select 'future_card',pg_temp.price_card((select id from price_ids where key='future'),jsonb_build_object('valid_from',now()+interval '2 days'),'[{"code":"base","rule_type":"fixed","unit_amount":"20","description":"Future test"}]');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.approve_pricing_card(id) from price_ids where key in ('threshold_card','future_card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='future'),jsonb_build_object('valid_until',now()+interval '3 days','terms','Test'),'future-price-key')$q$,'23514'),'Future-effective prices excluded');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.retire_pricing_card((select id from price_ids where key='future_card'),'Synthetic withdrawal','retire-future-key')$q$,'42501'),'Pricing maker cannot retire their own approved configuration');
insert into price_ids select 'threshold_quote',public.generate_quotation((select id from price_ids where key='threshold'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Test'),'threshold-price-key');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.retire_pricing_card((select id from price_ids where key='future_card'),'Synthetic withdrawal','retire-future-key');
select pg_temp.assert_true(public.retire_pricing_card((select id from price_ids where key='future_card'),'Synthetic withdrawal','retire-future-key')=(select id from price_ids where key='future_card'),'Retirement retry is idempotent');
select pg_temp.assert_true(public.read_pricing_card((select id from price_ids where key='future_card'))->>'status'='retired','Independent retirement preserves historical configuration');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='quantity_quote'),'approve')$q$,'23514'),'New stronger policy cannot be bypassed by an older draft');
select public.decide_quotation((select id from price_ids where key='starting_quote'),'approve');
select pg_temp.assert_true((select status='offered' from public.quotation_versions where id=(select id from price_ids where key='starting_quote')),'Below-threshold quotation needs only one independent approval');
select public.decide_quotation((select id from price_ids where key='threshold_quote'),'approve');
select public.decide_quotation((select id from price_ids where key='threshold_quote'),'approve');
select pg_temp.assert_true((select status='draft' from public.quotation_versions where id=(select id from price_ids where key='threshold_quote')),'Repeated first approval cannot satisfy two-person threshold');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000005',true);
select public.decide_quotation((select id from price_ids where key='threshold_quote'),'approve');
select pg_temp.assert_true((select status='offered' from public.quotation_versions where id=(select id from price_ids where key='threshold_quote')),'Two independent votes release quotation');
reset role;

-- Currency precision: synthetic currencies only, never production seed values.
insert into public.currencies(code,name,minor_units) values('XTA','Synthetic zero-decimal',0),('XTB','Synthetic three-decimal',3);
update public.customer_profiles set currency_id=(select id from public.currencies where code='XTA') where id='b3000000-0000-0000-0000-000000000001';
insert into price_ids values('zero',pg_temp.price_request('custom_quotation'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'zero_quote',public.prepare_quotation((select id from price_ids where key='zero'),(select id from public.currencies where code='XTA'),now()+interval '1 day','Zero scale','[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"10.6","tax_rule_id":"b4000000-0000-0000-0000-000000000001"}]','zero-currency-key');
select pg_temp.assert_true((select total=12 and money_scale=0 from public.quotation_versions where id=(select id from price_ids where key='zero_quote')),'Zero minor-unit gross and tax rounding');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.prepare_quotation((select id from price_ids where key='zero'),(select id from public.currencies where code='XTA'),now()+interval '1 day','Bad discount','[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"10","discount":"0.1"}]','bad-discount-key')$q$,'23514'),'Discount precision follows currency');
reset role;
update public.customer_profiles set currency_id=(select id from public.currencies where code='XTB') where id='b3000000-0000-0000-0000-000000000001';
insert into price_ids values('three',pg_temp.price_request('custom_quotation'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'three_quote',public.prepare_quotation((select id from price_ids where key='three'),(select id from public.currencies where code='XTB'),now()+interval '1 day','Three scale','[{"description":"Synthetic","kind":"materials","quantity":"1","unit_price":"1.2345","tax_rule_id":"b4000000-0000-0000-0000-000000000001"}]','three-currency-key');
select pg_temp.assert_true((select total=1.328 and money_scale=3 from public.quotation_versions where id=(select id from price_ids where key='three_quote')),'Three minor-unit gross and tax rounding');
select pg_temp.assert_true(jsonb_typeof(public.read_quotation((select id from price_ids where key='three_quote'))->'total')='string','Currency-aware RPC amounts remain decimal strings');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.prepare_quotation((select id from price_ids where key='three'),(select id from public.currencies where code='XTB'),now()+interval '1 day','Future tax','[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"1","tax_rule_id":"b4000000-0000-0000-0000-000000000002"}]','future-tax-key')$q$,'23514'),'Future tax configuration excluded');
reset role;

-- Zone applicability is validated against existing verified coverage records.
update public.customer_profiles set currency_id=(select id from public.currencies where code='NGN') where id='b3000000-0000-0000-0000-000000000001';
insert into price_ids values('zoned',pg_temp.price_request('fixed_price'));
insert into public.service_zones(id,state_id,code,name,timezone,status) select 'b6000000-0000-0000-0000-000000000001',id,'synthetic-price-zone','Synthetic price zone','Africa/Lagos','active' from public.states where code='LA';
insert into private.zone_boundaries_or_coverage(zone_id,state_id,city_id,version,verified_at) select 'b6000000-0000-0000-0000-000000000001',state_id,id,1,now() from public.cities where code='lagos-operations';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'zone_card',pg_temp.price_card((select id from price_ids where key='zoned'),'{"zone_id":"b6000000-0000-0000-0000-000000000001"}','[{"code":"base","rule_type":"fixed","unit_amount":"20","description":"Synthetic zoned price"}]');
insert into price_ids select 'overlap_card',pg_temp.price_card((select id from price_ids where key='zoned'),'{"zone_id":"b6000000-0000-0000-0000-000000000001"}','[{"code":"base","rule_type":"fixed","unit_amount":"30","description":"Synthetic overlap"}]');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.approve_pricing_card((select id from price_ids where key='zone_card'));
select pg_temp.assert_true(pg_temp.expect_error($q$select public.approve_pricing_card((select id from price_ids where key='overlap_card'))$q$,'23514'),'Overlapping approved pricing versions rejected');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='zoned'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Test'),'zone-omitted-key')$q$,'23514'),'Omitting zone cannot bypass applicable zone pricing');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='zoned'),jsonb_build_object('zone_id','b6000000-0000-0000-0000-000000000002','valid_until',now()+interval '1 day','terms','Test'),'zone-spoof-key')$q$,'23514'),'Unverified zone rejected');
insert into price_ids select 'zone_quote',public.generate_quotation((select id from price_ids where key='zoned'),jsonb_build_object('zone_id','b6000000-0000-0000-0000-000000000001','valid_until',now()+interval '1 day','terms','Test'),'zone-good-key');
select pg_temp.assert_true((select total=20 from public.quotation_versions where id=(select id from price_ids where key='zone_quote')),'Verified zone selects effective scoped price');
select pg_temp.assert_true(public.generate_quotation((select id from price_ids where key='zoned'),jsonb_build_object('zone_id','b6000000-0000-0000-0000-000000000001','valid_until',now()+interval '1 day','terms','Test'),'zone-good-key')=(select id from price_ids where key='zone_quote'),'Generated quote retry preserves original snapshot');
select pg_temp.assert_true(pg_temp.expect_error($q$select pg_temp.price_card((select id from price_ids where key='zoned'),'{}','[{"code":"bad","rule_type":"fixed","unit_amount":"NaN","description":"Bad"}]')$q$,'23514'),'Non-finite configuration amount rejected');
reset role;

-- Corporate agreements and two independent customer-side approvals.
insert into public.organisations(id,name,organisation_type,status) values
 ('b7000000-0000-0000-0000-000000000001','Synthetic commercial client A','customer','active'),
 ('b7000000-0000-0000-0000-000000000002','Synthetic commercial client B','customer','active');
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select 'b8000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001',id,'approved' from public.currencies where code='NGN';
insert into public.customer_profiles(id,organisation_id,currency_id,status)
 select 'b8000000-0000-0000-0000-000000000002','b7000000-0000-0000-0000-000000000002',id,'approved' from public.currencies where code='NGN';
insert into public.corporate_accounts(id,organisation_id,account_reference,approval_status) values
 ('b8000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001','SYN-PRICING-CORP-A','approved'),
 ('b8000000-0000-0000-0000-000000000002','b7000000-0000-0000-0000-000000000002','SYN-PRICING-CORP-B','approved');
insert into private.organisation_members(organisation_id,profile_id,status) select 'b7000000-0000-0000-0000-000000000001',('b1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'active' from generate_series(7,9) i;
insert into private.organisation_members(organisation_id,profile_id,status) values('b7000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000010','active');
insert into private.corporate_account_users(customer_account_id,organisation_id,profile_id,can_request,can_approve,status,branch_access)
 select 'b8000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001',('b1000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,i=7,i<>7,'approved','assigned' from generate_series(7,9) i;
insert into private.corporate_account_users(customer_account_id,organisation_id,profile_id,can_request,can_approve,status) values('b8000000-0000-0000-0000-000000000002','b7000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000010',true,true,'approved');
insert into public.organisation_locations(id,organisation_id,code,name,address_text) values
 ('b9000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001','pricing-one','Synthetic first branch','Synthetic address'),
 ('b9000000-0000-0000-0000-000000000002','b7000000-0000-0000-0000-000000000001','pricing-two','Synthetic second branch','Synthetic address');
insert into public.corporate_account_branches(id,customer_account_id,organisation_id,organisation_location_id,code) values
 ('ba000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000001','one'),
 ('ba000000-0000-0000-0000-000000000002','b8000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000002','two');
insert into private.corporate_account_user_branches(account_user_id,customer_account_id,organisation_id,branch_id) select id,customer_account_id,organisation_id,'ba000000-0000-0000-0000-000000000001' from private.corporate_account_users where customer_account_id='b8000000-0000-0000-0000-000000000001';
insert into price_ids values('corporate',pg_temp.price_request('fixed_price','b8000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001'));
create function pg_temp.clone_price_request(p_request uuid,p_account uuid,p_branch uuid) returns uuid language plpgsql as $$
declare r public.service_requests;customer public.customer_profiles;loc uuid;req uuid;
begin
 select * into r from public.service_requests where id=p_request;select * into customer from public.customer_profiles where id=p_account;
 insert into public.service_locations(customer_account_id,address_snapshot,country_id,state_id,city_id,created_by) select p_account,'Synthetic shared service',country_id,state_id,city_id,'b1000000-0000-0000-0000-000000000007' from public.service_locations where id=r.service_location_id returning id into loc;
 insert into public.service_requests(customer_account_id,organisation_id,branch_id,service_id,service_version_id,booking_schema_id,service_location_id,status,created_by)
 values(p_account,customer.organisation_id,p_branch,r.service_id,r.service_version_id,r.booking_schema_id,loc,'reviewed','b1000000-0000-0000-0000-000000000007') returning id into req;return req;
end $$;
insert into price_ids values('other_branch',pg_temp.clone_price_request((select id from price_ids where key='corporate'),'b8000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000002')),
 ('other_corporation',pg_temp.clone_price_request((select id from price_ids where key='corporate'),'b8000000-0000-0000-0000-000000000002',null));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'corp_policy',public.commercial_policy('create',jsonb_build_object('code','SYN-CUSTOMER-TWO','version',1,'approval_side','customer','customer_account_id','b8000000-0000-0000-0000-000000000001','branch_id','ba000000-0000-0000-0000-000000000001','minimum_approvers',2,'threshold_amount','0','currency_id',(select id from public.currencies where code='NGN')));
select pg_temp.assert_true(pg_temp.expect_error($q$select public.commercial_policy('approve',jsonb_build_object('id',(select id from price_ids where key='corp_policy')))$q$,'42501'),'Policy maker cannot activate own approval threshold');
insert into price_ids select 'global_corp_card',pg_temp.price_card((select id from price_ids where key='corporate'),'{}','[{"code":"base","rule_type":"fixed","unit_amount":"100","description":"Default price"}]');
insert into price_ids select 'corp_card',pg_temp.price_card((select id from price_ids where key='corporate'),'{"customer_account_id":"b8000000-0000-0000-0000-000000000001","branch_id":"ba000000-0000-0000-0000-000000000001","contract_reference":"SYNTHETIC-AGREEMENT"}','[{"code":"base","rule_type":"fixed","unit_amount":"80","description":"Negotiated branch price"}]');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.commercial_policy('approve',jsonb_build_object('id',(select id from price_ids where key='corp_policy')));
select public.approve_pricing_card(id) from price_ids where key in ('global_corp_card','corp_card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'corp_quote',public.generate_quotation((select id from price_ids where key='corporate'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Corporate scope'),'corp-price-key');
select pg_temp.assert_true((select total=80 from public.quotation_versions where id=(select id from price_ids where key='corp_quote')),'Exact corporate branch receives negotiated price');
insert into price_ids select 'other_branch_quote',public.generate_quotation((select id from price_ids where key='other_branch'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Other branch'),'other-branch-price-key');
insert into price_ids select 'other_corp_quote',public.generate_quotation((select id from price_ids where key='other_corporation'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Other corporation'),'other-corp-price-key');
select pg_temp.assert_true((select count(*)=2 from public.quotation_versions where id in (select id from price_ids where key in ('other_branch_quote','other_corp_quote')) and total=100),'Unrelated branch and corporation cannot inherit negotiated pricing');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='corporate'),jsonb_build_object('valid_until',now()+interval '11 days','terms','Overlong agreement'),'contract-expiry-key')$q$,'23514'),'Quotation cannot outlive pricing contract');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.decide_quotation((select id from price_ids where key='corp_quote'),'approve');
select public.decide_quotation((select id from price_ids where key='other_branch_quote'),'approve');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000005',true);
select public.decide_quotation((select id from price_ids where key='other_branch_quote'),'approve');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000007',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='corp_quote'),'accept')$q$,'42501'),'Corporate requester cannot act as approver');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000010',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='corp_quote'),'accept')$q$,'42501'),'Other client cannot approve corporate quotation');
select pg_temp.assert_true((select count(*)=0 from public.quotation_versions where id=(select id from price_ids where key='corp_quote')),'Other client cannot read corporate quotation');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000008',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.decide_quotation((select id from price_ids where key='other_branch_quote'),'accept')$q$,'42501'),'Assigned corporate approver cannot approve another branch');
select pg_temp.assert_true((select count(*)=0 from public.quotation_versions where id=(select id from price_ids where key='other_branch_quote')),'Assigned corporate approver cannot read another branch quote');
select public.decide_quotation((select id from price_ids where key='corp_quote'),'accept');
select public.decide_quotation((select id from price_ids where key='corp_quote'),'accept');
select pg_temp.assert_true((select status='offered' from public.quotation_versions where id=(select id from price_ids where key='corp_quote')),'Single corporate vote and retry cannot satisfy threshold');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000009',true);
select public.decide_quotation((select id from price_ids where key='corp_quote'),'accept');
select pg_temp.assert_true((select status='accepted' from public.quotation_versions where id=(select id from price_ids where key='corp_quote')),'Two distinct corporate approvers accept quotation');
select pg_temp.assert_true(pg_temp.expect_error($q$select public.read_quotation_commercial((select id from price_ids where key='corp_quote'))$q$,'42501'),'Corporate approvers cannot read internal commercial estimates');
reset role;
select pg_temp.assert_true(pg_temp.expect_error($q$update public.quotation_versions set total=0 where id=(select id from price_ids where key='corp_quote')$q$,'55000'),'Accepted configured quotation remains immutable');
insert into price_ids values('custom_configured',pg_temp.price_request('custom_quotation')),('expired',pg_temp.price_request('fixed_price'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'custom_card',pg_temp.price_card((select id from price_ids where key='custom_configured'),'{"minimum_service_charge":"50","discount_percent":"10"}','[{"code":"scoped","rule_type":"assessment_quote","minimum_charge":"40","description":"Custom scoped work"}]');
insert into price_ids select 'expired_card',pg_temp.price_card((select id from price_ids where key='expired'),jsonb_build_object('valid_from',now()-interval '10 days','valid_until',now()-interval '1 day'),'[{"code":"base","rule_type":"fixed","unit_amount":"10","description":"Historical price"}]');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.approve_pricing_card(id) from price_ids where key in ('custom_card','expired_card');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.generate_quotation((select id from price_ids where key='expired'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Test'),'expired-pricing-key')$q$,'23514'),'Expired pricing is unavailable');
insert into price_ids select 'custom_configured_quote',public.generate_quotation((select id from price_ids where key='custom_configured'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Custom scope','manual_lines','[{"description":"Custom labour","kind":"labour","quantity":"1","unit_price":"30"},{"description":"Custom materials","kind":"materials","quantity":"1","unit_price":"5"}]'::jsonb),'custom-configured-key');
select pg_temp.assert_true((select total=50 and discount_total=3.5 from public.quotation_versions where id=(select id from price_ids where key='custom_configured_quote')),'Configured custom lines respect discounts and minimum charges');
select pg_temp.assert_true((public.read_quotation_commercial((select id from price_ids where key='custom_configured_quote'))->>'internal_cost_complete')='false','Unknown internal costs are explicitly marked incomplete');
reset role;
insert into public.currencies(code,name,minor_units) values('XTC','Synthetic four-decimal',4),('XTD','Synthetic one-decimal',1);
update public.customer_profiles set currency_id=(select id from public.currencies where code='XTC') where id='b3000000-0000-0000-0000-000000000001';
insert into price_ids values('four',pg_temp.price_request('custom_quotation'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'four_quote',public.prepare_quotation((select id from price_ids where key='four'),(select id from public.currencies where code='XTC'),now()+interval '1 day','Four scale','[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"1.2345","tax_rule_id":"b4000000-0000-0000-0000-000000000001"}]','four-currency-key');
select pg_temp.assert_true((select total=1.3271 and money_scale=4 from public.quotation_versions where id=(select id from price_ids where key='four_quote')),'Four minor-unit gross and tax rounding');
reset role;
update public.customer_profiles set currency_id=(select id from public.currencies where code='XTD') where id='b3000000-0000-0000-0000-000000000001';
insert into price_ids values('one',pg_temp.price_request('custom_quotation'));
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'one_quote',public.prepare_quotation((select id from price_ids where key='one'),(select id from public.currencies where code='XTD'),now()+interval '1 day','One scale','[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"1.24","tax_rule_id":"b4000000-0000-0000-0000-000000000001"}]','one-currency-key');
select pg_temp.assert_true((select total=1.3 and money_scale=1 from public.quotation_versions where id=(select id from price_ids where key='one_quote')),'One minor-unit gross and tax rounding');
reset role;
insert into private.approval_policies(code,version,organisation_id,approval_type,status,approval_side,customer_account_id,branch_id,minimum_approvers,threshold_amount,currency_id)
 select 'SYN-ACCOUNT-STRONGER',1,'b7000000-0000-0000-0000-000000000001','quotation','active','customer','b8000000-0000-0000-0000-000000000001',null,2,0,id from public.currencies where code='NGN';
insert into private.approval_policies(code,version,organisation_id,approval_type,status,approval_side,customer_account_id,branch_id,minimum_approvers,threshold_amount,currency_id)
 select 'SYN-BRANCH-WEAKER',1,'b7000000-0000-0000-0000-000000000001','quotation','active','customer','b8000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000002',1,0,id from public.currencies where code='NGN';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
insert into price_ids select 'stronger_account_quote',public.generate_quotation((select id from price_ids where key='other_branch'),jsonb_build_object('valid_until',now()+interval '1 day','terms','Stronger account policy'),'stronger-account-key');
select pg_temp.assert_true(public.read_quotation_commercial((select id from price_ids where key='stronger_account_quote'))->>'customer_required'='2','Weaker branch policy cannot weaken account requirement');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
select public.decide_quotation((select id from price_ids where key='stronger_account_quote'),'approve');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000005',true);
select public.decide_quotation((select id from price_ids where key='stronger_account_quote'),'approve');
select pg_temp.assert_true((select status='offered' from public.quotation_versions where id=(select id from price_ids where key='stronger_account_quote')),'Strongest customer policy still permits valid internal release');
reset role;
rollback;
