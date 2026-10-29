begin;
-- Owner-created, unreleased security fixture: tests read isolation only, not dispatch/creation success.
create function pg_temp.assert_true(ok boolean,message text) returns text language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERTION FAILED: %',message;end if;return message;end$$;
create function pg_temp.expect_error(query text,code text) returns boolean language plpgsql as $$begin execute query;return false;exception when others then if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return true;end$$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to authenticated;
create temporary table corporate_execution_ids(key text primary key,id uuid);grant select on corporate_execution_ids to authenticated;
insert into corporate_execution_ids select 'order',id from private.service_orders where customer_account_id='a8000000-0000-0000-0000-000000000001' limit 1;
with proposal as(insert into private.dispatch_proposals(order_id,order_revision,status,expires_at,created_by) select id,1,'withdrawn',now(),'d1000000-0000-0000-0000-000000000003' from corporate_execution_ids where key='order' returning id) insert into corporate_execution_ids select 'proposal',id from proposal;
with work as(insert into private.work_orders(order_id,customer_account_id,proposal_id,policy_id,code,scope_snapshot,supervisor_id,owner_id,priority,starts_at,ends_at,created_by)
select o.id,o.customer_account_id,(select id from corporate_execution_ids where key='proposal'),(select id from private.fulfilment_policies limit 1),'synthetic-corporate-read-isolation','{"fixture":"Unreleased security projection only"}','d1000000-0000-0000-0000-000000000003','d1000000-0000-0000-0000-000000000003','normal',o.starts_at,o.ends_at,'d1000000-0000-0000-0000-000000000003' from private.service_orders o where o.id=(select id from corporate_execution_ids where key='order') returning id) insert into corporate_execution_ids select 'work',id from work;
update private.corporate_account_user_branches set revoked_at=null where account_user_id in(select id from private.corporate_account_users where profile_id='a1000000-0000-0000-0000-000000000005') and branch_id='aa000000-0000-0000-0000-000000000001';
set local role authenticated;select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
select pg_temp.assert_true(public.read_work_order((select id from corporate_execution_ids where key='work'))->>'id'=(select id::text from corporate_execution_ids where key='work'),'Current branch grant allows the correct corporate work projection');
select pg_temp.assert_true(not(public.read_work_order((select id from corporate_execution_ids where key='work')) ?| array['tasks','supervisor_id','history','exceptions']),'Corporate customer work projection hides staffing and internal decisions');
reset role;
update private.corporate_account_user_branches set branch_id='aa000000-0000-0000-0000-000000000002' where account_user_id in(select id from private.corporate_account_users where profile_id='a1000000-0000-0000-0000-000000000005') and branch_id='aa000000-0000-0000-0000-000000000001';
set local role authenticated;select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000005',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.read_work_order((select id from corporate_execution_ids where key='work'))$q$,'42501'),'A requester assigned only to another branch cannot read restricted work');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000006',true);
select pg_temp.assert_true(pg_temp.expect_error($q$select public.read_work_order((select id from corporate_execution_ids where key='work'))$q$,'42501'),'Unrelated corporate accounts cannot read work');
reset role;
rollback;
