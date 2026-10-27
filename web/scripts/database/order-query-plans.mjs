import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const test=JSON.parse(readFileSync('docs/database/phase-2-orders-test-results.json','utf8'));
if(!test.passed||!/^onit_phase2_\d+$/.test(test.database))throw Error('Passing disposable candidate required');
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:test.database,PGSSLMODE:'disable'};delete env.PGPASSWORD;
const queries={
 unassignedQueue:"select id,starts_at from private.service_orders where status='awaiting_dispatch' order by starts_at,id limit 25",
 providerOffers:"select id,proposal_id,status from private.assignment_offers where provider_id='d3000000-0000-0000-0000-000000000001' and status='pending' order by id limit 25",
 expiredOffers:"select id,order_id from private.dispatch_proposals where status in ('pending','ready') and expires_at<=clock_timestamp() order by expires_at,id limit 25",
 currentRank:"select id,score,provider_id,worker_id from private.dispatch_candidates where order_id=(select id from private.service_orders where status='awaiting_dispatch' order by id limit 1) and order_revision=1 order by score desc,provider_id,worker_id limit 25",
 orderHistory:"select id,action,created_at from private.order_history where order_id=(select id from private.service_orders order by id limit 1) order by created_at desc,id limit 25"
};
const plans={};
for(const [name,query] of Object.entries(queries)){
 const r=spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{env,input:'explain (analyze,buffers,format json) '+query,encoding:'utf8',windowsHide:true,timeout:15000});
 if(r.error||r.status!==0)throw Error('Local query-plan inspection failed');plans[name]=JSON.parse(r.stdout);
}
writeFileSync('docs/database/phase-2-order-query-plans.json',JSON.stringify({postgres:test.postgres,syntheticLocalOnly:true,limitation:'Small synthetic fixture plans; not a production volume benchmark or global matching optimality proof.',plans},null,2)+'\n');
console.log('Inspected five read-only local order/dispatch/history query plans.');
