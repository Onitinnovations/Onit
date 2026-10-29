import {compareReleaseSignatures} from './compare-release-signatures.mjs';
// Non-mutating hosted verification and canonical type generation after approved deployment.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,readdirSync,renameSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
const ref='utoxjlsvqfmmzsjruzsm',cli='node_modules/supabase/dist/supabase.js';
function official(args){const r=spawnSync(process.execPath,[cli,...args],{encoding:'utf8',windowsHide:true,timeout:180000,maxBuffer:32*1024*1024});if(r.error||r.status!==0)throw Error('Official CLI verification command failed; inspect safely without debug logging.');return r.stdout;}
function query(sql){const file='.local-tools/increments5-6-postdeployment-readonly.sql';writeFileSync(file,"begin read only;set local timezone='UTC';\n"+sql+';rollback;');const raw=official(['db','query','--linked','--project-ref',ref,'--file',file,'--output','json']);return JSON.parse(raw.slice(raw.indexOf('{'))).rows;}
const before=JSON.parse(readFileSync('docs/database/phase-2-increments-5-6-predeployment.json','utf8'));
if(!before.passed||!before.backup.restoreVerified)throw Error('Verified recovery evidence required');
const tests=JSON.parse(readFileSync('docs/database/phase-2-specialized-test-results.json','utf8'));
for(const [file,hash] of Object.entries(tests.migrationHashes))if(createHash('sha256').update(readFileSync('supabase/migrations/'+file)).digest('hex')!==hash)throw Error('Candidate migration changed');
const report={projectRef:ref,verifiedAt:new Date().toISOString(),checks:[]};
try{
 report.catalog=query(`select jsonb_build_object('version',current_setting('server_version'),
 'tables',(select count(*) from pg_tables where schemaname in ('public','private')),
 'missing_rls',(select count(*) from pg_tables where schemaname in ('public','private') and not rowsecurity),
 'public_definers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),
 'unsafe_paths',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app_private' and p.prosecdef and not coalesce(p.proconfig @> array['search_path=""'],false)),
 'public_internal_execute',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where n.nspname='app_private' and a.grantee=0 and a.privilege_type='EXECUTE'),
 'anon_private',has_schema_privilege('anon','private','USAGE'),'user_private',has_schema_privilege('authenticated','private','USAGE'),
 'client_writes',(select count(*) from information_schema.role_table_grants where grantee in ('anon','authenticated') and table_schema='public' and table_name in ('service_requests','request_history','request_attachments','quotations','quotation_versions','quotation_line_items') and privilege_type<>'SELECT'),
 'worker_client_execute',has_function_privilege('authenticated','public.operational_event_worker(text,jsonb)','EXECUTE') or has_function_privilege('anon','public.operational_event_worker(text,jsonb)','EXECUTE'),
 'client_private_grants',(select count(*) from information_schema.role_table_grants where table_schema='private' and grantee in ('anon','authenticated')),
 'expiry_client_execute',has_function_privilege('authenticated','public.expire_dispatch_offers(integer)','EXECUTE') or has_function_privilege('anon','public.expire_dispatch_offers(integer)','EXECUTE'),
 'sla_client_execute',has_function_privilege('authenticated','public.process_execution_slas(integer)','EXECUTE') or has_function_privilege('anon','public.process_execution_slas(integer)','EXECUTE'),
 'anonymous_specialized_execute',has_function_privilege('anon','public.service_operation_command(uuid,text,jsonb,text)','EXECUTE') or has_function_privilege('anon','public.fulfilment_command(uuid,text,jsonb,text)','EXECUTE'),
 'anonymous_order_execute',has_function_privilege('anon','public.order_command(uuid,text,jsonb,text)','EXECUTE') or has_function_privilege('anon','public.dispatch_command(uuid,text,jsonb,text)','EXECUTE'),
 'schema_counts',(select jsonb_object_agg(s,n) from (select schemaname s,count(*) n from pg_tables where schemaname in ('public','private') group by schemaname) q),
 'new_operational_role_grants',(select count(*) from private.role_permissions rp join private.permissions p on p.id=rp.permission_id where p.code like 'fulfilment.%' or p.code like 'specialized.%' or p.code in('procurement.source','procurement.approve','supplier.portal')),
 'auth_users',(select count(*) from auth.users),
 'history',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit,'mime_types',allowed_mime_types) order by id) from storage.buckets)) as catalog`)[0].catalog;
 const c=report.catalog,versions=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort().map(f=>f.slice(0,14));
 if(c.tables!==180||c.missing_rls||c.public_definers||c.unsafe_paths||c.public_internal_execute||c.anon_private||c.user_private||c.client_writes||c.worker_client_execute||c.client_private_grants||c.expiry_client_execute||c.anonymous_order_execute||c.sla_client_execute||c.anonymous_specialized_execute||c.new_operational_role_grants||c.version!=='17.11'||!isDeepStrictEqual(c.history,versions)||!isDeepStrictEqual(c.buckets,before.inventory.storage_buckets))throw Error('Hosted catalog/security/history/storage verification failed');
 const signature=readFileSync('supabase/inspection/application_signature.sql','utf8');
 const localEnv={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:tests.database,PGSSLMODE:'disable'};delete localEnv.PGPASSWORD;
 const replay=spawnSync('.local-tools/postgres17/pgsql/bin/psql.exe',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{encoding:'utf8',windowsHide:true,env:localEnv,input:signature,maxBuffer:32*1024*1024});
 if(replay.status!==0||!compareReleaseSignatures(JSON.parse(replay.stdout),query(signature)[0].signature))throw Error('Deployed application definitions differ from tested candidate');
 report.catalogDefinitionMatch=true;
 const cutoff=before.snapshotAt??before.startedAt;
 const rowSql="select jsonb_object_agg(key,jsonb_build_object('count',count,'hash',hash)) as rows from ("+before.inventory.application_tables.map(({schema,name})=>{const cols=before.inventory.columns.filter(c=>c.schema===schema&&c.table===name).map(c=>'"'+c.name+'"').join(',');return `select '${schema}.${name}' key,count(*)::text count,md5(coalesce(string_agg(row_json,'' order by row_json collate "C"),'')) hash from (select to_jsonb(t)::text row_json from (select ${cols} from "${schema}"."${name}" where created_at<='${cutoff}'::timestamptz) t) s`;}).join(' union all ')+') q';
 report.originalRowsPreserved=isDeepStrictEqual(query(rowSql)[0].rows,before.baselineRows);
 if(!report.originalRowsPreserved)throw Error('Baseline row preservation verification failed');
 const env=readFileSync('.env.local','utf8');const value=name=>env.match(new RegExp('^'+name+'\\s*=\\s*(.*)$','m'))?.[1].trim().replace(/^['"]|['"]$/g,'');
 const url=value('NEXT_PUBLIC_SUPABASE_URL'),key=value('NEXT_PUBLIC_SUPABASE_ANON_KEY');
 if(url!==`https://${ref}.supabase.co`||!key)throw Error('Application target/key configuration unavailable');
 for(const [name,endpoint,schema,expected] of [
  ['Auth connection','/auth/v1/settings',null,[200]],['Catalogue connection','/rest/v1/service_areas?select=code,name',null,[200]],
  ['Anonymous requests denied','/rest/v1/service_requests?select=id',null,[401,403]],['Anonymous quotes denied','/rest/v1/quotation_versions?select=id',null,[401,403]],
  ['Private API denied','/rest/v1/roles?select=id','private',[406]],['Helper API denied','/rest/v1/roles?select=id','app_private',[406]],
  ['Anonymous Storage listing denied','/storage/v1/bucket',null,[200,401,403]],
 ]){const headers={apikey:key,Authorization:'Bearer '+key};if(schema)headers['Accept-Profile']=schema;const response=await fetch(url+endpoint,{headers,signal:AbortSignal.timeout(20000)});let passed=expected.includes(response.status);if(name==='Anonymous Storage listing denied'&&response.status===200){const body=await response.json();passed=Array.isArray(body)&&body.length===0;}report.checks.push({name,status:response.status,passed});if(!passed)throw Error('Hosted API check failed: '+name);}
 for(const [name,rpc,args] of [
 ['Anonymous order command denied','order_command',{p_order:'00000000-0000-0000-0000-000000000000',p_action:'release',p_data:{expected_revision:1,reason:'Anonymous permission probe'},p_key:'anonymous-permission-probe'}],
 ['Anonymous dispatch denied','dispatch_command',{p_order:'00000000-0000-0000-0000-000000000000',p_action:'confirm',p_data:{expected_revision:1,reason:'Anonymous permission probe'},p_key:'anonymous-permission-probe'}],
 ['Anonymous expiry worker denied','expire_dispatch_offers',{p_limit:1}],
 ['Anonymous execution denied','fulfilment_command',{p_work:'00000000-0000-0000-0000-000000000000',p_action:'close_work',p_data:{expected_revision:1,reason:'Anonymous permission probe'},p_key:'anonymous-permission-probe'}],
 ['Anonymous specialised command denied','service_operation_command',{p_operation:'00000000-0000-0000-0000-000000000000',p_action:'close',p_data:{expected_revision:1,reason:'Anonymous permission probe'},p_key:'anonymous-permission-probe'}],
 ['Anonymous SLA worker denied','process_execution_slas',{p_limit:1}],
 ]){const response=await fetch(url+'/rest/v1/rpc/'+rpc,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(20000)});const passed=[401,403,404].includes(response.status);report.checks.push({name,status:response.status,passed});if(!passed)throw Error('Protected anonymous RPC probe failed: '+name);}
 const types=official(['gen','types','typescript','--project-id',ref,'--schema','public']);if(!types.includes('export type Database')||!types.includes('create_service_order:')||!types.includes('expire_dispatch_offers:')||!types.includes('service_operation_command:')||!types.includes('create_work_order:'))throw Error('Canonical type output incomplete');writeFileSync('types/database.generated.ts.tmp',types);renameSync('types/database.generated.ts.tmp','types/database.generated.ts');report.canonicalTypes=true;
 report.authenticatedWorkflowTests='Not executed: no approved existing test identities; hosted synthetic accounts/transactions not created.';
 report.passed=true;console.log('PASS hosted 48 migrations, 180 RLS tables, security, preserved Phase 1 rows, anonymous HTTP checks and canonical types.');
}catch(e){report.error=e.message;console.error(e.message);process.exitCode=1;}
finally{writeFileSync('docs/database/phase-2-increments-5-6-hosted-verification.json',JSON.stringify(report,null,2)+'\n');}
