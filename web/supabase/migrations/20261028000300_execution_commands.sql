begin;
alter table private.work_tasks add column is_container boolean not null default false;
create function app_private.execution_target_staff(p_profile uuid,p_order uuid,p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_orders o join private.user_role_assignments a on a.profile_id=p_profile and a.revoked_at is null and (a.valid_until is null or a.valid_until>now())
 join private.roles r on r.id=a.role_id and r.archived_at is null join private.role_permissions rp on rp.role_id=r.id join private.permissions permission on permission.id=rp.permission_id and permission.code=p_permission
 join private.employee_profiles e on e.profile_id=p_profile and e.status='active' join public.organisations employer on employer.id=e.organisation_id and employer.status='active' and employer.organisation_type='onit'
 join public.profiles subject on subject.id=p_profile and subject.status='active' where o.id=p_order and (a.scope='global' or(a.scope='organisation' and a.organisation_id=o.organisation_id and exists(select 1 from private.organisation_members m where m.profile_id=p_profile and m.organisation_id=a.organisation_id and m.status='active' and m.revoked_at is null and (m.valid_until is null or m.valid_until>now())))))
$$;
create function app_private.execution_sla(p_work uuid,p_task uuid,p_case uuid,p_event uuid,p_target text) returns uuid language plpgsql security definer set search_path='' as $$declare w private.work_orders;seconds integer;result uuid;begin
 select * into w from private.work_orders where id=p_work;
 select (configuration->'sla'->>p_target)::integer into seconds from private.fulfilment_policies where id=w.policy_id;
 if seconds is null then raise exception 'mandatory SLA configuration unavailable' using errcode='23514';end if;
 insert into private.sla_tracks(order_id,work_order_id,task_id,case_id,target,source_event_id,due_at,created_by) values(w.order_id,w.id,p_task,p_case,p_target,p_event,(case when p_target in ('mobilisation','arrival','start','task_completion') then coalesce((select starts_at from private.work_tasks where id=p_task),clock_timestamp()) else clock_timestamp() end)+make_interval(secs=>seconds),auth.uid()) returning id into result;return result;
end$$;
create function app_private.execution_evidence_ready(p_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.work_tasks t join private.work_orders w on w.id=t.work_order_id join private.fulfilment_policies p on p.id=w.policy_id where t.id=p_task
 and not exists(select 1 from jsonb_array_elements_text(p.configuration->'evidence') required where not exists(select 1 from private.execution_evidence e join private.document_objects d on d.id=e.document_id and d.scan_status='clean' and d.archived_at is null where e.task_id=t.id and e.execution_round=t.execution_round and e.classification=required and e.status='approved'))
 and not exists(select 1 from private.execution_submissions s,jsonb_array_elements(s.definition_snapshot->'fields') f where s.task_id=t.id and s.execution_round=t.execution_round and s.status in ('submitted','approved') and (f->>'evidence_required')::boolean and (f->'condition' is null or f->'condition'='null'::jsonb or app_private.answer_condition(s.answers->(f->'condition'->>'field'),f->'condition'->>'operator',f->'condition'->'value')) and not exists(select 1 from private.execution_evidence e join private.document_objects d on d.id=e.document_id and d.scan_status='clean' and d.archived_at is null where e.task_id=t.id and e.execution_round=t.execution_round and e.classification=f->>'key' and e.status='approved')))
$$;
create function app_private.execution_performance(p_event uuid,p_provider uuid,p_metric text,p_success integer) returns void language plpgsql security definer set search_path='' as $$begin
 insert into private.provider_performance_events(provider_id,metric,successful,observations,source_reference,occurred_at,source_event_id,created_by)
 values(p_provider,p_metric,p_success,1,'execution:'||p_event::text,clock_timestamp(),p_event,auth.uid()) on conflict(provider_id,metric,source_event_id) do nothing;
end$$;
create function app_private.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare w private.work_orders;t private.work_tasks;o private.service_orders;p private.fulfilment_policies;a private.assignment_resources;
 s private.execution_submissions;e private.execution_evidence;att private.execution_attendance;exception_row private.operational_exceptions;
 result uuid;event_id uuid;receipt private.transaction_commands;payload jsonb=jsonb_build_object('work',p_work,'action',p_action,'data',p_data);
 reason text=p_data->>'reason';permission text='fulfilment.manage';config jsonb;definition jsonb;nextstate text;v_phase text;contract_ref text;oldstate text;start_time timestamptz;end_time timestamptz;related record;round_number integer;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>131072 or reason is null or length(trim(reason)) not between 1 and 2000 then raise exception 'bounded execution command required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('execution-command:'||auth.uid()::text||p_key,0));
 if p_action='create_work' then select * into o from private.service_orders where id=(p_data->>'order_id')::uuid for update;
 else select order_id into o.id from private.work_orders where id=p_work;select * into o from private.service_orders where id=o.id for update;select * into w from private.work_orders where id=p_work for update;end if;
 if o.id is null then raise exception 'execution order unavailable' using errcode='42501';end if;
 if p_action<>'create_work' then
 select * into p from private.fulfilment_policies where id=w.policy_id;config=p.configuration;
 if p_data->>'task_id' is not null then select * into t from private.work_tasks where id=(p_data->>'task_id')::uuid and work_order_id=w.id for update;if not found then raise exception 'task unavailable' using errcode='42501';end if;end if;
 end if;
 permission=case when p_action in ('supervisor_verify','review_checklist','review_evidence','supervisor_assign') then 'fulfilment.supervise' when p_action='close_work' then 'fulfilment.close' when p_action='decide_exception' then 'fulfilment.exceptions.approve' else 'fulfilment.manage' end;
 if not (app_private.execution_staff(o.id,permission) or (p_action in ('accept_task','progress','attendance','save_checklist','submit_checklist','attach_evidence','prepare_upload') and app_private.execution_worker(t.id)) or (p_action in ('customer_confirm','feedback') and app_private.order_customer(o.id,'approve')) or (p_action in ('save_checklist','submit_checklist') and app_private.execution_staff(o.id,'fulfilment.qa.perform'))) then raise exception 'execution operation denied' using errcode='42501';end if;
 if app_private.execution_worker(t.id) and not app_private.execution_staff(o.id,permission) then permission='assigned.personnel';end if;
 if p_action in ('customer_confirm','feedback') then permission='customer.approve';end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='fulfilment_command' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'execution idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action<>'create_work' then
 if (p_data->>'expected_revision')::integer is distinct from w.revision or (w.status in ('closed','cancelled') and p_action<>'feedback') then raise exception 'stale or terminal work order' using errcode='40001';end if;
 if t.id is not null and t.status in ('closed','cancelled') then raise exception 'terminal task' using errcode='40001';end if;
 if t.id is not null and (p_data->>'task_revision')::integer is distinct from t.revision then raise exception 'stale task' using errcode='40001';end if;
 if w.status='suspended' and p_action in ('progress','accept_task','attendance','submit_checklist','supervisor_verify') then raise exception 'work suspended' using errcode='55000';end if;
 end if;
 if p_action in ('review_checklist','review_evidence','decide_exception') and jsonb_typeof(p_data->'approve') is distinct from 'boolean' then raise exception 'explicit review decision required' using errcode='23514';end if;
 oldstate=coalesce(t.status,w.status);
 case p_action
 when 'create_work' then
 if o.status not in ('assigned','in_progress','awaiting_qa') or not app_private.order_gate(o.id) or not exists(select 1 from private.dispatch_proposals where id=(p_data->>'proposal_id')::uuid and order_id=o.id and status='confirmed' and order_revision=o.revision) then raise exception 'commercially released confirmed assignment required' using errcode='23514';end if;
 select card.contract_reference into contract_ref from private.order_commercial_versions commercial join private.quotation_commercial_context commercial_context on commercial_context.id=commercial.quotation_version_id join private.service_rate_cards card on card.id=commercial_context.rate_card_id where commercial.order_id=o.id order by commercial.version desc limit 1;
 select * into p from private.fulfilment_policies where service_version_id=o.service_version_id and status='approved' and valid_from<=now() and (valid_until is null or valid_until>=o.ends_at) and (customer_account_id is null or customer_account_id=o.customer_account_id) and (contract_reference is null or contract_reference=contract_ref) order by (customer_account_id is not null) desc,(contract_reference is not null) desc limit 1;
 if p.id is null or not app_private.execution_target_staff((p_data->>'supervisor_id')::uuid,o.id,'fulfilment.supervise') or not app_private.execution_target_staff((p_data->>'owner_id')::uuid,o.id,'fulfilment.manage') then raise exception 'approved execution policy and scoped staff required' using errcode='23514';end if;
 insert into private.work_orders(order_id,customer_account_id,proposal_id,policy_id,code,scope_snapshot,supervisor_id,owner_id,priority,instructions,starts_at,ends_at,created_by)
 values(o.id,o.customer_account_id,(p_data->>'proposal_id')::uuid,p.id,p_data->>'code',(select jsonb_build_object('quotation_version_id',snapshot->'id','lines',(select jsonb_agg(jsonb_build_object('description',line->'description','kind',line->'kind','quantity',line->'quantity')) from jsonb_array_elements(snapshot->'lines') line),'service_location_id',o.service_location_id) from private.order_commercial_versions where order_id=o.id order by version desc limit 1),(p_data->>'supervisor_id')::uuid,(p_data->>'owner_id')::uuid,p_data->>'priority',coalesce(p_data->>'instructions',''),o.starts_at,o.ends_at,auth.uid()) returning * into w;perform app_private.validate_execution_assignment(w.id);result=w.id;
 when 'create_task' then
 if w.status not in ('awaiting_mobilisation','in_progress') then raise exception 'work planning closed' using errcode='55000';end if;
 select a1.* into a from private.assignment_resources a1 join private.assignment_offers f on f.id=a1.offer_id and f.proposal_id=w.proposal_id join private.provider_capacity_reservations r on r.id=a1.reservation_id and r.status='assigned' where a1.id=(p_data->>'resource_id')::uuid;
 start_time=(p_data->>'start')::timestamptz;end_time=(p_data->>'end')::timestamptz;
 if a.id is null or start_time is null or end_time is null or start_time<w.starts_at or end_time>w.ends_at or end_time<=start_time then raise exception 'task must fit assigned capacity window' using errcode='23514';end if;
 if not coalesce((p_data->>'is_container')::boolean,false) and exists(select 1 from private.work_tasks other join private.assignment_resources ar on ar.id=other.resource_id where other.order_id=o.id and ar.worker_id=a.worker_id and not other.is_container and other.status not in ('cancelled','closed') and tstzrange(other.starts_at,other.ends_at,'[)')&&tstzrange(start_time,end_time,'[)')) then raise exception 'personnel task schedule conflict' using errcode='23514';end if;
 if p_data->>'parent_task_id' is not null and not exists(select 1 from private.work_tasks where id=(p_data->>'parent_task_id')::uuid and work_order_id=w.id and is_container) then raise exception 'same-work container parent required' using errcode='23514';end if;
 insert into private.work_tasks(work_order_id,order_id,customer_account_id,parent_task_id,resource_id,code,description,mandatory,is_container,starts_at,ends_at,created_by)
 values(w.id,o.id,o.customer_account_id,(p_data->>'parent_task_id')::uuid,a.id,p_data->>'code',p_data->>'description',coalesce((p_data->>'mandatory')::boolean,true),coalesce((p_data->>'is_container')::boolean,false),start_time,end_time,auth.uid()) returning id into result;
 when 'operational_note' then
 if length(coalesce(p_data->>'note','')) not between 1 and 8000 then raise exception 'bounded operational note required' using errcode='23514';end if;result=w.id;
 when 'revise_work' then
 if w.status not in ('awaiting_mobilisation','in_progress','suspended') or p_data->>'priority' not in ('normal','urgent','critical') or p_data->>'instructions' is null then raise exception 'active work instructions and priority required' using errcode='23514';end if;
 if not app_private.execution_target_staff((p_data->>'owner_id')::uuid,o.id,'fulfilment.manage') then raise exception 'scoped operational owner required' using errcode='42501';end if;
 update private.work_orders set instructions=p_data->>'instructions',priority=p_data->>'priority',owner_id=(p_data->>'owner_id')::uuid,plan_revision=plan_revision+1 where id=w.id;result=w.id;
 when 'dependency' then
 if t.status<>'awaiting_mobilisation' then raise exception 'dependencies freeze before execution' using errcode='55000';end if;
 if exists(with recursive ancestors(id) as(select (p_data->>'depends_on_id')::uuid union select d.depends_on_id from private.task_dependencies d join ancestors x on d.task_id=x.id) select 1 from ancestors where id=t.id) then raise exception 'cyclic task dependencies' using errcode='23514';end if;
 insert into private.task_dependencies(task_id,depends_on_id,work_order_id,created_by) values(t.id,(p_data->>'depends_on_id')::uuid,w.id,auth.uid()) returning id into result;
 when 'accept_task' then
 if not app_private.execution_worker(t.id) or t.is_container or t.status<>'awaiting_mobilisation' then raise exception 'assigned worker acceptance required' using errcode='42501';end if;
 update private.work_tasks set accepted_at=clock_timestamp() where id=t.id;result=t.id;
 when 'progress' then
 nextstate=p_data->>'state';
 if t.id is null or t.is_container or t.accepted_at is null or p.status<>'approved' or not app_private.order_gate(o.id) or clock_timestamp()<t.starts_at or clock_timestamp()>=t.ends_at then raise exception 'active accepted work within capacity window required' using errcode='23514';end if;
 perform app_private.validate_execution_assignment(w.id,t.id);
 if nextstate not in ('mobilising','en_route','arrived','awaiting_customer_access','started','in_progress','paused','awaiting_materials','awaiting_customer_decision','work_completed') or not(config->'transitions' @> jsonb_build_array(jsonb_build_array(t.status,nextstate))) then raise exception 'execution transition is not approved' using errcode='55000';end if;
 if exists(select 1 from private.task_dependencies d join private.work_tasks dependency on dependency.id=d.depends_on_id where d.task_id=t.id and dependency.status not in ('qa_approved','closed')) then raise exception 'task dependencies incomplete' using errcode='23514';end if;
 if nextstate in ('started','in_progress') and exists(select 1 from private.work_tasks other join private.assignment_resources ar on ar.id=other.resource_id where other.id<>t.id and ar.worker_id=(select worker_id from private.assignment_resources where id=t.resource_id) and other.status in ('started','in_progress')) then raise exception 'worker already executing another task' using errcode='23514';end if;
 if nextstate in ('started','in_progress') and not exists(select 1 from private.execution_attendance where task_id=t.id and execution_round=t.execution_round and kind='check_in') then raise exception 'check-in required' using errcode='23514';end if;
 if nextstate='work_completed' and not exists(select 1 from private.execution_submissions where task_id=t.id and execution_round=t.execution_round and phase='execution' and status in ('submitted','approved')) then raise exception 'completion checklist submission required' using errcode='23514';end if;
 update private.work_tasks set status=nextstate,actual_start=case when nextstate in ('started','in_progress') then coalesce(actual_start,clock_timestamp()) else actual_start end,actual_finish=case when nextstate='work_completed' then clock_timestamp() else actual_finish end,completion_actor=case when nextstate='work_completed' then auth.uid() else completion_actor end where id=t.id;
 update private.work_orders set status=case when not exists(select 1 from private.work_tasks where work_order_id=w.id and not is_container and mandatory and status<>'work_completed') then 'work_completed' else 'in_progress' end where id=w.id;
 update private.service_orders set status='in_progress' where id=o.id;
 update private.sla_tracks set status='met' where task_id=t.id and status in ('running','paused') and target=case nextstate when 'mobilising' then 'mobilisation' when 'arrived' then 'arrival' when 'started' then 'start' when 'work_completed' then 'task_completion' end;
 if app_private.execution_staff(o.id,'fulfilment.manage') and config->'pause_states' @> jsonb_build_array(nextstate) then update private.sla_tracks set status='paused',remaining=greatest(due_at-clock_timestamp(),interval '0') where task_id=t.id and status='running';
 elsif config->'pause_states' @> jsonb_build_array(t.status) then update private.sla_tracks set status='running',due_at=clock_timestamp()+remaining,remaining=null where task_id=t.id and status='paused';end if;result=t.id;
 when 'attendance' then
 if t.id is null or (p_data->>'kind' in ('no_show','late','missed_appointment','discrepancy','supervisor_acknowledgement') and not app_private.execution_staff(o.id,'fulfilment.supervise')) then raise exception 'scoped attendance authority required' using errcode='42501';end if;
 if p_data->>'kind'='supervisor_acknowledgement' then select * into att from private.execution_attendance where id=(p_data->>'verifies_id')::uuid and task_id=t.id and execution_round=t.execution_round;if att.id is null or att.created_by=auth.uid() or not app_private.execution_independent(w.id) then raise exception 'independent attendance verification required' using errcode='42501';end if;end if;
 if (p_data->>'occurred_at')::timestamptz not between clock_timestamp()-interval '1 day' and clock_timestamp()+interval '1 minute' then raise exception 'bounded declared attendance time required' using errcode='23514';end if;
 insert into private.execution_attendance(task_id,worker_id,kind,occurred_at,declared_latitude,declared_longitude,verifies_id,execution_round,reason,created_by)
 select t.id,ar.worker_id,p_data->>'kind',coalesce((p_data->>'occurred_at')::timestamptz,clock_timestamp()),(p_data->>'latitude')::numeric,(p_data->>'longitude')::numeric,(p_data->>'verifies_id')::uuid,t.execution_round,reason,auth.uid() from private.assignment_resources ar where ar.id=t.resource_id returning id into result;
 when 'save_checklist' then
 v_phase=p_data->>'phase';if v_phase not in ('execution','quality','handover') or t.id is null then raise exception 'task checklist phase required' using errcode='23514';end if;
 if v_phase='quality' and not exists(select 1 from private.quality_inspections where task_id=t.id and execution_round=t.execution_round and inspector_id=auth.uid() and status='requested') then raise exception 'assigned quality inspector required' using errcode='42501';end if;
 if v_phase='execution' and t.status in ('qa_approved','closed','cancelled') then raise exception 'completed execution content is frozen' using errcode='55000';end if;
 definition=app_private.execution_definition((config->>case v_phase when 'quality' then 'quality_checklist' when 'handover' then 'handover_checklist' else 'execution_checklist' end)::uuid);
 if jsonb_typeof(p_data->'answers') is distinct from 'object' then raise exception 'draft answer object required' using errcode='23514';end if;
 insert into private.execution_submissions(task_id,checklist_id,phase,version,answers,definition_snapshot,task_revision,execution_round,created_by)
 select t.id,(definition->>'id')::uuid,v_phase,coalesce(max(version),0)+1,p_data->'answers',definition,t.revision,t.execution_round,auth.uid() from private.execution_submissions where task_id=t.id and execution_submissions.phase=v_phase returning id into result;
 when 'submit_checklist' then
 select * into s from private.execution_submissions where id=(p_data->>'id')::uuid and task_id=t.id for update;
 if s.id is null or s.status<>'draft' or s.created_by<>auth.uid() or s.execution_round<>t.execution_round then raise exception 'own current draft required' using errcode='42501';end if;
 perform app_private.validate_execution_answers(s.definition_snapshot,s.answers);update private.execution_submissions set status='submitted' where id=s.id;result=s.id;
 when 'review_checklist' then
 select * into s from private.execution_submissions where id=(p_data->>'id')::uuid and task_id=t.id for update;
 if s.id is null or s.status<>'submitted' or s.created_by=auth.uid() or s.execution_round<>t.execution_round or not app_private.execution_independent(w.id) then raise exception 'independent current checklist review required' using errcode='42501';end if;
 update private.execution_submissions set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,reviewed_by=auth.uid(),review_reason=reason where id=s.id;result=s.id;
 when 'prepare_upload','attach_evidence' then
 if t.id is null or t.status in ('closed','cancelled') then raise exception 'active assigned task evidence required' using errcode='55000';end if;
 if p_action='prepare_upload' then
 if p_data->>'content_type' not in ('image/jpeg','image/png','image/webp','video/mp4','video/webm','application/pdf','text/plain') or (p_data->>'byte_size')::bigint not between 1 and 20971520 then raise exception 'bounded supported evidence upload required' using errcode='23514';end if;
 insert into private.document_objects(bucket_id,object_name,customer_account_id,uploaded_by,classification,content_type,byte_size,retained_until,created_by)
 values('work-evidence',o.customer_account_id::text||'/execution/'||gen_random_uuid()::text,o.customer_account_id,auth.uid(),'work',p_data->>'content_type',(p_data->>'byte_size')::bigint,(p_data->>'retained_until')::timestamptz,auth.uid()) returning id into result;
 else result=(p_data->>'document_id')::uuid;end if;
 if not exists(select 1 from private.document_objects where id=result and customer_account_id=o.customer_account_id and classification in ('work','field','customer') and archived_at is null and (p_action='prepare_upload' or scan_status='clean')) then raise exception 'same-account evidence required' using errcode='23514';end if;
 insert into private.execution_evidence(task_id,work_order_id,order_id,customer_account_id,document_id,classification,task_revision,execution_round,created_by) values(t.id,w.id,o.id,o.customer_account_id,result,p_data->>'classification',t.revision,t.execution_round,auth.uid()) returning id into result;
 when 'review_evidence' then
 select * into e from private.execution_evidence where id=(p_data->>'id')::uuid and task_id=t.id for update;
 if e.id is null or e.status<>'pending' or e.created_by=auth.uid() or not app_private.execution_independent(w.id) or not exists(select 1 from private.document_objects where id=e.document_id and scan_status='clean' and archived_at is null) then raise exception 'independent clean evidence review required' using errcode='42501';end if;
 update private.execution_evidence set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),review_reason=reason,customer_visible=coalesce((p_data->>'customer_visible')::boolean,false) where id=e.id;result=e.id;
 when 'supervisor_verify' then
 if w.supervisor_id<>auth.uid() or t.completion_actor=auth.uid() or not app_private.execution_independent(w.id) or t.status<>'work_completed' or not app_private.execution_evidence_ready(t.id) or (select status from private.execution_submissions where task_id=t.id and execution_round=t.execution_round and phase='execution' order by version desc limit 1) is distinct from 'approved' then raise exception 'independent complete supervision required' using errcode='23514';end if;
 update private.work_tasks set supervisor_verified_by=auth.uid(),status='awaiting_qa' where id=t.id;update private.work_orders set status='awaiting_qa' where id=w.id;update private.service_orders set status='awaiting_qa' where id=o.id;result=t.id;
 when 'supervisor_assign' then
 if not app_private.execution_target_staff((p_data->>'profile_id')::uuid,o.id,'fulfilment.supervise') then raise exception 'scoped supervisor required' using errcode='42501';end if;
 update private.work_orders set supervisor_id=(p_data->>'profile_id')::uuid where id=w.id;result=w.id;
 when 'suspend' then
 if w.status in ('completed','closed','cancelled') then raise exception 'invalid suspension' using errcode='55000';end if;
 update private.work_orders set status='suspended',paused_from=status where id=w.id;update private.sla_tracks set status='paused',remaining=greatest(due_at-clock_timestamp(),interval '0') where work_order_id=w.id and status='running';result=w.id;
 when 'resume' then
 if w.status<>'suspended' or not app_private.order_gate(o.id) then raise exception 'resume blocked' using errcode='23514';end if;
 perform app_private.validate_execution_assignment(w.id);
 update private.work_orders set status=coalesce(paused_from,'in_progress'),paused_from=null where id=w.id;update private.sla_tracks set status='running',due_at=clock_timestamp()+remaining,remaining=null where work_order_id=w.id and status='paused';result=w.id;
 when 'complete_container' then
 if not t.is_container or not exists(select 1 from private.work_tasks where parent_task_id=t.id) or exists(select 1 from private.work_tasks where parent_task_id=t.id and status not in ('qa_approved','closed')) then raise exception 'all child tasks need quality approval' using errcode='23514';end if;
 update private.work_tasks set status='qa_approved' where id=t.id;result=t.id;
 when 'request_exception' then
 insert into private.operational_exceptions(work_order_id,work_revision,kind,proposal,reason,valid_until,created_by) values(w.id,w.plan_revision,p_data->>'kind',p_data->'proposal',reason,(p_data->>'valid_until')::timestamptz,auth.uid()) returning id into result;
 when 'decide_exception' then
 select * into exception_row from private.operational_exceptions where id=(p_data->>'id')::uuid and work_order_id=w.id for update;
 if exception_row.id is null or exception_row.created_by=auth.uid() or exception_row.status<>'pending' or exception_row.work_revision<>w.plan_revision or exception_row.valid_until<=now() or not app_private.execution_independent(w.id) then raise exception 'independent current exception required' using errcode='42501';end if;
 update private.operational_exceptions set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,decided_by=auth.uid() where id=exception_row.id;result=exception_row.id;
 when 'apply_sla_exception','transfer_rework','customer_confirm','feedback','close_work','cancel_work','retire_for_reschedule','substitute','task_reassign','task_cancel' then
 result=app_private.execution_final_command(w.id,p_action,p_data);
 else raise exception 'unsupported execution command' using errcode='23514';end case;
 if p_action in ('create_task','dependency','supervisor_assign') then update private.work_orders set plan_revision=plan_revision+1 where id=w.id;end if;
 if p_action not in ('create_work','close_work','cancel_work','retire_for_reschedule','feedback') then update private.work_orders set revision=revision+1 where id=w.id;end if;
 if t.id is not null then update private.work_tasks set revision=revision+1 where id=t.id;end if;
 event_id=app_private.execution_event(w.id,t.id,p_action,result,oldstate,coalesce((select status from private.work_tasks where id=t.id),(select status from private.work_orders where id=w.id)),reason,permission,case when p_action='operational_note' then jsonb_build_object('note',p_data->>'note') else '{}'::jsonb end);
 if p_action='close_work' then
 for related in select distinct ar.provider_id from private.work_tasks task join private.assignment_resources ar on ar.id=task.resource_id where task.work_order_id=w.id and task.status='closed' and not task.is_container loop perform app_private.execution_performance(event_id,related.provider_id,'completion',1);end loop;
 elsif p_action='customer_confirm' and p_data->>'decision'='disputed' then
 select id into result from private.service_cases where work_order_id=w.id and category='completion_dispute' order by created_at desc limit 1;perform app_private.execution_sla(w.id,null,result,event_id,'case_acknowledgement');perform app_private.execution_sla(w.id,null,result,event_id,'case_resolution');result=(select id from private.customer_confirmations where work_order_id=w.id order by created_at desc limit 1);
 elsif p_action='create_task' then
 perform app_private.execution_sla(w.id,result,null,event_id,'mobilisation');perform app_private.execution_sla(w.id,result,null,event_id,'arrival');perform app_private.execution_sla(w.id,result,null,event_id,'start');perform app_private.execution_sla(w.id,result,null,event_id,'task_completion');
 elsif p_action='supervisor_verify' then perform app_private.execution_sla(w.id,t.id,null,event_id,'quality_review');
 elsif p_action='attendance' and att.kind='arrival' then select * into a from private.assignment_resources where id=t.resource_id;perform app_private.execution_performance(event_id,a.provider_id,'timeliness',case when att.occurred_at<=(select due_at from private.sla_tracks where task_id=t.id and target='arrival' order by created_at desc limit 1) then 1 else 0 end);end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'fulfilment_command',p_key,payload,result);return result;
end$$;
create function public.create_work_order(p_order uuid,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(null,'create_work',p_data||jsonb_build_object('order_id',p_order),p_key)$$;
revoke all on function public.create_work_order(uuid,jsonb,text) from public,anon;grant execute on function public.create_work_order(uuid,jsonb,text) to authenticated;
create function public.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(p_work,p_action,p_data,p_key)$$;
revoke all on function public.fulfilment_command(uuid,text,jsonb,text) from public,anon;
grant execute on function public.fulfilment_command(uuid,text,jsonb,text),app_private.fulfilment_command(uuid,text,jsonb,text) to authenticated;
commit;
