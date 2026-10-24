begin;
alter table private.approval_policies drop constraint approval_policies_approval_type_check;
alter table private.approval_policies add constraint approval_policies_approval_type_check
  check(approval_type in ('quotation','expense','payroll','payout','procurement','project_variation','credit_terms'));
alter table private.corporate_credit_terms add constraint credit_terms_approval_target_key unique(approval_request_id);
create function app_private.validate_credit_terms_approval() returns trigger
language plpgsql set search_path = '' as $$
declare v_request private.approval_requests%rowtype; v_policy private.approval_policies%rowtype;
begin
  if new.status='approved' then
    select * into v_request from private.approval_requests where id=new.approval_request_id for update;
    select * into v_policy from private.approval_policies where id=v_request.policy_id for update;
    if v_request.id is null or v_request.status<>'approved' or v_request.requested_by<>new.created_by
      or v_policy.approval_type<>'credit_terms' or v_policy.status<>'active'
      or (select count(*) from private.approval_steps s where s.request_id=v_request.id and s.decision='approved')<v_policy.minimum_approvers
      or exists(select 1 from private.approval_steps s where s.request_id=v_request.id and s.decision='rejected')
      or not exists(select 1 from private.approval_steps s where s.request_id=v_request.id and s.decided_by=new.approved_by and s.decision='approved') then
      raise exception 'credit configuration requires an independently approved typed request' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger onit_credit_approval before insert or update on private.corporate_credit_terms
for each row execute function app_private.validate_credit_terms_approval();
-- Configuration approval only: no credit limit, invoice balance or spending command.
commit;
