import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.operations.generated';

export type ProviderType = 'service_associate' | 'artisan' | 'professional' | 'field_agent' | 'service_business' | 'processing_partner' | 'contractor';
export type ProviderStatus = 'applicant' | 'approved' | 'active' | 'suspended' | 'offboarded';
type Validity = { valid_from: string; valid_until?: string };
type ServiceZone = { service_version_id: string; zone_id: string };
type Subject = { id: string };
export type ProviderApplication = {
  provider_type: ProviderType; organisation_id?: string; profile_id?: string;
  source: 'online' | 'referral' | 'social' | 'offline' | 'internal'; campaign_id?: string; referrer_id?: string;
};
export type ProviderMutation =
  | { action: 'screen'; data: { passed: boolean } }
  | { action: 'interview'; data: { outcome: 'passed' | 'failed' | 'follow_up' } }
  | { action: 'reject_application' | 'withdraw' | 'advance_training' | 'approve_application' | 'activate' | 'reactivate' | 'suspend' | 'offboard'; data?: never }
  | { action: 'qualification'; data: Validity & { kind: 'verification' | 'skill' | 'credential'; code: string; document_id?: string; subject_profile_id?: string } }
  | { action: 'approve_qualification' | 'reject_qualification' | 'revoke_qualification' | 'approve_engagement' | 'terminate_engagement' | 'revoke_personnel' | 'revoke_restriction' | 'revoke_coverage' | 'revoke_availability' | 'revoke_schedule'; data: Subject }
  | { action: 'confirm_training'; data: Subject & { document_id?: string } }
  | { action: 'personnel'; data: Validity & { profile_id: string; role: 'administrator' | 'executing_worker' | 'field_agent' } }
  | { action: 'coverage'; data: ServiceZone & Validity & { travel_limit_km?: string } }
  | { action: 'availability'; data: { service_version_id: string; start: string; end: string; kind: 'working' | 'leave' | 'blackout' | 'temporary_unavailable' } }
  | { action: 'weekly_schedule'; data: ServiceZone & Validity & { valid_until: string; weekdays: number[]; local_start: string; local_end: string } }
  | { action: 'capacity'; data: { unit: string; units: string } }
  | { action: 'capacity_change'; data: Subject & { units: string; status: 'active' | 'inactive' } }
  | { action: 'restriction'; data: Validity & { service_version_id?: string; zone_id?: string } }
  | { action: 'engagement'; data: ServiceZone & Validity & { valid_until: string; version: number; contract_reference: string; currency_id: string; unit: string; unit_rate: string; obligations: string; document_id: string } }
  | { action: 'enrol'; data: { session_id: string; subject_profile_id?: string } }
  | { action: 'assess_training'; data: Subject & { attendance_percent: string; score: string } }
  | { action: 'performance'; data: { metric: 'acceptance' | 'completion' | 'timeliness' | 'quality' | 'reliability'; successful: number; observations: number; source_reference: string; document_id: string; occurred_at: string } };
export type ProviderRequirement = { kind: 'verification' | 'skill' | 'credential' | 'training'; code: string; scope: 'provider' | 'worker'; document_required: boolean };
export type ProviderConfiguration =
  | { action: 'requirements'; data: ServiceZone & Validity & { provider_type: ProviderType; version: number; requirements: ProviderRequirement[]; capacity_unit: string; engagement_required: boolean; maximum_travel_km?: string; performance_metric?: 'acceptance' | 'completion' | 'timeliness' | 'quality' | 'reliability'; minimum_performance?: string; performance_window_days?: number } }
  | { action: 'approve_requirements' | 'retire_requirements' | 'approve_course' | 'retire_course'; data: Subject }
  | { action: 'course'; data: { code: string; version: number; name: string; pass_mark: string; required_attendance: string; certificate_valid_days: number } }
  | { action: 'session'; data: { course_id: string; trainer_id: string; start: string; end: string } }
  | { action: 'campaign'; data: { code: string; name: string; start: string; end?: string } }
  | { action: 'close_campaign'; data: Subject };
export type EligibilityInput = { providerId: string; serviceVersionId: string; zoneId: string; start: string; end: string; units: string; workerId?: string };
export type EligibilityDecision = {
  eligible: boolean; reasons: { code: string; kind?: string; requirement?: string; scope?: string }[];
  provider_id: string; provider_revision: number; policy_id: string | null; pool_id: string | null;
  capacity_unit: string | null; capacity_used: string; capacity_requested: string; capacity_limit: string | null; performance_ratio: string | null;
  personnel_checked: boolean; worker_id?: string | null; worker_capacity_used?: string; worker_capacity_requested?: string; worker_capacity_limit?: string | null;
};
export type PersonnelMutation =
  | { action: 'capacity'; data: { profile_id: string; version: number; units: string; valid_from: string; valid_until?: string } }
  | { action: 'approve_capacity' | 'retire_capacity'; data: Subject }
  | { action: 'availability'; data: { profile_id: string; start: string; end: string; kind: 'working' | 'leave' | 'blackout' | 'temporary_unavailable' } }
  | { action: 'revoke_availability'; data: Subject & { profile_id: string } };
export type PersonnelResourceView = {
  profile_id: string;
  capacity: { id: string; version: number; units: string; valid_from: string; valid_until: string | null; status: 'draft' | 'approved' | 'retired' }[];
  availability: { id: string; starts_at: string; ends_at: string; kind: 'working' | 'leave' | 'blackout' | 'temporary_unavailable' }[];
};
export type ProviderSummary = { id: string; provider_type: ProviderType; status: ProviderStatus; revision: number };
export type ProviderView = {
  id: string; type: ProviderType; status: ProviderStatus; revision: number;
  display_name: string; personnel: { id: string; profile_id: string; role: string; valid_until: string | null }[];
  applications: { id: string; revision: number; stage: string }[];
  qualifications: { id: string; kind: string; code: string; status: string; subject_profile_id: string | null; valid_until: string | null; document_id: string | null }[];
  availability: { id: string; service_version_id: string; start: string; end: string; kind: string; schedule_id: string | null }[];
  capacity: { id: string; unit: string; units: string; status: string }[];
  training: { id: string; status: string; subject_profile_id: string | null; attendance_percent: string | null; score: string | null; qualification_id: string | null; session_id: string; starts_at: string; ends_at: string; code: string; version: number; name: string }[];
  engagements: { id: string; status: string; unit: string; unit_rate: string; currency_id: string; valid_from: string; valid_until: string }[] | null;
};
export class ProviderError extends Error {
  constructor(public readonly code: 'unauthenticated' | 'forbidden' | 'invalid_input' | 'conflict' | 'unavailable', message: string) { super(message); this.name = 'ProviderError'; }
}
const uuid = (value: string) => {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new ProviderError('invalid_input', 'A valid identifier is required.');
  return value;
};
function commandData(data: object, reason: string, key: string): Json {
  if (typeof reason !== 'string' || reason.trim().length < 1 || reason.length > 2000 || typeof key !== 'string' || key.length < 8 || key.length > 128) throw new ProviderError('invalid_input', 'A bounded reason and idempotency key are required.');
  let value: Json;
  try { const serialized = JSON.stringify({ ...data, reason }); if (serialized.length > 60000) throw Error(); value = JSON.parse(serialized) as Json; }
  catch { throw new ProviderError('invalid_input', 'A bounded JSON command is required.'); }
  return value;
}
function result<T>(response: { data: T | null; error: { code?: string } | null }): T {
  if (response.error) {
    const code = response.error.code || '';
    if (code === '42501') throw new ProviderError('forbidden', 'This operation is not permitted.');
    if (['40001', '23505', '55000'].includes(code)) throw new ProviderError('conflict', 'The record changed or this decision conflicts with its current state.');
    if (code.startsWith('22') || code.startsWith('23')) throw new ProviderError('invalid_input', 'The provider input or required configuration is invalid.');
    throw new ProviderError('unavailable', 'The provider operation could not be completed.');
  }
  if (response.data === null) throw new ProviderError('unavailable', 'The requested record is unavailable.');
  return response.data;
}
/** Server-only caller-JWT adapter. Each RPC rechecks current database permissions.
 * No privileged key, external verification result or notification delivery is inferred here.
 */
export function providerOperations(accessToken: string) {
  if (typeof accessToken !== 'string' || accessToken.length < 1 || accessToken.length > 16384 || /\s/.test(accessToken)) throw new ProviderError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new ProviderError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<Database>(url, key, { global: { headers: { Authorization: `Bearer ${accessToken}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  async function authenticate() { const { data, error } = await client.auth.getUser(accessToken); if (error || !data.user) throw new ProviderError('unauthenticated', 'A valid signed-in session is required.'); }
  return {
    async personnel(input: PersonnelMutation, reason: string, idempotencyKey: string) {
      const data = commandData(input.data, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('personnel_command', { p_action: input.action, p_data: data, p_key: idempotencyKey }));
    },
    async readPersonnel(profileId: string): Promise<PersonnelResourceView> { await authenticate(); return result(await client.rpc('read_personnel_resource', { p_profile: uuid(profileId) })) as unknown as PersonnelResourceView; },
    async apply(input: ProviderApplication, reason: string, idempotencyKey: string) {
      const data = commandData(input, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('apply_provider', { p_data: data, p_key: idempotencyKey }));
    },
    async change(providerId: string, expectedRevision: number, input: ProviderMutation, reason: string, idempotencyKey: string) {
      if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) throw new ProviderError('invalid_input', 'A positive expected revision is required.');
      const data = commandData({ ...input.data, expected_revision: expectedRevision }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('provider_command', { p_provider: uuid(providerId), p_action: input.action, p_data: data, p_key: idempotencyKey }));
    },
    async configure(input: ProviderConfiguration, reason: string, idempotencyKey: string) {
      const data = commandData(input.data, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('provider_configuration', { p_action: input.action, p_data: data, p_key: idempotencyKey }));
    },
    async read(providerId: string): Promise<ProviderView> { await authenticate(); return result(await client.rpc('read_provider', { p_provider: uuid(providerId) })) as unknown as ProviderView; },
    async documentReference(providerId: string, documentId: string): Promise<{ id: string; bucket: string; object_name: string; content_type: string; byte_size: string }> {
      await authenticate(); return result(await client.rpc('provider_document_reference', { p_provider: uuid(providerId), p_document: uuid(documentId) })) as unknown as { id: string; bucket: string; object_name: string; content_type: string; byte_size: string };
    },
    async list(input: { status?: ProviderStatus; after?: string; limit?: number } = {}): Promise<ProviderSummary[]> {
      const limit = input.limit ?? 25; if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new ProviderError('invalid_input', 'A page size between one and 100 is required.');
      await authenticate(); return result(await client.rpc('list_providers', { p_status: input.status, p_after: input.after ? uuid(input.after) : undefined, p_limit: limit })) as unknown as ProviderSummary[];
    },
    async eligibility(input: EligibilityInput): Promise<EligibilityDecision> {
      if (!/^\d+(\.\d{1,4})?$/.test(input.units) || !Number.isFinite(Date.parse(input.start)) || !Number.isFinite(Date.parse(input.end))) throw new ProviderError('invalid_input', 'An exact quantity and valid schedule are required.');
      await authenticate(); return result(await client.rpc('provider_eligibility', { p_provider: uuid(input.providerId), p_service: uuid(input.serviceVersionId), p_zone: uuid(input.zoneId), p_start: input.start, p_end: input.end, p_units: input.units, p_worker: input.workerId ? uuid(input.workerId) : undefined })) as unknown as EligibilityDecision;
    },
    async reserve(input: EligibilityInput & { expiresAt: string; purposeReference: string }, reason: string, idempotencyKey: string) {
      const data = commandData({ service_version_id: uuid(input.serviceVersionId), zone_id: uuid(input.zoneId), start: input.start, end: input.end, units: input.units, worker_id: input.workerId ? uuid(input.workerId) : undefined, expires_at: input.expiresAt, purpose_reference: input.purposeReference }, reason, idempotencyKey);
      await authenticate(); return result(await client.rpc('provider_reservation', { p_provider: uuid(input.providerId), p_action: 'reserve', p_data: data, p_key: idempotencyKey }));
    },
    async release(providerId: string, reservationId: string, action: 'release' | 'expire', reason: string, idempotencyKey: string) {
      const data = commandData({ id: uuid(reservationId) }, reason, idempotencyKey); await authenticate();
      return result(await client.rpc('provider_reservation', { p_provider: uuid(providerId), p_action: action, p_data: data, p_key: idempotencyKey }));
    },
    async readConfiguration(kind: 'requirements' | 'course' | 'session' | 'campaign', id: string) { await authenticate(); return result(await client.rpc('read_provider_configuration', { p_kind: kind, p_id: uuid(id) })); },
    async activity(providerId: string, cursor?: { timestamp: string; id: string }, limit = 25) {
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new ProviderError('invalid_input', 'A bounded page size is required.');
      await authenticate(); return result(await client.rpc('provider_activity', { p_provider: uuid(providerId), p_before: cursor?.timestamp, p_before_id: cursor ? uuid(cursor.id) : undefined, p_limit: limit }));
    },
  };
}
