import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const test=JSON.parse(readFileSync('docs/database/phase-2-operations-test-results.json','utf8'));
if(!test.passed||!/^onit_phase2_\d+$/.test(test.database))throw Error('Passing disposable candidate required');
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:test.database,PGSSLMODE:'disable'};delete env.PGPASSWORD;
const queries={
 providerPage:"select id,provider_type,status from private.provider_profiles where status='active' order by id limit 25",
 qualifications:"select id from private.provider_qualifications where provider_id=(select id from private.provider_profiles where individual_profile_id='c1000000-0000-0000-0000-000000000001') and kind='verification' and code='identity' and status='approved' and valid_from<=now() and (valid_until is null or valid_until>now())",
 overlappingCapacity:"select id,units from private.provider_capacity_reservations where pool_id=(select c.id from private.provider_capacity c join private.provider_profiles p on p.id=c.provider_id where p.individual_profile_id='c1000000-0000-0000-0000-000000000001' and c.unit='concurrent_jobs') and status in ('reserved','assigned') and starts_at<now()+interval '25 hours' and ends_at>now()+interval '24 hours'",
 overlappingHumanCapacity:"select id,worker_units from private.provider_capacity_reservations where worker_profile_id='d1000000-0000-0000-0000-000000000001' and status in ('reserved','assigned') and starts_at<now()+interval '25 hours' and ends_at>now()+interval '24 hours'",
 pendingEvents:"select id from private.operational_event_deliveries where (status='pending' and available_at<=now()) or (status='leased' and lease_until<=now()) order by available_at,id limit 10"
};
const plans={};
for(const [name,query] of Object.entries(queries)){
 const r=spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{env,input:'explain (analyze,buffers,format json) '+query,encoding:'utf8',windowsHide:true,timeout:15000});
 if(r.error||r.status!==0)throw Error('Local query-plan inspection failed');plans[name]=JSON.parse(r.stdout);
}
writeFileSync('docs/database/phase-2-provider-query-plans.json',JSON.stringify({postgres:test.postgres,syntheticLocalOnly:true,limitation:'Small synthetic fixture plans; not a production volume benchmark or matching-engine validation.',plans},null,2)+'\n');
console.log('Inspected five read-only local provider/personnel/capacity/outbox query plans.');
