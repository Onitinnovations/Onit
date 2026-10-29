import 'server-only';
import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../../types/database.specialized.generated';
import { SpecializedError } from './laundry';

export type OperationKind = 'laundry' | 'construction' | 'procurement' | 'field_campaign';
export type OperationQueue = 'all' | 'laundry_pickup' | 'laundry_processing' | 'laundry_exceptions' | 'laundry_delivery' | 'construction_progress' | 'construction_changes' | 'procurement_rfqs' | 'procurement_receiving' | 'field_review' | 'field_progress' | 'exceptions';
export type OperationSummary = { id: string; reference: string; kind: OperationKind; status: 'planning' | 'active' | 'ready' | 'closed' | 'cancelled'; revision: number; zone_id: string | null; city_id: string | null };
type QueryDatabase = Omit<Database, 'public'> & { public: Omit<Database['public'], 'Functions'> & { Functions: Database['public']['Functions'] & {
  list_service_operations: { Args: { p_queue: string; p_kind?: string; p_zone?: string; p_city?: string; p_after?: string; p_limit?: number }; Returns: Json };
  specialized_document_reference: { Args: { p_operation: string; p_document: string }; Returns: Json };
} } };
const uuid = (value: string) => { if (!/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value)) throw new SpecializedError('invalid_input', 'A valid ID is required.'); return value; };

/** Scoped OMS discovery and registry references; downloads still require Storage RLS. */
export function specializedQueries(accessToken: string) {
  if (!accessToken || accessToken.length > 16384 || /\s/.test(accessToken)) throw new SpecializedError('unauthenticated', 'Authentication is required.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new SpecializedError('unavailable', 'Supabase configuration is unavailable.');
  const client = createClient<QueryDatabase>(url, key, { global: { headers: { Authorization: `Bearer ${accessToken}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  async function authenticate() { const response = await client.auth.getUser(accessToken); if (response.error || !response.data.user) throw new SpecializedError('unauthenticated', 'A valid session is required.'); }
  function value<T>(response: { data: T | null; error: { code?: string } | null }): T {
    if (response.error?.code === '42501') throw new SpecializedError('forbidden', 'You are not authorised for this record.');
    if (response.error || response.data === null) throw new SpecializedError('unavailable', 'The query could not be completed.');
    return response.data;
  }
  return {
    async list(query: { queue: OperationQueue; kind?: OperationKind; zoneId?: string; cityId?: string; afterId?: string; limit?: number }): Promise<OperationSummary[]> {
      const limit = query.limit ?? 25;
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new SpecializedError('invalid_input', 'A page size from 1 to 100 is required.');
      await authenticate();
      return value(await client.rpc('list_service_operations', { p_queue: query.queue, p_kind: query.kind, p_zone: query.zoneId ? uuid(query.zoneId) : undefined, p_city: query.cityId ? uuid(query.cityId) : undefined, p_after: query.afterId ? uuid(query.afterId) : undefined, p_limit: limit })) as unknown as OperationSummary[];
    },
    async documentReference(operationId: string, documentId: string): Promise<{ document_id: string; bucket_id: string; object_name: string; scan_status: 'pending' | 'clean' }> {
      await authenticate();
      return value(await client.rpc('specialized_document_reference', { p_operation: uuid(operationId), p_document: uuid(documentId) })) as unknown as { document_id: string; bucket_id: string; object_name: string; scan_status: 'pending' | 'clean' };
    },
  };
}
