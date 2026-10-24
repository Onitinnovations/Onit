begin;
create table private.approval_policies (
  id uuid primary key default gen_random_uuid(), code text not null, version integer not null check(version>0),
  organisation_id uuid references public.organisations(id) on delete restrict,
  approval_type text not null check(approval_type in ('quotation','expense','payroll','payout','procurement','project_variation')),
  minimum_approvers integer not null default 1 check(minimum_approvers>0),
  require_independent_approver boolean not null default true check(require_independent_approver),
  status text not null default 'draft' check(status in ('draft','active','retired')),
  threshold_amount numeric(20,4) check(threshold_amount>=0), currency_id uuid references public.currencies(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(num_nonnulls(threshold_amount,currency_id) in (0,2)), unique(code,version)
);
create table private.approval_requests (
  id uuid primary key default gen_random_uuid(), policy_id uuid not null references private.approval_policies(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  -- Domain-specific tables must link the exact target/version with a real FK.
  -- No generic caller-selected target is approvable in this foundation.
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(id,requested_by)
);
create table private.approval_steps (
  id uuid primary key default gen_random_uuid(), request_id uuid not null, requested_by uuid not null,
  sequence integer not null check(sequence>0), decided_by uuid not null references public.profiles(id) on delete restrict,
  decision text not null check(decision in ('approved','rejected')), reason text not null,
  created_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict,
  foreign key(request_id,requested_by) references private.approval_requests(id,requested_by) on delete restrict,
  check(decided_by<>requested_by), unique(request_id,sequence), unique(request_id,decided_by)
);
create table private.system_configurations (
  id uuid primary key default gen_random_uuid(), key text not null, version integer not null check(version>0),
  value jsonb not null, description text not null,
  status text not null default 'draft' check(status in ('draft','active','retired')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(key,version)
);
create unique index system_configurations_active_key on private.system_configurations(key) where status='active';

create table private.document_objects (
  id uuid primary key default gen_random_uuid(), bucket_id text not null,
  object_name text not null check(length(object_name)>0 and object_name !~ '(^/|(^|/)\.\.(/|$))'),
  customer_account_id uuid references public.customer_profiles(id) on delete restrict,
  owner_profile_id uuid references public.profiles(id) on delete restrict,
  organisation_id uuid references public.organisations(id) on delete restrict,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  classification text not null check(classification in ('customer','identity','contract','field','invoice','employee','work','public')),
  content_type text not null check(content_type in ('application/pdf','image/jpeg','image/png','image/webp','text/plain')),
  byte_size bigint not null check(byte_size>0 and byte_size<=20971520), sha256 text check(sha256 ~ '^[a-f0-9]{64}$'),
  scan_status text not null default 'pending' check(scan_status in ('pending','clean','rejected')),
  upload_expires_at timestamptz not null default now()+interval '1 hour',
  retained_until timestamptz, legal_hold boolean not null default false, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  check(num_nonnulls(customer_account_id,owner_profile_id,organisation_id)=1),
  check((bucket_id='identity-documents' and classification='identity' and owner_profile_id is not null)
    or (bucket_id='customer-documents' and classification='customer' and customer_account_id is not null)
    or (bucket_id='contracts' and classification='contract')
    or (bucket_id='field-evidence' and classification='field')
    or (bucket_id='invoices' and classification='invoice')
    or (bucket_id='employee-documents' and classification='employee' and owner_profile_id is not null)
    or (bucket_id='work-evidence' and classification='work')
    or (bucket_id='marketing-assets' and classification='public' and organisation_id is not null)),
  unique(bucket_id,object_name), unique(id,customer_account_id)
);
create table public.customer_documents (
  id uuid primary key default gen_random_uuid(), customer_account_id uuid not null references public.customer_profiles(id) on delete restrict,
  document_object_id uuid not null, purpose text not null, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  foreign key(document_object_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
  unique(customer_account_id,document_object_id,purpose)
);
create table public.service_media (
  id uuid primary key default gen_random_uuid(), service_version_id uuid not null references public.service_versions(id) on delete restrict,
  document_object_id uuid not null references private.document_objects(id) on delete restrict,
  alt_text text not null, position integer not null check(position>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict, unique(service_version_id,position)
);
create function app_private.guard_document_owner() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.bucket_id,new.object_name,new.customer_account_id,new.owner_profile_id,new.organisation_id,new.uploaded_by,new.classification)
    is distinct from (old.bucket_id,old.object_name,old.customer_account_id,old.owner_profile_id,old.organisation_id,old.uploaded_by,old.classification) then
    raise exception 'document ownership and path are immutable' using errcode='55000';
  end if; return new;
end $$;
create trigger onit_document_owner before update on private.document_objects for each row execute function app_private.guard_document_owner();
create trigger onit_media_version before insert or update or delete on public.service_media for each row execute function app_private.guard_version_child();
create function app_private.guard_public_media() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists(select 1 from private.document_objects d where d.id=new.document_object_id
    and d.bucket_id='marketing-assets' and d.classification='public' and d.scan_status='clean' and d.archived_at is null) then
    raise exception 'catalogue media must be reviewed public marketing assets' using errcode='23514';
  end if; return new;
end $$;
create trigger onit_media_public before insert or update on public.service_media for each row execute function app_private.guard_public_media();

-- No evidence/HR/invoice access merely from being in the same organisation.
-- Those buckets require scoped server download commands until their domains exist.
create function app_private.can_read_object(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.document_objects d where d.bucket_id=p_bucket and d.object_name=p_name
    and d.scan_status='clean' and d.archived_at is null
    and ((d.classification='public' and d.bucket_id='marketing-assets')
      or (d.classification='customer' and app_private.can_access_customer(d.customer_account_id))
      or (d.classification='identity' and d.owner_profile_id=auth.uid()
        and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active'))
      or app_private.has_permission('documents.read')));
$$;
create function app_private.can_upload_object(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.document_objects d join public.profiles p on p.id=d.uploaded_by and p.status='active'
    where d.bucket_id=p_bucket and d.object_name=p_name and d.uploaded_by=auth.uid()
      and d.scan_status='pending' and d.archived_at is null and d.upload_expires_at>now()
      and ((d.classification='identity' and d.owner_profile_id=auth.uid())
        or (d.classification='customer' and app_private.can_access_customer(d.customer_account_id,true))));
$$;
grant execute on function app_private.can_read_object(text,text) to anon,authenticated;
grant execute on function app_private.can_upload_object(text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('identity-documents','identity-documents',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp']),
 ('contracts','contracts',false,20971520,array['application/pdf']),
 ('field-evidence','field-evidence',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp']),
 ('invoices','invoices',false,20971520,array['application/pdf']),
 ('customer-documents','customer-documents',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp','text/plain']),
 ('employee-documents','employee-documents',false,20971520,array['application/pdf','image/jpeg','image/png']),
 ('work-evidence','work-evidence',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp']),
 ('marketing-assets','marketing-assets',true,20971520,array['image/jpeg','image/png','image/webp']);
-- Existing bucket-name conflicts deliberately fail; never silently turn a private
-- bucket public or adopt existing policies without the remote baseline review.
create policy onit_object_read on storage.objects for select to anon,authenticated
using(app_private.can_read_object(bucket_id,name));
create policy onit_object_upload on storage.objects for insert to authenticated
with check(app_private.can_upload_object(bucket_id,name));
-- No end-user UPDATE/DELETE policies: overwrite and retention bypass are denied.
-- Public bucket publication is a trusted server copy of reviewed clean files only.

do $$ declare t record; begin
  for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','private') and c.relname in (
    'approval_policies','approval_requests','approval_steps','system_configurations','document_objects','customer_documents','service_media') loop
    execute format('alter table %I.%I enable row level security',t.nspname,t.relname);
    execute format('revoke all on %I.%I from public, anon, authenticated',t.nspname,t.relname);
    execute format('grant all on %I.%I to service_role',t.nspname,t.relname);
    if t.relname='approval_steps' then
      execute format('create trigger onit_immutable before update or delete or truncate on %I.%I for each statement execute function app_private.reject_mutation()',t.nspname,t.relname);
    else
      execute format('create trigger onit_updated_at before update on %I.%I for each row execute function app_private.touch_updated_at()',t.nspname,t.relname);
    end if;
  end loop;
end $$;
grant select on public.customer_documents to authenticated;
create policy customer_document_read on public.customer_documents for select to authenticated
using(app_private.can_access_customer(customer_account_id) or app_private.has_permission('documents.read'));
grant select on public.service_media to anon,authenticated;
create function app_private.is_public_media(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.document_objects d where d.id=p_id and d.classification='public'
    and d.bucket_id='marketing-assets' and d.scan_status='clean' and d.archived_at is null);
$$;
grant execute on function app_private.is_public_media(uuid) to anon,authenticated;
create policy service_media_published on public.service_media for select to anon,authenticated
using(app_private.is_version_published(service_version_id) and app_private.is_public_media(document_object_id));
commit;
