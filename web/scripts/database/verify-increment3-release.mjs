// Non-mutating hosted verification and canonical type generation after approved deployment.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,readdirSync,renameSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
const ref='utoxjlsvqfmmzsjruzsm',cli='node_modules/supabase/dist/supabase.js';
function official(args){const r=spawnSync(process.execPath,[cli,...args],{encoding:'utf8',windowsHide:true,timeout:180000,maxBuffer:32*1024*1024});if(r.error||r.status!==0)throw Error('Official CLI verification command failed; inspect safely without debug logging.');return r.stdout;}
function query(sql){const file='.local-tools/increment3-postdeployment-readonly.sql';writeFileSync(file,"begin read only;set local timezone='UTC';\n"+sql+';rollback;');const raw=official(['db','query','--linked','--project-ref',ref,'--file',file,'--output','json']);return JSON.parse(raw.slice(raw.indexOf('{'))).rows;}
const before=JSON.parse(readFileSync('docs/database/phase-2-increment-3-predeployment.json','utf8'));
if(!before.passed||!before.backup.restoreVerified)throw Error('Verified recovery evidence required');
const tests=JSON.parse(readFileSync('docs/database/phase-2-operations-test-results.json','utf8'));
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
 'auth_users',(select count(*) from auth.users),
 'history',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit,'mime_types',allowed_mime_types) order by id) from storage.buckets)) as catalog`)[0].catalog;
 const c=report.catalog,versions=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort().map(f=>f.slice(0,14));
 if(c.tables!==115||c.missing_rls||c.public_definers||c.unsafe_paths||c.public_internal_execute||c.anon_private||c.user_private||c.client_writes||c.worker_client_execute||!isDeepStrictEqual(c.history,versions)||!isDeepStrictEqual(c.buckets,before.inventory.storage_buckets))throw Error('Hosted catalog/security/history/storage verification failed');
 const cutoff=before.startedAt;
 const rowSql="select jsonb_object_agg(key,jsonb_build_object('count',count,'hash',hash)) as rows from ("+before.inventory.application_tables.map(({schema,name})=>{const cols=before.inventory.columns.filter(c=>c.schema===schema&&c.table===name).map(c=>'"'+c.name+'"').join(',');return `select '${schema}.${name}' key,count(*)::text count,md5(coalesce(string_agg(row_json,'' order by row_json collate "C"),'')) hash from (select to_jsonb(t)::text row_json from (select ${cols} from "${schema}"."${name}" where created_at<='${cutoff}'::timestamptz) t) s`;}).join(' union all ')+') q';
 report.originalRowsPreserved=isDeepStrictEqual(query(rowSql)[0].rows,before.phase1Rows);
 if(!report.originalRowsPreserved)throw Error('Phase 1 row preservation verification failed');
 const env=readFileSync('.env.local','utf8');const value=name=>env.match(new RegExp('^'+name+'\\s*=\\s*(.*)$','m'))?.[1].trim().replace(/^['"]|['"]$/g,'');
 const url=value('NEXT_PUBLIC_SUPABASE_URL'),key=value('NEXT_PUBLIC_SUPABASE_ANON_KEY');
 if(url!==`https://${ref}.supabase.co`||!key)throw Error('Application target/key configuration unavailable');
 for(const [name,endpoint,schema,expected] of [
  ['Auth connection','/auth/v1/settings',null,[200]],['Catalogue connection','/rest/v1/service_areas?select=code,name',null,[200]],
  ['Anonymous requests denied','/rest/v1/service_requests?select=id',null,[401,403]],['Anonymous quotes denied','/rest/v1/quotation_versions?select=id',null,[401,403]],
  ['Private API denied','/rest/v1/roles?select=id','private',[406]],['Helper API denied','/rest/v1/roles?select=id','app_private',[406]],
  ['Anonymous Storage listing denied','/storage/v1/bucket',null,[200,401,403]],
 ]){const headers={apikey:key,Authorization:'Bearer '+key};if(schema)headers['Accept-Profile']=schema;const response=await fetch(url+endpoint,{headers,signal:AbortSignal.timeout(20000)});let passed=expected.includes(response.status);if(name==='Anonymous Storage listing denied'&&response.status===200){const body=await response.json();passed=Array.isArray(body)&&body.length===0;}report.checks.push({name,status:response.status,passed});if(!passed)throw Error('Hosted API check failed: '+name);}
 const types=official(['gen','types','typescript','--project-id',ref,'--schema','public']);if(!types.includes('export type Database')||!types.includes('personnel_command:'))throw Error('Canonical type output incomplete');writeFileSync('types/database.generated.ts.tmp',types);renameSync('types/database.generated.ts.tmp','types/database.generated.ts');report.canonicalTypes=true;
 report.authenticatedWorkflowTests='Not executed: no approved existing test identities; hosted synthetic accounts/transactions not created.';
 report.passed=true;console.log('PASS hosted 22 migrations, 115 RLS tables, security, preserved Phase 1 rows, anonymous HTTP checks and canonical types.');
}catch(e){report.error=e.message;console.error(e.message);process.exitCode=1;}
finally{writeFileSync('docs/database/phase-2-increment-3-hosted-verification.json',JSON.stringify(report,null,2)+'\n');}

