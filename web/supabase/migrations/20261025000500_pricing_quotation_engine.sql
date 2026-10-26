begin;
create table private.quotation_commercial_context (
 id uuid primary key references public.quotation_versions(id) on delete restrict,
 rate_card_id uuid references private.service_rate_cards(id) on delete restrict,
 assessment_id uuid references private.site_assessments(id) on delete restrict,
 internal_policy_id uuid references private.approval_policies(id) on delete restrict,
 customer_policy_id uuid references private.approval_policies(id) on delete restrict,
 internal_required integer not null check(internal_required between 1 and 20),customer_required integer not null check(customer_required between 1 and 20),
 internal_cost_estimate numeric(20,4) not null check(internal_cost_estimate>=0),
 internal_cost_complete boolean not null default false,
 override_requested boolean not null default false,override_reason text,
 pricing_snapshot jsonb not null check(jsonb_typeof(pricing_snapshot)='object'),
 created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id) on delete restrict,
 check(not override_requested or length(trim(override_reason)) between 1 and 2000)
);
create table private.quotation_approval_votes (
 id uuid primary key default gen_random_uuid(),quotation_version_id uuid not null references public.quotation_versions(id) on delete restrict,
 side text not null check(side in ('internal','customer')),created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),unique(quotation_version_id,side,created_by)
);
create function app_private.store_quotation(p_request uuid,p_currency uuid,p_valid_until timestamptz,p_terms text,p_lines jsonb,p_key text,p_context jsonb) returns uuid
language plpgsql set search_path='' as $$
declare r public.service_requests; v_id uuid; q uuid; v_rev integer; item jsonb; pos integer=0; scale integer;
 qty numeric; price numeric; disc numeric; gross numeric; tax numeric; rate numeric; tax_id uuid; label text; country uuid;
 payload jsonb; prior private.transaction_commands; policy private.approval_policies; ip uuid; cp uuid; need_i integer=1; need_c integer=1; amount numeric;
begin
 select * into r from public.service_requests where id=p_request for update;
 if not found or not app_private.has_permission('quotes.manage',r.organisation_id) then raise exception 'quotation manager required' using errcode='42501'; end if;
 if p_key is null or length(p_key) not between 8 and 128 then raise exception 'invalid idempotency key' using errcode='23514'; end if;
 payload=jsonb_build_object('request',p_request,'currency',p_currency,'until',p_valid_until,'terms',p_terms,'lines',p_lines,'context',p_context);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':quote:'||p_key,0));
 select * into prior from private.transaction_commands where actor_id=auth.uid() and command='prepare_quote' and idempotency_key=p_key;
 if found then
  if prior.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505'; end if; return prior.result_id;
 end if;
 if r.status<>'reviewed' then raise exception 'reviewed request required' using errcode='23514'; end if;
 if p_valid_until is null or p_valid_until<=now() or p_valid_until>now()+interval '1 year' or jsonb_typeof(p_lines) is distinct from 'array' or octet_length(p_lines::text)>131072 then raise exception 'invalid quote input' using errcode='23514'; end if;
 if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'invalid line count' using errcode='23514'; end if;
 select cu.minor_units into scale from public.customer_profiles c join public.currencies cu on cu.id=c.currency_id where c.id=r.customer_account_id and cu.id=p_currency and cu.status='active';
 if not found then raise exception 'account currency mismatch' using errcode='23514'; end if;
 select country_id into country from public.service_locations where id=r.service_location_id;
 insert into public.quotations(request_id,created_by) values(r.id,auth.uid()) on conflict(request_id) do nothing;
 select id into q from public.quotations where request_id=r.id for update;
 if exists(select 1 from public.quotation_versions where quotation_id=q and status='accepted') then raise exception 'accepted quotation immutable' using errcode='55000'; end if;
 insert into private.quotation_decisions(quotation_version_id,decision,created_by) select id,'superseded',auth.uid() from public.quotation_versions where quotation_id=q and status in ('draft','offered');
 update public.quotation_versions set status='superseded' where quotation_id=q and status in ('draft','offered');
 select coalesce(max(version),0)+1 into v_rev from public.quotation_versions where quotation_id=q;
 insert into public.quotation_versions(quotation_id,version,request_revision,currency_id,pricing_mode,valid_until,terms,subtotal,discount_total,tax_total,total,money_scale,created_by)
 select q,v_rev,r.revision,p_currency,s.pricing_mode,p_valid_until,p_terms,0,0,0,0,scale,auth.uid() from public.service_versions s where s.id=r.service_version_id returning id into v_id;
 for item in select value from jsonb_array_elements(p_lines) loop
  if jsonb_typeof(item) is distinct from 'object' or exists(select 1 from jsonb_object_keys(item) k where k not in ('description','kind','quantity','unit_price','discount','tax_rule_id')) then raise exception 'invalid line keys' using errcode='23514'; end if;
  if jsonb_typeof(item->'quantity') is distinct from 'string' or jsonb_typeof(item->'unit_price') is distinct from 'string'
   or (item->>'quantity') !~ '^\d{1,10}(\.\d{1,4})?$' or (item->>'unit_price') !~ '^\d{1,12}(\.\d{1,4})?$'
   or (item ? 'discount' and (jsonb_typeof(item->'discount') is distinct from 'string' or (item->>'discount') !~ '^\d{1,16}(\.\d{1,4})?$')) then raise exception 'exact decimal strings required' using errcode='23514'; end if;
  qty=(item->>'quantity')::numeric;price=(item->>'unit_price')::numeric;disc=coalesce((item->>'discount')::numeric,0);
  if disc<>round(disc,scale) then raise exception 'discount exceeds currency precision' using errcode='23514'; end if;
  gross=round(qty*price,scale);rate=0;label=null;tax_id=null;
  if item->>'tax_rule_id' is not null then
   select t.id,t.code,t.rate into tax_id,label,rate from private.quotation_tax_rules t where t.id::text=item->>'tax_rule_id'
    and t.country_id=country and t.status='active' and t.valid_from<=now() and (t.valid_until is null or t.valid_until>now()) for share;
   if not found then raise exception 'tax configuration unavailable' using errcode='23514'; end if;
  end if;
  tax=round((gross-disc)*rate/100,scale);
  insert into public.quotation_line_items(quotation_version_id,position,description,kind,quantity,unit_price,discount,tax_rule_id,tax_label,tax_rate,gross,tax,total,money_scale,created_by)
  values(v_id,pos,item->>'description',item->>'kind',qty,price,disc,tax_id,label,rate,gross,tax,gross-disc+tax,scale,auth.uid());pos=pos+1;
 end loop;
 update public.quotation_versions set subtotal=t.gross,discount_total=t.discount,tax_total=t.tax,total=t.total from
 (select sum(li.gross) gross,sum(li.discount) discount,sum(li.tax) tax,sum(li.total) total from public.quotation_line_items li where li.quotation_version_id=v_id) t where id=v_id;
 select total into amount from public.quotation_versions where id=v_id;
 if p_context->>'internal_policy_id' is not null then
  select * into strict policy from private.approval_policies where id=(p_context->>'internal_policy_id')::uuid and status='active' and approval_type='quotation' and approval_side='internal';
  ip=policy.id;
  if policy.threshold_amount is null or amount>=policy.threshold_amount then need_i=policy.minimum_approvers; end if;
 end if;
 -- An explicitly selected card policy cannot weaken a stronger applicable
 -- company/account threshold. Retain the strongest applicable requirement.
 select * into policy from private.approval_policies p where p.approval_type='quotation' and p.approval_side='internal' and p.status='active'
  and (p.organisation_id is null or p.organisation_id=r.organisation_id) and (p.customer_account_id is null or p.customer_account_id=r.customer_account_id)
  and (p.branch_id is null or p.branch_id=r.branch_id) and (p.currency_id is null or p.currency_id=p_currency)
  and (p.threshold_amount is null or p.threshold_amount<=amount) order by p.minimum_approvers desc,p.id limit 1;
 if found and policy.minimum_approvers>need_i then ip=policy.id;need_i=policy.minimum_approvers;end if;
 -- Strongest applicable customer count, then branch/threshold specificity.
 -- A weaker branch policy cannot cause a permanently unreleasable proposal.
 select * into policy from private.approval_policies p where p.approval_type='quotation' and p.approval_side='customer' and p.status='active'
  and p.customer_account_id=r.customer_account_id and (p.branch_id is null or p.branch_id=r.branch_id)
  and (p.currency_id is null or p.currency_id=p_currency) and (p.threshold_amount is null or p.threshold_amount<=amount)
 order by p.minimum_approvers desc,(p.branch_id is not null) desc,p.threshold_amount desc nulls last,p.id limit 1;
 if found then
  if (select count(*) from private.approval_policies x where x.approval_type='quotation' and x.approval_side='customer' and x.status='active' and x.customer_account_id=r.customer_account_id
   and x.branch_id is not distinct from policy.branch_id and x.threshold_amount is not distinct from policy.threshold_amount and (x.currency_id is null or x.currency_id=p_currency))>1 then raise exception 'ambiguous corporate approval policy' using errcode='23514'; end if;
  cp=policy.id;need_c=policy.minimum_approvers;
 end if;
 insert into private.quotation_commercial_context(id,rate_card_id,assessment_id,internal_policy_id,customer_policy_id,internal_required,customer_required,internal_cost_estimate,internal_cost_complete,override_requested,override_reason,pricing_snapshot,created_by)
 values(v_id,(p_context->>'rate_card_id')::uuid,(p_context->>'assessment_id')::uuid,ip,cp,need_i,need_c,coalesce((p_context->>'internal_cost')::numeric,0),coalesce((p_context->>'internal_cost_complete')::boolean,false),
 coalesce((p_context->>'override')::boolean,false),p_context->>'override_reason',p_context,auth.uid());
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'prepare_quote',p_key,payload,v_id);
 insert into private.audit_logs(actor_id,action,subject_schema,subject_table,subject_id) values(auth.uid(),'quote_prepared','public','quotation_versions',v_id);
 return v_id;
end $$;

create or replace function app_private.prepare_quotation(p_request uuid,p_currency uuid,p_valid_until timestamptz,p_terms text,p_lines jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; mode text; a uuid;prior private.transaction_commands;payload jsonb;
begin
 select * into r from public.service_requests where id=p_request for update;
 if not found or not app_private.has_permission('quotes.manage',r.organisation_id) then raise exception 'quotation manager required' using errcode='42501'; end if;
 if p_key is null or length(p_key) not between 8 and 128 then raise exception 'invalid idempotency key' using errcode='23514'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':quote:'||p_key,0));
 select * into prior from private.transaction_commands where actor_id=auth.uid() and command='prepare_quote' and idempotency_key=p_key;
 if found then
  payload=jsonb_build_object('request',p_request,'currency',p_currency,'until',p_valid_until,'terms',p_terms,'lines',p_lines);
  if prior.payload-'context'<>payload or coalesce(prior.payload->'context'->>'source','manual')<>'manual' then raise exception 'idempotency payload conflict' using errcode='23505'; end if;
  return prior.result_id;
 end if;
 select pricing_mode into mode from public.service_versions where id=r.service_version_id;
 if mode not in ('custom_quotation','assessment_based') then raise exception 'configured pricing workflow required' using errcode='23514'; end if;
 if exists(select 1 from private.service_rate_cards c where c.service_version_id=r.service_version_id and (c.customer_account_id is null or c.customer_account_id=r.customer_account_id) and c.status='approved' and c.valid_from<=now() and (c.valid_until is null or c.valid_until>now())) then raise exception 'approved pricing configuration workflow required' using errcode='23514'; end if;
 select id into a from private.site_assessments where request_id=r.id and request_revision=r.revision and status='approved' order by revision desc limit 1;
 return app_private.store_quotation(p_request,p_currency,p_valid_until,p_terms,p_lines,p_key,jsonb_build_object('source','manual','assessment_id',a));
end $$;

create function app_private.generate_quotation(p_request uuid,p_input jsonb,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.service_requests; c private.service_rate_cards; rule private.service_pricing_rules; a private.site_assessments;
 zone uuid; variant uuid; currency uuid; city uuid; state uuid; score integer; v_count integer; scale integer;
 lines jsonb='[]'; line jsonb; qty numeric; price numeric; gross numeric; disc numeric; net numeric=0; costs numeric=0; minimum numeric; overrides jsonb; options jsonb; measurements jsonb;
overridden boolean=false; mode text; policy_id uuid;prior private.transaction_commands;cost_complete boolean=true;manual_net numeric;
begin
 select * into r from public.service_requests where id=p_request for update;
 if not found or not app_private.has_permission('quotes.manage',r.organisation_id) then raise exception 'quotation manager required' using errcode='42501'; end if;
 if jsonb_typeof(p_input) is distinct from 'object' or octet_length(p_input::text)>131072 then raise exception 'invalid pricing input' using errcode='23514'; end if;
 if p_key is null or length(p_key) not between 8 and 128 then raise exception 'invalid idempotency key' using errcode='23514'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':quote:'||p_key,0));
 select * into prior from private.transaction_commands where actor_id=auth.uid() and command='prepare_quote' and idempotency_key=p_key;
 if found then
  if prior.payload->'request'<>to_jsonb(p_request) or prior.payload->'context'->>'source'<>'configured' or prior.payload->'context'->'selections' is distinct from p_input then raise exception 'idempotency payload conflict' using errcode='23505'; end if;
  return prior.result_id;
 end if;
 zone=(p_input->>'zone_id')::uuid;variant=(p_input->>'variant_id')::uuid;
 select c1.currency_id,cu.minor_units into currency,scale from public.customer_profiles c1 join public.currencies cu on cu.id=c1.currency_id where c1.id=r.customer_account_id;
 select l.city_id,l.state_id into city,state from public.service_locations l where l.id=r.service_location_id;
 if zone is not null and not exists(select 1 from public.service_zones z join private.zone_boundaries_or_coverage b on b.zone_id=z.id
  where z.id=zone and z.status='active' and z.state_id=state and b.city_id=city and b.verified_at is not null
  and b.version=(select max(x.version) from private.zone_boundaries_or_coverage x where x.zone_id=z.id)) then raise exception 'verified zone/city coverage required' using errcode='23514'; end if;
 if zone is null and exists(select 1 from private.service_rate_cards rc join private.zone_boundaries_or_coverage cov on cov.zone_id=rc.zone_id
  where rc.service_version_id=r.service_version_id and rc.currency_id=currency and rc.variant_id is not distinct from variant and rc.approved_by is not null and rc.status='approved' and rc.valid_from<=now() and (rc.valid_until is null or rc.valid_until>now()) and cov.city_id=city and cov.verified_at is not null
  and cov.version=(select max(x.version) from private.zone_boundaries_or_coverage x where x.zone_id=rc.zone_id)
  and (rc.customer_account_id is null or rc.customer_account_id=r.customer_account_id) and (rc.branch_id is null or rc.branch_id=r.branch_id)) then raise exception 'explicit service zone required' using errcode='23514'; end if;
 if variant is not null and not exists(select 1 from public.service_variants where id=variant and service_version_id=r.service_version_id) then raise exception 'package/version mismatch' using errcode='23514'; end if;
 -- Deterministic specificity; overlapping scopes are prevented at approval.
 select card.* into c from private.service_rate_cards card where card.service_version_id=r.service_version_id and card.currency_id=currency
  and card.status='approved' and card.approved_by is not null and card.valid_from<=now() and (card.valid_until is null or card.valid_until>now())
  and (card.zone_id is null or card.zone_id=zone) and card.variant_id is not distinct from variant
  and (card.customer_account_id is null or card.customer_account_id=r.customer_account_id) and (card.branch_id is null or card.branch_id=r.branch_id)
 order by ((card.customer_account_id is not null)::integer*16+(card.branch_id is not null)::integer*8+(card.zone_id is not null)::integer*4) desc limit 1 for share;
 if not found then raise exception 'approved effective pricing unavailable' using errcode='23514'; end if;
 score=(c.customer_account_id is not null)::integer*16+(c.branch_id is not null)::integer*8+(c.zone_id is not null)::integer*4;
 select count(*) into v_count from private.service_rate_cards card where card.service_version_id=r.service_version_id and card.currency_id=currency
  and card.status='approved' and card.approved_by is not null and card.valid_from<=now() and (card.valid_until is null or card.valid_until>now())
  and (card.zone_id is null or card.zone_id=zone) and card.variant_id is not distinct from variant
  and (card.customer_account_id is null or card.customer_account_id=r.customer_account_id) and (card.branch_id is null or card.branch_id=r.branch_id)
  and ((card.customer_account_id is not null)::integer*16+(card.branch_id is not null)::integer*8+(card.zone_id is not null)::integer*4)=score;
 if v_count<>1 then raise exception 'ambiguous pricing configuration' using errcode='23514'; end if;
 if c.valid_until is not null and (p_input->>'valid_until')::timestamptz>c.valid_until then raise exception 'quote outlives pricing agreement' using errcode='23514'; end if;
 select pricing_mode into mode from public.service_versions where id=r.service_version_id;
 select * into a from private.site_assessments where request_id=r.id order by revision desc limit 1;
 if (select assessment_required from public.service_versions where id=r.service_version_id) and (a.id is null or a.status<>'approved' or a.request_revision<>r.revision) then raise exception 'approved current assessment required' using errcode='23514'; end if;
 measurements=case when a.status='approved' then a.measurements else coalesce(p_input->'quantities','{}') end;
 if a.status='approved' and p_input ? 'quantities' then raise exception 'assessment measurements are authoritative' using errcode='23514'; end if;
 overrides=coalesce(p_input->'overrides','{}');options=coalesce(p_input->'option_values','[]');
 if jsonb_typeof(measurements)<>'object' or jsonb_typeof(overrides)<>'object' or jsonb_typeof(options)<>'array' then raise exception 'invalid pricing selections' using errcode='23514'; end if;
 if p_input ? 'manual_lines' and not exists(select 1 from private.service_pricing_rules pr where pr.rate_card_id=c.id and pr.rule_type='assessment_quote') then raise exception 'manual lines cannot bypass configured prices' using errcode='23514'; end if;
 if exists(select 1 from jsonb_array_elements_text(options) o where not exists(select 1 from private.service_pricing_rules pr where pr.rate_card_id=c.id and pr.option_value_id::text=o)) then raise exception 'unpriced service option' using errcode='23514'; end if;
 if (select count(*)<>count(distinct o) from jsonb_array_elements_text(options) o) then raise exception 'duplicate option selection' using errcode='23514'; end if;
 if exists(select 1 from public.service_options opt where opt.service_version_id=r.service_version_id and opt.required and not exists(select 1 from public.service_option_values ov where ov.option_id=opt.id and options ? ov.id::text)) then raise exception 'required service option missing' using errcode='23514'; end if;
 if exists(select 1 from jsonb_object_keys(overrides) k where not exists(select 1 from private.service_pricing_rules pr where pr.rate_card_id=c.id and pr.code=k)) then raise exception 'unknown override rule' using errcode='23514'; end if;
 overridden=overrides<>'{}'::jsonb;
 if overridden and (not app_private.has_permission('quotes.override.request',r.organisation_id) or length(trim(coalesce(p_input->>'override_reason','')))=0) then raise exception 'evidenced override permission required' using errcode='42501'; end if;
 for rule in select * from private.service_pricing_rules where rate_card_id=c.id order by code loop
  if rule.option_value_id is not null and not (options ? rule.option_value_id::text) then continue; end if;
  if rule.rule_type='assessment_quote' then
   cost_complete=false;
   if mode not in ('custom_quotation','assessment_based') or jsonb_typeof(p_input->'manual_lines') is distinct from 'array' then raise exception 'scoped manual assessment lines required' using errcode='23514'; end if;
   if jsonb_array_length(p_input->'manual_lines') not between 1 and 100 then raise exception 'bounded nonempty custom scope required' using errcode='23514';end if;
   manual_net=0;
   for line in select value from jsonb_array_elements(p_input->'manual_lines') loop
    gross=round((line->>'quantity')::numeric*(line->>'unit_price')::numeric,scale);disc=round(gross*c.discount_percent/100,scale);
    if line ? 'discount' and (line->>'discount')::numeric is distinct from disc then raise exception 'configured custom discount mismatch' using errcode='23514';end if;
    line=line||jsonb_build_object('discount',disc::text);
    if rule.tax_rule_id is not null then
     if line->>'tax_rule_id' is not null and line->>'tax_rule_id'<>rule.tax_rule_id::text then raise exception 'configured custom tax mismatch' using errcode='23514';end if;
     line=line||jsonb_build_object('tax_rule_id',rule.tax_rule_id);
    end if;
    lines=lines||jsonb_build_array(line);manual_net=manual_net+gross-disc;
   end loop;
   if round(rule.minimum_charge,scale)>manual_net then
    line=jsonb_build_object('description',rule.description||' minimum adjustment','kind',rule.charge_kind,'quantity','1','unit_price',(round(rule.minimum_charge,scale)-manual_net)::text);
    if rule.tax_rule_id is not null then line=line||jsonb_build_object('tax_rule_id',rule.tax_rule_id);end if;
    lines=lines||jsonb_build_array(line);
   end if;
   continue;
  end if;
  if rule.rule_type='fixed' then
   if p_input->'quantities' ? rule.code and p_input->'quantities'->>rule.code<>'1' then raise exception 'fixed charge quantity must be one' using errcode='23514'; end if;
   qty=1;
  else
   if jsonb_typeof(measurements->rule.code) is distinct from 'string' or (measurements->>rule.code) !~ '^\d{1,10}(\.\d{1,4})?$' then raise exception 'configured quantity required' using errcode='23514'; end if;
   qty=(measurements->>rule.code)::numeric;
   if qty<=0 or (rule.minimum_quantity is not null and qty<rule.minimum_quantity) then raise exception 'quantity below configured minimum' using errcode='23514'; end if;
  end if;
  price=rule.unit_amount;
  if overrides ? rule.code then
   if jsonb_typeof(overrides->rule.code) is distinct from 'string' or (overrides->>rule.code) !~ '^\d{1,12}(\.\d{1,4})?$' then raise exception 'exact override amount required' using errcode='23514'; end if;
   price=(overrides->>rule.code)::numeric;
  end if;
  gross=round(qty*price,scale);disc=round(gross*c.discount_percent/100,scale);net=net+gross-disc;
  costs=costs+round(qty*coalesce(rule.internal_unit_cost,0),scale);
  if rule.internal_unit_cost is null then cost_complete=false;end if;
  line=jsonb_build_object('description',rule.description,'kind',rule.charge_kind,'quantity',qty::text,'unit_price',price::text,'discount',disc::text);
  if rule.tax_rule_id is not null then line=line||jsonb_build_object('tax_rule_id',rule.tax_rule_id); end if;
  lines=lines||jsonb_build_array(line);
  minimum=round(rule.minimum_charge,scale);
  if gross-disc<minimum then
   line=jsonb_build_object('description',rule.description||' minimum adjustment','kind',rule.charge_kind,'quantity','1','unit_price',(minimum-gross+disc)::text);
   if rule.tax_rule_id is not null then line=line||jsonb_build_object('tax_rule_id',rule.tax_rule_id); end if;
   lines=lines||jsonb_build_array(line);net=net+minimum-gross+disc;
  end if;
 end loop;
 select coalesce(sum(round((li->>'quantity')::numeric*(li->>'unit_price')::numeric,scale)-coalesce((li->>'discount')::numeric,0)),0) into net from jsonb_array_elements(lines) li;
 if round(c.minimum_service_charge,scale)>net then
  line=jsonb_build_object('description','Minimum service charge adjustment','kind','service','quantity','1','unit_price',(round(c.minimum_service_charge,scale)-net)::text);
  if c.minimum_tax_rule_id is not null then line=line||jsonb_build_object('tax_rule_id',c.minimum_tax_rule_id); end if;
  lines=lines||jsonb_build_array(line);
 end if;
 policy_id=c.approval_policy_id;
 return app_private.store_quotation(r.id,currency,(p_input->>'valid_until')::timestamptz,p_input->>'terms',lines,p_key,
 jsonb_build_object('source','configured','rate_card_id',c.id,'assessment_id',case when a.status='approved' then a.id else null end,'internal_policy_id',policy_id,
  'internal_cost',costs::text,'internal_cost_complete',cost_complete,'override',overridden,'override_reason',p_input->>'override_reason','rate_card',to_jsonb(c),
  'rules',(select jsonb_agg(to_jsonb(pr) order by pr.code) from private.service_pricing_rules pr where pr.rate_card_id=c.id),'selections',p_input));
end $$;

alter function app_private.decide_quotation(uuid,text) rename to decide_quotation_increment1;
revoke all on function app_private.decide_quotation_increment1(uuid,text) from public,anon,authenticated;
create function app_private.decide_quotation(p_id uuid,p_action text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.service_requests; v public.quotation_versions; ctx private.quotation_commercial_context; a private.site_assessments; required integer; v_side text;
begin
 select r1.* into r from public.quotation_versions v1 join public.quotations q on q.id=v1.quotation_id join public.service_requests r1 on r1.id=q.request_id where v1.id=p_id for update of r1;
 select * into v from public.quotation_versions where id=p_id for update;
 if not found or auth.uid() is null then raise exception 'quotation access denied' using errcode='42501'; end if;
 select * into ctx from private.quotation_commercial_context where id=p_id;
 if p_action in ('approve','accept') and v.status not in ('accepted','rejected','expired','superseded') then
  if ctx.rate_card_id is null and exists(select 1 from private.service_rate_cards c where c.service_version_id=r.service_version_id and c.status='approved'
   and c.valid_from<=now() and (c.valid_until is null or c.valid_until>now()) and (c.customer_account_id is null or c.customer_account_id=r.customer_account_id)) then raise exception 'configured pricing snapshot required' using errcode='23514'; end if;
  if (ctx.internal_policy_id is not null and not exists(select 1 from private.approval_policies where id=ctx.internal_policy_id and status='active'))
   or (ctx.customer_policy_id is not null and not exists(select 1 from private.approval_policies where id=ctx.customer_policy_id and status='active')) then raise exception 'quotation policy retired; prepare a new revision' using errcode='23514'; end if;
  if exists(select 1 from private.approval_policies p where p.approval_type='quotation' and p.status='active'
   and (p.organisation_id is null or p.organisation_id=r.organisation_id) and (p.customer_account_id is null or p.customer_account_id=r.customer_account_id)
   and (p.branch_id is null or p.branch_id=r.branch_id) and (p.currency_id is null or p.currency_id=v.currency_id) and (p.threshold_amount is null or p.threshold_amount<=v.total)
   and ((p.approval_side='internal' and p.minimum_approvers>coalesce(ctx.internal_required,1))
    or (p.approval_side='customer' and (p.minimum_approvers>coalesce(ctx.customer_required,1) or ctx.customer_policy_id is null)))) then raise exception 'stronger approval policy requires a new quotation revision' using errcode='23514'; end if;
  if (select assessment_required from public.service_versions where id=r.service_version_id) then
   select * into a from private.site_assessments where request_id=r.id order by revision desc limit 1;
   if a.id is null or a.status<>'approved' or a.request_revision<>r.revision or ctx.assessment_id is distinct from a.id
    or exists(select 1 from private.assessment_evidence e join private.document_objects d on d.id=e.document_object_id where e.assessment_id=a.id and (d.scan_status<>'clean' or d.archived_at is not null)) then raise exception 'approved current assessment snapshot required' using errcode='23514'; end if;
  end if;
  if ctx.rate_card_id is not null and not exists(select 1 from private.service_rate_cards c where c.id=ctx.rate_card_id and c.status='approved' and c.valid_from<=now() and (c.valid_until is null or c.valid_until>now())) then raise exception 'pricing agreement unavailable' using errcode='23514'; end if;
  if p_action='approve' then
   if v.status<>'draft' then return app_private.decide_quotation_increment1(p_id,p_action); end if;
   if not app_private.has_permission('quotes.approve',r.organisation_id) or auth.uid()=v.created_by
    or (ctx.override_requested and not app_private.has_permission('quotes.override.approve',r.organisation_id)) then raise exception 'independent commercial approver required' using errcode='42501'; end if;
   required=coalesce(ctx.internal_required,1);v_side='internal';
  else
   if not app_private.request_access(r.id,'approve') then raise exception 'customer approver required' using errcode='42501'; end if;
   if v.status<>'offered' or v.valid_until<=now() then raise exception 'offered unexpired quotation required' using errcode='23514'; end if;
   if ctx.customer_policy_id is not null and auth.uid()=r.created_by then raise exception 'independent corporate approver required' using errcode='42501'; end if;
   required=coalesce(ctx.customer_required,1);v_side='customer';
  end if;
  if v.valid_until<=now() or r.status<>'reviewed' or r.revision<>v.request_revision then raise exception 'stale quotation' using errcode='23514'; end if;
  insert into private.quotation_approval_votes(quotation_version_id,side,created_by) values(p_id,v_side,auth.uid()) on conflict(quotation_version_id,side,created_by) do nothing;
  if (select count(*) from private.quotation_approval_votes where quotation_version_id=p_id and quotation_approval_votes.side=v_side)<required then return p_id; end if;
 end if;
 return app_private.decide_quotation_increment1(p_id,p_action);
end $$;
grant execute on function app_private.decide_quotation(uuid,text) to authenticated;
-- Rebind/invalidate existing public SQL-function plans after renaming the old
-- implementation, including connections that used it before this upgrade.
create or replace function public.decide_quotation(p_id uuid,p_action text) returns uuid
language sql set search_path='' as $$ select app_private.decide_quotation(p_id,p_action); $$;
create function public.generate_quotation(p_request uuid,p_input jsonb,p_key text) returns uuid language sql set search_path='' as $$ select app_private.generate_quotation(p_request,p_input,p_key); $$;
grant execute on function public.generate_quotation(uuid,jsonb,text),app_private.generate_quotation(uuid,jsonb,text) to authenticated;
do $$ declare t text; begin
 foreach t in array array['quotation_commercial_context','quotation_approval_votes'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  execute format('grant all on private.%I to service_role',t);
  execute format('create trigger onit_immutable before update or delete on private.%I for each row execute function app_private.reject_mutation()',t);
  execute format('create trigger onit_no_truncate before truncate on private.%I for each statement execute function app_private.reject_mutation()',t);
  execute format('create trigger onit_audit after insert on private.%I for each row execute function app_private.audit_access_change()',t);
 end loop;
end $$;
create index quote_context_card on private.quotation_commercial_context(rate_card_id);
create index quote_context_assessment on private.quotation_commercial_context(assessment_id);
create function app_private.read_quotation_commercial(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.service_requests;ctx private.quotation_commercial_context;
begin
 select r1.* into r from public.quotation_versions v join public.quotations q on q.id=v.quotation_id join public.service_requests r1 on r1.id=q.request_id where v.id=p_id;
 if r.id is null or not (app_private.has_permission('quotes.manage',r.organisation_id) or app_private.has_permission('quotes.approve',r.organisation_id)) then raise exception 'commercial access denied' using errcode='42501'; end if;
 select * into ctx from private.quotation_commercial_context where id=p_id;
 return jsonb_build_object('quotation_version_id',p_id,'rate_card_id',ctx.rate_card_id,'assessment_id',ctx.assessment_id,'internal_cost_estimate',ctx.internal_cost_estimate::text,
  'internal_cost_complete',ctx.internal_cost_complete,
  'internal_required',ctx.internal_required,'customer_required',ctx.customer_required,'override_requested',ctx.override_requested,'override_reason',ctx.override_reason,
  'votes',(select jsonb_agg(jsonb_build_object('side',v.side,'actor_id',v.created_by,'created_at',v.created_at)) from private.quotation_approval_votes v where v.quotation_version_id=p_id));
end $$;
create function public.read_quotation_commercial(p_id uuid) returns jsonb language sql stable set search_path='' as $$ select app_private.read_quotation_commercial(p_id); $$;
grant execute on function public.read_quotation_commercial(uuid),app_private.read_quotation_commercial(uuid) to authenticated;
-- Canonical currency presentation; unit prices/quantities retain their four-place
-- contractual precision while rounded totals use the snapshotted minor units.
create or replace function app_private.read_quotation(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not app_private.quote_access(p_id) then raise exception 'quotation access denied' using errcode='42501'; end if;
 select jsonb_build_object('id',v.id,'quotation_id',v.quotation_id,'version',v.version,'currency',c.code,'money_scale',v.money_scale,
 'pricing_mode',v.pricing_mode,'status',v.status,'valid_until',v.valid_until,'terms',v.terms,
 'subtotal',round(v.subtotal,v.money_scale)::text,'discount_total',round(v.discount_total,v.money_scale)::text,'tax_total',round(v.tax_total,v.money_scale)::text,'total',round(v.total,v.money_scale)::text,
 'lines',(select jsonb_agg(jsonb_build_object('position',li.position,'description',li.description,'kind',li.kind,'quantity',li.quantity::text,'unit_price',li.unit_price::text,
 'discount',round(li.discount,v.money_scale)::text,'tax_label',li.tax_label,'tax_rate',li.tax_rate::text,'gross',round(li.gross,v.money_scale)::text,'tax',round(li.tax,v.money_scale)::text,'total',round(li.total,v.money_scale)::text) order by li.position)
 from public.quotation_line_items li where li.quotation_version_id=v.id)) into result from public.quotation_versions v join public.currencies c on c.id=v.currency_id where v.id=p_id;
 return result;
end $$;
do $$ declare fk record;cols text;begin
 for fk in select con.conrelid,con.conkey,con.conname,n.nspname,c.relname from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
 where con.contype='f' and n.nspname='private' and c.relname in ('site_assessments','assessment_evidence','quotation_commercial_context','quotation_approval_votes','service_rate_cards','service_pricing_rules','approval_policies')
 and not exists(select 1 from pg_index i where i.indrelid=c.oid and i.indisvalid and i.indpred is null and array(select k from unnest(i.indkey::smallint[]) with ordinality x(k,pos) where pos<=cardinality(con.conkey) order by pos)=con.conkey)
 loop
 select string_agg(quote_ident(a.attname),',' order by u.pos) into cols from unnest(fk.conkey) with ordinality u(num,pos) join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=u.num;
 execute format('create index %I on %I.%I(%s)','onit_price_fk_'||substr(md5(fk.relname||fk.conname),1,24),fk.nspname,fk.relname,cols);
 end loop;
end $$;
commit;
