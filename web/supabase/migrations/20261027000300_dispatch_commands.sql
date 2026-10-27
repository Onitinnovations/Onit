begin;
-- Canonical resource locks compose Increment 3 reservations across all parties.
create function app_private.dispatch_locks(p_order uuid,p_selection jsonb default '[]') returns void
language plpgsql security definer set search_path='' as $$declare resource uuid;service uuid;begin
 select service_version_id into service from private.service_orders where id=p_order;
 perform pg_advisory_xact_lock(hashtextextended('provider-policy:'||service::text,0));
 for resource in select worker_id from (
 select r.worker_id from private.assignment_resources r join private.assignment_offers f on f.id=r.offer_id join private.dispatch_proposals p on p.id=f.proposal_id where p.order_id=p_order and p.status in ('pending','ready','confirmed')
 union select (v->>'worker_id')::uuid from jsonb_array_elements(p_selection) v) q order by worker_id loop
 perform 1 from public.profiles where id=resource for no key update;
 end loop;
 for resource in select provider_id from (
 select f.provider_id from private.assignment_offers f join private.dispatch_proposals p on p.id=f.proposal_id where p.order_id=p_order and p.status in ('pending','ready','confirmed')
 union select (v->>'provider_id')::uuid from jsonb_array_elements(p_selection) v) q order by provider_id loop
 perform 1 from private.provider_profiles where id=resource for update;
 end loop;
end$$;
create function app_private.clear_order_dispatch(p_order uuid,p_reason text,p_status text default 'withdrawn') returns void
language plpgsql security definer set search_path='' as $$begin
 perform app_private.dispatch_locks(p_order);
 update private.provider_capacity_reservations r set status='released' where r.status in ('assigned','reserved') and exists(
 select 1 from private.assignment_resources a join private.assignment_offers f on f.id=a.offer_id join private.dispatch_proposals p on p.id=f.proposal_id
 where a.reservation_id=r.id and p.order_id=p_order and p.status in ('pending','ready','confirmed'));
 update private.assignment_offers f set status=case when p_status='expired' then 'expired' else 'withdrawn' end where exists(select 1 from private.dispatch_proposals p where p.id=f.proposal_id and p.order_id=p_order and p.status in ('pending','ready','confirmed'));
 update private.dispatch_proposals set status=p_status where order_id=p_order and status in ('pending','ready','confirmed');
end$$;
create function app_private.match_order(p_order uuid,p_candidates jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o private.service_orders;policy private.order_policies;v jsonb;decision jsonb;result jsonb='[]';score numeric;candidate uuid;begin
 select * into o from private.service_orders where id=p_order for update;
 if not found or not app_private.has_permission('dispatch.manage',o.organisation_id) then raise exception 'dispatch permission required' using errcode='42501';end if;
 if o.status<>'awaiting_dispatch' or o.released_revision is distinct from o.revision or not app_private.order_gate(o.id) then raise exception 'order is not released' using errcode='55000';end if;
 if jsonb_typeof(p_candidates) is distinct from 'array' or jsonb_array_length(p_candidates) not between 1 and 100 or octet_length(p_candidates::text)>32768 then raise exception 'bounded candidate selection required' using errcode='23514';end if;
 select * into policy from private.order_policies where id=o.policy_id;
 for v in select value from jsonb_array_elements(p_candidates) loop
 if v->>'worker_id' is null then raise exception 'explicit executing personnel required' using errcode='23514';end if;
 decision=app_private.provider_eligibility((v->>'provider_id')::uuid,o.service_version_id,o.zone_id,o.starts_at,o.ends_at,v->>'units',(v->>'worker_id')::uuid);
 score=policy.performance_weight*coalesce((decision->>'performance_ratio')::numeric,0)-policy.workload_weight*coalesce((decision->>'capacity_used')::numeric/nullif((decision->>'capacity_limit')::numeric,0),0);
 insert into private.dispatch_candidates(order_id,order_revision,provider_id,worker_id,units,decision,score,policy_id,created_by)
 values(o.id,o.revision,(v->>'provider_id')::uuid,(v->>'worker_id')::uuid,(v->>'units')::numeric,decision,score,policy.id,auth.uid()) returning id into candidate;
 result=result||jsonb_build_array(jsonb_build_object('id',candidate,'provider_id',v->>'provider_id','worker_id',v->>'worker_id','score',score::text,'decision',decision));
 end loop;
 perform app_private.order_receipt(o.id,'matched',o.id,o.status,o.status,'Explicit bounded eligible shortlist','dispatch.manage');
 return (select jsonb_agg(value order by (value->>'score')::numeric desc,value->>'provider_id',value->>'worker_id',value->>'id') from jsonb_array_elements(result));
end$$;
create function app_private.dispatch_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare o private.service_orders;p private.dispatch_proposals;f private.assignment_offers;c private.dispatch_candidates;
 policy private.order_policies;resource record;entry jsonb;selection jsonb='[]';decision jsonb;reservation uuid;offer uuid;result uuid;
 receipt private.transaction_commands;payload jsonb=jsonb_build_object('order',p_order,'action',p_action,'data',p_data);valid_assignment boolean=true;
 reason text=p_data->>'reason';oldstate text;permission text='dispatch.manage';
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'active authentication required' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 8 and 128 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 or reason is null or length(trim(reason)) not between 1 and 2000 then raise exception 'bounded dispatch input required' using errcode='23514';end if;
 perform pg_advisory_xact_lock(hashtextextended('dispatch-command:'||auth.uid()::text||p_key,0));
 select * into o from private.service_orders where id=p_order for update;
 if not found then raise exception 'order unavailable' using errcode='42501';end if;
 if p_action='respond' then
 select f1.* into f from private.assignment_offers f1 join private.dispatch_proposals p1 on p1.id=f1.proposal_id and p1.order_id=o.id where f1.id=(p_data->>'offer_id')::uuid;
 if f.id is null or not app_private.provider_self(f.provider_id,true) then raise exception 'addressed provider administrator required' using errcode='42501';end if;permission='provider.addressed_offer';
 else
 if not app_private.has_permission('dispatch.manage',o.organisation_id) then raise exception 'dispatch permission required' using errcode='42501';end if;
 end if;
 select * into receipt from private.transaction_commands where actor_id=auth.uid() and command='dispatch_command' and idempotency_key=p_key;
 if found then if receipt.payload<>payload then raise exception 'dispatch idempotency conflict' using errcode='23505';end if;return receipt.result_id;end if;
 if (p_data->>'expected_revision')::integer is distinct from o.revision or o.status not in ('awaiting_dispatch','assigned') then raise exception 'stale or unavailable order' using errcode='40001';end if;
 select * into policy from private.order_policies where id=o.policy_id;
 oldstate=o.status;
 case p_action
 when 'propose' then
 if o.status<>'awaiting_dispatch' or o.released_revision is distinct from o.revision or not app_private.order_gate(o.id) then raise exception 'commercial dispatch gate failed' using errcode='23514';end if;
 if jsonb_typeof(p_data->'candidates') is distinct from 'array' or jsonb_array_length(p_data->'candidates') not between 1 and 32 then raise exception 'bounded candidates required' using errcode='23514';end if;
 for entry in select value from jsonb_array_elements(p_data->'candidates') loop
 select * into c from private.dispatch_candidates where id=(entry#>>'{}')::uuid and order_id=o.id and order_revision=o.revision and policy_id=o.policy_id;
 if not found or (c.decision->>'eligible')::boolean is distinct from true then raise exception 'eligible current shortlist required' using errcode='23514';end if;
 selection=selection||jsonb_build_array(jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'worker_id',c.worker_id,'units',c.units::text));
 end loop;
 if (select count(*) from jsonb_array_elements(selection))<>(select count(distinct v->>'worker_id') from jsonb_array_elements(selection) v) then raise exception 'one resource per human per proposal' using errcode='23514';end if;
 perform app_private.dispatch_locks(o.id,selection);
 insert into private.dispatch_proposals(order_id,order_revision,expires_at,override_reason,created_by)
 values(o.id,o.revision,least(clock_timestamp()+make_interval(secs=>policy.offer_seconds),o.starts_at),p_data->>'override_reason',auth.uid()) returning * into p;
 if p.expires_at<=clock_timestamp() then raise exception 'offer window already elapsed' using errcode='23514';end if;
 -- A lower-ranked selection needs explicit independent preference override. No mandatory filter can be overridden.
 if exists(select 1 from private.dispatch_candidates d where d.order_id=o.id and d.order_revision=o.revision and (d.decision->>'eligible')::boolean
 and d.score>(select min((s->>'score')::numeric) from (select jsonb_build_object('score',dc.score) s from private.dispatch_candidates dc where dc.id in(select (v->>'candidate_id')::uuid from jsonb_array_elements(selection) v)) scores)) and p.override_reason is null then raise exception 'lower-ranked proposal requires override reason' using errcode='23514';end if;
 for entry in select value from jsonb_array_elements(selection) order by value->>'provider_id',value->>'worker_id' loop
 insert into private.assignment_offers(proposal_id,provider_id,created_by) values(p.id,(entry->>'provider_id')::uuid,auth.uid()) on conflict(proposal_id,provider_id) do nothing;
 select id into offer from private.assignment_offers where proposal_id=p.id and provider_id=(entry->>'provider_id')::uuid;
 reservation=app_private.provider_reservation((entry->>'provider_id')::uuid,'reserve',jsonb_build_object('service_version_id',o.service_version_id,'zone_id',o.zone_id,'start',o.starts_at,'end',o.ends_at,'units',entry->>'units','worker_id',entry->>'worker_id','expires_at',p.expires_at,'purpose_reference',p.id::text,'reason',reason),gen_random_uuid()::text);
 insert into private.assignment_resources(offer_id,provider_id,worker_id,reservation_id,candidate_id,created_by) values(offer,(entry->>'provider_id')::uuid,(entry->>'worker_id')::uuid,reservation,(entry->>'candidate_id')::uuid,auth.uid());
 end loop;result=p.id;
 when 'respond' then
 select * into p from private.dispatch_proposals where id=f.proposal_id for update;
 if p.status<>'pending' or p.order_revision<>o.revision or p.expires_at<=clock_timestamp() or f.status<>'pending' then raise exception 'stale, expired or answered offer' using errcode='40001';end if;
 if (p_data->>'accept')::boolean is null then raise exception 'explicit response required' using errcode='23514';end if;
 if (p_data->>'accept')::boolean then
 update private.assignment_offers set status='accepted',responded_by=auth.uid(),responded_at=clock_timestamp() where id=f.id;
 if not exists(select 1 from private.assignment_offers where proposal_id=p.id and status<>'accepted') then update private.dispatch_proposals set status='ready' where id=p.id;end if;
 else
 perform app_private.clear_order_dispatch(o.id,reason,'rejected');
 update private.assignment_offers set status='rejected',responded_by=auth.uid(),responded_at=clock_timestamp() where id=f.id;
 end if;result=f.id;
 when 'approve_override' then
 select * into p from private.dispatch_proposals where id=(p_data->>'id')::uuid and order_id=o.id for update;
 if p.id is null or p.status not in ('pending','ready') or p.expires_at<=clock_timestamp() or p.override_reason is null or p.created_by=auth.uid() or not app_private.has_permission('dispatch.override.approve',o.organisation_id) then raise exception 'independent override approval required' using errcode='42501';end if;
 if exists(select 1 from private.assignment_offers addressed where addressed.proposal_id=p.id and app_private.provider_self(addressed.provider_id)) or exists(select 1 from private.assignment_resources selected join private.assignment_offers addressed on addressed.id=selected.offer_id where addressed.proposal_id=p.id and selected.worker_id=auth.uid()) then raise exception 'selected providers and workers cannot approve their own override' using errcode='42501';end if;
 update private.dispatch_proposals set override_by=auth.uid() where id=p.id;result=p.id;
 when 'confirm','revalidate' then
 perform app_private.dispatch_locks(o.id);
 select * into p from private.dispatch_proposals where id=(p_data->>'id')::uuid and order_id=o.id for update;
 if p.id is null or p.order_revision<>o.revision or (p_action='confirm' and (p.status<>'ready' or p.expires_at<=clock_timestamp() or o.status<>'awaiting_dispatch')) or (p_action='revalidate' and (p.status<>'confirmed' or o.status<>'assigned')) or (p.override_reason is not null and p.override_by is null) then raise exception 'current accepted and authorised proposal required' using errcode='23514';end if;
 if not app_private.order_gate(o.id) then
 if p_action='confirm' then raise exception 'commercial revalidation failed' using errcode='23514';end if;
 valid_assignment=false;
 end if;
 -- Exclude only this bundle while rechecking; the resource locks prevent another transaction consuming the gap.
 if exists(select 1 from private.assignment_resources a join private.assignment_offers f1 on f1.id=a.offer_id join private.provider_capacity_reservations r1 on r1.id=a.reservation_id where f1.proposal_id=p.id and ((p_action='confirm' and (r1.status<>'reserved' or r1.expires_at<=clock_timestamp())) or (p_action='revalidate' and r1.status<>'assigned'))) then raise exception 'reservation expired or withdrawn' using errcode='40001';end if;
 update private.provider_capacity_reservations set status='released' where id in(select a.reservation_id from private.assignment_resources a join private.assignment_offers f1 on f1.id=a.offer_id where f1.proposal_id=p.id);
 for resource in select r1.* from private.provider_capacity_reservations r1 join private.assignment_resources a on a.reservation_id=r1.id join private.assignment_offers f1 on f1.id=a.offer_id where f1.proposal_id=p.id order by r1.provider_id,r1.worker_profile_id loop
 decision=app_private.provider_eligibility(resource.provider_id,o.service_version_id,o.zone_id,o.starts_at,o.ends_at,resource.units::text,resource.worker_profile_id);
 if (decision->>'eligible')::boolean is distinct from true then
 if p_action='confirm' then raise exception 'assignment eligibility revalidation failed' using errcode='23514';end if;
 valid_assignment=false;exit;
 end if;
 update private.provider_capacity_reservations set status='assigned' where id=resource.id;
 end loop;
 if valid_assignment then
 update private.dispatch_proposals set status='confirmed',confirmed_by=auth.uid() where id=p.id;
 update private.service_orders set status='assigned' where id=o.id;
 else
 perform app_private.clear_order_dispatch(o.id,reason);
 update private.service_orders set status='on_hold',revision=revision+1,released_by=null,released_revision=null where id=o.id;
 insert into private.dispatch_escalations(order_id,reason,created_by) values(o.id,'Assignment revalidation failed; review commercial and provider eligibility',auth.uid());
 end if;result=p.id;
 when 'withdraw','reassign','expire' then
 select * into p from private.dispatch_proposals where order_id=o.id and status in ('pending','ready','confirmed') for update;
 if p.id is null or (p_action='expire' and (p.expires_at>clock_timestamp() or p.status='confirmed')) then raise exception 'no applicable live proposal' using errcode='55000';end if;
 perform app_private.clear_order_dispatch(o.id,reason,case p_action when 'expire' then 'expired' else 'withdrawn' end);
 update private.service_orders set status='awaiting_dispatch' where id=o.id;result=p.id;
 when 'escalate' then
 insert into private.dispatch_escalations(order_id,reason,created_by) values(o.id,reason,auth.uid()) returning id into result;
 when 'resolve_escalation' then
 update private.dispatch_escalations set resolved_at=now(),resolved_by=auth.uid() where id=(p_data->>'id')::uuid and order_id=o.id and resolved_at is null returning id into result;
 if result is null then raise exception 'escalation unavailable' using errcode='42501';end if;
 else raise exception 'unsupported dispatch command' using errcode='23514';end case;
 perform app_private.order_receipt(o.id,'dispatch_'||p_action,result,oldstate,(select status from private.service_orders where id=o.id),reason,permission);
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'dispatch_command',p_key,payload,result);
 return result;
end$$;
-- Prevent the older standalone capacity RPC from releasing resources owned by dispatch.
alter function app_private.provider_reservation(uuid,text,jsonb,text) rename to standalone_provider_reservation;
revoke all on function app_private.standalone_provider_reservation(uuid,text,jsonb,text) from public,anon,authenticated;
create function app_private.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_action<>'reserve' and exists(select 1 from private.assignment_resources where reservation_id=(p_data->>'id')::uuid) then raise exception 'dispatch-owned capacity requires dispatch command' using errcode='55000';end if;
 return app_private.standalone_provider_reservation(p_provider,p_action,p_data,p_key);
end$$;
create or replace function public.provider_reservation(p_provider uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.provider_reservation(p_provider,p_action,p_data,p_key)$$;
create function public.match_order(p_order uuid,p_candidates jsonb) returns jsonb language sql set search_path='' as $$select app_private.match_order(p_order,p_candidates)$$;
create function public.dispatch_command(p_order uuid,p_action text,p_data jsonb,p_key text) returns uuid language sql set search_path='' as $$select app_private.dispatch_command(p_order,p_action,p_data,p_key)$$;
revoke all on function public.match_order(uuid,jsonb),public.dispatch_command(uuid,text,jsonb,text) from public,anon;
grant execute on function public.match_order(uuid,jsonb),public.dispatch_command(uuid,text,jsonb,text),app_private.match_order(uuid,jsonb),app_private.dispatch_command(uuid,text,jsonb,text),app_private.provider_reservation(uuid,text,jsonb,text) to authenticated;
commit;
