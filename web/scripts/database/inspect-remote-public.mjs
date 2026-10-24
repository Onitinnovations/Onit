import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

// Run with node --env-file=.env.local. Only public configuration is used.
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if(!url || !anon) throw new Error('Public Supabase configuration is missing.');
const host=new URL(url);
if(host.protocol!=='https:') throw new Error('Remote inspection requires HTTPS.');
const report={
  projectHostname:host.hostname,
  method:'GET public REST OpenAPI only; no row queries or hosted SQL',
  inspectedAt:new Date().toISOString(),
  completeSchemaInspected:false,
  privateSchemaInspected:false,
  migrationHistoryInspected:false,
  productionOrTestData:'unknown; no table data queried',
};
try {
  const response=await fetch(new URL('/rest/v1/',host),{
    method:'GET',headers:{apikey:anon,Authorization:`Bearer ${anon}`,Accept:'application/openapi+json'},
    signal:AbortSignal.timeout(15000),
  });
  report.httpStatus=response.status;
  if(response.ok){
    const body=await response.json();
    report.visibleApiPaths=Object.keys(body.paths||{}).sort();
    report.note='Paths reflect anon-visible OpenAPI, not a complete database inventory or proof of emptiness.';
  } else report.note='Remote API did not allow public OpenAPI inspection; no schema findings inferred.';
}catch(error){
  report.note=`Remote read unavailable (${error.name}); no schema findings inferred.`;
}
const target=fileURLToPath(new URL('../../docs/database/remote-public-inventory.json',import.meta.url));
await writeFile(target,JSON.stringify(report,null,2)+'\n','utf8');
console.log(JSON.stringify(report,null,2));
