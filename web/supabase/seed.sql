-- Safe reference data only. No customer identities, prices, taxes, payroll or payouts.
begin;
insert into public.countries(code,name) values('NG','Nigeria') on conflict(code) do nothing;
insert into public.currencies(code,name,minor_units) values('NGN','Nigerian Naira',2) on conflict(code) do nothing;
insert into public.states(country_id,code,name)
 select id,'LA','Lagos' from public.countries where code='NG' on conflict(country_id,code) do nothing;
insert into public.service_areas(code,name,status) values
 ('home-utilities','Home & Utilities','draft'),('construction','Construction','draft'),
 ('procurement','Procurement','draft'),('business-field-services','Business Field Services','draft') on conflict(code) do nothing;
insert into private.permissions(code,description) values
 ('identity.read','Read identity within explicitly granted scope'),('customers.read','Read customer operations within explicitly granted scope'),
 ('documents.read','Read protected documents for authorized operations'),('catalogue.publish','Publish approved service catalogue versions')
 on conflict(code) do nothing;
insert into private.roles(code,name) values
 ('customer','Individual customer'),('corporate_requester','Corporate requester'),('corporate_approver','Corporate approver'),
 ('provider','Independent service provider'),('supplier','Supplier'),('operations_reader','Operations reader'),
 ('access_administrator','Access administrator') on conflict(code) do nothing;
-- Definitions only: no user is assigned any role. Customer/provider role labels
-- never satisfy the staff permission helper's active-employment requirement.
insert into private.role_permissions(role_id,permission_id)
 select r.id,p.id from private.roles r cross join private.permissions p
 where (r.code='operations_reader' and p.code='customers.read')
    or (r.code='access_administrator' and p.code='identity.read')
 on conflict(role_id,permission_id) do nothing;
insert into private.system_configurations(key,version,value,description,status) values
 ('wallet.live_funding',1,'false'::jsonb,'Inactive pending approved compliance design','active'),
 ('payouts.live_execution',1,'false'::jsonb,'Inactive pending approved compliance design','active'),
 ('integrations.live_email',1,'false'::jsonb,'Zoho delivery is not implemented or enabled','active') on conflict(key,version) do nothing;
commit;
