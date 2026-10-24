import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, renameSync } from 'node:fs';

const ref='utoxjlsvqfmmzsjruzsm';
const cli='node_modules/supabase/dist/supabase.js';
function official(args){
  const result=spawnSync(process.execPath,[cli,...args],{encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:32*1024*1024});
  if(result.error||result.status!==0)throw new Error('Official CLI command failed; existing configuration preserved.');
  return result.stdout;
}
const raw=official(['db','query','--linked','--project-ref',ref,'--file','supabase/inspection/verify_phase1.sql','--output','json']);
const verification=JSON.parse(raw.slice(raw.indexOf('{'))).rows[0].verification;
if(verification.application_table_count!==79||verification.tables_without_rls.length||verification.unvalidated_constraints||verification.unsafe_definer_search_paths||verification.exposed_definers||verification.public_internal_function_exec||verification.disabled_guards||verification.migrations.length!==12
  ||verification.private_schema_usage.anon||verification.private_schema_usage.authenticated
  ||verification.roles!==7||verification.service_areas.length!==4
  ||verification.buckets.filter(bucket=>!bucket.public).length!==7)
  throw new Error('Hosted database verification failed.');
writeFileSync('docs/database/hosted-verification.json',JSON.stringify(verification,null,2)+'\n');
const types=official(['gen','types','typescript','--project-id',ref,'--schema','public']);
if(!types.includes('export type Database'))throw new Error('Hosted type generation returned invalid output.');
writeFileSync('types/database.generated.ts.tmp',types);
renameSync('types/database.generated.ts.tmp','types/database.generated.ts');

// API keys remain in memory. Only the public anon key may enter local public configuration.
const keysRaw=official(['projects','api-keys','--project-ref',ref,'--output','json']);
const keys=JSON.parse(keysRaw.slice(keysRaw.indexOf('[')));
const anon=keys.find(key=>key.name==='anon');
if(!anon?.api_key)throw new Error('Public anon key unavailable; no key values logged.');
const envPath='.env.local';
const env=readFileSync(envPath,'utf8');
if(!env.includes(`https://${ref}.supabase.co`))throw new Error('Application project differs from verified deployment.');
const line=/^NEXT_PUBLIC_SUPABASE_ANON_KEY\s*=.*$/m;
if(!line.test(env))throw new Error('Existing public key configuration not found.');
const updated=env.replace(line,`NEXT_PUBLIC_SUPABASE_ANON_KEY=${anon.api_key}`);
if(updated!==env)writeFileSync(envPath,updated);
const checks=[];
for(const [name,pathname,schema,expected] of [
  ['Auth settings','/auth/v1/settings',null,200],
  ['Public catalogue','/rest/v1/service_areas?select=code,name',null,200],
  ['Customer anonymous denial','/rest/v1/customer_profiles?select=id',null,[401,403]],
  ['Private schema unexposed','/rest/v1/roles?select=id','private',406],
  ['Helper schema unexposed','/rest/v1/roles?select=id','app_private',406],
]){
  const headers={apikey:anon.api_key,Authorization:`Bearer ${anon.api_key}`};
  if(schema)headers['Accept-Profile']=schema;
  const response=await fetch(`https://${ref}.supabase.co${pathname}`,{headers,signal:AbortSignal.timeout(20000)});
  const passed=Array.isArray(expected)?expected.includes(response.status):response.status===expected;
  checks.push({name,status:response.status,passed});
}
const report={projectRef:ref,verifiedAt:new Date().toISOString(),publicConfigurationUpdated:updated!==env,checks};
writeFileSync('docs/database/hosted-api-verification.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
if(checks.some(check=>!check.passed))throw new Error('One or more hosted API checks failed.');
console.log('PASS hosted catalog/security verification and official public TypeScript generation.');
