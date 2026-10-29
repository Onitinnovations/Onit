import type { Database } from '../../types/database.fulfilment.generated';
import type { FulfilmentMutation, QualityMutation } from '../../lib/fulfilment/server';

// Compile-only contracts. No session or client is constructed.
type PublicSchemas = keyof Database;
const allowed: PublicSchemas = 'public';
// @ts-expect-error Private tables must not enter browser-capable generated types.
const restricted: PublicSchemas = 'private';
const progress: FulfilmentMutation = { action: 'progress', data: { task_id: '', task_revision: 1, state: 'in_progress' } };
// @ts-expect-error Providers cannot self-approve quality through a progress action.
const bypass: FulfilmentMutation = { action: 'progress', data: { task_id: '', task_revision: 1, state: 'qa_approved' } };
// @ts-expect-error No arbitrary administrative status setter exists.
const setter: FulfilmentMutation = { action: 'set_status', data: { status: 'closed' } };
// @ts-expect-error QA decisions require the exact inspection identity.
const incomplete: QualityMutation = { action: 'decide', data: { decision: 'approved' } };
void [allowed, restricted, progress, bypass, setter, incomplete];
