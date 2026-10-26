begin;
insert into private.permissions(code,description) values
 ('pricing.manage','Prepare scoped versioned service pricing'),('pricing.approve','Independently approve scoped pricing'),
 ('assessments.manage','Schedule scoped internal assessments'),('assessments.perform','Complete assigned assessments'),
 ('assessments.approve','Independently approve scoped assessments'),
 ('quotes.override.request','Request an evidenced price override'),('quotes.override.approve','Independently approve price overrides') on conflict(code) do nothing;
alter table public.corporate_account_branches add constraint branch_account_pricing_key unique(id,customer_account_id);
alter table private.approval_policies
 add column approval_side text not null default 'internal' check(approval_side in ('internal','customer')),
 add column customer_account_id uuid references public.corporate_accounts(id) on delete restrict,
 add column branch_id uuid,
 add constraint policy_branch_account_fk foreign key(branch_id,customer_account_id) references public.corporate_account_branches(id,customer_account_id) on delete restrict,
 add constraint policy_customer_organisation_fk foreign key(customer_account_id,organisation_id) references public.corporate_accounts(id,organisation_id) on delete restrict,
 add constraint policy_branch_requires_account check(branch_id is null or customer_account_id is not null),
 add constraint policy_account_requires_organisation check(customer_account_id is null or organisation_id is not null),
 add constraint policy_customer_requires_account check(approval_side<>'customer' or (customer_account_id is not null and organisation_id is not null and approval_type='quotation'));
alter table private.service_rate_cards
 add column variant_id uuid,
 add column customer_account_id uuid references public.corporate_accounts(id) on delete restrict,
 add column branch_id uuid,
 add column contract_reference text check(length(contract_reference) between 1 and 160),
 add column minimum_service_charge numeric(20,4) not null default 0 check(minimum_service_charge>=0),
 add column discount_percent numeric(9,6) not null default 0 check(discount_percent between 0 and 100),
 add column minimum_tax_rule_id uuid references private.quotation_tax_rules(id) on delete restrict,
 add column approval_policy_id uuid references private.approval_policies(id) on delete restrict,
 add column approved_by uuid references public.profiles(id) on delete restrict,
 add constraint rate_variant_fk foreign key(variant_id,service_version_id) references public.service_variants(id,service_version_id) on delete restrict,
 add constraint rate_branch_account_fk foreign key(branch_id,customer_account_id) references public.corporate_account_branches(id,customer_account_id) on delete restrict,
 add constraint rate_branch_requires_account check(branch_id is null or customer_account_id is not null),
 add constraint negotiated_rate_requires_contract check(customer_account_id is null or (contract_reference is not null and valid_until is not null));
alter table private.service_pricing_rules
 add column description text not null default 'Service charge' check(length(description) between 1 and 1000),
 add column charge_kind text not null default 'service' check(charge_kind in ('service','labour','materials','logistics','other')),
 add column option_value_id uuid,
 add column internal_unit_cost numeric(20,4) check(internal_unit_cost>=0),
 add column minimum_charge numeric(20,4) not null default 0 check(minimum_charge>=0),
 add column tax_rule_id uuid references private.quotation_tax_rules(id) on delete restrict,
 add constraint pricing_option_value_fk foreign key(option_value_id,service_version_id) references public.service_option_values(id,service_version_id) on delete restrict;

-- Widen exact monetary precision without rewriting historical values or firing
-- row updates. Existing quotations retain their original two-decimal scale.
alter table public.quotation_versions add column money_scale integer not null default 2 check(money_scale between 0 and 4);
alter table public.quotation_versions alter column subtotal type numeric(20,4),alter column discount_total type numeric(20,4),alter column tax_total type numeric(20,4),alter column total type numeric(20,4);
alter table public.quotation_versions add constraint quotation_scale_key unique(id,money_scale);
alter table public.quotation_line_items add column money_scale integer not null default 2 check(money_scale between 0 and 4);
alter table public.quotation_line_items alter column discount type numeric(20,4),alter column gross type numeric(20,4),alter column tax type numeric(20,4),alter column total type numeric(20,4);
-- Replace only the two Increment 1 arithmetic checks containing round(...,2).
do $$ declare c record; v_count integer=0; begin
 for c in select conname from pg_constraint where conrelid='public.quotation_line_items'::regclass and contype='c'
 and pg_get_constraintdef(oid) like '%round(%' loop
  execute format('alter table public.quotation_line_items drop constraint %I',c.conname); v_count=v_count+1;
 end loop;
 if v_count<>2 then raise exception 'Unexpected quotation arithmetic baseline'; end if;
end $$;
alter table public.quotation_line_items
 add constraint quotation_line_gross_precision check(gross=round(quantity*unit_price,money_scale)),
 add constraint quotation_line_tax_precision check(tax=round((gross-discount)*tax_rate/100,money_scale)),
 add constraint quotation_line_discount_precision check(discount=round(discount,money_scale)),
 add constraint quotation_line_scale_fk foreign key(quotation_version_id,money_scale) references public.quotation_versions(id,money_scale) on delete restrict;

create function app_private.rate_card_scope(p_id uuid) returns uuid
language sql stable set search_path='' as $$ select c.organisation_id from private.service_rate_cards r left join public.customer_profiles c on c.id=r.customer_account_id where r.id=p_id; $$;
create function app_private.guard_pricing_approval() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.status='approved' and old.status='draft' then
  if new.created_by is null or new.approved_by is null or new.created_by=new.approved_by or new.approved_by is distinct from auth.uid()
   or not app_private.has_permission('pricing.approve',app_private.rate_card_scope(new.id)) then raise exception 'independent pricing approver required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.service_version_id::text||new.currency_id::text,0));
  if exists(select 1 from private.service_rate_cards r where r.id<>new.id and r.status='approved'
   and r.service_version_id=new.service_version_id and r.currency_id=new.currency_id
   and r.zone_id is not distinct from new.zone_id and r.variant_id is not distinct from new.variant_id
   and r.customer_account_id is not distinct from new.customer_account_id and r.branch_id is not distinct from new.branch_id
   and tstzrange(r.valid_from,r.valid_until,'[)') && tstzrange(new.valid_from,new.valid_until,'[)')) then raise exception 'overlapping approved pricing scope' using errcode='23514'; end if;
  if not exists(select 1 from private.service_pricing_rules where rate_card_id=new.id) then raise exception 'pricing rules required' using errcode='23514'; end if;
  if (select count(*) from private.service_pricing_rules where rate_card_id=new.id and rule_type='assessment_quote')>1 then raise exception 'one custom scope rule per card is supported' using errcode='23514';end if;
  if new.approval_policy_id is not null and not exists(select 1 from private.approval_policies p where p.id=new.approval_policy_id and p.status='active'
   and p.approval_type='quotation' and p.approval_side='internal' and (p.currency_id is null or p.currency_id=new.currency_id)
   and (p.organisation_id is null or p.organisation_id=app_private.rate_card_scope(new.id))
   and (p.customer_account_id is null or p.customer_account_id=new.customer_account_id)
   and (p.branch_id is null or p.branch_id=new.branch_id)) then raise exception 'invalid quotation approval policy' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger onit_pricing_approval before update on private.service_rate_cards for each row execute function app_private.guard_pricing_approval();

create function app_private.create_pricing_card(p_config jsonb,p_rules jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_org uuid; item jsonb; k text;
begin
 if jsonb_typeof(p_config) is distinct from 'object' or jsonb_typeof(p_rules) is distinct from 'array' or octet_length(p_rules::text)>131072 then raise exception 'invalid pricing configuration' using errcode='23514'; end if;
 if jsonb_array_length(p_rules) not between 1 and 100 then raise exception 'invalid pricing rules' using errcode='23514'; end if;
 if octet_length(p_config::text)>16384 or exists(select 1 from jsonb_object_keys(p_config) x where x not in ('service_version_id','currency_id','code','version','valid_from','valid_until','zone_id','variant_id','customer_account_id','branch_id','contract_reference','minimum_service_charge','discount_percent','minimum_tax_rule_id','approval_policy_id')) then raise exception 'unknown pricing configuration key' using errcode='23514'; end if;
 foreach k in array array['minimum_service_charge','discount_percent'] loop
  if p_config ? k and (jsonb_typeof(p_config->k) is distinct from 'string' or (p_config->>k) !~ '^\d{1,16}(\.\d{1,4})?$') then raise exception 'exact finite configuration decimal required' using errcode='23514'; end if;
 end loop;
 select organisation_id into v_org from public.customer_profiles where id=(p_config->>'customer_account_id')::uuid;
 if not app_private.has_permission('pricing.manage',v_org) then raise exception 'pricing manager required' using errcode='42501'; end if;
 insert into private.service_rate_cards(service_version_id,currency_id,code,version,valid_from,valid_until,zone_id,variant_id,customer_account_id,branch_id,contract_reference,minimum_service_charge,discount_percent,minimum_tax_rule_id,approval_policy_id,created_by)
 values((p_config->>'service_version_id')::uuid,(p_config->>'currency_id')::uuid,p_config->>'code',(p_config->>'version')::integer,
 (p_config->>'valid_from')::timestamptz,(p_config->>'valid_until')::timestamptz,(p_config->>'zone_id')::uuid,(p_config->>'variant_id')::uuid,
 (p_config->>'customer_account_id')::uuid,(p_config->>'branch_id')::uuid,p_config->>'contract_reference',coalesce((p_config->>'minimum_service_charge')::numeric,0),
 coalesce((p_config->>'discount_percent')::numeric,0),(p_config->>'minimum_tax_rule_id')::uuid,(p_config->>'approval_policy_id')::uuid,auth.uid()) returning id into v_id;
 for item in select value from jsonb_array_elements(p_rules) loop
  if jsonb_typeof(item) is distinct from 'object' or exists(select 1 from jsonb_object_keys(item) x where x not in ('code','rule_type','unit_amount','minimum_quantity','unit_name','description','charge_kind','option_value_id','internal_unit_cost','minimum_charge','tax_rule_id')) then raise exception 'unknown pricing rule key' using errcode='23514'; end if;
  foreach k in array array['unit_amount','minimum_quantity','internal_unit_cost','minimum_charge'] loop
   if item ? k and item->k<>'null'::jsonb and (jsonb_typeof(item->k) is distinct from 'string' or (item->>k) !~ '^\d{1,16}(\.\d{1,4})?$') then raise exception 'exact finite rule decimal required' using errcode='23514'; end if;
  end loop;
  insert into private.service_pricing_rules(rate_card_id,service_version_id,currency_id,code,rule_type,unit_amount,minimum_quantity,unit_name,description,charge_kind,option_value_id,internal_unit_cost,minimum_charge,tax_rule_id,created_by)
  values(v_id,(p_config->>'service_version_id')::uuid,(p_config->>'currency_id')::uuid,item->>'code',item->>'rule_type',(item->>'unit_amount')::numeric,
  (item->>'minimum_quantity')::numeric,item->>'unit_name',item->>'description',coalesce(item->>'charge_kind','service'),(item->>'option_value_id')::uuid,
  (item->>'internal_unit_cost')::numeric,coalesce((item->>'minimum_charge')::numeric,0),(item->>'tax_rule_id')::uuid,auth.uid());
 end loop;
 return v_id;
end $$;
create function app_private.approve_pricing_card(p_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from private.service_rate_cards where id=p_id and status='draft' for update;
 if not found then raise exception 'draft pricing card required' using errcode='23514'; end if;
 update private.service_rate_cards set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_id;
 return p_id;
end $$;
create function public.create_pricing_card(p_config jsonb,p_rules jsonb) returns uuid language sql set search_path='' as $$ select app_private.create_pricing_card(p_config,p_rules); $$;
create function public.approve_pricing_card(p_id uuid) returns uuid language sql set search_path='' as $$ select app_private.approve_pricing_card(p_id); $$;
grant execute on function public.create_pricing_card(jsonb,jsonb),app_private.create_pricing_card(jsonb,jsonb),public.approve_pricing_card(uuid),app_private.approve_pricing_card(uuid) to authenticated;
create index rate_card_account_scope on private.service_rate_cards(customer_account_id,branch_id,service_version_id);
create index rate_card_effective_lookup on private.service_rate_cards(service_version_id,currency_id,valid_from) where status='approved';
create function app_private.commercial_policy(p_action text,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare p private.approval_policies;v_org uuid;v_id uuid;
begin
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'policy object required' using errcode='23514'; end if;
 if p_action='create' then
  if p_data->>'customer_account_id' is not null then
   select organisation_id into v_org from public.corporate_accounts where id=(p_data->>'customer_account_id')::uuid;
   if not found then raise exception 'corporate account required' using errcode='23514'; end if;
  else v_org=(p_data->>'organisation_id')::uuid; end if;
  if not app_private.has_permission('pricing.manage',v_org) then raise exception 'pricing manager required' using errcode='42501'; end if;
  if (p_data->>'minimum_approvers')::integer not between 1 and 20 or p_data->>'minimum_approvers' is null then raise exception 'invalid approval count' using errcode='23514'; end if;
  if p_data->>'threshold_amount' is not null and (jsonb_typeof(p_data->'threshold_amount')<>'string' or (p_data->>'threshold_amount') !~ '^\d{1,16}(\.\d{1,4})?$') then raise exception 'exact threshold required' using errcode='23514'; end if;
  insert into private.approval_policies(code,version,organisation_id,approval_type,minimum_approvers,threshold_amount,currency_id,approval_side,customer_account_id,branch_id,created_by)
   values(p_data->>'code',(p_data->>'version')::integer,v_org,'quotation',(p_data->>'minimum_approvers')::integer,(p_data->>'threshold_amount')::numeric,
   (p_data->>'currency_id')::uuid,coalesce(p_data->>'approval_side','internal'),(p_data->>'customer_account_id')::uuid,(p_data->>'branch_id')::uuid,auth.uid()) returning id into v_id;
 elsif p_action='approve' then
  select * into p from private.approval_policies where id=(p_data->>'id')::uuid and approval_type='quotation' for update;
  if not found or not app_private.has_permission('pricing.approve',p.organisation_id) or p.created_by is null or p.created_by=auth.uid() then raise exception 'independent policy approver required' using errcode='42501'; end if;
  if p.status<>'draft' then raise exception 'draft policy required' using errcode='23514'; end if;
  update private.approval_policies set status='active' where id=p.id;v_id=p.id;
 else raise exception 'invalid policy action' using errcode='23514'; end if;
 return v_id;
end $$;
create function public.commercial_policy(p_action text,p_data jsonb) returns uuid language sql set search_path='' as $$ select app_private.commercial_policy(p_action,p_data); $$;
grant execute on function public.commercial_policy(text,jsonb),app_private.commercial_policy(text,jsonb) to authenticated;
create function app_private.read_pricing_card(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c private.service_rate_cards;
begin
 select * into c from private.service_rate_cards where id=p_id;
 if c.id is null or not (app_private.has_permission('pricing.manage',app_private.rate_card_scope(p_id)) or app_private.has_permission('pricing.approve',app_private.rate_card_scope(p_id))) then raise exception 'pricing access denied' using errcode='42501'; end if;
 return (to_jsonb(c)-array['minimum_service_charge','discount_percent'])||jsonb_build_object('minimum_service_charge',c.minimum_service_charge::text,'discount_percent',c.discount_percent::text,
 'rules',(select jsonb_agg((to_jsonb(r)-array['unit_amount','internal_unit_cost','minimum_quantity','minimum_charge'])||jsonb_build_object('unit_amount',r.unit_amount::text,'internal_unit_cost',r.internal_unit_cost::text,'minimum_quantity',r.minimum_quantity::text,'minimum_charge',r.minimum_charge::text) order by r.code) from private.service_pricing_rules r where r.rate_card_id=c.id));
end $$;
create function public.read_pricing_card(p_id uuid) returns jsonb language sql stable set search_path='' as $$ select app_private.read_pricing_card(p_id); $$;
grant execute on function public.read_pricing_card(uuid),app_private.read_pricing_card(uuid) to authenticated;
create function app_private.retire_pricing_card(p_id uuid,p_reason text,p_key text) returns uuid
language plpgsql security definer set search_path='' as $$
declare c private.service_rate_cards;prior private.transaction_commands;payload jsonb;
begin
 select * into c from private.service_rate_cards where id=p_id for update;
 if not found or not app_private.has_permission('pricing.approve',app_private.rate_card_scope(p_id)) or c.created_by=auth.uid() then raise exception 'independent pricing approver required' using errcode='42501'; end if;
 if p_reason is null or length(trim(p_reason)) not between 1 and 1000 or p_key is null or length(p_key) not between 8 and 128 then raise exception 'reason and idempotency key required' using errcode='23514';end if;
 payload=jsonb_build_object('card',p_id,'reason',p_reason);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':retire_price:'||p_key,0));
 select * into prior from private.transaction_commands where actor_id=auth.uid() and command='retire_price' and idempotency_key=p_key;
 if found then
  if prior.payload<>payload then raise exception 'idempotency payload conflict' using errcode='23505';end if;return prior.result_id;
 end if;
 if c.status<>'approved' then raise exception 'approved card required' using errcode='23514';end if;
 update private.service_rate_cards set status='retired' where id=p_id;
 insert into private.transaction_commands(actor_id,command,idempotency_key,payload,result_id) values(auth.uid(),'retire_price',p_key,payload,p_id);
 return p_id;
end $$;
create function public.retire_pricing_card(p_id uuid,p_reason text,p_key text) returns uuid language sql set search_path='' as $$ select app_private.retire_pricing_card(p_id,p_reason,p_key); $$;
grant execute on function public.retire_pricing_card(uuid,text,text),app_private.retire_pricing_card(uuid,text,text) to authenticated;
commit;
