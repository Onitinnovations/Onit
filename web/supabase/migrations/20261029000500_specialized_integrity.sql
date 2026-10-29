begin;
create function app_private.guard_specialized_record() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'specialised history must be retained' using errcode='55000';end if;
 if tg_table_name='specialized_service_policies' then
 if old.status<>'draft' and not(old.status='approved' and new.status='retired' and(to_jsonb(new)-array['status','updated_at'])=(to_jsonb(old)-array['status','updated_at'])) then raise exception 'approved capability policy immutable' using errcode='55000';end if;
 elsif tg_table_name='service_operations' then
 if old.status in ('closed','cancelled') or (to_jsonb(new)-array['status','revision','updated_at'])<>(to_jsonb(old)-array['status','revision','updated_at']) then raise exception 'operation identity and commercial snapshot immutable' using errcode='55000';end if;
 elsif tg_table_name='laundry_bags' then
 if old.customer_acknowledged_by is not null and (to_jsonb(new)-array['sorted_at','sorted_by','updated_at'])<>(to_jsonb(old)-array['sorted_at','sorted_by','updated_at']) then raise exception 'acknowledged intake immutable' using errcode='55000';end if;
 elsif tg_table_name='laundry_custody_transfers' then
 if old.status in ('received','rejected','resolved') or (to_jsonb(new)-array['status','sent_by','sent_at','received_by','received_at','updated_at'])<>(to_jsonb(old)-array['status','sent_by','sent_at','received_by','received_at','updated_at']) then raise exception 'custody terms and final acknowledgements immutable' using errcode='55000';end if;
 elsif tg_table_name='laundry_transfer_items' then
 if old.received_units is not null or (to_jsonb(new)-array['received_units','discrepancy_case_id','updated_at'])<>(to_jsonb(old)-array['received_units','discrepancy_case_id','updated_at']) then raise exception 'custody line terms and counted receipt immutable' using errcode='55000';end if;
 elsif tg_table_name='laundry_allocation_changes' then
 if old.status<>'pending' or (to_jsonb(new)-array['status','approved_by','updated_at'])<>(to_jsonb(old)-array['status','approved_by','updated_at']) then raise exception 'allocation correction evidence immutable' using errcode='55000';end if;
 end if;return new;
end$$;
do $$declare name text;begin foreach name in array array['specialized_service_policies','service_operations','laundry_bags','laundry_custody_transfers','laundry_transfer_items','laundry_allocation_changes'] loop execute format('create trigger specialized_guard before update or delete on private.%I for each row execute function app_private.guard_specialized_record()',name);end loop;end$$;
create function app_private.enforce_laundry_conservation() returns trigger language plpgsql security definer set search_path='' as $$declare operation uuid;begin
 operation=coalesce(new.operation_id,old.operation_id);
 if exists(select 1 from private.laundry_items item where item.operation_id=operation and item.units<>(select coalesce(sum(units),0) from private.laundry_custody_balances where item_id=item.id)) then raise exception 'garment custody conservation violated' using errcode='23514';end if;return null;
end$$;
create constraint trigger laundry_balance_conservation after insert or update or delete on private.laundry_custody_balances deferrable initially deferred for each row execute function app_private.enforce_laundry_conservation();
create constraint trigger laundry_intake_conservation after insert on private.laundry_items deferrable initially deferred for each row execute function app_private.enforce_laundry_conservation();
alter function app_private.fulfilment_command(uuid,text,jsonb,text) rename to pre_specialized_fulfilment_command;
revoke all on function app_private.pre_specialized_fulfilment_command(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$declare v_order uuid;operation uuid;purpose text;resource uuid;begin
 select w.order_id into v_order from private.work_orders w where w.id=p_work;perform 1 from private.service_orders where id=v_order for update;
 if p_action in ('progress','supervisor_verify','substitute','task_reassign') then
 select link.operation_id,link.purpose,task.resource_id into operation,purpose,resource from private.operation_tasks link join private.work_tasks task on task.id=link.task_id join private.service_operations parent on parent.id=link.operation_id and parent.kind='laundry' and parent.status='active' where task.id=(p_data->>'task_id')::uuid and task.work_order_id=p_work;
 if operation is not null then
 if not(app_private.operation_staff(operation) or app_private.execution_worker((p_data->>'task_id')::uuid) or app_private.execution_staff((select order_id from private.work_orders where id=p_work),'fulfilment.supervise')) then raise exception 'assigned specialised work authority required' using errcode='42501';end if;
 if p_action in ('substitute','task_reassign') and exists(select 1 from private.laundry_custody_balances where operation_id=operation and resource_id=resource and units>0) then raise exception 'acknowledged custody must move before changing its responsible human' using errcode='23514';end if;
 if purpose='processing' and p_action='progress' and p_data->>'state' in ('started','in_progress','work_completed') then
 if not exists(select 1 from private.laundry_processing_batches where operation_id=operation and processing_task_id=(p_data->>'task_id')::uuid) or exists(select 1 from private.laundry_processing_batches where operation_id=operation and processing_task_id=(p_data->>'task_id')::uuid and status not in ('received','processing','quality_review','packaged','returned')) then raise exception 'acknowledged processing batch receipt required before execution' using errcode='23514';end if;
 end if;
 if purpose='processing' and p_action='supervisor_verify' and exists(select 1 from private.laundry_processing_batches where operation_id=operation and processing_task_id=(p_data->>'task_id')::uuid and status not in ('quality_review','packaged','returned')) then raise exception 'batch completion submission required before shared quality' using errcode='23514';end if;
 if purpose='pickup' and p_action='progress' and p_data->>'state'='work_completed' and exists(select 1 from private.laundry_custody_balances where operation_id=operation and customer_holder and units>0) then raise exception 'pickup requires receiver-acknowledged intake' using errcode='23514';end if;
 end if;end if;
 if p_action in ('close_work','cancel_work','retire_for_reschedule') then
 select w.order_id into v_order from private.work_orders w where w.id=p_work;perform 1 from private.service_orders where id=v_order for update;
 if exists(select 1 from private.operation_orders member join private.service_operations operation on operation.id=member.operation_id where member.order_id=v_order and operation.status not in ('ready','closed','cancelled')) then raise exception 'mandatory specialised custody or deliverables incomplete' using errcode='23514';end if;
 end if;
 return app_private.pre_specialized_fulfilment_command(p_work,p_action,p_data,p_key);
end$$;
grant execute on function app_private.fulfilment_command(uuid,text,jsonb,text) to authenticated;
create or replace function public.fulfilment_command(p_work uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(p_work,p_action,p_data,p_key)$$;
create or replace function public.create_work_order(p_order uuid,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.fulfilment_command(null,'create_work',p_data||jsonb_build_object('order_id',p_order),p_key)$$;

-- Preserve API authority while sharing the same evaluator with operation actions.
create or replace function app_private.provider_party_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare provider private.provider_profiles;begin
 select * into provider from private.provider_profiles where id=p_provider;
 if provider.id is null or not(app_private.provider_self(provider.id) or app_private.has_permission('providers.read',provider.organisation_id) or app_private.has_permission('providers.capacity.manage',provider.organisation_id)) then raise exception 'provider eligibility access denied' using errcode='42501';end if;
 return app_private.provider_party_eligibility_kernel(p_provider,p_service,p_zone,p_start,p_end,p_units,p_worker);
end$$;
create or replace function app_private.provider_eligibility(p_provider uuid,p_service uuid,p_zone uuid,p_start timestamptz,p_end timestamptz,p_units text,p_worker uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare provider private.provider_profiles;worker uuid;begin
 select * into provider from private.provider_profiles where id=p_provider;
 if provider.id is null or not(app_private.provider_self(provider.id) or app_private.has_permission('providers.read',provider.organisation_id) or app_private.has_permission('providers.capacity.manage',provider.organisation_id)) then raise exception 'provider eligibility access denied' using errcode='42501';end if;
 worker=coalesce(p_worker,provider.individual_profile_id);
 if worker is not null and not(worker=auth.uid() or app_private.provider_self(provider.id,true) or app_private.has_permission('providers.read',provider.organisation_id) or app_private.has_permission('providers.capacity.manage',provider.organisation_id)) then raise exception 'worker resource access denied' using errcode='42501';end if;
 return app_private.provider_eligibility_kernel(p_provider,p_service,p_zone,p_start,p_end,p_units,p_worker);
end$$;
commit;
