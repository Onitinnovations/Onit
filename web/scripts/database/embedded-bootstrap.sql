-- TEST-ONLY compatibility scaffold for embedded PostgreSQL. Never a migration.
-- It does not emulate Auth HTTP, Storage HTTP, Realtime or Supabase grants in full.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;
create table auth.users(id uuid primary key, raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;
create table storage.buckets(id text primary key,name text not null,public boolean not null default false,
 file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null references storage.buckets(id),name text not null,
 unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert,update,delete on storage.objects to anon,authenticated;
grant all on storage.objects,storage.buckets to service_role;
