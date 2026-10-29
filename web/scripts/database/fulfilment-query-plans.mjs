import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const test=JSON.parse(readFileSync('docs/database/phase-2-fulfilment-test-results.json','utf8'));
if(!test.passed||!/^onit_phase2_\d+$/.test(test.database))throw Error('Passing disposable candidate required');
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:test.database,PGSSLMODE:'disable'};delete env.PGPASSWORD;
const queries={
 executionQueue:"select id,starts_at from private.work_orders where status='awaiting_mobilisation' order by starts_at,id limit 25",
 qualityQueue:"select id,task_id from private.quality_inspections where status='requested' order by scheduled_at,id limit 25",
 caseQueue:"select id,status from private.service_cases where status not in ('closed','resolved') order by id limit 25",
 slaQueue:"select id,order_id from private.sla_tracks where status='running' and due_at<=clock_timestamp() order by due_at,id limit 100",
 workHistory:"select id,action,created_at from private.execution_history where work_order_id=(select id from private.work_orders order by id limit 1) order by created_at desc,id limit 100"
};
const plans={};
for(const [name,query] of Object.entries(queries)){
 const r=spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{env,input:'explain (analyze,buffers,format json) '+query,encoding:'utf8',windowsHide:true,timeout:15000});
 if(r.error||r.status!==0)throw Error('Local query-plan inspection failed');plans[name]=JSON.parse(r.stdout);
}
writeFileSync('docs/database/phase-2-fulfilment-query-plans.json',JSON.stringify({postgres:test.postgres,syntheticLocalOnly:true,limitation:'Small synthetic fixture plans; not a production volume benchmark or global matching optimality proof.',plans},null,2)+'\n');
console.log('Inspected five read-only local fulfilment, QA, case, SLA and history query plans.');
