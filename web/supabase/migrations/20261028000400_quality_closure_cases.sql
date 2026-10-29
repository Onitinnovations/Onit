begin;
alter table private.work_orders add column plan_revision integer not null default 1,add column paused_from text;
alter table private.execution_evidence add column customer_visible boolean not null default false;
create unique index verified_attendance_once on private.execution_attendance(verifies_id) where verifies_id is not null;
create function app_private.validate_execution_assignment(p_work uuid,p_task uuid default null) returns void language plpgsql security definer set search_path='' as $$declare w private.work_orders;o private.service_orders;r record;decision jsonb;reserved_ids uuid[];begin
 select * into w from private.work_orders where id=p_work;select * into o from private.service_orders where id=w.order_id;
 perform app_private.dispatch_locks(o.id);
 if not exists(select 1 from private.dispatch_proposals where id=w.proposal_id and order_id=o.id and status='confirmed') then raise exception 'confirmed execution bundle required' using errcode='23514';end if;
 if exists(select 1 from private.work_tasks task join private.assignment_resources a on a.id=task.resource_id join private.provider_capacity_reservations capacity on capacity.id=a.reservation_id where task.work_order_id=w.id and (p_task is null or task.id=p_task) and task.status not in ('cancelled','closed') and capacity.status<>'assigned') then raise exception 'execution capacity lost' using errcode='23514';end if;
 select array_agg(capacity.id) into reserved_ids from private.provider_capacity_reservations capacity join private.assignment_resources a on a.reservation_id=capacity.id join private.assignment_offers f on f.id=a.offer_id and f.proposal_id=w.proposal_id where capacity.status='assigned' and (p_task is null or exists(select 1 from private.work_tasks task where task.id=p_task and task.resource_id=a.id));
 if reserved_ids is null then raise exception 'assigned execution resource required' using errcode='23514';end if;
 update private.provider_capacity_reservations set status='released' where id=any(reserved_ids);
 for r in select * from private.provider_capacity_reservations where id=any(reserved_ids) order by provider_id,worker_profile_id loop
 decision=app_private.provider_eligibility(r.provider_id,o.service_version_id,o.zone_id,r.starts_at,r.ends_at,r.units::text,r.worker_profile_id);
 if (decision->>'eligible')::boolean is distinct from true then raise exception 'execution resource revalidation failed' using errcode='23514';end if;
 update private.provider_capacity_reservations set status='assigned' where id=r.id;
 end loop;
end$$;
create function app_private.execution_final_command(p_work uuid,p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare w private.work_orders;o private.service_orders;t private.work_tasks;p private.fulfilment_policies;ex private.operational_exceptions;
 resource private.assignment_resources;old_capacity private.provider_capacity_reservations;result uuid;new_resource uuid;new_capacity uuid;candidate uuid;decision jsonb;profile uuid;newstart timestamptz;related record;
begin
 select * into w from private.work_orders where id=p_work;select * into o from private.service_orders where id=w.order_id;select * into p from private.fulfilment_policies where id=w.policy_id;
 if p_data->>'task_id' is not null then select * into t from private.work_tasks where id=(p_data->>'task_id')::uuid and work_order_id=w.id;end if;
 if p_action in ('cancel_work','retire_for_reschedule','substitute','task_reassign','task_cancel','apply_sla_exception','transfer_rework') then
 select * into ex from private.operational_exceptions where id=(p_data->>'exception_id')::uuid and work_order_id=w.id for update;
 if ex.id is null or ex.status<>'approved' or ex.work_revision<>w.plan_revision or ex.valid_until<=now() or ex.decided_by=ex.created_by then raise exception 'current independently approved exception required' using errcode='23514';end if;
 end if;
 case p_action
 when 'apply_sla_exception' then
 if ex.kind<>'sla_extension' or not exists(select 1 from private.sla_tracks where id=(ex.proposal->>'sla_id')::uuid and work_order_id=w.id and (ex.proposal->>'new_due')::timestamptz>greatest(due_at,clock_timestamp())) then raise exception 'approved future SLA extension required' using errcode='23514';end if;
 update private.sla_tracks set due_at=(ex.proposal->>'new_due')::timestamptz,remaining=case when status='paused' then (ex.proposal->>'new_due')::timestamptz-clock_timestamp() end,status=case when status='breached' then 'running' else status end where id=(ex.proposal->>'sla_id')::uuid;
 update private.operational_exceptions set status='consumed' where id=ex.id;result=(ex.proposal->>'sla_id')::uuid;
 when 'transfer_rework' then
 if ex.kind<>'substitution' or ex.proposal->>'new_task_id' is distinct from t.id::text or t.status<>'awaiting_mobilisation' or t.is_container then raise exception 'independent rework transfer approval and unstarted execution task required' using errcode='23514';end if;
 if not exists(select 1 from private.rework_requests r join private.work_tasks original on original.id=r.original_task_id where r.id=(ex.proposal->>'rework_id')::uuid and r.status='active' and original.order_id=o.id) then raise exception 'same-order unresolved defect required' using errcode='23514';end if;
 update private.work_tasks set status='cancelled' where id=(select rework_task_id from private.rework_requests where id=(ex.proposal->>'rework_id')::uuid) and status='awaiting_capacity';
 update private.sla_tracks set task_id=t.id,work_order_id=w.id where target='rework' and task_id=(select rework_task_id from private.rework_requests where id=(ex.proposal->>'rework_id')::uuid) and status in ('running','paused','breached');
 update private.rework_requests set rework_task_id=t.id where id=(ex.proposal->>'rework_id')::uuid;update private.operational_exceptions set status='consumed' where id=ex.id;result=t.id;
 when 'customer_confirm' then
 if w.status not in ('awaiting_customer_confirmation','customer_disputed') or not app_private.order_customer(o.id,'approve') then raise exception 'current customer approver confirmation required' using errcode='42501';end if;
 if p_data->>'decision' not in ('confirmed','disputed') then raise exception 'explicit customer decision required' using errcode='23514';end if;
 if p_data->>'document_id' is not null and not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and customer_account_id=w.customer_account_id and scan_status='clean' and archived_at is null and classification in ('customer','work')) then raise exception 'same-account clean sign-off required' using errcode='23514';end if;
 insert into private.customer_confirmations(work_order_id,work_revision,decision,document_id,comment,created_by) values(w.id,w.plan_revision,p_data->>'decision',(p_data->>'document_id')::uuid,coalesce(p_data->>'comment',''),auth.uid()) returning id into result;
 if p_data->>'decision'='disputed' then
 update private.work_orders set status='customer_disputed' where id=w.id;update private.service_orders set status='customer_disputed' where id=o.id;
 insert into private.service_cases(order_id,customer_account_id,work_order_id,category,severity,priority,blocking,description,created_by) values(o.id,o.customer_account_id,w.id,'completion_dispute','major','urgent',true,coalesce(p_data->>'comment','Customer disputed completion'),auth.uid());
 else update private.work_orders set status='completed',completed_at=now() where id=w.id;
 update private.service_orders set status='completed' where id=o.id and not exists(select 1 from private.work_orders outstanding where outstanding.order_id=o.id and outstanding.status not in ('completed','closed','cancelled'));end if;
 update private.sla_tracks set status='met' where work_order_id=w.id and target='customer_response' and status in ('running','paused');
 when 'feedback' then
 if not app_private.order_customer(o.id,'approve') or w.status not in ('completed','closed') then raise exception 'customer completion feedback required' using errcode='42501';end if;
 insert into public.customer_feedback(customer_account_id,order_id,work_order_id,revision,previous_id,rating,comment,created_by)
 select o.customer_account_id,o.id,w.id,coalesce(max(revision),0)+1,(select id from public.customer_feedback where work_order_id=w.id order by revision desc limit 1),(p_data->>'rating')::integer,p_data->>'comment',auth.uid() from public.customer_feedback where work_order_id=w.id returning id into result;
 when 'close_work' then
 if w.status not in ('completed','awaiting_customer_confirmation') or not app_private.execution_independent(w.id) then raise exception 'independent administrative closure required' using errcode='42501';end if;
 if exists(select 1 from private.work_tasks task where task.work_order_id=w.id and task.mandatory and task.status not in ('qa_approved','closed') and not(task.status='cancelled' and (p.configuration->>'allow_partial_completion')::boolean and exists(select 1 from private.operational_exceptions exception where exception.work_order_id=w.id and exception.kind='partial_completion' and exception.status='consumed' and exception.proposal->>'task_id'=task.id::text))) then raise exception 'mandatory tasks or rework incomplete' using errcode='23514';end if;
 if exists(select 1 from private.work_tasks where work_order_id=w.id and status not in ('qa_approved','closed','cancelled')) then raise exception 'all active tasks need completion or authorised cancellation' using errcode='23514';end if;
 if not exists(select 1 from private.work_tasks where work_order_id=w.id) or exists(select 1 from private.rework_requests r join private.work_tasks task on task.id=r.rework_task_id where task.work_order_id=w.id and r.status='active') or exists(select 1 from private.service_cases where order_id=o.id and blocking and status not in ('resolved','closed')) then raise exception 'blocking work or cases remain' using errcode='23514';end if;
 for related in select * from private.work_tasks where work_order_id=w.id and not is_container and status<>'cancelled' loop
 if not app_private.execution_evidence_ready(related.id) or (select status from private.execution_submissions where task_id=related.id and execution_round=related.execution_round and phase='handover' order by version desc limit 1) is distinct from 'approved' then raise exception 'clean evidence and handover checklist required' using errcode='23514';end if;
 end loop;
 if not exists(select 1 from private.customer_confirmations where work_order_id=w.id and work_revision=w.plan_revision and customer_confirmations.decision='confirmed') then
 select * into ex from private.operational_exceptions where id=(p_data->>'exception_id')::uuid and work_order_id=w.id and kind='closure_without_confirmation' and status='approved' and work_revision=w.plan_revision and valid_until>now() for update;
 if ex.id is null or not (p.configuration->>'allow_closure_exception')::boolean or exists(select 1 from private.customer_confirmations where work_order_id=w.id and work_revision=w.plan_revision and customer_confirmations.decision='disputed') then raise exception 'explicit confirmation or approved alternative required' using errcode='23514';end if;
 update private.operational_exceptions set status='consumed' where id=ex.id;
 end if;
 update private.work_tasks set status='closed' where work_order_id=w.id and status='qa_approved';update private.work_orders set status='closed',closed_at=now(),revision=revision+1 where id=w.id;
 if not exists(select 1 from private.work_orders where order_id=o.id and status not in ('closed','cancelled')) then
 if exists(select 1 from private.assignment_resources ar join private.assignment_offers offer on offer.id=ar.offer_id and offer.proposal_id=w.proposal_id join private.provider_capacity_reservations capacity on capacity.id=ar.reservation_id and capacity.status='assigned' where not exists(select 1 from private.work_tasks planned where planned.order_id=o.id and planned.resource_id=ar.id and not planned.is_container and planned.status in ('closed','cancelled'))) then raise exception 'every allocated execution resource needs accounted work' using errcode='23514';end if;
 perform app_private.clear_order_dispatch(o.id,p_data->>'reason');update private.service_orders set status='closed' where id=o.id;
 end if;result=w.id;
 when 'cancel_work','retire_for_reschedule' then
 if ex.kind<>'cancel_work' or w.status in ('completed','closed','cancelled') then raise exception 'independent cancellation required' using errcode='23514';end if;
 update private.work_tasks set status='cancelled' where work_order_id=w.id and status<>'closed';update private.work_orders set status='cancelled',revision=revision+1 where id=w.id;
 update private.sla_tracks set status='met' where work_order_id=w.id and status in ('running','paused');
 if not exists(select 1 from private.work_orders where order_id=o.id and status not in ('closed','cancelled')) then
 perform app_private.clear_order_dispatch(o.id,p_data->>'reason');update private.service_orders set status=case p_action when 'retire_for_reschedule' then 'on_hold' else 'cancelled' end,revision=revision+1,released_by=null,released_revision=null where id=o.id;
 end if;update private.operational_exceptions set status='consumed' where id=ex.id;result=w.id;
 when 'task_cancel' then
 if ex.kind<>'partial_completion' or not (p.configuration->>'allow_partial_completion')::boolean or ex.proposal->>'task_id' is distinct from t.id::text then raise exception 'explicit partial task cancellation required' using errcode='23514';end if;
 update private.work_tasks set status='cancelled' where id=t.id;update private.operational_exceptions set status='consumed' where id=ex.id;result=t.id;
 when 'substitute','task_reassign' then
 if exists(select 1 from private.work_tasks other where other.resource_id=t.resource_id and other.work_order_id<>w.id and other.status not in ('closed','cancelled','qa_approved')) then raise exception 'shared-resource work orders must be suspended and retired before substitution' using errcode='23514';end if;
 if ex.kind<>'substitution' or ex.proposal->>'task_id' is distinct from t.id::text or t.id is null or t.status in ('qa_approved','closed','cancelled') then raise exception 'current task substitution exception required' using errcode='23514';end if;
 perform app_private.dispatch_locks(o.id,jsonb_build_array(jsonb_build_object('provider_id',(select provider_id from private.assignment_resources where id=t.resource_id),'worker_id',ex.proposal->>'worker_id')));
 if p_action='task_reassign' then
 perform app_private.validate_execution_assignment(w.id);
 select a.* into resource from private.assignment_resources a join private.assignment_offers offer on offer.id=a.offer_id and offer.proposal_id=w.proposal_id join private.provider_capacity_reservations cap on cap.id=a.reservation_id and cap.status='assigned' where a.id=(ex.proposal->>'resource_id')::uuid;
 if resource.id is null then raise exception 'current assigned replacement resource required' using errcode='23514';end if;new_resource=resource.id;
 else
 select * into resource from private.assignment_resources where id=t.resource_id;select * into old_capacity from private.provider_capacity_reservations where id=resource.reservation_id for update;profile=(ex.proposal->>'worker_id')::uuid;
 if profile is null or profile=resource.worker_id or exists(select 1 from private.assignment_resources other join private.provider_capacity_reservations cap on cap.id=other.reservation_id and cap.status='assigned' where other.offer_id=resource.offer_id and other.worker_id=profile) then raise exception 'different unallocated human required' using errcode='23514';end if;
 newstart=greatest(clock_timestamp()+interval '1 second',old_capacity.starts_at);
 if newstart>=old_capacity.ends_at then raise exception 'new reservation window required for overdue work' using errcode='23514';end if;
 update private.provider_capacity_reservations set status='released' where id=old_capacity.id;
 decision=app_private.provider_eligibility(resource.provider_id,o.service_version_id,o.zone_id,newstart,old_capacity.ends_at,old_capacity.units::text,profile);
 new_capacity=app_private.provider_reservation(resource.provider_id,'reserve',jsonb_build_object('service_version_id',o.service_version_id,'zone_id',o.zone_id,'start',newstart,'end',old_capacity.ends_at,'units',old_capacity.units::text,'worker_id',profile,'expires_at',least(newstart+interval '1 hour',old_capacity.ends_at),'purpose_reference','substitution:'||ex.id::text,'reason',p_data->>'reason'),gen_random_uuid()::text);
 update private.provider_capacity_reservations set status='assigned' where id=new_capacity;

 insert into private.dispatch_candidates(order_id,order_revision,provider_id,worker_id,units,decision,score,policy_id,created_by) values(o.id,o.revision,resource.provider_id,profile,old_capacity.units,decision,0,o.policy_id,auth.uid()) returning id into candidate;
 insert into private.assignment_resources(offer_id,provider_id,worker_id,reservation_id,candidate_id,resource_version,created_by) select resource.offer_id,resource.provider_id,profile,new_capacity,candidate,coalesce(max(resource_version),0)+1,auth.uid() from private.assignment_resources where offer_id=resource.offer_id and worker_id=profile returning id into new_resource;
 end if;
 if exists(select 1 from private.work_tasks other where other.resource_id=new_resource and other.id<>t.id and other.status not in ('cancelled','closed','qa_approved') and tstzrange(other.starts_at,other.ends_at,'[)')&&tstzrange(greatest(t.starts_at,clock_timestamp()+interval '1 second'),t.ends_at,'[)')) then raise exception 'replacement task schedule conflict' using errcode='23514';end if;
 -- Substitution is a resource change: all active tasks sharing that resource move together.
 update private.work_tasks set resource_id=new_resource,status='awaiting_mobilisation',execution_round=execution_round+1,revision=revision+1,accepted_at=null,actual_start=null,actual_finish=null,completion_actor=null,supervisor_verified_by=null,starts_at=greatest(starts_at,clock_timestamp()+interval '1 second') where resource_id=t.resource_id and status not in ('closed','cancelled','qa_approved') and (p_action='substitute' or id=t.id);
 if p_action='task_reassign' and not exists(select 1 from private.work_tasks remaining where remaining.resource_id=t.resource_id and remaining.status not in ('closed','cancelled')) then update private.provider_capacity_reservations set status='released' where id=(select reservation_id from private.assignment_resources where id=t.resource_id) and status='assigned';end if;
 update private.work_orders set plan_revision=plan_revision+1,status='in_progress' where id=w.id;update private.operational_exceptions set status='consumed' where id=ex.id;result=new_resource;
 else raise exception 'unsupported final execution operation' using errcode='23514';end case;return result;
end$$;
create function app_private.quality_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare w private.work_orders;o private.service_orders;t private.work_tasks;q private.quality_inspections;s private.execution_submissions;p private.fulfilment_policies;finding jsonb;r record;result uuid;ev uuid;provider uuid;receipt private.transaction_commands;payload jsonb=jsonb_build_object('work',p_work,'action',p_action,'data',p_data);permission text;
begin
 if auth.uid() is null or p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 or length(coalesce(p_data->>'reason','')) not between 1 and 2000 then raise exception 'bounded authenticated quality operation required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('quality:'||auth.uid()::text||p_key,0));select order_id into o.id from private.work_orders where id=p_work;select * into o from private.service_orders where id=o.id for update;select * into w from private.work_orders where id=p_work for update;
 permission=case p_action when 'request' then 'fulfilment.manage' when 'submit' then 'fulfilment.qa.perform' else 'fulfilment.qa.approve' end;
 if w.id is null or not app_private.execution_staff(o.id,permission) or not app_private.execution_independent(w.id) then raise exception 'independent scoped quality authority required' using errcode='42501';end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='quality_command' and idempotency_key=p_key;if found then if receipt.payload<>payload then raise exception 'quality idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if (p_data->>'expected_revision')::integer is distinct from w.revision or w.status in ('closed','cancelled','suspended') then raise exception 'stale quality operation' using errcode='40001';end if;
 select * into p from private.fulfilment_policies where id=w.policy_id;
 if p_action='request' then
 select * into t from private.work_tasks where id=(p_data->>'task_id')::uuid and work_order_id=w.id for update;
 if t.id is null or t.status<>'awaiting_qa' or t.supervisor_verified_by is null or not app_private.execution_evidence_ready(t.id) or not app_private.execution_target_staff((p_data->>'inspector_id')::uuid,o.id,'fulfilment.qa.perform') or not app_private.execution_target_independent(w.id,(p_data->>'inspector_id')::uuid) then raise exception 'verified task and qualified quality inspector required' using errcode='23514';end if;
 insert into private.quality_inspections(task_id,version,execution_round,inspector_id,scheduled_at,created_by) select t.id,coalesce(max(version),0)+1,t.execution_round,(p_data->>'inspector_id')::uuid,(p_data->>'scheduled_at')::timestamptz,auth.uid() from private.quality_inspections where task_id=t.id returning id into result;
 else
 select q1.* into q from private.quality_inspections q1 join private.work_tasks task on task.id=q1.task_id and task.work_order_id=w.id where q1.id=(p_data->>'id')::uuid for update of q1;select * into t from private.work_tasks where id=q.task_id for update;
 if q.id is null or q.execution_round<>t.execution_round or q.version<>(select max(version) from private.quality_inspections where task_id=t.id and execution_round=t.execution_round) then raise exception 'current quality inspection required' using errcode='42501';end if;
 if p_action='submit' then
 select * into s from private.execution_submissions where id=(p_data->>'submission_id')::uuid and task_id=t.id and phase='quality' and execution_round=t.execution_round and created_by=auth.uid() and status='submitted';
 if q.status<>'requested' or q.inspector_id<>auth.uid() or s.id is null or jsonb_typeof(p_data->'findings') is distinct from 'array' or jsonb_array_length(p_data->'findings')>100 then raise exception 'assigned inspector and quality submission required' using errcode='42501';end if;
 for finding in select value from jsonb_array_elements(p_data->'findings') loop insert into private.quality_findings(inspection_id,code,severity,description,corrective_action,blocking,created_by) values(q.id,finding->>'code',finding->>'severity',finding->>'description',finding->>'corrective_action',coalesce((finding->>'blocking')::boolean,true),auth.uid());end loop;
 update private.quality_inspections set status='submitted',submission_id=s.id where id=q.id;result=q.id;
 elsif p_action='decide' then
 if q.status<>'submitted' or q.inspector_id=auth.uid() or q.created_by=auth.uid() or t.completion_actor=auth.uid() or t.supervisor_verified_by=auth.uid() or not app_private.execution_evidence_ready(t.id) then raise exception 'independent quality checker required' using errcode='42501';end if;
 if p_data->>'decision' not in ('approved','rejected','conditional') then raise exception 'explicit quality outcome required' using errcode='23514';end if;
 if p_data->>'decision' in ('approved','conditional') and (exists(select 1 from private.quality_findings where inspection_id=q.id and blocking) or (p_data->>'decision'='conditional' and not(p.configuration->>'allow_conditional_qa')::boolean)) then raise exception 'blocking defects prevent quality approval' using errcode='23514';end if;
 update private.quality_inspections set status=p_data->>'decision',decided_by=auth.uid(),decision_reason=p_data->>'reason' where id=q.id;
 update private.execution_submissions set status=case when p_data->>'decision'='rejected' then 'rejected' else 'approved' end,reviewed_by=auth.uid(),review_reason=p_data->>'reason' where id=q.submission_id;
 if p_data->>'decision'='rejected' then
 if not exists(select 1 from private.quality_findings where inspection_id=q.id) then raise exception 'rejected quality needs evidenced findings' using errcode='23514';end if;
 for r in select * from private.quality_findings where inspection_id=q.id loop
 insert into private.work_tasks(work_order_id,order_id,customer_account_id,resource_id,code,description,mandatory,status,starts_at,ends_at,created_by) values(w.id,o.id,w.customer_account_id,t.resource_id,'rework-'||r.id::text,r.corrective_action,true,case when clock_timestamp()>=t.ends_at then 'awaiting_capacity' else 'awaiting_mobilisation' end,t.starts_at,t.ends_at,auth.uid()) returning id into result;
 insert into private.rework_requests(finding_id,original_task_id,rework_task_id,due_at,created_by) values(r.id,t.id,result,clock_timestamp()+make_interval(secs=>(p.configuration->'sla'->>'rework')::integer),auth.uid());
 end loop;update private.work_tasks set status='rework_required' where id=t.id;update private.work_orders set status='rework_required',plan_revision=plan_revision+1 where id=w.id;
 else
 update private.work_tasks set status='qa_approved' where id=t.id;update private.rework_requests set status='accepted' where rework_task_id=t.id and status='active';
 update private.work_tasks original set status='qa_approved' where original.status not in ('closed','cancelled') and original.id in(select original_task_id from private.rework_requests where rework_task_id=t.id) and not exists(select 1 from private.rework_requests remaining where remaining.original_task_id=original.id and remaining.status='active');
 if not exists(select 1 from private.work_tasks where work_order_id=w.id and mandatory and status not in ('qa_approved','closed','cancelled')) then update private.work_orders set status='awaiting_customer_confirmation' where id=w.id;update private.service_orders set status='awaiting_customer_confirmation' where id=o.id;end if;
 end if;result=q.id;
 else raise exception 'unsupported quality action' using errcode='23514';end if;
 end if;
 update private.work_orders set revision=revision+1 where id=w.id;update private.work_tasks set revision=revision+1 where id=t.id;
 ev=app_private.execution_event(w.id,t.id,'quality_'||p_action,result,t.status,(select status from private.work_tasks where id=t.id),p_data->>'reason',permission);
 if p_action='decide' then select provider_id into provider from private.assignment_resources where id=t.resource_id;perform app_private.execution_performance(ev,provider,'quality',case when p_data->>'decision'='rejected' then 0 else 1 end);update private.sla_tracks set status='met' where task_id=t.id and target='quality_review' and status in ('running','paused');
 if p_data->>'decision'='rejected' then for r in select corrective.id from private.rework_requests rework join private.quality_findings finding on finding.id=rework.finding_id and finding.inspection_id=q.id join private.work_tasks corrective on corrective.id=rework.rework_task_id loop perform app_private.execution_sla(w.id,r.id,null,ev,'rework');end loop;else update private.sla_tracks set status='met' where task_id=t.id and target='rework' and status in ('running','paused');end if;
 if (select status from private.work_orders where id=w.id)='awaiting_customer_confirmation' then perform app_private.execution_sla(w.id,null,null,ev,'customer_response');end if;end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'quality_command',p_key,payload,result);return result;
end$$;
create function public.quality_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.quality_command(p_work,p_action,p_data,p_key)$$;
revoke all on function public.quality_command(uuid,text,jsonb,text) from public,anon;
grant execute on function public.quality_command(uuid,text,jsonb,text),app_private.quality_command(uuid,text,jsonb,text) to authenticated;
commit;
