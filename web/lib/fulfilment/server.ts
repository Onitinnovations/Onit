import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.fulfilment.generated';

export type ExecutionState = 'awaiting_mobilisation' | 'mobilising' | 'en_route' | 'arrived' | 'awaiting_customer_access' | 'started' | 'in_progress' | 'paused' | 'awaiting_materials' | 'awaiting_customer_decision' | 'work_completed';
export type WorkState = ExecutionState | 'awaiting_capacity' | 'awaiting_qa' | 'qa_rejected' | 'rework_required' | 'qa_approved' | 'awaiting_customer_confirmation' | 'customer_disputed' | 'completed' | 'closed' | 'cancelled' | 'suspended';
type ChecklistPhase = 'execution' | 'quality' | 'handover';
type TaskInput = { task_id: string; task_revision: number };
export type FulfilmentMutation =
  | { action: 'create_task'; data: { resource_id: string; code: string; description: string; start: string; end: string; mandatory: boolean; is_container?: boolean; parent_task_id?: string } }
  | { action: 'operational_note'; data: { note: string } }
  | { action: 'revise_work'; data: { owner_id: string; priority: 'normal' | 'urgent' | 'critical'; instructions: string } }
  | { action: 'dependency'; data: TaskInput & { depends_on_id: string } }
  | { action: 'accept_task' | 'supervisor_verify' | 'complete_container'; data: TaskInput }
  | { action: 'progress'; data: TaskInput & { state: Exclude<ExecutionState, 'awaiting_mobilisation'> } }
  | { action: 'attendance'; data: TaskInput & { kind: 'mobilisation' | 'departure' | 'arrival' | 'check_in' | 'check_out' | 'no_show' | 'late' | 'missed_appointment' | 'access_problem' | 'interruption' | 'discrepancy' | 'supervisor_acknowledgement'; occurred_at: string; latitude?: string; longitude?: string; verifies_id?: string } }
  | { action: 'save_checklist'; data: TaskInput & { phase: ChecklistPhase; answers: Record<string, Json> } }
  | { action: 'submit_checklist'; data: TaskInput & { id: string } }
  | { action: 'review_checklist'; data: TaskInput & { id: string; approve: boolean } }
  | { action: 'prepare_upload'; data: TaskInput & { classification: string; content_type: 'image/jpeg' | 'image/png' | 'image/webp' | 'application/pdf' | 'video/mp4' | 'video/webm' | 'text/plain'; byte_size: number; retained_until?: string } }
  | { action: 'attach_evidence'; data: TaskInput & { classification: string; document_id: string } }
  | { action: 'review_evidence'; data: TaskInput & { id: string; approve: boolean; customer_visible?: boolean } }
  | { action: 'supervisor_assign'; data: { profile_id: string } }
  | { action: 'suspend' | 'resume'; data?: never }
  | { action: 'request_exception'; data: { kind: 'substitution' | 'sla_extension' | 'partial_completion' | 'closure_without_confirmation' | 'cancel_work'; proposal: Json; valid_until: string } }
  | { action: 'decide_exception'; data: { id: string; approve: boolean } }
  | { action: 'substitute' | 'task_reassign' | 'task_cancel' | 'transfer_rework'; data: TaskInput & { exception_id: string } }
  | { action: 'cancel_work' | 'retire_for_reschedule' | 'apply_sla_exception'; data: { exception_id: string } }
  | { action: 'customer_confirm'; data: { decision: 'confirmed' | 'disputed'; comment?: string; document_id?: string } }
  | { action: 'feedback'; data: { rating: 1 | 2 | 3 | 4 | 5; comment: string } }
  | { action: 'close_work'; data?: { exception_id?: string } };
export type QualityMutation =
  | { action: 'request'; data: { task_id: string; inspector_id: string; scheduled_at: string } }
  | { action: 'submit'; data: { id: string; submission_id: string; findings: { code: string; severity: 'minor' | 'major' | 'critical'; description: string; corrective_action: string; blocking: boolean }[] } }
  | { action: 'decide'; data: { id: string; decision: 'approved' | 'rejected' | 'conditional' } };
export type CaseMutation =
  | { action: 'report'; data: { work_order_id?: string; task_id?: string; provider_id?: string; category: string; severity: 'minor' | 'major' | 'critical'; priority: 'normal' | 'urgent' | 'critical'; confidential?: boolean; description: string } }
  | { action: 'assign_owner'; data: { id: string; profile_id: string } }
  | { action: 'acknowledge' | 'investigate' | 'escalate' | 'close' | 'reopen'; data: { id: string } }
  | { action: 'entry'; data: { id: string; kind: 'evidence' | 'investigation' | 'finding' | 'corrective_action' | 'communication' | 'escalation' | 'note'; visibility: 'internal' | 'customer'; content: string; document_id?: string } }
  | { action: 'propose_resolution'; data: { id: string; requirements: Record<string, Json> } }
  | { action: 'resolve'; data: { id: string; provider_responsible?: boolean } };
export type ChecklistField = { key: string; label: string; type: 'boolean' | 'text' | 'number' | 'single_choice' | 'multiple_choice'; required: boolean; evidence_required?: boolean; choices?: string[]; validation?: Record<string, Json>; condition?: { field: string; operator: string; value: Json } };
export type ExecutionPolicy = { service_version_id: string; customer_account_id?: string; contract_reference?: string; version: number; valid_from: string; valid_until?: string; configuration: { transitions: [ExecutionState, ExecutionState][]; evidence: string[]; case_categories: string[]; pause_states: ExecutionState[]; execution_checklist: string; quality_checklist: string; handover_checklist: string; allow_conditional_qa: boolean; allow_partial_completion: boolean; allow_closure_exception: boolean; sla: Record<'mobilisation' | 'arrival' | 'start' | 'task_completion' | 'quality_review' | 'rework' | 'case_acknowledgement' | 'case_resolution' | 'customer_response', number> } };
export type ExecutionConfiguration =
  | { action: 'prepare_checklist'; data: { service_version_id: string; code: string; version: number; type: 'execution' | 'quality'; name: string; fields: ChecklistField[] } }
  | { action: 'publish_checklist'; data: { id: string } }
  | { action: 'prepare_policy'; data: ExecutionPolicy }
  | { action: 'approve_policy' | 'retire_policy'; data: { id: string } };
export type WorkProjection = { id: string; reference: string; order_id: string; revision: number; plan_revision: number; status: WorkState | 'quality_review' | 'under_review'; start: string; end: string; scope?: Json; instructions?: string; priority?: 'normal' | 'urgent' | 'critical'; owner_id?: string; supervisor_id?: string; policy_id?: string; exceptions?: Json[]; evidence?: Json[]; tasks?: { id: string; revision: number; status: WorkState; execution_round: number; resource_id: string; description: string; start: string; end: string; checklists: Json[]; evidence: Json[]; attendance: Json[] }[]; confirmations?: Json[]; feedback?: Json[]; quality?: Json[]; findings?: Json[]; rework?: Json[]; slas?: Json[]; history?: Json[] };
export type CaseProjection = { id: string; reference: string; order_id: string; revision: number; status: string; description: string; severity: string; entries: Json[] };
export type ExecutionView = 'scheduled' | 'active' | 'supervision' | 'quality' | 'rework' | 'customer_confirmation' | 'completed' | 'closed' | 'delayed' | 'complaints' | 'incidents' | 'sla_breaches' | 'performance';
export class FulfilmentError extends Error {
  constructor(public readonly code: 'unauthenticated' | 'forbidden' | 'invalid_input' | 'conflict' | 'unavailable', message: string) { super(message); this.name = 'FulfilmentError'; }
}
const uuid = (value: string) => { if (!/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value)) throw new FulfilmentError('invalid_input', 'A valid ID is required.'); return value; };
const revision = (value: number) => { if (!Number.isSafeInteger(value) || value < 1) throw new FulfilmentError('invalid_input', 'A positive expected revision is required.'); return value; };
function payload(value: object, reason: string, key: string): Json {
  if (!reason?.trim() || reason.length > 2000 || !key || key.length < 8 || key.length > 128) throw new FulfilmentError('invalid_input', 'A bounded reason and idempotency key are required.');
  const input = { ...value, reason };
  if (new TextEncoder().encode(JSON.stringify(input)).length > 65536) throw new FulfilmentError('invalid_input', 'The operation is too large.');
  return input as Json;
}
function result<T>(response: { data: T | null; error: { code?: string } | null }): T {
  if (response.error) {
    const code = response.error.code ?? '';
    if (code === '42501') throw new FulfilmentError('forbidden', 'You are not authorised for this operation.');
    if (['23505', '40001', '40P01', '55000'].includes(code)) throw new FulfilmentError('conflict', 'The record changed or cannot change in its current state.');
    if (code.startsWith('22') || ['23514', '23503', '23502'].includes(code)) throw new FulfilmentError('invalid_input', 'The operation does not satisfy the business rules.');
    throw new FulfilmentError('unavailable', 'The operation could not be completed.');
  }
  if (response.data === null) throw new FulfilmentError('unavailable', 'The record is unavailable.');
  return response.data;
}
/** Caller-JWT boundary. Privileged SLA processing deliberately has no ordinary-user adapter. */
export function fulfilmentOperations(accessToken: string) {
  if (!accessToken || accessToken.length > 16384 || /\s/.test(accessToken)) throw new FulfilmentError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new FulfilmentError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<Database>(url, key, { global: { headers: { Authorization: `Bearer ${accessToken}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  async function authenticate() { const response = await client.auth.getUser(accessToken); if (response.error || !response.data.user) throw new FulfilmentError('unauthenticated', 'A valid session is required.'); }
  return {
    async create(orderId: string, input: { proposal_id: string; code: string; supervisor_id: string; owner_id: string; priority: 'normal' | 'urgent' | 'critical'; instructions: string }, reason: string, idempotencyKey: string) {
      const value = payload(input, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('create_work_order', { p_order: uuid(orderId), p_data: value, p_key: idempotencyKey }));
    },
    async change(workId: string, expectedRevision: number, input: FulfilmentMutation, reason: string, idempotencyKey: string) {
      const value = payload({ ...input.data, expected_revision: revision(expectedRevision) }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('fulfilment_command', { p_work: uuid(workId), p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async quality(workId: string, expectedRevision: number, input: QualityMutation, reason: string, idempotencyKey: string) {
      const value = payload({ ...input.data, expected_revision: revision(expectedRevision) }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('quality_command', { p_work: uuid(workId), p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async case(orderId: string, expectedRevision: number | null, input: CaseMutation, reason: string, idempotencyKey: string) {
      const value = payload({ ...input.data, ...(expectedRevision === null ? {} : { expected_revision: revision(expectedRevision) }) }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('execution_case_command', { p_order: uuid(orderId), p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async configure(input: ExecutionConfiguration, reason: string, idempotencyKey: string) {
      const value = payload(input.data, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('fulfilment_configuration', { p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async read(workId: string): Promise<WorkProjection> { await authenticate(); return result(await client.rpc('read_work_order', { p_work: uuid(workId) })) as unknown as WorkProjection; },
    async readCase(caseId: string): Promise<CaseProjection> { await authenticate(); return result(await client.rpc('read_service_case', { p_case: uuid(caseId) })) as unknown as CaseProjection; },
    async readConfiguration(id: string): Promise<Json> { await authenticate(); return result(await client.rpc('read_fulfilment_configuration', { p_id: uuid(id) })); },
    async documentReference(evidenceId: string): Promise<{ id: string; bucket: string; object_name: string; scan_status: string; content_type: string; byte_size: string; upload_expires_at: string | null }> { await authenticate(); return result(await client.rpc('execution_document_reference', { p_evidence: uuid(evidenceId) })) as unknown as { id: string; bucket: string; object_name: string; scan_status: string; content_type: string; byte_size: string; upload_expires_at: string | null };  },
    async list(view: ExecutionView, filters: { from?: string; until?: string; zone_id?: string; city_id?: string; after_id?: string; limit?: number } = {}): Promise<Json[]> {
      const limit = filters.limit ?? 25; if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new FulfilmentError('invalid_input', 'A page size from 1 to 100 is required.');
      await authenticate(); return result(await client.rpc('execution_dashboard', { p_view: view, p_from: filters.from, p_until: filters.until, p_zone: filters.zone_id ? uuid(filters.zone_id) : undefined, p_city: filters.city_id ? uuid(filters.city_id) : undefined, p_after: filters.after_id ? uuid(filters.after_id) : undefined, p_limit: limit })) as Json[];
    },
  };
}
