begin;
create function app_private.read_fulfilment_configuration(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare policy private.fulfilment_policies;checklist public.service_checklists;begin
 if not(app_private.has_permission('fulfilment.policy.manage') or app_private.has_permission('fulfilment.policy.approve')) then raise exception 'global execution configuration authority required' using errcode='42501';end if;
 select * into policy from private.fulfilment_policies where id=p_id;
 if found then return jsonb_build_object('kind','policy','record',to_jsonb(policy),'execution_checklist',app_private.execution_definition((policy.configuration->>'execution_checklist')::uuid),'quality_checklist',app_private.execution_definition((policy.configuration->>'quality_checklist')::uuid),'handover_checklist',app_private.execution_definition((policy.configuration->>'handover_checklist')::uuid));end if;
 select * into checklist from public.service_checklists where id=p_id and checklist_type in ('execution','quality');
 if found then return jsonb_build_object('kind','checklist','record',to_jsonb(checklist),'definition',app_private.execution_definition(checklist.id));end if;
 raise exception 'execution configuration unavailable' using errcode='42501';end$$;
create function public.read_fulfilment_configuration(p_id uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_fulfilment_configuration(p_id)$$;
revoke all on function public.read_fulfilment_configuration(uuid) from public,anon;
grant execute on function public.read_fulfilment_configuration(uuid),app_private.read_fulfilment_configuration(uuid) to authenticated;
create function app_private.execution_read_access(p_work uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.work_orders w where w.id=p_work and (app_private.execution_staff(w.order_id,'fulfilment.read') or app_private.execution_staff(w.order_id,'fulfilment.manage') or (w.supervisor_id=auth.uid() and app_private.execution_staff(w.order_id,'fulfilment.supervise')) or app_private.order_customer(w.order_id) or app_private.execution_party(w.id) or (app_private.execution_staff(w.order_id,'fulfilment.qa.perform') and exists(select 1 from private.quality_inspections q join private.work_tasks t on t.id=q.task_id where t.work_order_id=w.id and q.inspector_id=auth.uid()))))
$$;
create function app_private.read_work_order(p_work uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w private.work_orders;staff boolean;customer boolean;result jsonb;begin
 select * into w from private.work_orders where id=p_work;
 if w.id is null or not app_private.execution_read_access(w.id) then raise exception 'work access denied' using errcode='42501';end if;
 customer=app_private.order_customer(w.order_id);staff=app_private.execution_staff(w.order_id,'fulfilment.read') or app_private.execution_staff(w.order_id,'fulfilment.manage') or app_private.execution_staff(w.order_id,'fulfilment.supervise') or app_private.execution_staff(w.order_id,'fulfilment.qa.perform');
 result=jsonb_build_object('id',w.id,'reference',w.reference,'order_id',w.order_id,'revision',w.revision,'plan_revision',w.plan_revision,'status',case when customer and not staff then case when w.status in ('awaiting_qa','rework_required') then 'quality_review' when w.status='customer_disputed' then 'under_review' else w.status end else w.status end,'start',w.starts_at,'end',w.ends_at);
 if staff or not customer then result=result||jsonb_build_object('scope',w.scope_snapshot,'instructions',w.instructions,'priority',w.priority,
 'tasks',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'revision',t.revision,'status',t.status,'description',t.description,'mandatory',t.mandatory,'is_container',t.is_container,'parent_task_id',t.parent_task_id,'resource_id',t.resource_id,'execution_round',t.execution_round,'start',t.starts_at,'end',t.ends_at,'actual_start',t.actual_start,'actual_finish',t.actual_finish,
 'checklists',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'phase',s.phase,'version',s.version,'status',s.status,'answers',s.answers,'definition',s.definition_snapshot)),'[]') from private.execution_submissions s where s.task_id=t.id),
 'evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'document_id',e.document_id,'classification',e.classification,'status',e.status,'scan_status',d.scan_status,'execution_round',e.execution_round)),'[]') from private.execution_evidence e join private.document_objects d on d.id=e.document_id where e.task_id=t.id),
 'attendance',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from private.execution_attendance a where a.task_id=t.id))), '[]') from private.work_tasks t join private.assignment_resources resource on resource.id=t.resource_id where t.work_order_id=w.id and (staff or app_private.execution_worker(t.id) or app_private.provider_self(resource.provider_id,true))));end if;
 if staff then result=result||jsonb_build_object('owner_id',w.owner_id,'supervisor_id',w.supervisor_id,'policy_id',w.policy_id,
 'quality',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from private.quality_inspections q join private.work_tasks task on task.id=q.task_id where task.work_order_id=w.id),
 'findings',(select coalesce(jsonb_agg(to_jsonb(f)),'[]') from private.quality_findings f join private.quality_inspections q on q.id=f.inspection_id join private.work_tasks task on task.id=q.task_id where task.work_order_id=w.id),
 'rework',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from private.rework_requests r join private.work_tasks task on task.id=r.rework_task_id where task.work_order_id=w.id),
 'exceptions',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from private.operational_exceptions e where e.work_order_id=w.id),
 'slas',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from private.sla_tracks s where s.work_order_id=w.id and (s.case_id is null or app_private.case_access(s.case_id))),
 'history',(select coalesce(jsonb_agg(to_jsonb(h)),'[]') from (select * from private.execution_history h where h.work_order_id=w.id and (h.action not like 'case_%' or app_private.case_access(h.subject_id)) and (h.details->>'case_id' is null or app_private.case_access((h.details->>'case_id')::uuid)) order by h.created_at desc,h.id limit 100) h));end if;
 if staff or customer then result=result||jsonb_build_object('feedback',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',revision,'rating',rating,'comment',comment,'created_at',created_at) order by revision),'[]') from public.customer_feedback where work_order_id=w.id));end if;
 if customer then result=result||jsonb_build_object('confirmations',(select coalesce(jsonb_agg(jsonb_build_object('decision',decision,'work_revision',work_revision,'created_at',created_at)),'[]') from private.customer_confirmations where work_order_id=w.id),
 'evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'document_id',e.document_id,'classification',e.classification)),'[]') from private.execution_evidence e join private.document_objects d on d.id=e.document_id and d.scan_status='clean' and d.archived_at is null where e.work_order_id=w.id and e.customer_visible and e.status='approved'));
 end if;return result;
end$$;
create function app_private.read_service_case(p_case uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare c private.service_cases;staff boolean;begin
 select * into c from private.service_cases where id=p_case;
 if not app_private.case_access(c.id) then raise exception 'case read denied' using errcode='42501';end if;
 staff=app_private.case_access(c.id,true);
 return jsonb_build_object('id',c.id,'reference',c.reference,'order_id',c.order_id,'revision',c.revision,'status',c.status,'description',c.description,'severity',c.severity,
 'entries',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'content',content,'document_id',document_id,'created_at',created_at)),'[]') from private.service_case_entries where case_id=c.id and (staff or visibility='customer')))||case when staff then jsonb_build_object('owner_id',c.owner_id,'provider_id',c.provider_id,'confidential',c.confidential,'resolution_requirements',c.resolution_requirements,'created_by',c.created_by,'resolution_proposed_by',c.resolution_proposed_by) else '{}'::jsonb end;
end$$;
create function app_private.execution_dashboard(p_view text,p_from timestamptz default null,p_until timestamptz default null,p_zone uuid default null,p_city uuid default null,p_after uuid default null,p_limit integer default 25) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if p_limit is null or p_limit not between 1 and 100 or p_view not in ('scheduled','active','supervision','quality','rework','customer_confirmation','completed','closed','delayed','complaints','incidents','sla_breaches','performance') then raise exception 'bounded typed operations page required' using errcode='23514';end if;
 if p_view in ('complaints','incidents') then return (select coalesce(jsonb_agg(app_private.read_service_case(c.id) order by c.id),'[]') from (select id from private.service_cases where (p_after is null or id>p_after) and status<>'closed' and app_private.case_access(id) and (p_view<>'incidents' or category<>'completion_dispute') order by id limit p_limit) c);end if;
 if p_view='performance' then return (select coalesce(jsonb_agg(to_jsonb(e)-'document_id'-'created_by'),'[]') from (select metric.* from private.provider_performance_events metric join private.provider_profiles provider on provider.id=metric.provider_id where metric.source_event_id is not null and (p_after is null or metric.id>p_after) and (app_private.has_permission('providers.read',provider.organisation_id) or app_private.provider_self(provider.id,true)) order by metric.id limit p_limit) e);end if;
 return (select coalesce(jsonb_agg(app_private.read_work_order(q.id) order by q.id),'[]') from (
 select w.id from private.work_orders w join private.service_orders o on o.id=w.order_id join public.service_locations location on location.id=o.service_location_id where app_private.execution_read_access(w.id)
 and (p_after is null or w.id>p_after) and (p_from is null or w.starts_at>=p_from) and (p_until is null or w.starts_at<p_until) and(p_zone is null or o.zone_id=p_zone) and(p_city is null or location.city_id=p_city)
 and ((p_view='scheduled' and w.status not in ('closed','cancelled')) or (p_view='active' and w.status in ('in_progress','awaiting_mobilisation','work_completed','suspended')) or (p_view='supervision' and exists(select 1 from private.work_tasks task where task.work_order_id=w.id and task.status='work_completed')) or(p_view='quality' and exists(select 1 from private.work_tasks task where task.work_order_id=w.id and task.status='awaiting_qa')) or(p_view='rework' and exists(select 1 from private.rework_requests rework join private.work_tasks task on task.id=rework.rework_task_id where task.work_order_id=w.id and rework.status='active')) or(p_view='customer_confirmation' and w.status='awaiting_customer_confirmation') or(p_view='completed' and w.status='completed') or(p_view='closed' and w.status='closed') or(p_view in ('delayed','sla_breaches') and exists(select 1 from private.sla_tracks s where s.work_order_id=w.id and (s.status='breached' or(s.status='running' and s.due_at<clock_timestamp()))))) order by w.id limit p_limit) q);
end$$;
-- Sensitive files remain in existing private buckets. Videos are bounded by the registry's existing 20 MiB limit.
do $$declare constraint_row record;begin for constraint_row in select conname from pg_constraint where conrelid='private.document_objects'::regclass and contype='c' and pg_get_constraintdef(oid) like '%content_type%application/pdf%' loop execute format('alter table private.document_objects drop constraint %I',constraint_row.conname);end loop;end$$;
alter table private.document_objects add constraint document_content_types check(content_type in ('application/pdf','image/jpeg','image/png','image/webp','text/plain','video/mp4','video/webm'));
update storage.buckets set allowed_mime_types=array(select distinct type from unnest(allowed_mime_types||array['video/mp4','video/webm','text/plain']) type) where id in ('work-evidence','field-evidence');
alter function app_private.can_read_object(text,text) rename to pre_execution_can_read_object;
revoke all on function app_private.pre_execution_can_read_object(text,text) from public,anon,authenticated;
create function app_private.can_read_object(p_bucket text,p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.pre_execution_can_read_object(p_bucket,p_name) or exists(select 1 from private.document_objects d join private.execution_evidence e on e.document_id=d.id where d.bucket_id=p_bucket and d.object_name=p_name and d.scan_status='clean' and d.archived_at is null and
 (app_private.execution_worker(e.task_id) or app_private.execution_staff(e.order_id,'fulfilment.manage') or app_private.execution_staff(e.order_id,'fulfilment.supervise') or (app_private.execution_staff(e.order_id,'fulfilment.qa.perform') and exists(select 1 from private.quality_inspections where task_id=e.task_id and inspector_id=auth.uid())) or (e.customer_visible and e.status='approved' and app_private.order_customer(e.order_id))))
 or exists(select 1 from private.service_case_entries entry join private.service_cases c on c.id=entry.case_id join private.document_objects d on d.id=entry.document_id where d.bucket_id=p_bucket and d.object_name=p_name and d.scan_status='clean' and d.archived_at is null and app_private.case_access(c.id) and (app_private.case_access(c.id,true) or entry.visibility='customer'))
$$;
alter function app_private.can_upload_object(text,text) rename to pre_execution_can_upload_object;
revoke all on function app_private.pre_execution_can_upload_object(text,text) from public,anon,authenticated;
create function app_private.can_upload_object(p_bucket text,p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.pre_execution_can_upload_object(p_bucket,p_name) or exists(select 1 from private.document_objects d join private.execution_evidence e on e.document_id=d.id where d.bucket_id=p_bucket and d.object_name=p_name and d.bucket_id='work-evidence' and d.classification='work' and d.uploaded_by=auth.uid() and d.scan_status='pending' and d.upload_expires_at>now() and d.archived_at is null and (app_private.execution_worker(e.task_id) or app_private.execution_staff(e.order_id,'fulfilment.manage')))
$$;
grant execute on function app_private.can_read_object(text,text) to anon;
grant execute on function app_private.can_read_object(text,text),app_private.can_upload_object(text,text) to authenticated;
-- Rebind stored Storage policy expressions to the new helpers, retaining all previous predicates.
do $$declare policy record;expression text;begin for policy in select * from pg_policies where schemaname='storage' and tablename='objects' loop
 if policy.qual like '%can_read_object%' then expression=replace(policy.qual,'pre_execution_can_read_object','can_read_object');execute format('alter policy %I on storage.objects using (%s)',policy.policyname,expression);end if;
 if policy.with_check like '%can_upload_object%' then expression=replace(policy.with_check,'pre_execution_can_upload_object','can_upload_object');execute format('alter policy %I on storage.objects with check (%s)',policy.policyname,expression);end if;
 end loop;end$$;
create function app_private.execution_registry_reference(p_evidence uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare e private.execution_evidence;d private.document_objects;begin
 select * into e from private.execution_evidence where id=p_evidence;select * into d from private.document_objects where id=e.document_id;
 if d.id is null or not(app_private.can_read_object(d.bucket_id,d.object_name) or app_private.can_upload_object(d.bucket_id,d.object_name)) then raise exception 'execution file access denied' using errcode='42501';end if;
 return jsonb_build_object('id',d.id,'bucket',d.bucket_id,'object_name',d.object_name,'content_type',d.content_type,'byte_size',d.byte_size::text,'scan_status',d.scan_status,'upload_expires_at',d.upload_expires_at);
end$$;
create function public.read_work_order(p_work uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_work_order(p_work)$$;
create function public.read_service_case(p_case uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_service_case(p_case)$$;
create function public.execution_dashboard(p_view text,p_from timestamptz default null,p_until timestamptz default null,p_zone uuid default null,p_city uuid default null,p_after uuid default null,p_limit integer default 25) returns jsonb language sql stable set search_path='' as $$select app_private.execution_dashboard(p_view,p_from,p_until,p_zone,p_city,p_after,p_limit)$$;
create function public.execution_document_reference(p_evidence uuid) returns jsonb language sql stable set search_path='' as $$select app_private.execution_registry_reference(p_evidence)$$;
revoke all on function public.read_work_order(uuid),public.read_service_case(uuid),public.execution_dashboard(text,timestamptz,timestamptz,uuid,uuid,uuid,integer),public.execution_document_reference(uuid) from public,anon;
grant execute on function public.read_work_order(uuid),public.read_service_case(uuid),public.execution_dashboard(text,timestamptz,timestamptz,uuid,uuid,uuid,integer),public.execution_document_reference(uuid),app_private.read_work_order(uuid),app_private.read_service_case(uuid),app_private.execution_dashboard(text,timestamptz,timestamptz,uuid,uuid,uuid,integer),app_private.execution_registry_reference(uuid) to authenticated;
create function app_private.guard_execution_record() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'execution records must be retained' using errcode='55000';end if;
 if tg_table_name='fulfilment_policies' then
 if old.status<>'draft' and not(old.status='approved' and new.status='retired' and(to_jsonb(new)-array['status','updated_at'])=(to_jsonb(old)-array['status','updated_at'])) then raise exception 'approved execution policy immutable' using errcode='55000';end if;
 elsif tg_table_name='execution_submissions' then
 if old.status in ('approved','rejected') or (old.status='submitted' and (to_jsonb(new)-array['status','reviewed_by','review_reason','updated_at'])<>(to_jsonb(old)-array['status','reviewed_by','review_reason','updated_at'])) then raise exception 'submitted answers immutable; correction requires new version' using errcode='55000';end if;
 elsif tg_table_name='execution_evidence' then
 if old.status<>'pending' or (to_jsonb(new)-array['status','reviewed_by','reviewed_at','review_reason','customer_visible','updated_at'])<>(to_jsonb(old)-array['status','reviewed_by','reviewed_at','review_reason','customer_visible','updated_at']) then raise exception 'reviewed evidence immutable' using errcode='55000';end if;
 elsif tg_table_name='quality_inspections' and old.status in ('approved','rejected','conditional') then raise exception 'quality decisions immutable' using errcode='55000';
 elsif tg_table_name='work_orders' then
 if old.status in ('closed','cancelled') or(to_jsonb(new)-array['revision','plan_revision','status','supervisor_id','owner_id','instructions','priority','paused_from','updated_at','completed_at','closed_at'])<>(to_jsonb(old)-array['revision','plan_revision','status','supervisor_id','owner_id','instructions','priority','paused_from','updated_at','completed_at','closed_at']) then raise exception 'work scope and terminal records immutable' using errcode='55000';end if;
 elsif tg_table_name='work_tasks' and old.status='closed' then raise exception 'closed task immutable' using errcode='55000';end if;return new;
end$$;
do $$declare t text;begin foreach t in array array['fulfilment_policies','work_orders','work_tasks','execution_submissions','execution_evidence','quality_inspections'] loop execute format('create trigger onit_execution_guard before update or delete on private.%I for each row execute function app_private.guard_execution_record()',t);end loop;end$$;
create function app_private.guard_work_feedback() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op<>'INSERT' and old.order_id is not null then raise exception 'feedback revision history immutable' using errcode='55000';end if;
 if tg_op='INSERT' and new.order_id is not null and not pg_has_role(current_user,(select relowner from pg_class where oid=tg_relid),'USAGE') then raise exception 'use authorised feedback command' using errcode='42501';end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger onit_work_feedback before insert or update or delete on public.customer_feedback for each row execute function app_private.guard_work_feedback();
alter table private.work_tasks add constraint execution_task_states check(status in ('awaiting_mobilisation','awaiting_capacity','mobilising','en_route','arrived','awaiting_customer_access','started','in_progress','paused','awaiting_materials','awaiting_customer_decision','work_completed','awaiting_qa','qa_rejected','rework_required','qa_approved','closed','cancelled'));
alter table private.work_orders add constraint execution_work_states check(status in ('awaiting_mobilisation','in_progress','work_completed','awaiting_qa','rework_required','qa_approved','awaiting_customer_confirmation','customer_disputed','completed','closed','cancelled','suspended'));
alter table private.fulfilment_policies add constraint approved_execution_policy_checker check(status='draft' or(approved_by is not null and approved_at is not null)),add unique nulls not distinct(service_version_id,customer_account_id,contract_reference,version);
create unique index one_live_inspection on private.quality_inspections(task_id,execution_round) where status in ('requested','submitted');
create index execution_work_queue on private.work_orders(status,starts_at,id);
create index execution_task_queue on private.work_tasks(work_order_id,status,id);
create index execution_history_page on private.execution_history(work_order_id,created_at desc,id);
create index execution_evidence_round on private.execution_evidence(task_id,execution_round,status);
create index service_case_queue on private.service_cases(order_id,status,severity,id);
create index execution_sla_due on private.sla_tracks(status,due_at,id);
do $$declare fk record;columns_sql text;begin for fk in select c.conrelid,c.conkey,c.conname,n.nspname,t.relname from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where c.contype='f' and n.nspname='private' and t.relname in ('fulfilment_policies','work_orders','work_tasks','task_dependencies','execution_history','execution_attendance','execution_evidence','execution_submissions','quality_inspections','quality_findings','rework_requests','service_cases','service_case_entries','customer_confirmations','operational_exceptions','sla_tracks') and not exists(select 1 from pg_index i where i.indrelid=t.oid and i.indkey[0]=c.conkey[1]) loop
 select string_agg(quote_ident(a.attname),',' order by k.pos) into columns_sql from unnest(fk.conkey) with ordinality k(num,pos) join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=k.num;
 execute format('create index %I on %I.%I(%s)','exe_fk_'||left(fk.relname,20)||'_'||substr(md5(fk.relname||':'||fk.conname),1,16),fk.nspname,fk.relname,columns_sql);
 end loop;end$$;
commit;
