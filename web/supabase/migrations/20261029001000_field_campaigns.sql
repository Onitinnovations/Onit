begin;
alter table private.field_campaigns add column customer_approved_by uuid references public.profiles(id) on delete restrict,add column customer_approved_at timestamptz;
alter table private.field_campaign_locations add column location_snapshot jsonb not null default '{}' check(jsonb_typeof(location_snapshot)='object'),add column milestone text not null default 'delivery',add column mandatory boolean not null default true,add unique(campaign_id,task_id);
alter table private.field_campaign_submissions add column execution_round integer not null check(execution_round>0),add column content_digest text not null,add unique(location_id,execution_round,content_digest);
create function app_private.field_ready(p_operation uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.field_campaigns where operation_id=p_operation and customer_approved_by is not null)
 and exists(select 1 from private.field_campaign_locations where operation_id=p_operation)
 and not exists(select 1 from private.operation_orders member where member.operation_id=p_operation and not exists(select 1 from private.field_campaign_locations location join private.work_tasks task on task.id=location.task_id where location.operation_id=p_operation and task.order_id=member.order_id))
 and not exists(select 1 from private.field_campaign_locations where operation_id=p_operation and(mandatory or status<>'cancelled') and status<>'client_accepted')
$$;
create function app_private.field_action(p_operation uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare operation private.service_operations;campaign private.field_campaigns;location private.field_campaign_locations;submission private.field_campaign_submissions;response private.execution_submissions;
 task private.work_tasks;work private.work_orders;result uuid;staff boolean;begin
 select * into operation from private.service_operations where id=p_operation;staff=app_private.operation_staff(operation.id);
 if operation.kind<>'field_campaign' then raise exception 'field campaign operation required' using errcode='23514';end if;
 case p_action
 when 'campaign.create' then
 if not staff or operation.status<>'planning' or not exists(select 1 from private.service_orders where id=operation.primary_order_id and classification='corporate') or jsonb_typeof(p_data->'specification') is distinct from 'object' or not exists(select 1 from public.service_checklists checklist where checklist.id=(p_data->>'checklist_id')::uuid and checklist.service_version_id=operation.service_version_id and checklist.checklist_type='execution' and checklist.publication_status='published' and checklist.published_by is not null) then raise exception 'corporate campaign, approved field form and explicit specification required' using errcode='23514';end if;
 insert into private.field_campaigns(operation_id,specification,checklist_id,starts_at,ends_at,created_by) values(operation.id,p_data->'specification',(p_data->>'checklist_id')::uuid,(p_data->>'start')::timestamptz,(p_data->>'end')::timestamptz,auth.uid()) returning id into result;
 when 'location.create' then
 select * into campaign from private.field_campaigns where operation_id=operation.id;
 select task_row.* into task from private.operation_tasks link join private.work_tasks task_row on task_row.id=link.task_id where link.operation_id=operation.id and link.purpose='field_visit' and task_row.id=(p_data->>'task_id')::uuid;
 select * into work from private.work_orders where id=task.work_order_id;
 if not staff or operation.status<>'planning' or campaign.id is null or campaign.customer_approved_by is not null or task.id is null or task.starts_at<campaign.starts_at or task.ends_at>campaign.ends_at or(select(configuration->>'execution_checklist')::uuid from private.fulfilment_policies where id=work.policy_id) is distinct from campaign.checklist_id or jsonb_typeof(p_data->'location') is distinct from 'object' or p_data->'location' ?| array['gps_verified','verified','verification_success'] then raise exception 'planned assigned location, pinned form and declared-only location required' using errcode='23514';end if;
 insert into private.field_campaign_locations(operation_id,campaign_id,task_id,external_reference,location_snapshot,milestone,mandatory,created_by) values(operation.id,campaign.id,task.id,p_data->>'reference',p_data->'location',p_data->>'milestone',coalesce((p_data->>'mandatory')::boolean,true),auth.uid()) returning id into result;
 when 'campaign.customer_scope' then
 select * into campaign from private.field_campaigns where operation_id=operation.id;
 if campaign.id is null or operation.status<>'planning' or campaign.customer_approved_by is not null or not app_private.order_customer(operation.primary_order_id,'approve') or not exists(select 1 from private.field_campaign_locations where campaign_id=campaign.id) then raise exception 'current corporate approval of planned campaign required' using errcode='42501';end if;
 update private.field_campaigns set customer_approved_by=auth.uid(),customer_approved_at=clock_timestamp() where id=campaign.id;result=campaign.id;
 when 'field.submit' then
 select * into location from private.field_campaign_locations where id=(p_data->>'location_id')::uuid and operation_id=operation.id for update;
 select * into task from private.work_tasks where id=location.task_id;select * into campaign from private.field_campaigns where id=location.campaign_id;
 select * into response from private.execution_submissions where id=(p_data->>'submission_id')::uuid;
 if operation.status<>'active' or location.id is null or location.status not in ('pending','rework') or campaign.customer_approved_by is null or not app_private.execution_worker(task.id) or task.status not in ('started','in_progress','work_completed') or response.task_id is distinct from task.id or response.created_by<>auth.uid() or response.execution_round<>task.execution_round or response.phase<>'execution' or response.status<>'submitted' or response.checklist_id<>campaign.checklist_id or not exists(select 1 from private.execution_attendance where task_id=task.id and execution_round=task.execution_round and kind='check_in') then raise exception 'current field agent, actual attendance and submitted pinned form required' using errcode='42501';end if;
 perform app_private.operation_validate_resource(operation.id,task.resource_id);
 if not app_private.execution_evidence_ready(task.id) then raise exception 'mandatory accepted field evidence required' using errcode='23514';end if;
 insert into private.field_campaign_submissions(operation_id,location_id,execution_submission_id,version,execution_round,content_digest,created_by)
 select operation.id,location.id,response.id,coalesce(max(version),0)+1,task.execution_round,md5(response.answers::text||coalesce((select string_agg(document_id::text,',' order by document_id) from private.execution_evidence where task_id=task.id and execution_round=task.execution_round and status='approved'),'')),auth.uid() from private.field_campaign_submissions where location_id=location.id returning id into result;
 update private.field_campaign_locations set status='submitted' where id=location.id;
 when 'field.review' then
 select * into submission from private.field_campaign_submissions where id=(p_data->>'id')::uuid and operation_id=operation.id for update;
 select * into location from private.field_campaign_locations where id=submission.location_id;select * into task from private.work_tasks where id=location.task_id;select * into work from private.work_orders where id=task.work_order_id;
 if submission.id is null or submission.status<>'submitted' or submission.execution_round<>task.execution_round or not app_private.execution_staff(task.order_id,'fulfilment.supervise') or not app_private.execution_independent(work.id) or submission.created_by=auth.uid() or jsonb_typeof(p_data->'approve') is distinct from 'boolean' then raise exception 'independent current field review required' using errcode='42501';end if;
 perform app_private.fulfilment_command(work.id,'review_checklist',jsonb_build_object('id',submission.execution_submission_id,'task_id',task.id,'expected_revision',work.revision,'task_revision',task.revision,'approve',(p_data->>'approve')::boolean,'reason',p_data->>'reason'),gen_random_uuid()::text);
 update private.field_campaign_submissions set status=case when(p_data->>'approve')::boolean then 'submitted' else 'rejected' end,reviewed_by=auth.uid() where id=submission.id;
 update private.field_campaign_locations set status=case when(p_data->>'approve')::boolean then 'submitted' else 'rework' end where id=location.id;result=submission.id;
 when 'field.quality' then
 select * into location from private.field_campaign_locations where id=(p_data->>'location_id')::uuid and operation_id=operation.id for update;select * into task from private.work_tasks where id=location.task_id;
 select * into submission from private.field_campaign_submissions where location_id=location.id order by version desc limit 1;
 if location.id is null or location.status<>'submitted' or submission.reviewed_by is null or task.status<>'qa_approved' or submission.execution_round<>task.execution_round or not app_private.operation_staff(operation.id,'specialized.approve') or not app_private.execution_target_independent(task.work_order_id,auth.uid()) or not exists(select 1 from private.execution_submissions where id=submission.execution_submission_id and status='approved') or not exists(select 1 from private.quality_inspections where task_id=task.id and status='approved' and decided_by is not null) then raise exception 'supervisor review and independent shared field quality approval required' using errcode='42501';end if;
 update private.field_campaign_submissions set status='quality_approved' where id=submission.id;update private.field_campaign_locations set status='quality_approved' where id=location.id;result=location.id;
 when 'field.client_accept' then
 select * into location from private.field_campaign_locations where id=(p_data->>'location_id')::uuid and operation_id=operation.id for update;select * into task from private.work_tasks where id=location.task_id;
 if location.id is null or location.status<>'quality_approved' or task.status<>'qa_approved' or not app_private.order_customer(task.order_id,'approve') then raise exception 'current scoped corporate client and approved deliverable required' using errcode='42501';end if;
 update private.field_campaign_locations set status='client_accepted',client_approved_by=auth.uid() where id=location.id;update private.field_campaign_submissions set status='client_accepted' where location_id=location.id and status='quality_approved';result=location.id;
 when 'field.client_cancel' then
 select * into location from private.field_campaign_locations where id=(p_data->>'location_id')::uuid and operation_id=operation.id for update;select * into task from private.work_tasks where id=location.task_id;
 if location.id is null or location.mandatory or location.status in ('client_accepted','cancelled') or task.status<>'cancelled' or not app_private.order_customer(task.order_id,'approve') or not exists(select 1 from private.operational_exceptions exception where exception.work_order_id=task.work_order_id and exception.kind='partial_completion' and exception.status='consumed' and exception.proposal->>'task_id'=task.id::text) then raise exception 'optional target, independently approved shared cancellation and current client acknowledgement required' using errcode='42501';end if;
 update private.field_campaign_locations set status='cancelled',client_approved_by=auth.uid() where id=location.id;result=location.id;
 when 'field.rework_link' then
 select * into location from private.field_campaign_locations where id=(p_data->>'location_id')::uuid and operation_id=operation.id for update;
 select * into task from private.work_tasks where id=(p_data->>'task_id')::uuid;
 if not staff or location.id is null or location.status in ('client_accepted','cancelled') or task.status<>'awaiting_mobilisation' or not exists(select 1 from private.rework_requests request where request.original_task_id=location.task_id and request.rework_task_id=task.id and request.status='active') then raise exception 'actual shared corrective task required' using errcode='23514';end if;
 insert into private.operation_tasks(operation_id,order_id,customer_account_id,work_order_id,task_id,purpose,created_by) values(operation.id,task.order_id,task.customer_account_id,task.work_order_id,task.id,'field_visit',auth.uid());
 perform app_private.operation_validate_resource(operation.id,task.resource_id,false);update private.field_campaign_locations set task_id=task.id,status='rework' where id=location.id;result=location.id;
 else raise exception 'unknown field command' using errcode='23514';end case;return result;
end$$;
revoke all on function app_private.field_ready(uuid),app_private.field_action(uuid,text,jsonb) from public,anon,authenticated;
do $$declare source text;begin
 source=pg_get_functiondef('app_private.service_operation_command(uuid,text,jsonb,text)'::regprocedure);
 source=replace(source,'when ''procurement'' then app_private.procurement_ready(operation.id) else false','when ''procurement'' then app_private.procurement_ready(operation.id) when ''field_campaign'' then app_private.field_ready(operation.id) else false');
 source=replace(source,$fragment$else raise exception 'unsupported specialised command' using errcode='23514';end if;$fragment$,$fragment$elsif operation.kind='field_campaign' then result=app_private.field_action(operation.id,p_action,p_data);
 else raise exception 'unsupported specialised command' using errcode='23514';end if;$fragment$);execute source;
end$$;
commit;
