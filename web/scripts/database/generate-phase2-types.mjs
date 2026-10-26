import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { writeTypes } from './write-types.mjs';
import { createHash } from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
const report=JSON.parse(readFileSync('docs/database/phase-2-test-results.json','utf8'));
if(!report.passed||!report.postgres.startsWith('17.')||!/^onit_phase2_\d+$/.test(report.database))throw new Error('Successful native Phase 2 validation required.');
for(const file of report.migrations){
 if(createHash('sha256').update(readFileSync('supabase/migrations/'+file)).digest('hex')!==report.migrationHashes?.[file])throw new Error('Candidate changed since validation; rerun local tests before generating types.');
}
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:report.database,PGSSLMODE:'disable'};
delete env.PGPASSWORD;
const db={async query(sql,parameters=[]){
 // This adapter accepts only the numeric catalog OID parameters used by the generator.
 for(let i=parameters.length;i>0;i--){
  if(!Number.isInteger(parameters[i-1]))throw new Error('Non-numeric catalog parameter.');
  sql=sql.replaceAll('$'+i,String(parameters[i-1]));
 }
 const result=spawnSync(root+'/.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{
  env,input:`select coalesce(json_agg(to_jsonb(catalog_row)),'[]'::json) from (${sql}) catalog_row;`,encoding:'utf8',windowsHide:true,timeout:10000,
 });
 if(result.error||result.status!==0)throw new Error(result.stderr||'Catalog query failed.');
 return {rows:JSON.parse(result.stdout.trim())};
}};
await writeTypes(db,root,{source:'native PostgreSQL 17.11 Phase 2 candidate',filename:'database.phase2.generated.ts',command:'node scripts/database/generate-phase2-types.mjs'});
