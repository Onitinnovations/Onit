import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
const test=JSON.parse(readFileSync('docs/database/phase-2-test-results.json','utf8'));
if(!test.passed||test.migrations.length!==17)throw Error('Verified 17-migration baseline required');
for(const [file,hash] of Object.entries(test.migrationHashes))if(createHash('sha256').update(readFileSync('supabase/migrations/'+file)).digest('hex')!==hash)throw Error('Deployed migration changed');
const sql=readFileSync('supabase/inspection/application_signature.sql','utf8');
const queryFile='.local-tools/operational-baseline-readonly.sql';writeFileSync(queryFile,'begin read only;'+sql+'rollback;');
function run(exe,args,options={}){const r=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:60000,maxBuffer:32*1024*1024,...options});if(r.error||r.status!==0)throw Error('Baseline inspection failed; no candidate authorised');return r.stdout;}
const raw=run(process.execPath,['node_modules/supabase/dist/supabase.js','db','query','--linked','--project-ref','utoxjlsvqfmmzsjruzsm','--file',queryFile,'--output','json']);
const remote=JSON.parse(raw.slice(raw.indexOf('{'))).rows[0].signature;
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:test.database,PGSSLMODE:'disable'};delete env.PGPASSWORD;
const local=JSON.parse(run('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{env,input:sql}).trim());
if(!isDeepStrictEqual(remote,local))throw Error('Hosted/local definition drift; stop before new migrations');
writeFileSync(queryFile,`begin read only;select jsonb_build_object(
 'private_anon',has_schema_privilege('anon','private','USAGE'),'private_auth',has_schema_privilege('authenticated','private','USAGE'),
 'public_definers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),
 'public_internal_execute',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where n.nspname='app_private' and a.grantee=0 and a.privilege_type='EXECUTE'),
 'tables',(select count(*) from pg_tables where schemaname in ('public','private')),
 'missing_rls',(select count(*) from pg_tables where schemaname in ('public','private') and not rowsecurity),
 'migrations',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations)
 ) as security;rollback;`);
const guardRaw=run(process.execPath,['node_modules/supabase/dist/supabase.js','db','query','--linked','--project-ref','utoxjlsvqfmmzsjruzsm','--file',queryFile,'--output','json']);
const security=JSON.parse(guardRaw.slice(guardRaw.indexOf('{'))).rows[0].security;
if(security.private_anon||security.private_auth||security.public_definers||security.public_internal_execute||security.missing_rls||security.tables!==93||!isDeepStrictEqual(security.migrations,test.migrations.map(file=>file.slice(0,14))))throw Error('Hosted baseline security/history drift; no deployment authorised');
const config=readFileSync('.env.local','utf8');const value=name=>config.match(new RegExp('^'+name+'\\s*=\\s*(.*)$','m'))?.[1].trim().replace(/^['"]|['"]$/g,'');
const url=value('NEXT_PUBLIC_SUPABASE_URL'),key=value('NEXT_PUBLIC_SUPABASE_ANON_KEY');
if(url!=='https://utoxjlsvqfmmzsjruzsm.supabase.co'||!key)throw Error('Configured application target mismatch');
const api=[];
for(const schema of ['private','app_private']){const response=await fetch(url+'/rest/v1/roles?select=id',{headers:{apikey:key,Authorization:'Bearer '+key,'Accept-Profile':schema},signal:AbortSignal.timeout(20000)});api.push({schema,status:response.status});if(response.status!==406)throw Error('Restricted schema API exposure changed');}
writeFileSync('docs/database/phase-2-operational-baseline.json',JSON.stringify({checkedAt:new Date().toISOString(),projectRef:'utoxjlsvqfmmzsjruzsm',migrations:17,tables:93,postgres:'17.11',definitionMatch:true,security,api,migrationHashes:test.migrationHashes,hostedWrites:false},null,2)+'\n');
console.log('PASS deployed migration hashes and complete application definition signature match PostgreSQL 17 baseline.');
