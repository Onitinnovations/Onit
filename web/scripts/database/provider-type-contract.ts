import type { providerOperations } from '../../lib/providers/server';
import type { Database } from '../../types/database.operations.generated';

declare const operations: ReturnType<typeof providerOperations>;
// Compile-only checks: this file is never a runtime entry point.
if (false) {
  // @ts-expect-error private tables are excluded from client database types
  const privateSchema: Database['private'] = {};
  void privateSchema;
  // @ts-expect-error no payouts or payment success command exists
  operations.payProvider('provider');
  // @ts-expect-error exact capacity uses decimal strings
  operations.change('provider', 1, { action: 'capacity', data: { unit: 'concurrent_jobs', units: 2 } }, 'reason', 'a-key-123');
  // @ts-expect-error training certificates cannot be granted through direct qualification input
  operations.change('provider', 1, { action: 'qualification', data: { kind: 'training', code: 'safety', valid_from: '2026-01-01' } }, 'reason', 'a-key-123');
}
