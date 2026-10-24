begin;
create function app_private.guard_released_configuration() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status in ('approved','active','retired') then
    if tg_op='DELETE' then raise exception 'retain released configuration' using errcode='55000'; end if;
    if old.status='retired' or new.status<>'retired' or
      (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then
      raise exception 'released configuration is immutable; create a new version' using errcode='55000';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger onit_configuration_guard before update or delete on private.approval_policies
for each row execute function app_private.guard_released_configuration();
create trigger onit_configuration_guard before update or delete on private.system_configurations
for each row execute function app_private.guard_released_configuration();
create trigger onit_configuration_guard before update or delete on private.service_rate_cards
for each row execute function app_private.guard_released_configuration();

create function app_private.guard_rate_card_child() returns trigger
language plpgsql set search_path = '' as $$
declare v_old uuid; v_new uuid; v_status text;
begin
  if tg_op<>'INSERT' then v_old=old.rate_card_id; end if;
  if tg_op<>'DELETE' then v_new=new.rate_card_id; end if;
  for v_status in select status from private.service_rate_cards where id in (v_old,v_new) order by id for update loop
    if v_status<>'draft' then raise exception 'approved rate card lines are immutable' using errcode='55000'; end if;
  end loop;
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger onit_rate_card_child before insert or update or delete on private.service_pricing_rules
for each row execute function app_private.guard_rate_card_child();
do $$ declare t text; begin
  foreach t in array array['approval_policies','system_configurations','service_rate_cards','service_pricing_rules'] loop
    execute format('create trigger onit_no_truncate before truncate on private.%I for each statement execute function app_private.reject_mutation()',t);
  end loop;
  foreach t in array array['corporate_account_users','approval_policies','approval_requests','approval_steps','document_objects','system_configurations'] loop
    execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
  end loop;
end $$;
commit;
