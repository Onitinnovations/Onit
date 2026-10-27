begin;
create function app_private.order_customer(p_order uuid,p_action text default 'read') returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_orders o where o.id=p_order and
 ((o.branch_id is not null and app_private.can_access_branch(o.branch_id,p_action,o.department_id)) or
 (o.branch_id is null and app_private.can_access_customer(o.customer_account_id,p_action='request',o.department_id) and
 (p_action<>'approve' or exists(select 1 from public.customer_profiles c where c.id=o.customer_account_id and c.individual_profile_id=auth.uid()) or
 exists(select 1 from private.corporate_account_users u where u.customer_account_id=o.customer_account_id and u.profile_id=auth.uid() and u.can_approve)))))
$$;
create function app_private.order_receipt(p_order uuid,p_action text,p_subject uuid,p_previous text,p_new text,p_reason text,p_permission text) returns void
language plpgsql security definer set search_path='' as $$
declare ev uuid;correlation uuid=gen_random_uuid();begin
 insert into private.order_history(order_id,order_revision,action,subject_id,previous_state,new_state,reason,permission_code,actor_id,correlation_id,order_snapshot)
 select id,revision,p_action,p_subject,p_previous,p_new,p_reason,p_permission,auth.uid(),correlation,to_jsonb(o) from private.service_orders o where id=p_order;
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(p_order,'order.'||p_action,p_subject,correlation) returning id into ev;
 insert into private.operational_event_deliveries(event_id,created_by) values(ev,auth.uid());
end$$;
create function app_private.order_policy(p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare r private.order_policies;result uuid;receipt private.transaction_commands;payload jsonb=jsonb_build_object('action',p_action,'data',p_data);begin
 if auth.uid() is null or not app_private.has_permission(case when p_action='prepare' then 'orders.policy.manage' else 'orders.policy.approve' end) then raise exception 'global order policy permission required' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192 then raise exception 'bounded policy input required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('order-policy-command:'||auth.uid()::text||p_key,0));
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='order_policy' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'policy idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action='prepare' then
 insert into private.order_policies(service_version_id,version,valid_from,valid_until,payment_gate,offer_seconds,performance_weight,workload_weight,created_by)
 values((p_data->>'service_version_id')::uuid,(p_data->>'version')::integer,(p_data->>'valid_from')::timestamptz,(p_data->>'valid_until')::timestamptz,p_data->>'payment_gate',(p_data->>'offer_seconds')::integer,(p_data->>'performance_weight')::numeric,(p_data->>'workload_weight')::numeric,auth.uid()) returning id into result;
 elsif p_action in ('approve','retire') then
 select * into r from private.order_policies where id=(p_data->>'id')::uuid;
 if not found then raise exception 'policy unavailable' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('order-policy:'||r.service_version_id::text,0));
 select * into r from private.order_policies where id=r.id for update;
 if r.created_by=auth.uid() or (p_action='approve' and r.status<>'draft') or (p_action='retire' and r.status<>'approved') then raise exception 'independent policy decision required' using errcode='42501';end if;
 if p_action='approve' and exists(select 1 from private.order_policies p where p.service_version_id=r.service_version_id and p.status='approved' and tstzrange(p.valid_from,p.valid_until,'[)')&&tstzrange(r.valid_from,r.valid_until,'[)')) then raise exception 'overlapping order policy' using errcode='23514';end if;
 update private.order_policies set status=case p_action when 'approve' then 'approved' else 'retired' end,approved_by=case when p_action='approve' then auth.uid() else approved_by end,approved_at=case when p_action='approve' then now() else approved_at end where id=r.id;result=r.id;
 else raise exception 'unsupported policy command' using errcode='23514';end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'order_policy',p_key,payload,result);
 return result;
end$$;
create function app_private.order_policy_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or (old.status<>'draft' and ((to_jsonb(new)-array['status','updated_at']) is distinct from (to_jsonb(old)-array['status','updated_at']) or not(old.status='approved' and new.status='retired'))) then raise exception 'released order policy immutable' using errcode='55000';end if;return new;end$$;
create trigger order_policy_immutable before update or delete on private.order_policies for each row execute function app_private.order_policy_guard();
create function app_private.order_zone(p_location uuid,p_zone uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.service_locations l join public.countries country on country.id=l.country_id and country.status='active'
 join public.states state on state.id=l.state_id and state.country_id=l.country_id and state.status='active'
 join public.cities city on city.id=l.city_id and city.state_id=l.state_id and city.status='active'
 join public.service_zones z on z.id=p_zone and z.state_id=l.state_id and z.status='active'
 join private.zone_boundaries_or_coverage c on c.zone_id=z.id and c.state_id=l.state_id and c.city_id=l.city_id and c.verified_at is not null
 where l.id=p_location and c.version=(select max(version) from private.zone_boundaries_or_coverage where zone_id=z.id))
$$;
create function app_private.order_gate(p_order uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.service_orders o join private.order_policies p on p.id=o.policy_id
 join private.order_commercial_versions c on c.order_id=o.id and c.version=(select max(version) from private.order_commercial_versions where order_id=o.id)
 join public.quotation_versions q on q.id=c.quotation_version_id and q.status='accepted'
 where o.id=p_order and p.status='approved' and p.valid_from<=now() and (p.valid_until is null or p.valid_until>=o.ends_at)
 and exists(select 1 from public.customer_profiles account where account.id=o.customer_account_id and account.status='approved')
 and (o.organisation_id is null or exists(select 1 from public.organisations organisation where organisation.id=o.organisation_id and organisation.status='active'))
 and (o.branch_id is null or exists(select 1 from public.corporate_account_branches branch where branch.id=o.branch_id and branch.status='active'))
 and app_private.order_zone(o.service_location_id,o.zone_id)
 and (p.payment_gate='no_upfront_payment' or exists(select 1 from private.order_authorizations a join private.document_objects d on d.id=a.document_id and d.scan_status='clean' and d.archived_at is null
 where a.order_id=o.id and a.order_revision=o.revision and a.status='approved' and a.valid_until>=greatest(now(),o.ends_at) and a.currency_id=c.currency_id and a.amount>=c.total
 and (a.kind in ('payment_evidence','exception') or (a.kind='corporate_credit' and p.payment_gate='payment_or_credit' and o.organisation_id is not null)))))
$$;
create function app_private.order_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare o private.service_orders;q public.quotation_versions;r public.service_requests;policy private.order_policies;
 a private.order_authorizations;change private.order_changes;c private.order_commercial_versions;
 result uuid;receipt private.transaction_commands;payload jsonb=jsonb_build_object('order',p_order,'action',p_action,'data',p_data);
 reason text=p_data->>'reason';permission text;oldstate text;start_time timestamptz;end_time timestamptz;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 or reason is null or length(trim(reason)) not between 1 and 2000 then raise exception 'bounded order command required' using errcode='23514';end if;
 -- One receipt lock precedes the order lock, consistently for every command.
 perform pg_advisory_xact_lock(hashtextextended('order-command:'||auth.uid()::text||p_key,0));
 if p_action='create' then
 select * into q from public.quotation_versions where id=(p_data->>'quotation_version_id')::uuid;
 select * into r from public.service_requests where id=(select request_id from public.quotations where id=q.quotation_id);
 if r.id is null or not (app_private.request_access(r.id,'approve') or app_private.has_permission('orders.manage',r.organisation_id)) then raise exception 'order creation denied' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('order-quote:'||q.id::text,0));
 else
 select * into o from private.service_orders where id=p_order for update;
 if not found then raise exception 'order unavailable' using errcode='42501';end if;
 permission=case p_action when 'release' then 'orders.release' when 'decide_authorization' then
 (select case kind when 'payment_evidence' then 'orders.payment.verify' when 'corporate_credit' then 'orders.credit.approve' else 'orders.exception.approve' end from private.order_authorizations where id=(p_data->>'id')::uuid and order_id=o.id)
 else 'orders.manage' end;
 if not (app_private.has_permission(permission,o.organisation_id) or (p_action='propose_change' and app_private.order_customer(o.id,'request'))) then raise exception 'order command permission denied' using errcode='42501';end if;
 if p_action='propose_change' and not app_private.has_permission(permission,o.organisation_id) then permission='customer.request';end if;
 end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='order_command' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'order idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if p_action<>'create' and ((p_data->>'expected_revision')::integer is distinct from o.revision or o.status='cancelled') then raise exception 'stale or terminal order' using errcode='40001';end if;
 oldstate=o.status;
 if p_action in ('release','decide_authorization') and (exists(select 1 from public.customer_profiles account where account.id=o.customer_account_id and account.individual_profile_id=auth.uid()) or exists(select 1 from private.corporate_account_users member where member.customer_account_id=o.customer_account_id and member.profile_id=auth.uid() and member.status='approved')) then raise exception 'customer parties cannot approve their own commercial release' using errcode='42501';end if;
 case p_action
 when 'create' then
 if q.status is distinct from 'accepted' or q.approved_at is null or q.decided_at is null then raise exception 'accepted independently approved quotation required' using errcode='23514';end if;
 select order_id into result from private.order_commercial_versions where quotation_version_id=q.id;
 if result is not null then
 if not exists(select 1 from private.service_orders existing where existing.id=result and existing.zone_id=(p_data->>'zone_id')::uuid and existing.starts_at=(p_data->>'start')::timestamptz and existing.ends_at=(p_data->>'end')::timestamptz) then raise exception 'commercial transaction already has an order; use approved change workflow' using errcode='23505';end if;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'order_command',p_key,payload,result);return result;end if;
 select * into policy from private.order_policies where service_version_id=r.service_version_id and status='approved' and valid_from<=now() and (valid_until is null or valid_until>=(p_data->>'end')::timestamptz);
 if policy.id is null then raise exception 'approved effective order policy required' using errcode='23514';end if;
 start_time=(p_data->>'start')::timestamptz;end_time=(p_data->>'end')::timestamptz;
 if start_time is null or start_time<=now() or end_time is null or not app_private.order_zone(r.service_location_id,(p_data->>'zone_id')::uuid) then raise exception 'future verified service schedule required' using errcode='23514';end if;
 insert into private.service_orders(request_id,customer_account_id,organisation_id,branch_id,department_id,service_version_id,service_location_id,zone_id,policy_id,classification,starts_at,ends_at,created_by)
 values(r.id,r.customer_account_id,r.organisation_id,r.branch_id,r.department_id,r.service_version_id,r.service_location_id,(p_data->>'zone_id')::uuid,policy.id,case when r.organisation_id is null then 'individual' else 'corporate' end,start_time,end_time,auth.uid()) returning * into o;
 insert into private.order_commercial_versions(order_id,quotation_version_id,version,snapshot,currency_id,total,minor_units,created_by)
 values(o.id,q.id,1,app_private.read_quotation(q.id),q.currency_id,q.total,q.money_scale,auth.uid());result=o.id;permission='accepted_quote.order';
 when 'authorization' then
 select * into c from private.order_commercial_versions where order_id=o.id order by version desc limit 1;
 if p_data->>'amount' is null or p_data->>'amount' !~ '^[0-9]+(\.[0-9]{1,4})?$' or not exists(select 1 from private.document_objects where id=(p_data->>'document_id')::uuid and customer_account_id=o.customer_account_id and scan_status='clean' and archived_at is null and classification not in ('identity','employee')) then raise exception 'exact amount and clean account evidence required' using errcode='23514';end if;
 if p_data->>'kind'='corporate_credit' and o.organisation_id is null then raise exception 'corporate account required' using errcode='23514';end if;
 insert into private.order_authorizations(order_id,customer_account_id,order_revision,kind,document_id,reference,currency_id,amount,valid_until,reason,created_by)
 values(o.id,o.customer_account_id,o.revision,p_data->>'kind',(p_data->>'document_id')::uuid,p_data->>'reference',c.currency_id,(p_data->>'amount')::numeric,(p_data->>'valid_until')::timestamptz,reason,auth.uid()) returning id into result;
 when 'decide_authorization' then
 select * into a from private.order_authorizations where id=(p_data->>'id')::uuid and order_id=o.id for update;
 if a.id is null or a.status<>'pending' or a.created_by=auth.uid() or a.order_revision<>o.revision or a.valid_until<o.ends_at then raise exception 'independent current authorization required' using errcode='42501';end if;
 select * into c from private.order_commercial_versions where order_id=o.id order by version desc limit 1;
 if p_data->>'approve' is null or a.amount<>round(a.amount,c.minor_units) then raise exception 'explicit precision-aware authorization required' using errcode='23514';end if;
 if a.kind='payment_evidence' then
 perform pg_advisory_xact_lock(hashtextextended('external-payment-evidence:'||a.reference,0));
 if exists(select 1 from private.order_authorizations used where used.kind=a.kind and used.reference=a.reference and used.status='approved' and used.order_id<>o.id) then raise exception 'payment evidence already allocated to another order' using errcode='23514';end if;
 end if;
 update private.order_authorizations set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,decided_by=auth.uid(),decided_at=now() where id=a.id;result=a.id;
 when 'release' then
 if o.created_by=auth.uid() or o.status<>'pending_authorization' or o.starts_at<=clock_timestamp() or not app_private.order_gate(o.id) then raise exception 'independent commercial release blocked' using errcode='23514';end if;
 update private.service_orders set status='awaiting_dispatch',released_by=auth.uid(),released_revision=revision where id=o.id;result=o.id;
 when 'propose_change' then
 if p_data->>'kind' not in ('reschedule','cancel','amend') then raise exception 'unsupported order change' using errcode='23514';end if;
 insert into private.order_changes(order_id,order_revision,kind,proposal,reason,created_by) values(o.id,o.revision,p_data->>'kind',coalesce(p_data->'proposal','{}'),reason,auth.uid()) returning id into result;
 when 'decide_change' then
 select * into change from private.order_changes where id=(p_data->>'id')::uuid and order_id=o.id for update;
 if change.id is null or change.created_by=auth.uid() or change.status<>'pending' or change.order_revision<>o.revision then raise exception 'independent current change decision required' using errcode='42501';end if;
 if p_data->>'approve' is null then raise exception 'explicit change decision required' using errcode='23514';end if;
 if (p_data->>'approve')::boolean then
 perform app_private.clear_order_dispatch(o.id,reason);
 if change.kind='amend' then
 select * into q from public.quotation_versions where id=(change.proposal->>'quotation_version_id')::uuid;
 select * into r from public.service_requests where id=(select request_id from public.quotations where id=q.quotation_id);
 if q.status is distinct from 'accepted' or r.customer_account_id<>o.customer_account_id or r.branch_id is distinct from o.branch_id or r.department_id is distinct from o.department_id or r.service_version_id<>o.service_version_id or
 (select row(address_snapshot,country_id,state_id,city_id,latitude,longitude) from public.service_locations where id=r.service_location_id) is distinct from (select row(address_snapshot,country_id,state_id,city_id,latitude,longitude) from public.service_locations where id=o.service_location_id)
 then raise exception 'accepted same-scope commercial amendment required' using errcode='23514';end if;
 insert into private.order_commercial_versions(order_id,quotation_version_id,version,snapshot,currency_id,total,minor_units,created_by)
 select o.id,q.id,max(version)+1,app_private.read_quotation(q.id),q.currency_id,q.total,q.money_scale,auth.uid() from private.order_commercial_versions where order_id=o.id;
 elsif change.kind='reschedule' then
 start_time=(change.proposal->>'start')::timestamptz;end_time=(change.proposal->>'end')::timestamptz;
 if start_time is null or start_time<=now() or end_time is null then raise exception 'future schedule required' using errcode='23514';end if;
 update private.service_orders set starts_at=start_time,ends_at=end_time where id=o.id;
 end if;
 if change.kind<>'cancel' then
 select * into policy from private.order_policies where service_version_id=o.service_version_id and status='approved' and valid_from<=now() and (valid_until is null or valid_until>=(select ends_at from private.service_orders where id=o.id));
 if policy.id is null then raise exception 'effective approved order policy required for revised work' using errcode='23514';end if;
 end if;
 update private.service_orders set revision=revision+1,status=case when change.kind='cancel' then 'cancelled' else 'pending_authorization' end,policy_id=case when change.kind='cancel' then policy_id else policy.id end,released_by=null,released_revision=null where id=o.id;
 end if;
 update private.order_changes set status=case when (p_data->>'approve')::boolean then 'approved' else 'rejected' end,decided_by=auth.uid() where id=change.id;result=change.id;
 when 'hold','resume' then
 if (p_action='hold' and o.status not in ('awaiting_dispatch','assigned','pending_authorization')) or (p_action='resume' and o.status<>'on_hold') then raise exception 'invalid hold transition' using errcode='55000';end if;
 perform app_private.clear_order_dispatch(o.id,reason);
 if p_action='resume' then
 select * into policy from private.order_policies where service_version_id=o.service_version_id and status='approved' and valid_from<=now() and (valid_until is null or valid_until>=o.ends_at);
 if policy.id is null then raise exception 'effective order policy required' using errcode='23514';end if;end if;
 update private.service_orders set status=case p_action when 'hold' then 'on_hold' else 'pending_authorization' end,revision=revision+1,policy_id=case when p_action='resume' then policy.id else policy_id end,released_by=null,released_revision=null where id=o.id;result=o.id;
 else raise exception 'unsupported order command' using errcode='23514';end case;
 perform app_private.order_receipt(o.id,p_action,result,oldstate,(select status from private.service_orders where id=o.id),reason,permission);
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'order_command',p_key,payload,result);
 return result;
end$$;
create function public.order_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.order_command(p_order,p_action,p_data,p_key)$$;
create function public.order_policy_command(p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.order_policy(p_action,p_data,p_key)$$;
create function public.create_service_order(p_quote uuid,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.order_command(null,'create',p_data||jsonb_build_object('quotation_version_id',p_quote),p_key)$$;
revoke all on function public.create_service_order(uuid,jsonb,text) from public,anon;
grant execute on function public.create_service_order(uuid,jsonb,text) to authenticated;
revoke all on function public.order_command(uuid,text,jsonb,text),public.order_policy_command(text,jsonb,text) from public,anon;
grant execute on function public.order_command(uuid,text,jsonb,text),public.order_policy_command(text,jsonb,text),app_private.order_command(uuid,text,jsonb,text),app_private.order_policy(text,jsonb,text) to authenticated;
commit;
