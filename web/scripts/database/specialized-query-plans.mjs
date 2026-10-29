import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const report = JSON.parse(readFileSync('docs/database/phase-2-specialized-test-results.json', 'utf8'));
if (!report.passed || !/^onit_phase2_\d+$/.test(report.database)) throw Error('Passing disposable integrated candidate required');
const env = { ...process.env, PGHOST: '127.0.0.1', PGPORT: '55439', PGUSER: 'postgres', PGDATABASE: report.database, PGSSLMODE: 'disable' }; delete env.PGPASSWORD;
const queries = {
  operationQueue: "select id,kind,status from private.service_operations where kind='laundry' and status='active' order by id limit 25",
  custodyConservation: 'select item.id,item.units,sum(balance.units) from private.laundry_items item join private.laundry_custody_balances balance on balance.item_id=item.id group by item.id order by item.id limit 25',
  custodyExceptions: "select id,operation_id from private.laundry_custody_transfers where status='discrepant' order by id limit 25",
  milestoneHandover: 'select id,task_id from private.construction_milestones where customer_approved_at is null order by operation_id,id limit 25',
  supplierInvitations: 'select recipient.id,rfq.reference from private.procurement_rfq_recipients recipient join private.procurement_rfqs rfq on rfq.id=recipient.rfq_id where recipient.supplier_organisation_id=(select supplier_organisation_id from private.procurement_rfq_recipients order by id limit 1) order by recipient.id limit 25',
  actualReceipts: 'select line.id,line.accepted_quantity from private.procurement_receipt_lines line join private.procurement_receipts header on header.id=line.receipt_id where header.operation_id=(select id from private.service_operations where kind=\'procurement\' order by id limit 1) order by line.id limit 25',
  campaignReview: "select id,task_id from private.field_campaign_locations where status='submitted' order by operation_id,id limit 25",
  verifiedSupplierPerformance: 'select supplier_organisation_id,metric,sum(successful),sum(observations) from private.supplier_performance_observations group by supplier_organisation_id,metric',
};
const plans = {};
for (const [name, query] of Object.entries(queries)) {
  const domain=name.startsWith('custody')||name==='operationQueue'?'laundry':name.startsWith('milestone')?'construction':name==='campaignReview'?'field':'procurement';
  env.PGDATABASE=domain==='laundry'?report.laundryConcurrency.database:report.specializedConcurrency.databases[domain];
  const result = spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'], { env, input: 'explain (analyze,buffers,format json) ' + query, encoding: 'utf8', windowsHide: true, timeout: 15000 });
  if (result.error || result.status !== 0) throw Error('Local specialised plan inspection failed: ' + name);
  plans[name] = JSON.parse(result.stdout);
}
writeFileSync('docs/database/phase-2-specialized-query-plans.json', JSON.stringify({ postgres: report.postgres, syntheticLocalOnly: true, limitation: 'Small disposable fixture plans; no production-volume or latency certification.', plans }, null, 2) + '\n');
console.log('Inspected eight specialised operations EXPLAIN ANALYZE/BUFFERS plans.');
