-- READ-ONLY inventory. Run with psql using an authorised read-only role and
-- environment/PGPASSFILE credentials. Never use this file as a migration.
-- Do not commit output containing project-specific metadata. No row values read.
begin read only;
set local statement_timeout='15s';
select current_setting('server_version') as postgres_version;
select nspname as schema_name from pg_namespace where nspname not like 'pg_%' and nspname<>'information_schema' order by nspname;
select e.extname,e.extversion,n.nspname as extension_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace order by e.extname;
select n.nspname as schema_name,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,
  pg_get_userbyid(c.relowner) as owner,c.reltuples::bigint as estimated_rows
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','app_private','supabase_migrations','storage','auth') and c.relkind in ('r','v','m','p')
  order by n.nspname,c.relname;
select table_schema,table_name,column_name,data_type,is_nullable,column_default
  from information_schema.columns where table_schema in ('public','private','app_private') order by table_schema,table_name,ordinal_position;
select n.nspname as schema_name,c.relname,con.conname,con.contype,pg_get_constraintdef(con.oid) as definition
  from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private') order by n.nspname,c.relname,con.conname;
select schemaname,tablename,indexname,indexdef from pg_indexes where schemaname in ('public','private') order by schemaname,tablename,indexname;
select n.nspname as schema_name,p.proname,pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result,p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) as owner
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','app_private')
  order by n.nspname,p.proname;
-- Function signatures only: do not inadvertently export hardcoded secrets in old bodies.
select n.nspname as schema_name,c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) as definition
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal and n.nspname in ('public','private','auth','storage') order by n.nspname,c.relname,t.tgname;
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
  where schemaname in ('public','private','storage') order by schemaname,tablename,policyname;
select grantee,table_schema,table_name,privilege_type from information_schema.role_table_grants
  where table_schema in ('public','private','app_private') order by table_schema,table_name,grantee,privilege_type;
select id,public,file_size_limit,allowed_mime_types from storage.buckets order by id;
select to_regclass('supabase_migrations.schema_migrations') as migration_history_relation;
-- The XML query is conditional: missing history is reported as NULL, not repaired.
select case when to_regclass('supabase_migrations.schema_migrations') is not null
  then query_to_xml('select version from supabase_migrations.schema_migrations order by version',false,true,'')
  else null end as applied_migration_versions;
rollback;
