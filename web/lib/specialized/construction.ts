import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.specialized.generated';

type OperationDatabase = Omit<Database, 'public'> & { public: Omit<Database['public'], 'Functions'> & { Functions: Omit<Database['public']['Functions'], 'operation_policy_command' | 'read_operation_policy' | 'service_operation_command' | 'read_service_operation'> & {
  operation_policy_command: { Args: { p_action: string; p_data: Json; p_key: string }; Returns: string };
  read_operation_policy: { Args: { p_policy: string }; Returns: Json };
  service_operation_command: { Args: { p_operation: string | null; p_action: string; p_data: Json; p_key: string }; Returns: string };
  read_service_operation: { Args: { p_operation: string; p_after?: string; p_limit?: number }; Returns: Json };
} } };
export type ConstructionMutation =
 | { action: 'link_task'; data: { task_id: string; purpose: 'site_inspection' | 'construction_milestone' } }
 | { action: 'activate' | 'ready' | 'close' | 'cancel'; data?: never }
 | { action: 'project.create'; data: { site_id: string; specification: Json; access: string } }
 | { action: 'document'; data: { document_id: string; task_id?: string; classification: 'technical_specification' | 'drawing' | 'measurement' | 'client_deliverable' } }
 | { action: 'milestone.create'; data: { task_id: string; code: string; trade: string; scope: Json; measurements: Record<string, string>; variation_id?: string } }
 | { action: 'milestone.inspect'; data: { id: string; evidence_id: string } }
 | { action: 'milestone.accept' | 'material.approve' | 'material.retire' | 'variation.authorize' | 'variation.withdraw' | 'variation.reject'; data: { id: string } }
 | { action: 'material.prepare'; data: { code: string; description: string; unit: string; quantity: string } }
 | { action: 'material.record'; data: { id: string; task_id: string; kind: 'received' | 'consumed' | 'returned' | 'waste'; quantity: string; evidence_id: string } }
 | { action: 'variation.propose'; data: { scope: Json; cost_impact: string; time_impact_seconds: number; quote_id?: string; evidence_id: string } }
 | { action: 'variation.customer'; data: { id: string; accept: boolean } }
 | { action: 'variation.implement'; data: { id: string; task_id: string; predecessors?: string[] } };
export type ConstructionPolicy = { service_version_id: string; version: number; valid_from: string; valid_until?: string; configuration: { required_purposes: ('site_inspection' | 'construction_milestone')[] } };
export type ConstructionProjection = { id: string; reference: string; revision: number; kind: 'construction'; status: 'planning' | 'active' | 'ready' | 'closed' | 'cancelled'; project: Json; milestones: Json[]; variations?: { id: string; status: string; cost_impact: string; time_impact_seconds: number }[]; materials?: { id: string; quantity: string; held: string; unit: string }[] };
export class SpecializedError extends Error {
  constructor(public readonly code: 'unauthenticated' | 'forbidden' | 'invalid_input' | 'conflict' | 'unavailable', message: string) { super(message); this.name = 'SpecializedError'; }
}
const uuid = (value: string) => { if (!/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value)) throw new SpecializedError('invalid_input', 'A valid ID is required.'); return value; };
function input(value: object, reason: string, key: string): Json {
  if (!key || key.length < 8 || key.length > 128 || !reason?.trim() || reason.length > 2000) throw new SpecializedError('invalid_input', 'A bounded reason and idempotency key are required.');
  const data = { ...value, reason }; if (new TextEncoder().encode(JSON.stringify(data)).length > 65536) throw new SpecializedError('invalid_input', 'The operation is too large.'); return data as Json;
}
function result<T>(response: { data: T | null; error: { code?: string } | null }): T {
  if (response.error) {
    const code = response.error.code ?? '';
    if (code === '42501') throw new SpecializedError('forbidden', 'You are not authorised for this operation.');
    if (['23505', '40001', '40P01', '55000'].includes(code)) throw new SpecializedError('conflict', 'The record changed or cannot change in its current state.');
    if (code.startsWith('22') || ['23514', '23503', '23502'].includes(code)) throw new SpecializedError('invalid_input', 'The operation does not satisfy the business rules.');
    throw new SpecializedError('unavailable', 'The operation could not be completed.');
  }
  if (response.data === null) throw new SpecializedError('unavailable', 'The record is unavailable.'); return response.data;
}
/** Caller-JWT operations; capacity and quality remain in the shared engine. */
export function constructionOperations(accessToken: string) {
  if (!accessToken || accessToken.length > 16384 || /\s/.test(accessToken)) throw new SpecializedError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new SpecializedError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<OperationDatabase>(url, key, { global: { headers: { Authorization: `Bearer ${accessToken}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  async function authenticate() { const response = await client.auth.getUser(accessToken); if (response.error || !response.data.user) throw new SpecializedError('unauthenticated', 'A valid session is required.'); }
  return {
    async preparePolicy(policy: ConstructionPolicy, reason: string, idempotencyKey: string) {
      const data = input({ ...policy, kind: 'construction', service_version_id: uuid(policy.service_version_id) }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('operation_policy_command', { p_action: 'prepare', p_data: data, p_key: idempotencyKey }));
    },
    async decidePolicy(id: string, action: 'approve' | 'retire', reason: string, idempotencyKey: string) {
      const data = input({ id: uuid(id) }, reason, idempotencyKey); await authenticate(); return result(await client.rpc('operation_policy_command', { p_action: action, p_data: data, p_key: idempotencyKey }));
    },
    async readPolicy(id: string): Promise<Json> { await authenticate(); return result(await client.rpc('read_operation_policy', { p_policy: uuid(id) })); },
    async create(orderId: string, reason: string, idempotencyKey: string) {
      const data = input({ order_id: uuid(orderId), kind: 'construction' }, reason, idempotencyKey); await authenticate(); return result(await client.rpc('service_operation_command', { p_operation: null, p_action: 'create', p_data: data, p_key: idempotencyKey }));
    },
    async change(operationId: string, expectedRevision: number, mutation: ConstructionMutation, reason: string, idempotencyKey: string) {
      if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) throw new SpecializedError('invalid_input', 'A positive expected revision is required.');
      const data = input({ ...mutation.data, expected_revision: expectedRevision }, reason, idempotencyKey); await authenticate(); return result(await client.rpc('service_operation_command', { p_operation: uuid(operationId), p_action: mutation.action, p_data: data, p_key: idempotencyKey }));
    },
    async read(operationId: string, afterId?: string, limit = 25): Promise<ConstructionProjection> {
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new SpecializedError('invalid_input', 'A page size from 1 to 100 is required.');
      await authenticate(); return result(await client.rpc('read_service_operation', { p_operation: uuid(operationId), p_after: afterId ? uuid(afterId) : undefined, p_limit: limit })) as unknown as ConstructionProjection;
    },
  };
}
