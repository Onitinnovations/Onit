import { spawn,spawnSync } from 'node:child_process';
import { readFileSync,writeFileSync,readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const bin=path.join(root,'.local-tools/postgres17/pgsql/bin');
const cluster=path.join(root,'.local-tools/postgres17/cluster');
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:'postgres',PGSSLMODE:'disable'};
delete env.PGPASSWORD;
const report={startedAt:new Date().toISOString(),migrations:[],migrationHashes:{},tests:[],hostedWrites:false,checkpoint:'orders-dispatch'};
function run(tool,args,input){
 const result=spawnSync(path.join(bin,tool+'.exe'),args,{env,input,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:32*1024*1024});
 if(result.error||result.status!==0)throw new Error(result.error?.message||result.stderr);
 return result.stdout;
}
const database='onit_phase2_'+Date.now();
function sql(source){return run('psql',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',database],source);}
try{
 if(spawnSync(path.join(bin,'pg_isready.exe'),['-h','127.0.0.1','-p','55439'],{windowsHide:true,stdio:'ignore'}).status!==0){
  const child=spawn(path.join(bin,'pg_ctl.exe'),['-D',cluster,'-l',path.join(cluster,'server.log'),'-o','-h 127.0.0.1 -p 55439','-w','start'],{windowsHide:true,detached:true,stdio:'ignore'});child.unref();
  for(let i=0;i<40;i++){
   if(spawnSync(path.join(bin,'pg_isready.exe'),['-h','127.0.0.1','-p','55439'],{windowsHide:true,stdio:'ignore'}).status===0)break;
   await new Promise(resolve=>setTimeout(resolve,250));
  }
 }
 let acceptingQueries=false;
 for(let attempt=0;attempt<600;attempt++){
  const probe=spawnSync(path.join(bin,'psql.exe'),['-X','-q','-t','-A','-c','select 1'],{env,windowsHide:true,encoding:'utf8',timeout:2000});
  if(probe.status===0&&probe.stdout.trim()==='1'){acceptingQueries=true;break;}
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 if(!acceptingQueries)throw new Error('Local PostgreSQL is not accepting queries; no migration attempted.');
 report.postgres=run('psql',['-X','-t','-A','-c','show server_version']).trim();
 if(!report.postgres.startsWith('17.'))throw new Error('PostgreSQL 17 required.');
 const recovery=JSON.parse(readFileSync('.local-tools/native17-recovery-report.json','utf8'));
 const archive=path.resolve(root,recovery.backupArchive);
 const {createHash}=await import('node:crypto');
 if(!recovery.backupVerified||createHash('sha256').update(readFileSync(archive)).digest('hex')!==recovery.backupSha256)throw new Error('Verified baseline archive is missing or changed.');
 const list=run('pg_restore',['--list',archive]).split('\n').map(line=>/ SCHEMA - public /.test(line)?';'+line:line).join('\n');
 const listPath=path.join(root,'.local-tools',database+'.list');writeFileSync(listPath,list);
 run('createdb',['-T','template0',database]);
 run('pg_restore',['--no-owner','--exit-on-error','--use-list',listPath,'-d',database,archive]);
 report.database=database;
 for(const entry of readFileSync('docs/database/phase-2-operations-candidate.sha256','utf8').trim().split(/\r?\n/)){const [hash,file]=entry.split(/\s+/,2);if(createHash('sha256').update(readFileSync(file)).digest('hex')!==hash)throw Error('Increment 3 deployed migration changed');}
 // Verify previously deployed migration bytes before replaying the candidate.
 for(const entry of readFileSync('docs/database/deployment-candidate.sha256','utf8').trim().split(/\r?\n/)){
  const [hash,file]=entry.split(/\s+/,2);
  if(createHash('sha256').update(readFileSync(file)).digest('hex')!==hash)throw new Error('Phase 1 candidate changed: '+file);
 }
 for(const entry of readFileSync('docs/database/phase-2-candidate.sha256','utf8').trim().split(/\r?\n/)){
  const [hash,file]=entry.split(/\s+/,2);
  if(createHash('sha256').update(readFileSync(file)).digest('hex')!==hash)throw new Error('Deployed Increment 1/2 migration changed: '+file);
 }
 for(const file of readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort()){
  const contents=readFileSync('supabase/migrations/'+file);
  report.migrationHashes[file]=createHash('sha256').update(contents).digest('hex');
  sql(contents.toString('utf8'));report.migrations.push(file);console.log('PASS migration',file);
 }
 const seed=readFileSync('supabase/seed.sql','utf8');sql(seed);sql(seed);
 report.security=JSON.parse(sql(`select json_build_object(
 'tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r'),
 'tables_without_rls',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity),
 'public_definers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),
 'unsafe_search_paths',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app_private' and p.prosecdef and not coalesce(p.proconfig @> array['search_path=""'],false)),
 'public_internal_execute',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where n.nspname='app_private' and a.grantee=0 and a.privilege_type='EXECUTE'),
 'private_anon_usage',has_schema_privilege('anon','private','USAGE'),
 'private_authenticated_usage',has_schema_privilege('authenticated','private','USAGE'),
 'client_worker_execute',has_function_privilege('authenticated','public.operational_event_worker(text,jsonb)','EXECUTE') or has_function_privilege('anon','public.operational_event_worker(text,jsonb)','EXECUTE'),
 'client_expiry_execute',has_function_privilege('authenticated','public.expire_dispatch_offers(integer)','EXECUTE') or has_function_privilege('anon','public.expire_dispatch_offers(integer)','EXECUTE'),
 'anonymous_provider_execute',has_function_privilege('anon','public.provider_command(uuid,text,jsonb,text)','EXECUTE'),
 'client_transaction_writes',(select count(*) from information_schema.role_table_grants where grantee in ('anon','authenticated') and table_schema='public' and table_name in ('service_requests','request_history','request_attachments','quotations','quotation_versions','quotation_line_items') and privilege_type<>'SELECT')
 );`).trim());
 const security=report.security;
 if(security.tables!==126||security.tables_without_rls||security.public_definers||security.unsafe_search_paths||security.public_internal_execute||security.private_anon_usage||security.private_authenticated_usage||security.client_transaction_writes||security.client_worker_execute||security.anonymous_provider_execute||security.client_expiry_execute)throw new Error('Candidate catalog security gate failed.');
 console.log('PASS candidate catalog: 126 RLS tables; private schemas, definers and client write grants secured.');
 const fixture=readFileSync('supabase/fixtures/catalogue-development.sql','utf8');
 for(const file of readdirSync('supabase/tests').filter(f=>f.endsWith('.sql')).sort()){
  let source=readFileSync('supabase/tests/'+file,'utf8');
  // Keep the final synthetic fixture only in this newly-created local database
  // so separate connections can exercise real locking after SQL assertions.
  if(['003_service_transactions.sql','005_provider_network.sql','006_personnel_resources.sql','007_orders_dispatch.sql'].includes(file))source=source.replace(/rollback;\s*$/,'commit;');
  sql(source.replace('begin;',`begin;\n${fixture}`));
  const assertions=(source.match(/select pg_temp\.assert_true\(/g)||[]).length;
  report.tests.push({file,assertions,passed:true});console.log('PASS',file,assertions,'assertions');
 }
 const {testRequestConcurrency}=await import('./test-request-concurrency.mjs');
 report.concurrency=await testRequestConcurrency({bin,env,database});
 const {testProviderConcurrency}=await import('./test-provider-concurrency.mjs');
 report.providerConcurrency=await testProviderConcurrency({bin,env,database,sql});
 const {testOrderConcurrency}=await import('./test-order-concurrency.mjs');
 report.orderConcurrency=await testOrderConcurrency({bin,env,database,sql});
 const {testPricingUpgrade}=await import('./test-pricing-upgrade.mjs');
 report.upgrade=testPricingUpgrade({run,env,archive,listPath});
 const {testOrderUpgrade}=await import('./test-order-upgrade.mjs');
 report.providerUpgrade=testOrderUpgrade({run,env,archive,listPath});
 for(const [file,hash] of Object.entries(report.migrationHashes))if(createHash('sha256').update(readFileSync('supabase/migrations/'+file)).digest('hex')!==hash)throw Error('Candidate changed during validation; rerun the exact final files.');
 report.passed=true;
 writeFileSync('docs/database/phase-2-orders-candidate.sha256',Object.entries(report.migrationHashes).map(([file,hash])=>`${hash}  supabase/migrations/${file}`).join('\n')+'\n');
}catch(error){report.error=error.message;console.error(error.message);process.exitCode=1;}
finally{report.completedAt=new Date().toISOString();writeFileSync('docs/database/phase-2-orders-test-results.json',JSON.stringify(report,null,2)+'\n');}
