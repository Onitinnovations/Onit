begin;
insert into private.permissions(code,description) values
 ('fulfilment.read','Read scoped execution operations'),('fulfilment.manage','Coordinate scoped execution and issues'),
 ('fulfilment.supervise','Verify scoped execution independently'),('fulfilment.qa.perform','Conduct assigned quality inspections'),
 ('fulfilment.qa.approve','Independently decide quality'),('fulfilment.close','Authorise operational closure'),
 ('fulfilment.exceptions.approve','Independently approve operational exceptions'),('fulfilment.cases.sensitive','Investigate confidential cases'),
 ('fulfilment.policy.manage','Prepare global execution configuration'),('fulfilment.policy.approve','Independently publish execution configuration') on conflict(code) do nothing;
-- Version existing checklist definitions instead of creating another form registry.
alter table public.service_checklists add column version integer not null default 1 check(version>0),
 add column publication_status text not null default 'draft' check(publication_status in ('draft','published','retired')),
 add column published_by uuid references public.profiles(id) on delete restrict,
 add column published_at timestamptz;
alter table public.service_checklists disable trigger onit_version_child_guard;
alter table public.service_checklists disable trigger onit_updated_at;
update public.service_checklists c set publication_status='published',published_at=v.published_at from public.service_versions v where v.id=c.service_version_id and v.status<>'draft';
alter table public.service_checklists enable trigger onit_updated_at;
alter table public.service_checklists enable trigger onit_version_child_guard;
alter table public.service_checklists drop constraint service_checklists_service_version_id_code_key,
 add unique(service_version_id,code,version);
create unique index assessment_checklist_code on public.service_checklists(service_version_id,code) where checklist_type='assessment';
alter table public.service_checklist_items add column field_type text not null default 'boolean' check(field_type in ('boolean','text','number','single_choice','multiple_choice')),
 add column choices jsonb not null default '[]' check(jsonb_typeof(choices)='array' and jsonb_array_length(choices)<=100),
 add column validation jsonb not null default '{}' check(jsonb_typeof(validation)='object'),
 add column condition jsonb,add column evidence_required boolean not null default false;
create function app_private.guard_execution_checklist() returns trigger language plpgsql set search_path='' as $$
declare c public.service_checklists;vid uuid;begin
 if tg_table_name='service_checklists' then c=case when tg_op='DELETE' then old else new end;
 else select * into c from public.service_checklists where id=case when tg_op='DELETE' then old.checklist_id else new.checklist_id end;end if;
 if c.checklist_type='assessment' then
 vid=c.service_version_id;
 if exists(select 1 from public.service_versions where id=vid and status<>'draft') then raise exception 'released assessment checklist immutable' using errcode='55000';end if;
 elsif tg_table_name='service_checklists' then
 if tg_op='DELETE' or (tg_op='UPDATE' and old.publication_status<>'draft' and not(old.publication_status='published' and new.publication_status='retired' and (to_jsonb(new)-array['publication_status','updated_at'])=(to_jsonb(old)-array['publication_status','updated_at']))) then raise exception 'published checklist immutable' using errcode='55000';end if;
 elsif c.publication_status<>'draft' then raise exception 'published checklist fields immutable' using errcode='55000';end if;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
drop trigger onit_version_child_guard on public.service_checklists;
drop trigger onit_version_child_guard on public.service_checklist_items;
create trigger onit_execution_definition before insert or update or delete on public.service_checklists for each row execute function app_private.guard_execution_checklist();
create trigger onit_execution_definition before insert or update or delete on public.service_checklist_items for each row execute function app_private.guard_execution_checklist();
create table private.fulfilment_policies (
 id uuid primary key default gen_random_uuid(),service_version_id uuid not null references public.service_versions(id) on delete restrict,
 customer_account_id uuid references public.customer_profiles(id) on delete restrict,contract_reference text,version integer not null check(version>0),
 valid_from timestamptz not null,valid_until timestamptz,status text not null default 'draft' check(status in ('draft','approved','retired')),
 configuration jsonb not null check(jsonb_typeof(configuration)='object' and octet_length(configuration::text)<=65536),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 check(valid_until is null or valid_until>valid_from),check(contract_reference is null or customer_account_id is not null),
 check(approved_by is null or approved_by<>created_by),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.work_orders (
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('WO-'||upper(replace(gen_random_uuid()::text,'-',''))),
 order_id uuid not null,customer_account_id uuid not null,proposal_id uuid not null references private.dispatch_proposals(id) on delete restrict,
 policy_id uuid not null references private.fulfilment_policies(id) on delete restrict,code text not null check(length(code) between 1 and 80),
 scope_snapshot jsonb not null,instructions text not null default '' check(length(instructions)<=8000),
 supervisor_id uuid not null references public.profiles(id) on delete restrict,owner_id uuid not null references public.profiles(id) on delete restrict,
 priority text not null check(priority in ('normal','urgent','critical')),status text not null default 'awaiting_mobilisation',revision integer not null default 1 check(revision>0),
 starts_at timestamptz not null,ends_at timestamptz not null,completed_at timestamptz,closed_at timestamptz,
 foreign key(order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 check(ends_at>starts_at),unique(order_id,code),unique(id,order_id,customer_account_id),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.work_tasks (
 id uuid primary key default gen_random_uuid(),work_order_id uuid not null,order_id uuid not null,customer_account_id uuid not null,
 parent_task_id uuid,resource_id uuid not null references private.assignment_resources(id) on delete restrict,
 code text not null,description text not null check(length(description) between 1 and 4000),mandatory boolean not null default true,
 status text not null default 'awaiting_mobilisation',revision integer not null default 1 check(revision>0),accepted_at timestamptz,
 starts_at timestamptz not null,ends_at timestamptz not null,actual_start timestamptz,actual_finish timestamptz,
 supervisor_verified_by uuid references public.profiles(id) on delete restrict,completion_actor uuid references public.profiles(id) on delete restrict,
 foreign key(work_order_id,order_id,customer_account_id) references private.work_orders(id,order_id,customer_account_id) on delete restrict,
 unique(work_order_id,code),unique(id,work_order_id),unique(id,work_order_id,order_id,customer_account_id),
 foreign key(parent_task_id,work_order_id) references private.work_tasks(id,work_order_id) on delete restrict,
 check(parent_task_id is null or parent_task_id<>id),check(ends_at>starts_at),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.task_dependencies (
 id uuid primary key default gen_random_uuid(),task_id uuid not null,depends_on_id uuid not null,work_order_id uuid not null,
 foreign key(task_id,work_order_id) references private.work_tasks(id,work_order_id) on delete restrict,
 foreign key(depends_on_id,work_order_id) references private.work_tasks(id,work_order_id) on delete restrict,
 check(task_id<>depends_on_id),unique(task_id,depends_on_id),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now()
);
create table private.execution_history (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,
 work_order_id uuid references private.work_orders(id) on delete restrict,task_id uuid references private.work_tasks(id) on delete restrict,
 action text not null,subject_id uuid not null,previous_state text,new_state text,revision integer,details jsonb not null default '{}',
 reason text not null check(length(reason) between 1 and 2000),actor_id uuid references public.profiles(id) on delete restrict,
 actor_type text not null default 'user' check(actor_type in ('user','system_worker')),check((actor_id is null)=(actor_type='system_worker')),
 permission_code text not null,correlation_id uuid not null default gen_random_uuid(),created_at timestamptz not null default clock_timestamp()
);
create table private.execution_attendance (
 id uuid primary key default gen_random_uuid(),task_id uuid not null references private.work_tasks(id) on delete restrict,
 worker_id uuid not null references public.profiles(id) on delete restrict,
 kind text not null check(kind in ('mobilisation','departure','arrival','check_in','check_out','no_show','late','missed_appointment','access_problem','interruption','discrepancy','supervisor_acknowledgement')),
 occurred_at timestamptz not null,declared_latitude numeric(9,6),declared_longitude numeric(9,6),
 verifies_id uuid references private.execution_attendance(id) on delete restrict,
 check(num_nonnulls(declared_latitude,declared_longitude) in (0,2)),check(declared_latitude between -90 and 90),check(declared_longitude between -180 and 180),
 reason text not null,created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now()
);
create table private.execution_evidence (
 id uuid primary key default gen_random_uuid(),task_id uuid not null,work_order_id uuid not null,order_id uuid not null,customer_account_id uuid not null,
 document_id uuid not null,classification text not null check(length(classification) between 1 and 60),task_revision integer not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),reviewed_by uuid references public.profiles(id) on delete restrict,reviewed_at timestamptz,review_reason text,
 foreign key(task_id,work_order_id,order_id,customer_account_id) references private.work_tasks(id,work_order_id,order_id,customer_account_id) on delete restrict,
 foreign key(document_id,customer_account_id) references private.document_objects(id,customer_account_id) on delete restrict,
 check(reviewed_by is null or reviewed_by<>created_by),unique(task_id,document_id),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.execution_submissions (
 id uuid primary key default gen_random_uuid(),task_id uuid not null references private.work_tasks(id) on delete restrict,
 checklist_id uuid not null references public.service_checklists(id) on delete restrict,phase text not null check(phase in ('execution','quality','handover')),
 version integer not null check(version>0),answers jsonb not null,definition_snapshot jsonb not null,task_revision integer not null,
 status text not null default 'draft' check(status in ('draft','submitted','approved','rejected')),
 reviewed_by uuid references public.profiles(id) on delete restrict,review_reason text,
 unique(task_id,phase,version),check(reviewed_by is null or reviewed_by<>created_by),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.quality_inspections (
 id uuid primary key default gen_random_uuid(),task_id uuid not null references private.work_tasks(id) on delete restrict,version integer not null check(version>0),
 inspector_id uuid not null references public.profiles(id) on delete restrict,scheduled_at timestamptz not null,
 status text not null default 'requested' check(status in ('requested','submitted','approved','rejected','conditional')),
 submission_id uuid references private.execution_submissions(id) on delete restrict,decided_by uuid references public.profiles(id) on delete restrict,
 decision_reason text,unique(task_id,version),check(decided_by is null or (decided_by<>inspector_id and decided_by<>created_by)),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.quality_findings (
 id uuid primary key default gen_random_uuid(),inspection_id uuid not null references private.quality_inspections(id) on delete restrict,
 code text not null,severity text not null check(severity in ('minor','major','critical')),description text not null,corrective_action text not null,
 blocking boolean not null,created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now()
);
create table private.rework_requests (
 id uuid primary key default gen_random_uuid(),finding_id uuid not null references private.quality_findings(id) on delete restrict,
 original_task_id uuid not null references private.work_tasks(id) on delete restrict,rework_task_id uuid not null unique references private.work_tasks(id) on delete restrict,
 due_at timestamptz not null,status text not null default 'active' check(status in ('active','accepted','cancelled')),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index one_unresolved_defect_rework on private.rework_requests(finding_id) where status='active';
create table private.service_cases (
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('CASE-'||upper(replace(gen_random_uuid()::text,'-',''))),
 order_id uuid not null,customer_account_id uuid not null,work_order_id uuid,task_id uuid,
 provider_id uuid references private.provider_profiles(id) on delete restrict,category text not null,severity text not null check(severity in ('minor','major','critical')),
 priority text not null check(priority in ('normal','urgent','critical')),confidential boolean not null default false,blocking boolean not null default true,
 status text not null default 'open' check(status in ('open','acknowledged','investigating','escalated','resolution_proposed','resolved','closed')),
 revision integer not null default 1,owner_id uuid references public.profiles(id) on delete restrict,
 description text not null,resolution_requirements jsonb,resolution_proposed_by uuid references public.profiles(id) on delete restrict,
 resolved_by uuid references public.profiles(id) on delete restrict,
 foreign key(order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 foreign key(work_order_id,order_id,customer_account_id) references private.work_orders(id,order_id,customer_account_id) on delete restrict,
 foreign key(task_id,work_order_id,order_id,customer_account_id) references private.work_tasks(id,work_order_id,order_id,customer_account_id) on delete restrict,
 check(task_id is null or work_order_id is not null),
 created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.service_case_entries (
 id uuid primary key default gen_random_uuid(),case_id uuid not null references private.service_cases(id) on delete restrict,
 kind text not null check(kind in ('evidence','investigation','finding','corrective_action','communication','escalation','resolution','reopen','note')),
 document_id uuid references private.document_objects(id) on delete restrict,visibility text not null check(visibility in ('internal','customer')),
 content text not null,created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now()
);
create table private.customer_confirmations (
 id uuid primary key default gen_random_uuid(),work_order_id uuid not null references private.work_orders(id) on delete restrict,
 work_revision integer not null,decision text not null check(decision in ('confirmed','disputed')),document_id uuid references private.document_objects(id) on delete restrict,
 comment text not null default '',created_by uuid not null references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),unique(work_order_id,work_revision)
);
create table private.operational_exceptions (
 id uuid primary key default gen_random_uuid(),work_order_id uuid not null references private.work_orders(id) on delete restrict,work_revision integer not null,
 kind text not null check(kind in ('substitution','sla_extension','partial_completion','closure_without_confirmation','cancel_work')),
 proposal jsonb not null,status text not null default 'pending' check(status in ('pending','approved','rejected','consumed')),
 decided_by uuid references public.profiles(id) on delete restrict,reason text not null,valid_until timestamptz not null,
 check(decided_by is null or decided_by<>created_by),created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.sla_tracks (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references private.service_orders(id) on delete restrict,
 work_order_id uuid references private.work_orders(id) on delete restrict,task_id uuid references private.work_tasks(id) on delete restrict,case_id uuid references private.service_cases(id) on delete restrict,
 target text not null,source_event_id uuid not null references private.execution_history(id) on delete restrict,
 due_at timestamptz not null,status text not null default 'running' check(status in ('running','paused','met','breached')),
 remaining interval,breached_at timestamptz,unique nulls not distinct(source_event_id,target,task_id,case_id),
 created_by uuid references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.customer_feedback add column order_id uuid,add column work_order_id uuid,add column revision integer,add column previous_id uuid references public.customer_feedback(id) on delete restrict,
 add foreign key(order_id,customer_account_id) references private.service_orders(id,customer_account_id) on delete restrict,
 add foreign key(work_order_id,order_id,customer_account_id) references private.work_orders(id,order_id,customer_account_id) on delete restrict,
 add constraint feedback_execution_revision check((order_id is null and work_order_id is null and revision is null) or (order_id is not null and work_order_id is not null and revision>0)),add unique(work_order_id,revision);
alter table private.provider_performance_events alter column document_id drop not null,add column source_event_id uuid references private.execution_history(id) on delete restrict,
 add constraint performance_evidence_source check(document_id is not null or source_event_id is not null),add unique(provider_id,metric,source_event_id);
do $$declare t text;begin foreach t in array array['fulfilment_policies','work_orders','work_tasks','task_dependencies','execution_history','execution_attendance','execution_evidence','execution_submissions','quality_inspections','quality_findings','rework_requests','service_cases','service_case_entries','customer_confirmations','operational_exceptions','sla_tracks'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);execute format('grant all on private.%I to service_role',t);
 execute format('create trigger onit_audit after insert or update or delete on private.%I for each row execute function app_private.audit_access_change()',t);
 if t not in ('execution_history') then execute format('create index %I on private.%I(created_by)',t||'_creator_idx',t);end if;
 if t in ('fulfilment_policies','work_orders','work_tasks','execution_evidence','execution_submissions','quality_inspections','rework_requests','service_cases','operational_exceptions','sla_tracks') then execute format('create trigger onit_updated_at before update on private.%I for each row execute function app_private.touch_updated_at()',t);else execute format('create trigger onit_immutable before update or delete on private.%I for each row execute function app_private.reject_mutation()',t);end if;
 end loop;end$$;
commit;
