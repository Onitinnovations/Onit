begin;
create table private.supplier_document_links(
 id uuid primary key default gen_random_uuid(),operation_id uuid not null references private.service_operations(id) on delete restrict,
 supplier_organisation_id uuid not null references public.organisations(id) on delete restrict,document_id uuid not null unique,
 kind text not null check(kind in ('verification','response','shipping')),rfq_id uuid,purchase_order_id uuid,
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),
 foreign key(document_id,supplier_organisation_id) references private.document_objects(id,organisation_id) on delete restrict,
 foreign key(rfq_id,operation_id) references private.procurement_rfqs(id,operation_id) on delete restrict,
 foreign key(purchase_order_id,operation_id,supplier_organisation_id) references private.purchase_orders(id,operation_id,supplier_organisation_id) on delete restrict,
 check((kind='verification' and rfq_id is null and purchase_order_id is null) or(kind='response' and rfq_id is not null and purchase_order_id is null) or(kind='shipping' and purchase_order_id is not null and rfq_id is null))
);
alter table private.supplier_document_links enable row level security;
revoke all on private.supplier_document_links from public,anon,authenticated;
grant all on private.supplier_document_links to service_role;
create trigger supplier_document_link_immutable before update or delete on private.supplier_document_links for each row execute function app_private.reject_mutation();
create trigger supplier_document_link_audit after insert on private.supplier_document_links for each row execute function app_private.audit_access_change();
create function app_private.prepare_supplier_document(p_operation uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;supplier uuid=(p_data->>'supplier_id')::uuid;po private.purchase_orders;recipient private.procurement_rfq_recipients;document uuid=gen_random_uuid();kind text=p_data->>'kind';mime text=p_data->>'content_type';extension text;begin
 select * into operation from private.service_operations where id=p_operation;
 if operation.kind<>'procurement' or operation.status not in ('planning','active') or mime not in ('application/pdf','image/jpeg','image/png','image/webp','text/plain') or(p_data->>'byte_size')::bigint not between 1 and 20971520 then raise exception 'active procurement and bounded registry document required' using errcode='23514';end if;
 if kind='verification' then
 if not app_private.has_permission('procurement.source') or not exists(select 1 from public.organisations where id=supplier and organisation_type in ('supplier','mixed') and status='active') then raise exception 'global OnIt supplier-verification document authority required' using errcode='42501';end if;
 elsif kind='shipping' then
 select * into po from private.purchase_orders where id=(p_data->>'po_id')::uuid and operation_id=operation.id and supplier_organisation_id=supplier;
 if po.id is null or po.status in ('cancelled','closed') or not(app_private.supplier_actor(supplier) or app_private.operation_staff(operation.id,'procurement.source')) then raise exception 'addressed active supplier purchase order required' using errcode='42501';end if;
 elsif kind='response' then
 select * into recipient from private.procurement_rfq_recipients where id=(p_data->>'recipient_id')::uuid and supplier_organisation_id=supplier;
 if recipient.id is null or not exists(select 1 from private.procurement_rfqs where id=recipient.rfq_id and operation_id=operation.id and status='issued') or not(app_private.supplier_actor(supplier) or app_private.operation_staff(operation.id,'procurement.source')) then raise exception 'addressed issued supplier invitation required' using errcode='42501';end if;
 else raise exception 'typed supplier document purpose required' using errcode='23514';end if;
 extension=case mime when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' else 'txt' end;
 insert into private.document_objects(id,bucket_id,object_name,organisation_id,uploaded_by,classification,content_type,byte_size,created_by)
 values(document,'contracts',supplier::text||'/'||operation.id::text||'/'||document::text||'.'||extension,supplier,auth.uid(),'contract',mime,(p_data->>'byte_size')::bigint,auth.uid());
 insert into private.supplier_document_links(operation_id,supplier_organisation_id,document_id,kind,rfq_id,purchase_order_id,created_by) values(operation.id,supplier,document,kind,recipient.rfq_id,po.id,auth.uid());return document;end$$;
create function app_private.supplier_document_upload(p_document uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.document_objects document join private.supplier_document_links link on link.document_id=document.id join private.service_operations operation on operation.id=link.operation_id and operation.status in ('planning','active')
 where document.id=p_document and document.uploaded_by=auth.uid() and document.scan_status='pending' and document.archived_at is null and document.upload_expires_at>now() and((link.kind='verification' and app_private.has_permission('procurement.source')) or(link.kind<>'verification' and(app_private.supplier_actor(link.supplier_organisation_id) or app_private.operation_staff(operation.id,'procurement.source')))))
$$;
do $$declare source text;begin
 source=pg_get_functiondef('app_private.service_operation_command(uuid,text,jsonb,text)'::regprocedure);
 source=replace(source,$fragment$elsif operation.kind='procurement' then
 if p_action like 'receipt.%'$fragment$,$fragment$elsif operation.kind='procurement' then
 if p_action='supplier.document_prepare' then result=app_private.prepare_supplier_document(operation.id,p_data);
 elsif p_action like 'receipt.%'$fragment$);execute source;
 source=pg_get_functiondef('app_private.specialized_document_reference(uuid,uuid)'::regprocedure);
 source=replace(source,'not app_private.can_read_object(document.bucket_id,document.object_name)','not(app_private.can_read_object(document.bucket_id,document.object_name) or app_private.supplier_document_upload(document.id))');
 source=replace(source,'exists(select 1 from private.operation_documents where operation_id=p_operation and document_id=document.id)','exists(select 1 from private.supplier_document_links where operation_id=p_operation and document_id=document.id) or exists(select 1 from private.operation_documents where operation_id=p_operation and document_id=document.id)');execute source;
end$$;
alter function app_private.specialized_document_access(uuid) rename to before_supplier_document_access;
revoke all on function app_private.before_supplier_document_access(uuid) from public,anon,authenticated;
create function app_private.specialized_document_access(p_document uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.before_supplier_document_access(p_document) or exists(select 1 from private.document_objects document join private.supplier_document_links link on link.document_id=document.id where document.id=p_document and document.scan_status='clean' and document.archived_at is null and(app_private.supplier_actor(link.supplier_organisation_id) or(link.kind='verification' and(app_private.has_permission('procurement.source') or app_private.has_permission('procurement.approve'))) or(link.kind<>'verification' and app_private.operation_staff(link.operation_id,'procurement.source'))))
$$;
alter function app_private.can_upload_object(text,text) rename to before_supplier_can_upload_object;
revoke all on function app_private.before_supplier_can_upload_object(text,text) from public,anon,authenticated;
create function app_private.can_upload_object(p_bucket text,p_name text) returns boolean language sql stable security definer set search_path='' as $$select app_private.before_supplier_can_upload_object(p_bucket,p_name) or exists(select 1 from private.document_objects where bucket_id=p_bucket and object_name=p_name and app_private.supplier_document_upload(id))$$;
grant execute on function app_private.can_upload_object(text,text) to authenticated;
do $$declare policy record;begin for policy in select policyname,qual,with_check from pg_policies where schemaname='storage' and tablename='objects' loop
 if policy.qual like '%before_supplier_can_upload_object%' then execute format('alter policy %I on storage.objects using (%s)',policy.policyname,replace(policy.qual,'before_supplier_can_upload_object','can_upload_object'));end if;
 if policy.with_check like '%before_supplier_can_upload_object%' then execute format('alter policy %I on storage.objects with check (%s)',policy.policyname,replace(policy.with_check,'before_supplier_can_upload_object','can_upload_object'));end if;end loop;end$$;
revoke all on function app_private.specialized_document_access(uuid),app_private.prepare_supplier_document(uuid,jsonb),app_private.supplier_document_upload(uuid) from public,anon,authenticated;
create index supplier_document_operation on private.supplier_document_links(operation_id,supplier_organisation_id);
create index supplier_document_organisation on private.supplier_document_links(supplier_organisation_id);
create index supplier_document_rfq on private.supplier_document_links(rfq_id,operation_id);
create index supplier_document_po on private.supplier_document_links(purchase_order_id,operation_id,supplier_organisation_id);
create index supplier_document_creator on private.supplier_document_links(created_by);
commit;
