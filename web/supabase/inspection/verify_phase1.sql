begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
  'postgres_version',current_setting('server_version'),
  'application_table_count',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r'),
  'public_table_count',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'),
  'private_table_count',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r'),
  'tables_without_rls',(select coalesce(jsonb_agg(n.nspname||'.'||c.relname),'[]'::jsonb) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity),
  'unvalidated_constraints',(select count(*) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not con.convalidated),
  'unsafe_definer_search_paths',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','app_private') and p.prosecdef and not coalesce(p.proconfig @> array['search_path=""'],false)),
  'exposed_definers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),
  'public_internal_function_exec',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace,
    lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where n.nspname='app_private' and a.grantee=0 and a.privilege_type='EXECUTE'),
  'private_schema_usage',jsonb_build_object('anon',has_schema_privilege('anon','private','USAGE'),'authenticated',has_schema_privilege('authenticated','private','USAGE')),
  'disabled_guards',(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not t.tgisinternal and t.tgenabled='D'),
  'policies',(select count(*) from pg_policies where schemaname in ('public','private')),
  'auth_users',(select count(*) from auth.users),
  'customer_accounts',(select count(*) from public.customer_profiles),
  'employee_records',(select count(*) from private.employee_profiles),
  'operational_zones',(select count(*) from public.service_zones),
  'services',(select count(*) from public.services),
  'service_areas',(select jsonb_agg(jsonb_build_object('code',code,'name',name,'status',status) order by code) from public.service_areas),
  'roles',(select count(*) from private.roles),
  'countries',(select jsonb_agg(jsonb_build_object('code',code,'name',name)) from public.countries),
  'states',(select jsonb_agg(jsonb_build_object('code',code,'name',name)) from public.states),
  'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public) order by id) from storage.buckets),
  'migrations',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations)
) as verification;
rollback;
