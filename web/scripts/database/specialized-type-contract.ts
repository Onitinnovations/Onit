import type { Database } from '../../types/database.specialized.generated';
import type { LaundryMutation } from '../../lib/specialized/laundry';
import type { ConstructionMutation } from '../../lib/specialized/construction';
import type { ProcurementMutation } from '../../lib/specialized/procurement';
import type { FieldMutation } from '../../lib/specialized/field';

// Compile-only negative contracts: no client, session, identity or transaction is created.
const schema: keyof Database = 'public';
// @ts-expect-error Operational private schemas cannot enter client-capable generated types.
const privateSchema: keyof Database = 'private';
const acknowledgement: LaundryMutation = { action: 'custody.receive', data: { id: '', lines: [{ id: '', units: 1 }] } };
// @ts-expect-error Sender-only completion and arbitrary status assignment are not commands.
const custodyBypass: LaundryMutation = { action: 'set_status', data: { status: 'received' } };
// @ts-expect-error Commercial impact is an exact decimal string, never a JavaScript number.
const variation: ConstructionMutation = { action: 'variation.propose', data: { scope: {}, cost_impact: 50, time_impact_seconds: 0, evidence_id: '' } };
// @ts-expect-error Supplier responses require explicit exact prices and specified items.
const quote: ProcurementMutation = { action: 'quote.submit', data: { recipient_id: '', currency_id: '', valid_until: '', conditions: {}, lines: [{ item_id: '', quantity: '1', unit_price: 2 }] } };
// @ts-expect-error Field coordinates remain declared; no trusted GPS verification flag exists.
const gps: FieldMutation = { action: 'location.create', data: { task_id: '', reference: '', milestone: '', location: { declared_address: '', gps_verified: true } } };
void [schema, privateSchema, acknowledgement, custodyBypass, variation, quote, gps];
