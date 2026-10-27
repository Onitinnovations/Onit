import type { Database } from '../../types/database.orders.generated';
import type { orderOperations } from '../../lib/orders/server';
declare const operations: ReturnType<typeof orderOperations>;
// @ts-expect-error Restricted operational tables are absent from public API types.
type PrivateOrders = Database['private'];
void (undefined as unknown as PrivateOrders);
// @ts-expect-error No arbitrary order status command exists.
void operations.change('id', 1, { action: 'set_status', data: { status: 'assigned' } }, 'reason', 'receipt-key');
// @ts-expect-error Operational demand must cross the API as an exact decimal string.
void operations.match('id', [{ provider_id: 'id', worker_id: 'id', units: 1 }]);
// @ts-expect-error Customers cannot choose a provider during commercial order creation.
void operations.create({ quotation_version_id: 'id', zone_id: 'id', start: '', end: '', provider_id: 'id' }, 'reason', 'receipt-key');
// @ts-expect-error There is no payment callback or settlement operation.
void operations.confirmPayment('id');
