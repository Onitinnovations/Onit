begin;
alter table private.work_tasks add column execution_round integer not null default 1 check(execution_round>0);
alter table private.execution_evidence add column execution_round integer not null default 1;
alter table private.execution_submissions add column execution_round integer not null default 1;
alter table private.quality_inspections add column execution_round integer not null default 1;
alter table private.execution_attendance add column execution_round integer not null default 1;
alter table private.assignment_resources add column resource_version integer not null default 1,
 drop constraint assignment_resources_offer_id_worker_id_key,add unique(offer_id,worker_id,resource_version);
create function app_private.execution_staff(p_order uuid,p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_orders o where o.id=p_order and app_private.has_permission(p_permission,o.organisation_id))
$$;
create function app_private.execution_worker(p_task uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.work_tasks t join private.work_orders w on w.id=t.work_order_id
 join private.assignment_resources a on a.id=t.resource_id join private.assignment_offers f on f.id=a.offer_id
 join private.dispatch_proposals p on p.id=f.proposal_id and p.status='confirmed' and p.id=w.proposal_id
 join private.provider_capacity_reservations r on r.id=a.reservation_id and r.status='assigned'
 join public.profiles me on me.id=auth.uid() and me.status='active'
 where t.id=p_task and a.worker_id=me.id and w.status not in ('closed','cancelled') and app_private.order_provider(t.order_id,a.provider_id)
 and exists(select 1 from private.provider_profiles party where party.id=a.provider_id and party.status='active')
 and (exists(select 1 from private.provider_profiles party where party.id=a.provider_id and party.individual_profile_id=me.id)
 or exists(select 1 from private.provider_personnel m join private.organisation_members om on om.profile_id=m.profile_id and om.organisation_id=m.organisation_id and om.status='active' and om.revoked_at is null and (om.valid_until is null or om.valid_until>now()) where m.provider_id=a.provider_id and m.profile_id=me.id and m.personnel_role in ('executing_worker','field_agent') and m.revoked_at is null and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now()))))
$$;
create function app_private.execution_party(p_work uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.work_orders w join private.work_tasks t on t.work_order_id=w.id join private.assignment_resources a on a.id=t.resource_id
 where w.id=p_work and w.status not in ('closed','cancelled') and exists(select 1 from private.provider_profiles party where party.id=a.provider_id and party.status='active') and app_private.order_provider(w.order_id,a.provider_id) and (app_private.execution_worker(t.id) or app_private.provider_self(a.provider_id)))
$$;
create function app_private.execution_target_independent(p_work uuid,p_profile uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.assignment_resources a where (a.offer_id in(select offer.id from private.assignment_offers offer join private.work_orders work on work.proposal_id=offer.proposal_id where work.id=p_work) or a.id in(select resource_id from private.work_tasks where work_order_id=p_work) or a.id in(select (h.details->'task_snapshot'->>'resource_id')::uuid from private.execution_history h where h.work_order_id=p_work and h.details->'task_snapshot'->>'resource_id' is not null)) and (a.worker_id=p_profile or exists(select 1 from private.provider_personnel where provider_id=a.provider_id and profile_id=p_profile) or exists(select 1 from private.provider_profiles where id=a.provider_id and individual_profile_id=p_profile)))
$$;
create function app_private.execution_independent(p_work uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.execution_target_independent(p_work,auth.uid())
$$;
create function app_private.execution_event(p_work uuid,p_task uuid,p_action text,p_subject uuid,p_previous text,p_new text,p_reason text,p_permission text,p_details jsonb default '{}') returns uuid
language plpgsql security definer set search_path='' as $$declare w private.work_orders;ev uuid;delivery uuid;correlation uuid=gen_random_uuid();begin
 select * into w from private.work_orders where id=p_work;
 insert into private.execution_history(order_id,work_order_id,task_id,action,subject_id,previous_state,new_state,revision,reason,actor_id,permission_code,correlation_id,details)
 values(w.order_id,w.id,p_task,p_action,p_subject,p_previous,p_new,w.revision,p_reason,auth.uid(),p_permission,correlation,p_details||jsonb_build_object('work_snapshot',to_jsonb(w),'task_snapshot',(select to_jsonb(t) from private.work_tasks t where id=p_task))) returning id into ev;
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(w.order_id,'execution.'||p_action,p_subject,correlation) returning id into delivery;
 insert into private.operational_event_deliveries(event_id,created_by) values(delivery,auth.uid());return ev;
end$$;
create function app_private.execution_definition(p_checklist uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'version',c.version,'service_version_id',c.service_version_id,'type',c.checklist_type,'fields',(select coalesce(jsonb_agg(jsonb_build_object('key',i.item_key,'label',i.label,'type',i.field_type,'required',i.required,'choices',i.choices,'validation',i.validation,'condition',i.condition,'evidence_required',i.evidence_required) order by i.position),'[]') from public.service_checklist_items i where i.checklist_id=c.id)) from public.service_checklists c where c.id=p_checklist
$$;
create function app_private.validate_execution_answers(p_definition jsonb,p_answers jsonb) returns void language plpgsql immutable set search_path='' as $$
declare f jsonb;v jsonb;visible boolean;rule record;begin
 if jsonb_typeof(p_answers) is distinct from 'object' or octet_length(p_answers::text)>65536 then raise exception 'bounded checklist answers required' using errcode='23514';end if;
 if exists(select 1 from jsonb_object_keys(p_answers) k where not exists(select 1 from jsonb_array_elements(p_definition->'fields') field where field->>'key'=k)) then raise exception 'unknown checklist field' using errcode='23514';end if;
 for f in select value from jsonb_array_elements(p_definition->'fields') loop
 visible=f->'condition' is null or f->'condition'='null'::jsonb or app_private.answer_condition(p_answers->(f->'condition'->>'field'),f->'condition'->>'operator',f->'condition'->'value');
 if not visible then if p_answers ? (f->>'key') then raise exception 'hidden checklist answer' using errcode='23514';end if;continue;end if;
 v=p_answers->(f->>'key');
 if v is null or v='null'::jsonb then if (f->>'required')::boolean then raise exception 'required checklist answer missing' using errcode='23514';end if;continue;end if;
 if (f->>'type'='boolean' and jsonb_typeof(v)<>'boolean') or (f->>'type'='number' and jsonb_typeof(v)<>'number') or (f->>'type' in ('text','single_choice') and jsonb_typeof(v)<>'string') or (f->>'type'='multiple_choice' and jsonb_typeof(v)<>'array') then raise exception 'checklist type mismatch' using errcode='23514';end if;
 if f->>'type'='text' and (f->>'required')::boolean and length(trim(v#>>'{}'))=0 then raise exception 'empty required checklist answer' using errcode='23514';end if;
 if f->>'type'='single_choice' and not (f->'choices' @> jsonb_build_array(v)) then raise exception 'unknown checklist choice' using errcode='23514';end if;
 if f->>'type'='multiple_choice' and (jsonb_array_length(v)>100 or exists(select 1 from jsonb_array_elements(v) x where not(f->'choices' @> jsonb_build_array(x))) or (select count(*)<>count(distinct x) from jsonb_array_elements(v) x)) then raise exception 'invalid checklist choices' using errcode='23514';end if;
 for rule in select key,value from jsonb_each(coalesce(f->'validation','{}')) loop
 if (rule.key='minimum' and (v#>>'{}')::numeric<(rule.value#>>'{}')::numeric) or (rule.key='maximum' and (v#>>'{}')::numeric>(rule.value#>>'{}')::numeric) or (rule.key='min_length' and length(v#>>'{}')<(rule.value#>>'{}')::integer) or (rule.key='max_length' and length(v#>>'{}')>(rule.value#>>'{}')::integer) then raise exception 'checklist validation rule failed' using errcode='23514';end if;
 end loop;
 end loop;
end$$;
create function app_private.fulfilment_configuration(p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;c public.service_checklists;p private.fulfilment_policies;field jsonb;config jsonb;row_item record;receipt private.transaction_commands;payload jsonb=jsonb_build_object('action',p_action,'data',p_data);begin
 if auth.uid() is null or not app_private.has_permission(case when p_action in ('publish_checklist','approve_policy','retire_policy') then 'fulfilment.policy.approve' else 'fulfilment.policy.manage' end) then raise exception 'global execution configuration permission required' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>65536 then raise exception 'bounded configuration required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('execution-config:'||auth.uid()::text||p_key,0));select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='fulfilment_config' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'configuration idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 case p_action
 when 'prepare_checklist' then
 if p_data->>'type' not in ('execution','quality') or jsonb_typeof(p_data->'fields') is distinct from 'array' or jsonb_array_length(p_data->'fields') not between 1 and 100 then raise exception 'typed execution checklist fields required' using errcode='23514';end if;
 insert into public.service_checklists(service_version_id,code,checklist_type,name,version,created_by) values((p_data->>'service_version_id')::uuid,p_data->>'code',p_data->>'type',p_data->>'name',(p_data->>'version')::integer,auth.uid()) returning id into result;
 for field in select value from jsonb_array_elements(p_data->'fields') loop
 if jsonb_typeof(field) is distinct from 'object' or field->>'key' is null or field->>'label' is null or length(field->>'label') not between 1 and 500 or field->>'type' is null or field->>'type' not in ('boolean','text','number','single_choice','multiple_choice') or (field ? 'required' and jsonb_typeof(field->'required')<>'boolean') or (field ? 'evidence_required' and jsonb_typeof(field->'evidence_required')<>'boolean') then raise exception 'explicit typed checklist field required' using errcode='23514';end if;
 if field->>'type' in ('single_choice','multiple_choice') then
 if jsonb_typeof(field->'choices') is distinct from 'array' or jsonb_array_length(field->'choices') not between 1 and 100 or exists(select 1 from jsonb_array_elements(field->'choices') choice where jsonb_typeof(choice)<>'string' or length(choice#>>'{}') not between 1 and 200) or (select count(*)<>count(distinct choice) from jsonb_array_elements(field->'choices') choice) then raise exception 'bounded distinct choices required' using errcode='23514';end if;
 elsif coalesce(field->'choices','[]')<>'[]'::jsonb then raise exception 'choices require selectable field type' using errcode='23514';end if;
 if field->>'key' !~ '^[a-z][a-z0-9_]{0,59}$' or jsonb_typeof(coalesce(field->'validation','{}'))<>'object' or exists(select 1 from jsonb_object_keys(coalesce(field->'validation','{}')) k where k not in ('minimum','maximum','min_length','max_length')) then raise exception 'safe bounded checklist definition required' using errcode='23514';end if;
 if field->'condition' is not null and (field->'condition'->>'operator' not in ('equals','not_equals','is_present','greater_than','less_than','contains') or not exists(select 1 from jsonb_array_elements(p_data->'fields') f where f->>'key'=field->'condition'->>'field' and f->'condition' is null and f->>'key'<>field->>'key')) then raise exception 'conditional checklist source must be unconditional and defined' using errcode='23514';end if;
 if exists(select 1 from jsonb_object_keys(coalesce(field->'validation','{}')) k where (k in ('minimum','maximum') and field->>'type'<>'number') or (k in ('min_length','max_length') and field->>'type'<>'text')) then raise exception 'typed validation rule required' using errcode='23514';end if;
 if exists(select 1 from jsonb_each(coalesce(field->'validation','{}')) rule where jsonb_typeof(rule.value)<>'number' or(rule.key in ('min_length','max_length') and ((rule.value#>>'{}')::numeric not between 0 and 65536 or trunc((rule.value#>>'{}')::numeric)<>(rule.value#>>'{}')::numeric))) or (field->'validation' ?& array['minimum','maximum'] and (field->'validation'->>'minimum')::numeric>(field->'validation'->>'maximum')::numeric) or (field->'validation' ?& array['min_length','max_length'] and (field->'validation'->>'min_length')::numeric>(field->'validation'->>'max_length')::numeric) then raise exception 'bounded numeric validation parameters required' using errcode='23514';end if;
 insert into public.service_checklist_items(checklist_id,service_version_id,item_key,label,required,position,field_type,choices,validation,condition,evidence_required,created_by)
 values(result,(p_data->>'service_version_id')::uuid,field->>'key',field->>'label',coalesce((field->>'required')::boolean,false),(select count(*) from public.service_checklist_items where checklist_id=result),field->>'type',coalesce(field->'choices','[]'),coalesce(field->'validation','{}'),field->'condition',coalesce((field->>'evidence_required')::boolean,false),auth.uid());
 end loop;
 when 'publish_checklist' then
 select * into c from public.service_checklists where id=(p_data->>'id')::uuid for update;
 if c.id is null or c.created_by=auth.uid() or c.publication_status<>'draft' or c.checklist_type='assessment' then raise exception 'independent execution checklist publication required' using errcode='42501';end if;
 update public.service_checklists set publication_status='published',published_by=auth.uid(),published_at=now() where id=c.id;result=c.id;
 when 'prepare_policy' then
 insert into private.fulfilment_policies(service_version_id,customer_account_id,contract_reference,version,valid_from,valid_until,configuration,created_by) values((p_data->>'service_version_id')::uuid,(p_data->>'customer_account_id')::uuid,p_data->>'contract_reference',(p_data->>'version')::integer,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,p_data->'configuration',auth.uid()) returning id into result;
 when 'approve_policy','retire_policy' then
 select * into p from private.fulfilment_policies where id=(p_data->>'id')::uuid;
 if not found then raise exception 'policy unavailable' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('execution-policy:'||p.service_version_id::text,0));select * into p from private.fulfilment_policies where id=p.id for update;
 if p.created_by=auth.uid() or (p_action='approve_policy' and p.status<>'draft') or (p_action='retire_policy' and p.status<>'approved') then raise exception 'independent policy decision required' using errcode='42501';end if;
 if p_action='approve_policy' then
 config=p.configuration;
 if exists(select 1 from unnest(array['allow_conditional_qa','allow_partial_completion','allow_closure_exception']) flag where jsonb_typeof(config->flag) is distinct from 'boolean') or jsonb_typeof(config->'pause_states') is distinct from 'array' then raise exception 'explicit boolean policy controls and pause states required' using errcode='23514';end if;
 if exists(select 1 from jsonb_array_elements(config->'pause_states') state where jsonb_typeof(state)<>'string' or state#>>'{}' not in ('paused','awaiting_materials','awaiting_customer_decision','awaiting_customer_access')) or exists(select 1 from jsonb_array_elements(config->'evidence') value where jsonb_typeof(value)<>'string' or value#>>'{}' !~ '^[a-z][a-z0-9_]{0,59}$') or exists(select 1 from jsonb_array_elements(config->'case_categories') value where jsonb_typeof(value)<>'string' or value#>>'{}' !~ '^[a-z][a-z0-9_]{0,59}$') then raise exception 'bounded typed policy classifications required' using errcode='23514';end if;
 if jsonb_typeof(config->'transitions') is distinct from 'array' or jsonb_typeof(config->'evidence') is distinct from 'array' or jsonb_typeof(config->'case_categories') is distinct from 'array' or jsonb_typeof(config->'sla') is distinct from 'object' or not(config ?& array['execution_checklist','quality_checklist','handover_checklist','allow_conditional_qa','allow_partial_completion','allow_closure_exception','pause_states']) then raise exception 'complete explicit execution configuration required' using errcode='23514';end if;
 if jsonb_array_length(config->'transitions') not between 1 and 200 or exists(select 1 from jsonb_array_elements(config->'transitions') edge where jsonb_typeof(edge)<>'array' or jsonb_array_length(edge)<>2 or edge->>0 not in ('awaiting_mobilisation','mobilising','en_route','arrived','awaiting_customer_access','started','in_progress','paused','awaiting_materials','awaiting_customer_decision','work_completed') or edge->>1 not in ('mobilising','en_route','arrived','awaiting_customer_access','started','in_progress','paused','awaiting_materials','awaiting_customer_decision','work_completed') or edge->>0=edge->>1) then raise exception 'bounded execution-only transition edges required' using errcode='23514';end if;
 if not exists(with recursive reachable(state) as(select 'awaiting_mobilisation'::text union select edge->>1 from reachable r cross join jsonb_array_elements(config->'transitions') edge where edge->>0=r.state) select 1 from reachable where state='work_completed') then raise exception 'workflow must permit controlled completion' using errcode='23514';end if;
 for row_item in select key,value from jsonb_each(config->'sla') loop if jsonb_typeof(row_item.value)<>'number' or (row_item.value#>>'{}')::numeric not between 1 and 31536000 or trunc((row_item.value#>>'{}')::numeric)<>(row_item.value#>>'{}')::numeric then raise exception 'positive configured SLA seconds required' using errcode='23514';end if;end loop;
 if not (config->'sla' ?& array['mobilisation','arrival','start','task_completion','quality_review','rework','case_acknowledgement','case_resolution','customer_response']) then raise exception 'mandatory SLA configuration missing' using errcode='23514';end if;
 for row_item in select unnest(array['execution_checklist','quality_checklist','handover_checklist']) key loop
 if not exists(select 1 from public.service_checklists where id=(config->>row_item.key)::uuid and service_version_id=p.service_version_id and publication_status='published' and checklist_type=case when row_item.key='quality_checklist' then 'quality' else 'execution' end) then raise exception 'published service-consistent checklist required' using errcode='23514';end if;
 end loop;
 if exists(select 1 from private.fulfilment_policies other where other.status='approved' and other.service_version_id=p.service_version_id and other.customer_account_id is not distinct from p.customer_account_id and other.contract_reference is not distinct from p.contract_reference and tstzrange(other.valid_from,other.valid_until,'[)')&&tstzrange(p.valid_from,p.valid_until,'[)')) then raise exception 'overlapping execution policy' using errcode='23514';end if;
 update private.fulfilment_policies set status='approved',approved_by=auth.uid(),approved_at=now() where id=p.id;
 else update private.fulfilment_policies set status='retired' where id=p.id;end if;result=p.id;
 else raise exception 'unsupported configuration command' using errcode='23514';end case;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'fulfilment_config',p_key,payload,result);return result;
end$$;
create function public.fulfilment_configuration(p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_configuration(p_action,p_data,p_key)$$;
revoke all on function public.fulfilment_configuration(text,jsonb,text) from public,anon;
grant execute on function public.fulfilment_configuration(text,jsonb,text),app_private.fulfilment_configuration(text,jsonb,text) to authenticated;
commit;
