begin;
create function app_private.execution_order_event(p_order uuid,p_work uuid,p_task uuid,p_action text,p_subject uuid,p_reason text,p_details jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare ev uuid;outbox uuid;correlation uuid=gen_random_uuid();begin
 insert into private.execution_history(order_id,work_order_id,task_id,action,subject_id,reason,actor_id,permission_code,correlation_id,details) values(p_order,p_work,p_task,p_action,p_subject,p_reason,auth.uid(),'fulfilment.cases',correlation,p_details) returning id into ev;
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(p_order,'execution.'||p_action,p_subject,correlation) returning id into outbox;
 insert into private.operational_event_deliveries(event_id,created_by) values(outbox,auth.uid());return ev;
end$$;
create function app_private.case_access(p_case uuid,p_write boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_cases c where c.id=p_case and ((app_private.execution_staff(c.order_id,case when p_write then 'fulfilment.manage' else 'fulfilment.read' end) and (not c.confidential or app_private.execution_staff(c.order_id,'fulfilment.cases.sensitive')) and (c.work_order_id is null or app_private.execution_independent(c.work_order_id)) and (c.provider_id is null or not exists(select 1 from private.provider_personnel where provider_id=c.provider_id and profile_id=auth.uid())))
 or (not p_write and c.created_by=auth.uid() and (app_private.order_customer(c.order_id) or app_private.execution_worker(c.task_id)))))
$$;
create function app_private.execution_case_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare o private.service_orders;c private.service_cases;w private.work_orders;p private.fulfilment_policies;result uuid;ev uuid;receipt private.transaction_commands;payload jsonb=jsonb_build_object('order',p_order,'action',p_action,'data',p_data);reason text=p_data->>'reason';begin
 if auth.uid() is null or length(coalesce(p_key,'')) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 or length(coalesce(reason,'')) not between 1 and 2000 then raise exception 'bounded authenticated case command required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('execution-case:'||auth.uid()::text||p_key,0));select * into o from private.service_orders where id=p_order for update;
 if o.id is null then raise exception 'case order unavailable' using errcode='42501';end if;
 if p_action='report' then
 if not (app_private.order_customer(o.id) or app_private.execution_staff(o.id,'fulfilment.manage') or exists(select 1 from private.work_tasks task where task.id=(p_data->>'task_id')::uuid and task.order_id=o.id and app_private.execution_worker(task.id))) then raise exception 'case report denied' using errcode='42501';end if;
 else select * into c from private.service_cases where id=(p_data->>'id')::uuid and order_id=o.id for update;
 if c.id is null or not (app_private.case_access(c.id,true) or(p_action='reopen' and c.created_by=auth.uid() and app_private.order_customer(o.id))) then raise exception 'restricted case access denied' using errcode='42501';end if;end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='execution_case' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'case idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action<>'report' and (p_data->>'expected_revision')::integer is distinct from c.revision then raise exception 'stale case revision' using errcode='40001';end if;
 if p_action='report' then
 if p_data->>'work_order_id' is not null then select * into w from private.work_orders where id=(p_data->>'work_order_id')::uuid and order_id=o.id;if not found then raise exception 'work order mismatch' using errcode='23514';end if;end if;
 select * into p from private.fulfilment_policies where id=w.policy_id;
 if p.id is null then select * into p from private.fulfilment_policies where service_version_id=o.service_version_id and status='approved' and valid_from<=now() and (valid_until is null or valid_until>now()) and contract_reference is null and (customer_account_id is null or customer_account_id=o.customer_account_id) order by(customer_account_id is not null) desc limit 1;end if;
 if p.id is null or not(p.configuration->'case_categories' @> jsonb_build_array(p_data->>'category')) then raise exception 'approved issue classification required' using errcode='23514';end if;
 if p_data->>'provider_id' is not null and not exists(select 1 from private.assignment_offers f join private.dispatch_proposals proposal on proposal.id=f.proposal_id where proposal.order_id=o.id and f.provider_id=(p_data->>'provider_id')::uuid) then raise exception 'case provider not related to order' using errcode='23514';end if;
 insert into private.service_cases(order_id,customer_account_id,work_order_id,task_id,provider_id,category,severity,priority,confidential,blocking,description,created_by)
 values(o.id,o.customer_account_id,w.id,(p_data->>'task_id')::uuid,(p_data->>'provider_id')::uuid,p_data->>'category',p_data->>'severity',p_data->>'priority',coalesce((p_data->>'confidential')::boolean,false) or p_data->>'category' in ('misconduct','safety'),true,p_data->>'description',auth.uid()) returning * into c;result=c.id;
 else
 case p_action
 when 'assign_owner' then
 if not app_private.execution_target_staff((p_data->>'profile_id')::uuid,o.id,'fulfilment.manage') or (c.confidential and not app_private.execution_target_staff((p_data->>'profile_id')::uuid,o.id,'fulfilment.cases.sensitive')) then raise exception 'scoped case investigator required' using errcode='42501';end if;
 update private.service_cases set owner_id=(p_data->>'profile_id')::uuid where id=c.id;
 when 'acknowledge','investigate','escalate' then
 if c.status in ('closed','resolved') then raise exception 'closed case needs explicit reopening' using errcode='55000';end if;
 update private.service_cases set status=case p_action when 'acknowledge' then 'acknowledged' when 'investigate' then 'investigating' else 'escalated' end where id=c.id;
 if p_action='acknowledge' then update private.sla_tracks set status='met' where case_id=c.id and target='case_acknowledgement';end if;
 when 'entry' then
 if p_data->>'kind' not in ('evidence','investigation','finding','corrective_action','communication','escalation','note') or p_data->>'visibility' not in ('internal','customer') then raise exception 'typed case entry required' using errcode='23514';end if;
 if p_data->>'document_id' is not null and not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and customer_account_id=c.customer_account_id and classification in ('work','field','customer') and scan_status='clean' and archived_at is null) then raise exception 'clean same-account case evidence required' using errcode='23514';end if;
 insert into private.service_case_entries(case_id,kind,document_id,visibility,content,created_by) values(c.id,p_data->>'kind',(p_data->>'document_id')::uuid,p_data->>'visibility',p_data->>'content',auth.uid());
 when 'propose_resolution' then
 if c.status in ('closed','resolved') or jsonb_typeof(p_data->'requirements') is distinct from 'object' then raise exception 'bounded resolution requirements required' using errcode='23514';end if;
 update private.service_cases set status='resolution_proposed',resolution_requirements=p_data->'requirements',resolution_proposed_by=auth.uid() where id=c.id;
 when 'resolve' then
 if c.status<>'resolution_proposed' or c.created_by=auth.uid() or c.resolution_proposed_by=auth.uid() or not app_private.execution_staff(o.id,'fulfilment.exceptions.approve') or (c.work_order_id is not null and not app_private.execution_independent(c.work_order_id)) or(c.provider_id is not null and (app_private.provider_self(c.provider_id) or exists(select 1 from private.provider_personnel where provider_id=c.provider_id and profile_id=auth.uid()))) then raise exception 'independent resolution decision required' using errcode='42501';end if;
 if exists(select 1 from private.work_tasks t join private.rework_requests r on r.rework_task_id=t.id where t.work_order_id=c.work_order_id and r.status='active') then raise exception 'required corrective work unresolved' using errcode='23514';end if;
 update private.service_cases set status='resolved',resolved_by=auth.uid() where id=c.id;update private.sla_tracks set status='met' where case_id=c.id and target='case_resolution';
 if c.work_order_id is not null and not exists(select 1 from private.service_cases where work_order_id=c.work_order_id and id<>c.id and blocking and status not in ('resolved','closed')) then
 update private.work_orders set status='awaiting_customer_confirmation',plan_revision=plan_revision+1,revision=revision+1 where id=c.work_order_id and status='customer_disputed';end if;
 when 'close' then if c.status<>'resolved' then raise exception 'resolved case required' using errcode='55000';end if;update private.service_cases set status='closed' where id=c.id;
 when 'reopen' then if c.status not in ('resolved','closed') then raise exception 'terminal case required for reopening' using errcode='55000';end if;update private.service_cases set status='open',resolution_requirements=null,resolution_proposed_by=null,resolved_by=null where id=c.id;
 else raise exception 'unsupported case command' using errcode='23514';end case;update private.service_cases set revision=revision+1 where id=c.id;result=c.id;
 end if;
 ev=app_private.execution_order_event(o.id,c.work_order_id,c.task_id,'case_'||p_action,c.id,reason,jsonb_build_object('case_snapshot',(select to_jsonb(x) from private.service_cases x where id=c.id)));
 if p_action in ('report','reopen') then
 if p.id is null then select policy.* into p from private.fulfilment_policies policy where policy.id=(select policy_id from private.work_orders where id=c.work_order_id);end if;
 if p.id is null then select policy.* into p from private.fulfilment_policies policy where policy.service_version_id=o.service_version_id and policy.status='approved' and policy.valid_from<=now() and (policy.valid_until is null or policy.valid_until>now()) and policy.contract_reference is null and (policy.customer_account_id is null or policy.customer_account_id=o.customer_account_id) order by(policy.customer_account_id is not null) desc limit 1;end if;
 if p.id is null then raise exception 'case SLA policy unavailable' using errcode='23514';end if;
 insert into private.sla_tracks(order_id,work_order_id,case_id,target,source_event_id,due_at,created_by) select o.id,c.work_order_id,c.id,target,ev,clock_timestamp()+make_interval(secs=>(policy.configuration->'sla'->>target)::integer),auth.uid() from private.fulfilment_policies policy cross join unnest(array['case_acknowledgement','case_resolution']) target where policy.id=coalesce(p.id,(select policy_id from private.work_orders where id=c.work_order_id));
 elsif p_action='resolve' and c.provider_id is not null and coalesce((p_data->>'provider_responsible')::boolean,false) then perform app_private.execution_performance(ev,c.provider_id,'reliability',0);end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'execution_case',p_key,payload,result);return result;
end$$;
create function public.execution_case_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.execution_case_command(p_order,p_action,p_data,p_key)$$;
revoke all on function public.execution_case_command(uuid,text,jsonb,text) from public,anon;
grant execute on function public.execution_case_command(uuid,text,jsonb,text),app_private.execution_case_command(uuid,text,jsonb,text) to authenticated;
create function app_private.process_execution_slas(p_limit integer) returns integer language plpgsql security definer set search_path='' as $$declare track private.sla_tracks;ev uuid;outbox uuid;correlation uuid;processed integer=0;order_row record;begin
 if auth.role() is distinct from 'service_role' then raise exception 'server SLA worker only' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'bounded SLA batch required' using errcode='23514';end if;
 for order_row in select o.id from private.service_orders o where exists(select 1 from private.sla_tracks s where s.order_id=o.id and s.status='running' and s.due_at<=clock_timestamp()) order by o.id limit p_limit for update of o skip locked loop
 for track in select * from private.sla_tracks where order_id=order_row.id and status='running' and due_at<=clock_timestamp() order by due_at,id limit (p_limit-processed) for update skip locked loop
 update private.sla_tracks set status='breached',breached_at=clock_timestamp() where id=track.id;correlation=gen_random_uuid();
 insert into private.execution_history(order_id,work_order_id,task_id,action,subject_id,reason,actor_type,permission_code,correlation_id,details) values(track.order_id,track.work_order_id,track.task_id,'sla_breach',track.id,'Configured SLA deadline exceeded','system_worker','system.execution.sla',correlation,jsonb_build_object('target',track.target,'due_at',track.due_at,'case_id',track.case_id)) returning id into ev;
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(track.order_id,'execution.sla_breach',track.id,correlation) returning id into outbox;
 insert into private.operational_event_deliveries(event_id,system_generated) values(outbox,true);
 if track.case_id is not null then update private.service_cases set status='escalated',revision=revision+1 where id=track.case_id and status not in ('resolved','closed');end if;processed=processed+1;
 end loop;exit when processed>=p_limit;end loop;return processed;
end$$;
create function public.process_execution_slas(p_limit integer) returns integer language sql set search_path='' as $$select app_private.process_execution_slas(p_limit)$$;
revoke all on function public.process_execution_slas(integer),app_private.process_execution_slas(integer) from public,anon,authenticated;
grant execute on function public.process_execution_slas(integer),app_private.process_execution_slas(integer) to service_role;
-- Existing order/dispatch commands must not release resources underneath execution.
alter function app_private.order_command(uuid,text,jsonb,text) rename to pre_execution_order_command;
revoke all on function app_private.pre_execution_order_command(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.order_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_order is not null then perform 1 from private.service_orders where id=p_order for update;end if;
 if p_action not in ('create','propose_change','authorization','decide_authorization') and exists(select 1 from private.work_orders where order_id=p_order and status not in ('closed','cancelled')) then raise exception 'active execution requires coordinated fulfilment operation' using errcode='55000';end if;
 return app_private.pre_execution_order_command(p_order,p_action,p_data,p_key);
end$$;
create or replace function public.order_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.order_command(p_order,p_action,p_data,p_key)$$;
create or replace function public.create_service_order(p_quote uuid,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.order_command(null,'create',p_data||jsonb_build_object('quotation_version_id',p_quote),p_key)$$;
alter function app_private.dispatch_command(uuid,text,jsonb,text) rename to pre_execution_dispatch_command;
revoke all on function app_private.pre_execution_dispatch_command(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.dispatch_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform 1 from private.service_orders where id=p_order for update;
 if exists(select 1 from private.work_orders where order_id=p_order and status not in ('closed','cancelled')) then raise exception 'active execution dispatch change requires fulfilment review' using errcode='55000';end if;
 return app_private.pre_execution_dispatch_command(p_order,p_action,p_data,p_key);
end$$;
create or replace function public.dispatch_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.dispatch_command(p_order,p_action,p_data,p_key)$$;
grant execute on function app_private.dispatch_command(uuid,text,jsonb,text),app_private.order_command(uuid,text,jsonb,text) to authenticated;
alter table private.service_orders drop constraint service_orders_status_check,add constraint service_orders_status_check check(status in ('pending_authorization','awaiting_dispatch','assigned','on_hold','in_progress','awaiting_qa','awaiting_customer_confirmation','customer_disputed','completed','closed','cancelled'));
do $$declare body text;begin
 select pg_get_functiondef('app_private.order_provider(uuid,uuid)'::regprocedure) into body;
 body=replace(body,'o.status in (''awaiting_dispatch'',''assigned'')','o.status in (''awaiting_dispatch'',''assigned'',''in_progress'',''awaiting_qa'',''awaiting_customer_confirmation'',''customer_disputed'',''completed'')');
 body=replace(body,'where p.order_id=p_order','where exists(select 1 from private.provider_profiles active_party where active_party.id=f.provider_id and active_party.status=''active'') and p.order_id=p_order');
 body=replace(body,'where a.offer_id=f.id and a.worker_id=auth.uid()', 'where a.offer_id=f.id and exists(select 1 from private.provider_capacity_reservations capacity where capacity.id=a.reservation_id and capacity.status in (''assigned'',''reserved'')) and a.worker_id=auth.uid()');execute body;
end$$;
create function app_private.performance_source_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.provider_performance_events metric where metric.id=p_id and ((metric.document_id is not null and app_private.provider_document(metric.provider_id,metric.document_id)) or (metric.source_event_id is not null and exists(select 1 from private.execution_history ev where ev.id=metric.source_event_id and ev.action in ('quality_decide','attendance','close_work','case_resolve')))))
$$;
do $$declare body text;begin select pg_get_functiondef('app_private.provider_party_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,text,uuid)'::regprocedure) into body;
 body=replace(body,'and app_private.provider_document(p.id,document_id);','and app_private.performance_source_valid(provider_performance_events.id);');execute body;end$$;
commit;
