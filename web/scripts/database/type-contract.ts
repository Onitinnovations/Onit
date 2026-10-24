// Compile-only checks: no runtime import, network request or application change.
type Client = typeof import('../../supabaseClient').supabase;

export function verifyPublicClientContract(client: Client) {
  client.from('profiles').select('id,display_name');
  client.rpc('ensure_individual_customer');
  client.rpc('prepare_customer_upload', { p_account_id: 'synthetic', p_content_type: 'application/pdf', p_byte_size: 10 });
  // @ts-expect-error Private operational schema must not be exposed in shared types.
  client.schema('private');
  // @ts-expect-error There is no independent password/account table in the public API.
  client.from('passwords');
  // @ts-expect-error Generated RPC types require the byte size parameter.
  client.rpc('prepare_customer_upload', { p_account_id: 'synthetic', p_content_type: 'application/pdf' });
}
