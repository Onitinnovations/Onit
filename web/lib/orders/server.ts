import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.orders.generated';

type Schedule = { start: string; end: string };
export type OrderPolicy = {
  service_version_id: string; version: number; valid_from: string; valid_until?: string;
  payment_gate: 'payment_required' | 'payment_or_credit' | 'no_upfront_payment';
  offer_seconds: number; performance_weight: string; workload_weight: string;
};
export type OrderMutation =
  | { action: 'release' | 'hold' | 'resume'; data?: never }
  | { action: 'authorization'; data: { kind: 'payment_evidence' | 'corporate_credit' | 'exception'; document_id: string; reference: string; amount: string; valid_until: string } }
  | { action: 'decide_authorization' | 'decide_change'; data: { id: string; approve: boolean } }
  | { action: 'propose_change'; data: { kind: 'reschedule'; proposal: Schedule } | { kind: 'cancel'; proposal?: never } | { kind: 'amend'; proposal: { quotation_version_id: string } } };
export type DispatchMutation =
  | { action: 'propose'; data: { candidates: string[]; override_reason?: string } }
  | { action: 'respond'; data: { offer_id: string; accept: boolean } }
  | { action: 'confirm' | 'revalidate' | 'approve_override' | 'resolve_escalation'; data: { id: string } }
  | { action: 'withdraw' | 'reassign' | 'expire' | 'escalate'; data?: never };
export type MatchInput = { provider_id: string; worker_id: string; units: string };
export type Candidate = { id: string; provider_id: string; worker_id: string; score: string; decision: { eligible: boolean; reasons: { code: string }[] } };
export type OrderProjection = {
  id: string; reference: string; revision: number;
  status: 'awaiting_confirmation' | 'confirmed' | 'assigned' | 'on_hold' | 'cancelled' | 'in_progress' | 'awaiting_qa' | 'awaiting_customer_confirmation' | 'customer_disputed' | 'completed' | 'closed';
  service_version_id: string; start: string; end: string;
  customer_account_id?: string; request_id?: string; branch_id?: string | null;
  commercial?: { id: string; currency: string; total: string; terms: string; lines: Json[] };
  internal_status?: 'pending_authorization' | 'awaiting_dispatch' | 'assigned' | 'on_hold' | 'cancelled' | 'in_progress' | 'awaiting_qa' | 'awaiting_customer_confirmation' | 'customer_disputed' | 'completed' | 'closed';
  commercial_gate?: boolean;
  authorizations?: { id: string; kind: 'payment_evidence' | 'corporate_credit' | 'exception'; status: string; order_revision: number; amount: string; currency_id: string; valid_until: string; document_id?: string; reference?: string; reason?: string; created_by?: string; decided_by?: string | null }[];
  offers?: { id: string; provider_id: string; proposal_id: string; status: string; proposal_status: string; expires_at: string; override_reason: string | null; override_by: string | null; proposed_by: string | null; resources: { worker_id: string; units: string; status: string }[] }[];
  location?: { address: string; city_id: string | null; latitude: string | null; longitude: string | null };
  changes?: { id: string; kind: string; status: string; order_revision: number; proposal: Json; created_by: string }[];
};
export type OrderView = 'orders' | 'unassigned' | 'pending_offers' | 'confirmed_assignments' | 'upcoming' | 'exceptions' | 'workload' | 'expired_offers' | 'failed_dispatch';
export class OrderError extends Error {
  constructor(public readonly code: 'unauthenticated' | 'forbidden' | 'invalid_input' | 'conflict' | 'unavailable', message: string) { super(message); this.name = 'OrderError'; }
}
const uuid = (v: string) => { if (typeof v !== 'string' || !/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(v)) throw new OrderError('invalid_input', 'A valid record ID is required.'); return v; };
function data(value: object, reason: string, key: string): Json {
  if (!reason?.trim() || reason.length > 2000 || !key || key.length < 8 || key.length > 128) throw new OrderError('invalid_input', 'A bounded reason and idempotency key are required.');
  const input = { ...value, reason };
  if (JSON.stringify(input).length > 16384) throw new OrderError('invalid_input', 'The operation is too large.');
  return input as Json;
}
function result<T>(r: { data: T | null; error: { code?: string } | null }): T {
  if (r.error) {
    const code = r.error.code;
    if (code === '42501') throw new OrderError('forbidden', 'You are not authorised for this operation.');
    if (['23505', '40001', '40P01', '55000'].includes(code ?? '')) throw new OrderError('conflict', 'The record changed or is unavailable in its current state. Refresh before retrying.');
    if (['23514', '23503', '23502', '22P02', '22007', '22008', '22003'].includes(code ?? '')) throw new OrderError('invalid_input', 'The operation does not satisfy the required business rules.');
    throw new OrderError('unavailable', 'The order operation could not be completed.');
  }
  if (r.data === null) throw new OrderError('unavailable', 'The record is unavailable.');
  return r.data;
}
/** Caller-JWT operations. No service-role client, payment callback or financial arithmetic. */
export function orderOperations(accessToken: string) {
  if (!accessToken || accessToken.length > 16384 || /\s/.test(accessToken)) throw new OrderError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new OrderError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<Database>(url, key, { global: { headers: { Authorization: `Bearer ${accessToken}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  async function authenticate() { const r = await client.auth.getUser(accessToken); if (r.error || !r.data.user) throw new OrderError('unauthenticated', 'A valid signed-in session is required.'); }
  const revision = (v: number) => { if (!Number.isSafeInteger(v) || v < 1) throw new OrderError('invalid_input', 'A positive expected revision is required.'); return v; };
  return {
    async create(input: Schedule & { quotation_version_id: string; zone_id: string }, reason: string, idempotencyKey: string) {
      const value = data({ ...input, quotation_version_id: uuid(input.quotation_version_id), zone_id: uuid(input.zone_id) }, reason, idempotencyKey);
      await authenticate(); return result(await client.rpc('create_service_order', { p_quote: uuid(input.quotation_version_id), p_data: value, p_key: idempotencyKey }));
    },
    async change(orderId: string, expectedRevision: number, input: OrderMutation, reason: string, idempotencyKey: string) {
      const value = data({ ...input.data, expected_revision: revision(expectedRevision) }, reason, idempotencyKey);
      await authenticate(); return result(await client.rpc('order_command', { p_order: uuid(orderId), p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async dispatch(orderId: string, expectedRevision: number, input: DispatchMutation, reason: string, idempotencyKey: string) {
      const value = data({ ...input.data, expected_revision: revision(expectedRevision) }, reason, idempotencyKey);
      await authenticate(); return result(await client.rpc('dispatch_command', { p_order: uuid(orderId), p_action: input.action, p_data: value, p_key: idempotencyKey }));
    },
    async configure(input: { action: 'prepare'; data: OrderPolicy } | { action: 'approve' | 'retire'; data: { id: string } }, idempotencyKey: string) {
      if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) throw new OrderError('invalid_input', 'A bounded idempotency key is required.');
      await authenticate(); return result(await client.rpc('order_policy_command', { p_action: input.action, p_data: input.data as unknown as Json, p_key: idempotencyKey }));
    },
    async match(orderId: string, candidates: MatchInput[]): Promise<Candidate[]> {
      if (!Array.isArray(candidates) || candidates.length < 1 || candidates.length > 100 || candidates.some(c => !/^\d+(\.\d{1,4})?$/.test(c.units))) throw new OrderError('invalid_input', 'A bounded candidate set with exact capacity quantities is required.');
      await authenticate(); return result(await client.rpc('match_order', { p_order: uuid(orderId), p_candidates: candidates.map(c => ({ ...c, provider_id: uuid(c.provider_id), worker_id: uuid(c.worker_id) })) })) as unknown as Candidate[];
    },
    async discover(orderId: string, unit: string, units: string, cursor?: { providerId: string; workerId: string }, limit = 50): Promise<Candidate[]> {
      if (!unit || unit.length > 40 || !/^\d+(\.\d{1,4})?$/.test(units) || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new OrderError('invalid_input', 'A bounded resource search and exact units are required.');
      await authenticate(); return result(await client.rpc('discover_order_candidates', { p_order: uuid(orderId), p_unit: unit, p_units: units, p_after_provider: cursor ? uuid(cursor.providerId) : undefined, p_after_worker: cursor ? uuid(cursor.workerId) : undefined, p_limit: limit })) as unknown as Candidate[];
    },
    async readPolicy(id: string) { await authenticate(); return result(await client.rpc('read_order_policy', { p_id: uuid(id) })); },
    async read(orderId: string): Promise<OrderProjection> { await authenticate(); return result(await client.rpc('read_order', { p_order: uuid(orderId) })) as unknown as OrderProjection; },
    async list(view: OrderView = 'orders', after?: string, limit = 25): Promise<OrderProjection[]> {
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new OrderError('invalid_input', 'A page size from one to 100 is required.');
      await authenticate(); return result(await client.rpc('list_order_operations', { p_view: view, p_after: after ? uuid(after) : undefined, p_limit: limit })) as unknown as OrderProjection[];
    },
  };
}
