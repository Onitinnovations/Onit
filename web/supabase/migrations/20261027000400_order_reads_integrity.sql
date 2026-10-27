begin;
create function app_private.order_provider(p_order uuid,p_provider uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.assignment_offers f join private.dispatch_proposals p on p.id=f.proposal_id join private.service_orders o on o.id=p.order_id
 where p.order_id=p_order and f.provider_id=p_provider and o.status in ('awaiting_dispatch','assigned') and p.order_revision=o.revision
 and exists(select 1 from public.profiles where id=auth.uid() and status='active')
 and ((p.status in ('pending','ready') and p.expires_at>clock_timestamp()) or p.status='confirmed')
 and (app_private.provider_self(f.provider_id,true) or exists(select 1 from private.assignment_resources a join private.provider_personnel w on w.provider_id=a.provider_id and w.profile_id=a.worker_id
 join private.organisation_members m on m.profile_id=w.profile_id and m.organisation_id=w.organisation_id and m.status='active' and m.revoked_at is null and (m.valid_until is null or m.valid_until>now())
 where a.offer_id=f.id and a.worker_id=auth.uid() and w.revoked_at is null and w.valid_from<=now() and (w.valid_until is null or w.valid_until>now()))))
$$;
create function app_private.read_order(p_order uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o private.service_orders;staff boolean;customer boolean;provider boolean;result jsonb;begin
 select * into o from private.service_orders where id=p_order;
 staff=app_private.has_permission('orders.read',o.organisation_id) or app_private.has_permission('orders.manage',o.organisation_id) or app_private.has_permission('dispatch.manage',o.organisation_id);
 customer=app_private.order_customer(o.id);
 provider=exists(select 1 from private.assignment_offers f join private.dispatch_proposals p on p.id=f.proposal_id where p.order_id=o.id and app_private.order_provider(o.id,f.provider_id));
 if o.id is null or not coalesce(staff or customer or provider,false) then raise exception 'order read denied' using errcode='42501';end if;
 result=jsonb_build_object('id',o.id,'reference',o.reference,'revision',o.revision,'status',case when o.status='pending_authorization' then 'awaiting_confirmation' when o.status='awaiting_dispatch' then 'confirmed' else o.status end,
 'service_version_id',o.service_version_id,'start',o.starts_at,'end',o.ends_at);
 if staff or customer then
 result=result||jsonb_build_object('request_id',o.request_id,'customer_account_id',o.customer_account_id,'branch_id',o.branch_id,'commercial',(select snapshot from private.order_commercial_versions where order_id=o.id order by version desc limit 1));
 end if;
 if staff then result=result||jsonb_build_object('internal_status',o.status,'commercial_gate',app_private.order_gate(o.id),'policy_id',o.policy_id,
 'authorizations',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'status',status,'order_revision',order_revision,'amount',amount::text,'currency_id',currency_id,'valid_until',valid_until)||
 case when app_private.has_permission('orders.manage',o.organisation_id) or app_private.has_permission(case kind when 'payment_evidence' then 'orders.payment.verify' when 'corporate_credit' then 'orders.credit.approve' else 'orders.exception.approve' end,o.organisation_id)
 then jsonb_build_object('document_id',document_id,'reference',reference,'reason',reason,'created_by',created_by,'decided_by',decided_by) else '{}'::jsonb end),'[]') from private.order_authorizations where order_id=o.id),
 'changes',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from (select id,kind,status,order_revision,proposal,reason,created_by,decided_by,created_at from private.order_changes where order_id=o.id order by created_at desc,id limit 100) v),
 'history',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from (select id,action,order_revision,subject_id,previous_state,new_state,reason,actor_id,actor_type,permission_code,correlation_id,order_snapshot,created_at from private.order_history where order_id=o.id order by created_at desc,id limit 100) v));end if;
 if staff or provider then result=result||jsonb_build_object('offers',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'provider_id',f.provider_id,'proposal_id',p.id,'status',f.status,'proposal_status',p.status,'expires_at',p.expires_at,
 'override_reason',case when staff then p.override_reason end,'override_by',case when staff then p.override_by end,'proposed_by',case when staff then p.created_by end,
 'resources',(select jsonb_agg(jsonb_build_object('worker_id',a.worker_id,'units',r.units::text,'status',r.status)) from private.assignment_resources a join private.provider_capacity_reservations r on r.id=a.reservation_id where a.offer_id=f.id))),'[]')
 from private.assignment_offers f join private.dispatch_proposals p on p.id=f.proposal_id where p.order_id=o.id and (staff or app_private.order_provider(o.id,f.provider_id))));end if;
 if staff or (provider and o.status='assigned') then result=result||jsonb_build_object('location',(select jsonb_build_object('address',address_snapshot,'city_id',city_id,'latitude',latitude::text,'longitude',longitude::text) from public.service_locations where id=o.service_location_id),
 'scope',(select jsonb_agg(jsonb_build_object('description',line->>'description','kind',line->>'kind','quantity',line->>'quantity')) from private.order_commercial_versions c,jsonb_array_elements(c.snapshot->'lines') line where c.order_id=o.id and c.version=(select max(version) from private.order_commercial_versions where order_id=o.id)));end if;
 return result;
end$$;
create function app_private.list_order_operations(p_view text,p_after uuid default null,p_limit integer default 25) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if p_view not in ('orders','unassigned','pending_offers','confirmed_assignments','upcoming','exceptions','workload','expired_offers','failed_dispatch') or p_limit not between 1 and 100 or p_limit is null then raise exception 'bounded operational page required' using errcode='23514';end if;
 return (select coalesce(jsonb_agg(app_private.read_order(q.id) order by q.id),'[]') from (
 select o.id from private.service_orders o where (p_after is null or o.id>p_after)
 and (app_private.order_customer(o.id) or app_private.has_permission('orders.read',o.organisation_id) or app_private.has_permission('orders.manage',o.organisation_id) or app_private.has_permission('dispatch.manage',o.organisation_id)
 or exists(select 1 from private.assignment_offers f join private.dispatch_proposals p on p.id=f.proposal_id where p.order_id=o.id and app_private.order_provider(o.id,f.provider_id)))
 and (p_view='orders' or (p_view='unassigned' and o.status='awaiting_dispatch') or (p_view in ('confirmed_assignments','workload') and o.status='assigned') or (p_view='upcoming' and o.starts_at>now() and o.status in ('assigned','awaiting_dispatch'))
 or (p_view='pending_offers' and exists(select 1 from private.dispatch_proposals p where p.order_id=o.id and p.status in ('pending','ready') and p.expires_at>clock_timestamp()))
 or (p_view='expired_offers' and exists(select 1 from private.dispatch_proposals p where p.order_id=o.id and (p.status='expired' or (p.status in ('pending','ready') and p.expires_at<=clock_timestamp()))))
 or (p_view='failed_dispatch' and o.status='awaiting_dispatch' and exists(select 1 from private.dispatch_proposals p where p.order_id=o.id and p.status in ('expired','rejected','withdrawn')))
 or (p_view='exceptions' and exists(select 1 from private.dispatch_escalations e where e.order_id=o.id and e.resolved_at is null)))
 order by o.id limit p_limit) q);
end$$;
create function public.read_order(p_order uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_order(p_order)$$;
create function public.list_order_operations(p_view text,p_after uuid default null,p_limit integer default 25) returns jsonb language sql stable set search_path='' as $$select app_private.list_order_operations(p_view,p_after,p_limit)$$;
revoke all on function public.read_order(uuid),public.list_order_operations(text,uuid,integer) from public,anon;
grant execute on function public.read_order(uuid),public.list_order_operations(text,uuid,integer),app_private.read_order(uuid),app_private.list_order_operations(text,uuid,integer) to authenticated;
create function app_private.discover_order_candidates(p_order uuid,p_unit text,p_units text,p_after_provider uuid default null,p_after_worker uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare o private.service_orders;candidates jsonb;begin
 select * into o from private.service_orders where id=p_order;
 if o.id is null or not app_private.has_permission('dispatch.manage',o.organisation_id) then raise exception 'dispatch permission required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or p_unit is null or length(p_unit) not between 1 and 40 or ((p_after_provider is null)<>(p_after_worker is null)) then raise exception 'bounded resource search and complete keyset cursor required' using errcode='23514';end if;
 select coalesce(jsonb_agg(jsonb_build_object('provider_id',q.provider_id,'worker_id',q.worker_id,'units',p_units) order by q.provider_id,q.worker_id),'[]') into candidates from (
 select distinct p.id provider_id,w.worker_id from private.provider_profiles p join private.provider_capacity capacity on capacity.provider_id=p.id and capacity.status='active' and capacity.unit=p_unit
 cross join lateral (select p.individual_profile_id worker_id where p.individual_profile_id is not null union select profile_id from private.provider_personnel where provider_id=p.id and personnel_role in ('executing_worker','field_agent') and revoked_at is null) w
 where p.status='active' and exists(select 1 from private.provider_coverage_areas c where c.provider_id=p.id and c.service_version_id=o.service_version_id and c.zone_id=o.zone_id and c.revoked_at is null)
 and (app_private.has_permission('providers.read',p.organisation_id) or app_private.has_permission('providers.capacity.manage',p.organisation_id))
 and (p_after_provider is null or (p.id,w.worker_id)>(p_after_provider,p_after_worker)) order by p.id,w.worker_id limit p_limit) q;
 if jsonb_array_length(candidates)=0 then return '[]';end if;
 return app_private.match_order(o.id,candidates);
end$$;
create function public.discover_order_candidates(p_order uuid,p_unit text,p_units text,p_after_provider uuid default null,p_after_worker uuid default null,p_limit integer default 50) returns jsonb
language sql set search_path='' as $$select app_private.discover_order_candidates(p_order,p_unit,p_units,p_after_provider,p_after_worker,p_limit)$$;
create function app_private.read_order_policy(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not (app_private.has_permission('orders.policy.manage') or app_private.has_permission('orders.policy.approve')) then raise exception 'global policy read permission required' using errcode='42501';end if;
 return (select to_jsonb(p)||jsonb_build_object('performance_weight',performance_weight::text,'workload_weight',workload_weight::text) from private.order_policies p where id=p_id);
end$$;
create function public.read_order_policy(p_id uuid) returns jsonb language sql stable set search_path='' as $$select app_private.read_order_policy(p_id)$$;
revoke all on function public.discover_order_candidates(uuid,text,text,uuid,uuid,integer),public.read_order_policy(uuid) from public,anon;
grant execute on function public.discover_order_candidates(uuid,text,text,uuid,uuid,integer),app_private.discover_order_candidates(uuid,text,text,uuid,uuid,integer),public.read_order_policy(uuid),app_private.read_order_policy(uuid) to authenticated;
-- Terms and evidence decisions are retained; service-role maintenance cannot rewrite final evidence accidentally.
create function app_private.order_record_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'order records retained' using errcode='55000';end if;
 if tg_table_name='service_orders' then
 if (to_jsonb(new)-array['status','revision','starts_at','ends_at','policy_id','released_by','released_revision','updated_at']) is distinct from (to_jsonb(old)-array['status','revision','starts_at','ends_at','policy_id','released_by','released_revision','updated_at']) then raise exception 'order ownership and source immutable' using errcode='55000';end if;
 elsif old.status<>'pending' or (to_jsonb(new)-array['status','decided_by','decided_at','updated_at']) is distinct from (to_jsonb(old)-array['status','decided_by','decided_at','updated_at']) then raise exception 'order decision content immutable' using errcode='55000';end if;
 return new;
end$$;
create trigger order_scope_immutable before update or delete on private.service_orders for each row execute function app_private.order_record_guard();
create trigger order_authorization_immutable before update or delete on private.order_authorizations for each row execute function app_private.order_record_guard();
create trigger order_change_immutable before update or delete on private.order_changes for each row execute function app_private.order_record_guard();
-- Carry typed order provenance through the existing service-only worker response.
do $$declare body text;begin
 select pg_get_functiondef('app_private.operational_event_worker(text,jsonb)'::regprocedure) into body;
 body=replace(body,'''provider_id'',e.provider_id,','''provider_id'',e.provider_id,''order_id'',e.order_id,');
 execute body;
end$$;
-- Expiry workers use system provenance, never a fabricated employee identity.
alter table private.operational_event_deliveries alter column created_by drop not null,
 add column system_generated boolean not null default false,
 add constraint event_delivery_creator check(created_by is not null or system_generated);
create function app_private.expire_dispatch_offers(p_limit integer) returns integer
language plpgsql security definer set search_path='' as $$declare o private.service_orders;expired integer=0;ev uuid;correlation uuid;begin
 if auth.role() is distinct from 'service_role' then raise exception 'server expiry worker only' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'bounded expiry batch required' using errcode='23514';end if;
 for o in select orders.* from private.service_orders orders where orders.status='awaiting_dispatch' and exists(select 1 from private.dispatch_proposals p where p.order_id=orders.id and p.status in ('pending','ready') and p.expires_at<=clock_timestamp()) order by orders.id limit p_limit for update skip locked loop
 perform app_private.clear_order_dispatch(o.id,'Offer expired by system sweep','expired');correlation=gen_random_uuid();
 insert into private.order_history(order_id,order_revision,action,subject_id,previous_state,new_state,order_snapshot,reason,permission_code,actor_type,correlation_id)
 values(o.id,o.revision,'dispatch_expire',o.id,o.status,o.status,to_jsonb(o),'Offer expired by system sweep','system.dispatch.expire','system_worker',correlation);
 insert into private.operational_events(order_id,event_code,subject_id,correlation_id) values(o.id,'order.dispatch_expire',o.id,correlation) returning id into ev;
 insert into private.operational_event_deliveries(event_id,system_generated) values(ev,true);expired=expired+1;
 end loop;return expired;
end$$;
create function public.expire_dispatch_offers(p_limit integer) returns integer language sql set search_path='' as $$select app_private.expire_dispatch_offers(p_limit)$$;
revoke all on function public.expire_dispatch_offers(integer),app_private.expire_dispatch_offers(integer) from public,anon,authenticated;
grant execute on function public.expire_dispatch_offers(integer),app_private.expire_dispatch_offers(integer) to service_role;
create index orders_queue on private.service_orders(status,starts_at,id);
create index orders_account on private.service_orders(customer_account_id,created_at,id);
create index order_history_page on private.order_history(order_id,created_at desc,id);
create index dispatch_candidate_rank on private.dispatch_candidates(order_id,order_revision,score desc,provider_id,worker_id);
create index dispatch_offer_expiry on private.dispatch_proposals(expires_at) where status in ('pending','ready');
create index offer_provider_page on private.assignment_offers(provider_id,status,id);
-- Index every new FK that lacks a leading-column index, including actor references.
do $$declare fk record;cols text;begin
 for fk in select con.conrelid,con.conkey,con.conname,n.nspname,c.relname from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
 where con.contype='f' and n.nspname='private' and c.relname in ('order_policies','service_orders','order_commercial_versions','order_authorizations','order_changes','order_history','dispatch_candidates','dispatch_proposals','assignment_offers','assignment_resources','dispatch_escalations')
 and not exists(select 1 from pg_index i where i.indrelid=c.oid and i.indisvalid and i.indkey::smallint[] @> con.conkey and i.indkey[0]=con.conkey[1]) loop
 select string_agg(quote_ident(a.attname),',' order by s.pos) into cols from unnest(fk.conkey) with ordinality s(attnum,pos) join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=s.attnum;
 execute format('create index %I on %I.%I(%s)','ord_fk_'||left(fk.relname,20)||'_'||substr(md5(fk.relname||':'||fk.conname),1,16),fk.nspname,fk.relname,cols);
 end loop;
end$$;
commit;
