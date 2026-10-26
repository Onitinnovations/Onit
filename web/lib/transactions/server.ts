import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.phase2.generated';

export type RequestStatus = 'draft' | 'submitted' | 'reviewed' | 'cancelled';
export type BookingAnswers = Record<string, Record<string, Json>[]>;
export type QuoteLineInput = {
  description: string;
  kind: 'service' | 'labour' | 'materials' | 'logistics' | 'other';
  quantity: string;
  unit_price: string;
  discount?: string;
  tax_rule_id?: string;
};
export type CreateRequestInput = {
  accountId: string; serviceVersionId: string; addressId: string;
  answers: BookingAnswers; idempotencyKey: string;
  branchId?: string; departmentId?: string;
  preferredStart?: string; preferredEnd?: string; instructions?: string;
};
export type PricingCardConfig = {
  service_version_id: string; currency_id: string; code: string; version: number;
  valid_from: string; valid_until?: string; zone_id?: string; variant_id?: string;
  customer_account_id?: string; branch_id?: string; contract_reference?: string;
  minimum_service_charge?: string; discount_percent?: string;
  minimum_tax_rule_id?: string; approval_policy_id?: string;
};
export type PricingRuleInput = {
  code: string; rule_type: 'fixed' | 'per_unit' | 'assessment_quote'; description: string;
  unit_amount?: string; minimum_quantity?: string; unit_name?: string;
  charge_kind?: QuoteLineInput['kind']; option_value_id?: string;
  internal_unit_cost?: string; minimum_charge?: string; tax_rule_id?: string;
};
export type GenerateQuoteInput = {
  requestId: string; idempotencyKey: string; validUntil: string; terms: string;
  variantId?: string; zoneId?: string; quantities?: Record<string, string>;
  optionValues?: string[]; overrides?: Record<string, string>; overrideReason?: string;
  manualLines?: QuoteLineInput[];
};
export type CommercialPolicyInput = {
  code: string; version: number; minimum_approvers: number;
  approval_side: 'internal' | 'customer'; customer_account_id?: string;
  organisation_id?: string; branch_id?: string; threshold_amount?: string; currency_id?: string;
};
export class TransactionError extends Error {
  constructor(public readonly code: 'unauthenticated' | 'forbidden' | 'invalid_input' | 'conflict' | 'unavailable', message: string) {
    super(message); this.name = 'TransactionError';
  }
}
const uuid = (value: string) => {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))
    throw new TransactionError('invalid_input', 'A valid identifier is required.');
  return value;
};
const key = (value: string) => {
  if (typeof value !== 'string' || value.length < 8 || value.length > 128) throw new TransactionError('invalid_input', 'Invalid idempotency key.');
  return value;
};
const timestamp = (value?: string) => {
  if (value !== undefined && (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))))
    throw new TransactionError('invalid_input', 'An ISO timestamp with a timezone is required.');
  return value;
};
function unwrap<T>(result: { data: T | null; error: { code?: string } | null }): T {
  if (result.error) {
    const code = result.error.code || '';
    if (code === '42501') throw new TransactionError('forbidden', 'This operation is not permitted.');
    if (['40001', '23505', '55000'].includes(code)) throw new TransactionError('conflict', 'The record changed or this operation conflicts with its current state.');
    if (code.startsWith('22') || code.startsWith('23')) throw new TransactionError('invalid_input', 'The transaction input or state is invalid.');
    throw new TransactionError('unavailable', 'The transaction could not be completed.');
  }
  if (result.data === null) throw new TransactionError('unavailable', 'No transaction result was returned.');
  return result.data;
}

/** Call from a route handler/server action with the caller's access token.
 * Uses the public anon key and caller JWT; never uses a service-role key.
 * Creating this adapter grants no authority: Auth and each database command
 * independently verify the current user and trusted memberships.
 */
export function transactionOperations(accessToken: string) {
  if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 || /\s/.test(accessToken))
    throw new TransactionError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) throw new TransactionError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<Database>(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  async function authenticate() {
    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) throw new TransactionError('unauthenticated', 'A valid signed-in session is required.');
  }
  return {
    async createPricingCard(config: PricingCardConfig, rules: PricingRuleInput[]) {
      await authenticate();
      if (!Array.isArray(rules) || rules.length < 1 || rules.length > 100)
        throw new TransactionError('invalid_input', 'Between one and 100 pricing rules are required.');
      return unwrap(await client.rpc('create_pricing_card', { p_config: config, p_rules: rules }));
    },
    async approvePricingCard(id: string) {
      await authenticate();
      return unwrap(await client.rpc('approve_pricing_card', { p_id: uuid(id) }));
    },
    async readPricingCard(id: string) {
      await authenticate();
      return unwrap(await client.rpc('read_pricing_card', { p_id: uuid(id) }));
    },
    async retirePricingCard(id: string, reason: string, idempotencyKey: string) {
      await authenticate();
      return unwrap(await client.rpc('retire_pricing_card', { p_id: uuid(id), p_reason: reason, p_key: key(idempotencyKey) }));
    },
    async createCommercialPolicy(input: CommercialPolicyInput) {
      await authenticate();
      return unwrap(await client.rpc('commercial_policy', { p_action: 'create', p_data: input }));
    },
    async approveCommercialPolicy(id: string) {
      await authenticate();
      return unwrap(await client.rpc('commercial_policy', { p_action: 'approve', p_data: { id: uuid(id) } }));
    },
    async createAssessment(requestId: string, mode: 'remote' | 'physical', idempotencyKey: string) {
      await authenticate();
      return unwrap(await client.rpc('assessment_command', { p_request: uuid(requestId), p_action: 'create', p_data: { mode, idempotency_key: key(idempotencyKey) } }));
    },
    async scheduleAssessment(input: { requestId: string; assessmentId: string; assessorId: string; start: string; end: string }) {
      await authenticate();
      return unwrap(await client.rpc('assessment_command', { p_request: uuid(input.requestId), p_action: 'schedule', p_data: {
        id: uuid(input.assessmentId), assessor_id: uuid(input.assessorId), start: timestamp(input.start), end: timestamp(input.end),
      } }));
    },
    async attachAssessmentEvidence(requestId: string, assessmentId: string, documentId: string) {
      await authenticate();
      return unwrap(await client.rpc('assessment_command', { p_request: uuid(requestId), p_action: 'evidence', p_data: { id: uuid(assessmentId), document_id: uuid(documentId) } }));
    },
    async completeAssessment(input: { requestId: string; assessmentId: string; measurements: Record<string, string>; checklistAnswers: Record<string, boolean>; findings: string }) {
      await authenticate();
      return unwrap(await client.rpc('assessment_command', { p_request: uuid(input.requestId), p_action: 'complete', p_data: {
        id: uuid(input.assessmentId), measurements: input.measurements, checklist_answers: input.checklistAnswers, findings: input.findings,
      } }));
    },
    async decideAssessment(requestId: string, assessmentId: string, decision: 'approve' | 'reject') {
      await authenticate();
      return unwrap(await client.rpc('assessment_command', { p_request: uuid(requestId), p_action: decision, p_data: { id: uuid(assessmentId) } }));
    },
    async readAssessment(id: string) {
      await authenticate();
      return unwrap(await client.rpc('read_assessment', { p_id: uuid(id) }));
    },
    async generateQuote(input: GenerateQuoteInput) {
      await authenticate();
      const selections: Json = {
        valid_until: timestamp(input.validUntil), terms: input.terms,
        ...(input.variantId ? { variant_id: uuid(input.variantId) } : {}),
        ...(input.zoneId ? { zone_id: uuid(input.zoneId) } : {}),
        ...(input.quantities ? { quantities: input.quantities } : {}),
        ...(input.optionValues ? { option_values: input.optionValues.map(uuid) } : {}),
        ...(input.overrides ? { overrides: input.overrides, override_reason: input.overrideReason } : {}),
        ...(input.manualLines ? { manual_lines: input.manualLines } : {}),
      };
      return unwrap(await client.rpc('generate_quotation', { p_request: uuid(input.requestId), p_input: selections, p_key: key(input.idempotencyKey) }));
    },
    async readQuoteCommercial(id: string) {
      await authenticate();
      return unwrap(await client.rpc('read_quotation_commercial', { p_id: uuid(id) }));
    },
    async createRequest(input: CreateRequestInput) {
      await authenticate();
      return unwrap(await client.rpc('create_service_request', {
        p_account: uuid(input.accountId), p_version: uuid(input.serviceVersionId), p_address: uuid(input.addressId),
        p_answers: input.answers, p_key: key(input.idempotencyKey),
        ...(input.branchId ? { p_branch: uuid(input.branchId) } : {}),
        ...(input.departmentId ? { p_department: uuid(input.departmentId) } : {}),
        p_start: timestamp(input.preferredStart), p_end: timestamp(input.preferredEnd), p_instructions: input.instructions,
      }));
    },
    async changeRequest(input: { id: string; revision: number; action: 'amend' | 'submit' | 'cancel'; answers?: BookingAnswers; preferredStart?: string; preferredEnd?: string; instructions?: string }) {
      await authenticate();
      if (!Number.isSafeInteger(input.revision) || input.revision < 1) throw new TransactionError('invalid_input', 'Invalid revision.');
      return unwrap(await client.rpc('change_service_request', {
        p_id: uuid(input.id), p_revision: input.revision, p_action: input.action, p_answers: input.answers,
        p_start: timestamp(input.preferredStart), p_end: timestamp(input.preferredEnd), p_instructions: input.instructions,
      }));
    },
    async reviewRequest(id: string, revision: number) {
      await authenticate();
      if (!Number.isSafeInteger(revision) || revision < 1) throw new TransactionError('invalid_input', 'Invalid revision.');
      return unwrap(await client.rpc('review_service_request', { p_id: uuid(id), p_revision: revision }));
    },
    async attachDocument(requestId: string, documentId: string) {
      await authenticate();
      return unwrap(await client.rpc('attach_request_document', { p_id: uuid(requestId), p_document: uuid(documentId) }));
    },
    async listRequests(filter: { accountId?: string; status?: RequestStatus; offset?: number; limit?: number } = {}) {
      await authenticate();
      const offset = filter.offset ?? 0; const limit = filter.limit ?? 25;
      if (!Number.isInteger(offset) || offset < 0 || offset > 10000 || !Number.isInteger(limit) || limit < 1 || limit > 100)
        throw new TransactionError('invalid_input', 'Invalid pagination.');
      let query = client.from('service_requests').select('*').order('created_at', { ascending: false }).order('id', { ascending: false });
      if (filter.accountId) query = query.eq('customer_account_id', uuid(filter.accountId));
      if (filter.status) query = query.eq('status', filter.status);
      return unwrap(await query.range(offset, offset + limit - 1));
    },
    async prepareQuote(input: { requestId: string; currencyId: string; validUntil: string; terms: string; lines: QuoteLineInput[]; idempotencyKey: string }) {
      await authenticate();
      if (!Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > 100) throw new TransactionError('invalid_input', 'Invalid quotation lines.');
      return unwrap(await client.rpc('prepare_quotation', {
        p_request: uuid(input.requestId), p_currency: uuid(input.currencyId), p_valid_until: timestamp(input.validUntil)!,
        p_terms: input.terms, p_lines: input.lines, p_key: key(input.idempotencyKey),
      }));
    },
    async decideQuote(id: string, action: 'approve' | 'accept' | 'reject' | 'expire') {
      await authenticate();
      return unwrap(await client.rpc('decide_quotation', { p_id: uuid(id), p_action: action }));
    },
    async readQuote(id: string) {
      await authenticate();
      // Financial values inside this JSON document are exact decimal strings.
      return unwrap(await client.rpc('read_quotation', { p_id: uuid(id) }));
    },
  };
}
