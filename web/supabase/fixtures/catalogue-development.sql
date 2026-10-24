-- SYNTHETIC DEVELOPMENT CATALOGUE ONLY. Not a production seed. No transactions: tests inject inside rollback.
insert into public.cities(state_id,code,name,is_operational_label)
 select s.id,'lagos-operations','Lagos',true from public.states s join public.countries c on c.id=s.country_id
 where c.code='NG' and s.code='LA' on conflict(state_id,code) do nothing;
insert into public.service_zones(state_id,code,name,timezone,status)
 select s.id,'lagos-pilot','Lagos operational pilot (coverage unverified)','Africa/Lagos','draft'
 from public.states s join public.countries c on c.id=s.country_id where c.code='NG' and s.code='LA'
 on conflict(code) do nothing;
insert into public.service_families(service_area_id,code,name)
 select a.id,v.code,v.name from (values
 ('home-utilities','laundry','Laundry'),('home-utilities','cleaning','Cleaning'),('home-utilities','maintenance','Maintenance'),
 ('construction','building-projects','Building Projects'),('procurement','sourcing-purchasing','Sourcing and Purchasing'),
 ('business-field-services','field-operations','Field Operations')) v(area,code,name)
 join public.service_areas a on a.code=v.area on conflict(service_area_id,code) do nothing;
insert into public.services(service_family_id,code,name,slug)
 select f.id,v.code,v.name,v.code from (values
 ('laundry','laundry','Laundry'),('cleaning','home-cleaning','Home Cleaning'),
 ('maintenance','plumbing','Plumbing'),('maintenance','electrical-repairs','Electrical Repairs'),
 ('maintenance','air-conditioner-maintenance','Air Conditioner Maintenance'),
 ('building-projects','building-renovation','Building Renovation'),('building-projects','construction-project-management','Construction Project Management'),
 ('sourcing-purchasing','product-sourcing','Product Sourcing'),('sourcing-purchasing','bulk-purchasing','Bulk Purchasing'),
 ('field-operations','merchant-onboarding','Merchant Onboarding'),('field-operations','address-verification','Address Verification'),
 ('field-operations','outlet-mapping','Outlet Mapping'),('field-operations','surveys','Surveys'),
 ('field-operations','document-collection','Document Collection'),('field-operations','field-support','Field Support')) v(family,code,name)
 join public.service_families f on f.code=v.family on conflict(code) do nothing;
insert into public.service_versions(service_id,version,description,assessment_required,payment_gate)
 select id,1,name||' — representative draft configuration; operational approval required.',
 code in ('building-renovation','construction-project-management'),'completion' from public.services
 on conflict(service_id,version) do nothing;
