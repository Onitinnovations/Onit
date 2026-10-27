import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {compareReleaseSignatures,weekdaysNested,weekdaysFlat} from './compare-release-signatures.mjs';

assert.ok(compareReleaseSignatures({constraints:[weekdaysNested]},{constraints:[weekdaysFlat]}));
assert.equal(compareReleaseSignatures({constraints:[weekdaysNested]},{constraints:[weekdaysFlat.replace('<= 7','<= 8')]}),false);
assert.equal(compareReleaseSignatures({constraints:[weekdaysNested],indexes:['original']},{constraints:[weekdaysFlat],indexes:['changed']}),false);
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:'postgres',PGSSLMODE:'disable'};delete env.PGPASSWORD;
const query=`with samples as (
 select array_fill(v,ARRAY[n])::smallint[] weekdays from generate_series(0,9) n cross join unnest(ARRAY[null,-1,0,1,2,3,4,5,6,7,8]::smallint[]) v
 union all select null::smallint[] union all select ARRAY[1,2,3,4,5,6,7]::smallint[] union all select ARRAY[1,null,7]::smallint[]
) select json_build_object('cases',count(*),'equivalent',bool_and(
 (((cardinality(weekdays)>=1 AND cardinality(weekdays)<=7) AND weekdays<@ARRAY[1,2,3,4,5,6,7]::smallint[]) IS NOT DISTINCT FROM
 (cardinality(weekdays)>=1 AND cardinality(weekdays)<=7 AND weekdays<@ARRAY[1,2,3,4,5,6,7]::smallint[])))) from samples`;
const result=spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{env,input:query,encoding:'utf8',windowsHide:true});
assert.equal(result.status,0,result.stderr);const truth=JSON.parse(result.stdout);assert.equal(truth.equivalent,true);
writeFileSync('docs/database/phase-2-increment-4-recovery-comparison.json',JSON.stringify({checkedAt:new Date().toISOString(),initialRestoreComparison:'Failed raw text comparison: one equivalent CHECK constraint has nested versus flat AND after pg_dump/restore.',normalization:'Only the two exact known provider_work_schedules_weekdays_check strings are equivalent; every other definition remains compared exactly.',nested:weekdaysNested,flat:weekdaysFlat,negativeGuards:2,truthTable:truth,passed:true},null,2)+'\n');
console.log(`PASS exact known CHECK equivalence, two negative guards and ${truth.cases} local PostgreSQL truth-table cases.`);
