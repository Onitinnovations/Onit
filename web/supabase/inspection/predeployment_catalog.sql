-- Read-only aggregate inventory. No credentials, function bodies or row values.
begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
  'postgres_version',current_setting('server_version'),
  'migration_history_relation',to_regclass('supabase_migrations.schema_migrations'),
  'auth_user_count',(select count(*) from auth.users),
  'storage_object_count',(select count(*) from storage.objects),
  'schemas',(select jsonb_agg(nspname order by nspname) from pg_namespace where nspname not like 'pg_%' and nspname<>'information_schema'),
  'extensions',(select jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname) order by e.extname)
    from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
  'application_tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,
    'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'estimated_rows',c.reltuples,'owner',pg_get_userbyid(c.relowner)) order by n.nspname,c.relname),'[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','app_private') and c.relkind in ('r','p','v','m')),
  'columns',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',a.attname,
    'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'has_default',a.atthasdef) order by n.nspname,c.relname,a.attnum),'[]'::jsonb)
    from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in ('public','private','app_private') and c.relkind in ('r','p') and a.attnum>0 and not a.attisdropped),
  'constraints',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',con.conname,
    'type',con.contype,'validated',con.convalidated) order by n.nspname,c.relname,con.conname),'[]'::jsonb)
    from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','app_private')),
  'indexes',(select coalesce(jsonb_agg(jsonb_build_object('schema',schemaname,'table',tablename,'name',indexname) order by schemaname,tablename,indexname),'[]'::jsonb)
    from pg_indexes where schemaname in ('public','private','app_private')),
  'functions',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,
    'arguments',pg_get_function_identity_arguments(p.oid),'result',pg_get_function_result(p.oid),'security_definer',p.prosecdef,
    'settings',p.proconfig,'owner',pg_get_userbyid(p.proowner)) order by n.nspname,p.proname),'[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','app_private')),
  'triggers',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',t.tgname,'enabled',t.tgenabled)
    order by n.nspname,c.relname,t.tgname),'[]'::jsonb) from pg_trigger t join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname in ('public','private','app_private','auth','storage')),
  'policies',(select coalesce(jsonb_agg(jsonb_build_object('schema',schemaname,'table',tablename,'name',policyname,'roles',roles,'command',cmd)
    order by schemaname,tablename,policyname),'[]'::jsonb) from pg_policies where schemaname in ('public','private','app_private','storage')),
  'storage_buckets',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit,'mime_types',allowed_mime_types) order by id),'[]'::jsonb) from storage.buckets)
) as inventory;
rollback;
