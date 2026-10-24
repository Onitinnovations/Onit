import { spawnSync,spawn } from 'node:child_process';
import { readFileSync,writeFileSync,existsSync,mkdirSync,readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../../',import.meta.url));
const ref='utoxjlsvqfmmzsjruzsm';
const tools=path.join(root,'.local-tools/postgres17/pgsql/bin');
const cluster=path.join(root,'.local-tools/postgres17/cluster');
const backupDir=path.join(root,'.local-tools/hosted-backup');
const cli=path.join(root,'node_modules/supabase/dist/supabase.js');
const runId=new Date().toISOString().replace(/\D/g,'').slice(0,14);
let archive=path.join(backupDir,`pre-phase1-${runId}.dump`);
const report={projectRef:ref,startedAt:new Date().toISOString(),backupVerified:false,migrationsValidated:[],tests:[]};
let remotePassword='';
function command(exe,args,options={}){
  const r=spawnSync(exe,args,{cwd:root,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:32*1024*1024,...options});
  if(r.error||r.status!==0){
    let message=r.error?.code||r.stderr||`exit ${r.status}`;
    if(remotePassword) message=message.replaceAll(remotePassword,'[REDACTED]');
    throw new Error(`${path.basename(exe)} failed: ${message.slice(0,1800)}`);
  }
  return r.stdout;
}
function official(args){return command(process.execPath,[cli,...args],{timeout:60000});}
function queryResult(sql){
  const raw=official(['db','query','--linked','--project-ref',ref,sql,'--output','json']);
  return JSON.parse(raw.slice(raw.indexOf('{'))).rows;
}
const localEnv={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:'postgres',PGSSLMODE:'disable'};
delete localEnv.PGPASSWORD;
function local(sql,database='postgres'){
  return command(path.join(tools,'psql.exe'),['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',database],{env:localEnv,input:sql});
}
function restore(database){
  command(path.join(tools,'createdb.exe'),['-T','template0',database],{env:localEnv});
  const list=command(path.join(tools,'pg_restore.exe'),['--list',archive]);
  const listPath=path.join(backupDir,`${database}-restore.list`);
  // A fresh PostgreSQL 17 database already contains public. Preserve it and
  // restore every other archive entry, including its privileges and contents.
  writeFileSync(listPath,list.split('\n').map(line=>/ SCHEMA - public /.test(line)?`;${line}`:line).join('\n'));
  command(path.join(tools,'pg_restore.exe'),['--exit-on-error','--no-owner','--use-list',listPath,'-d',database,archive],{env:localEnv});
}
try {
  if(!existsSync(path.join(tools,'pg_dump.exe'))) throw new Error('Run portable PostgreSQL setup first.');
  mkdirSync(backupDir,{recursive:true});
  report.nativeVersion=command(path.join(tools,'pg_dump.exe'),['--version']).trim();
  const projects=JSON.parse(official(['projects','list','--output','json']));
  const target=projects.find(p=>p.id===ref);
  if(!target||target.name!=='OnIt'||target.status!=='ACTIVE_HEALTHY') throw new Error('Project identity/health changed.');
  report.projectName=target.name;
  const [{baseline}]=queryResult(`begin read only; select jsonb_build_object('version',current_setting('server_version'),
    'auth_users',(select count(*) from auth.users),'storage_objects',(select count(*) from storage.objects),
    'buckets',(select count(*) from storage.buckets),'vault_secrets',(select count(*) from vault.secrets),
    'application_tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','app_private') and c.relkind in ('r','p','v','m')),
    'roles',(select jsonb_agg(jsonb_build_object('name',rolname,'bypassrls',rolbypassrls)) from pg_roles where rolname not like 'pg_%')) as baseline; rollback;`);
  if(!baseline.version.startsWith('17.')||baseline.auth_users||baseline.storage_objects||baseline.buckets||baseline.vault_secrets||baseline.application_tables)
    throw new Error('Baseline changed or contains data outside the approved empty-project recovery scope.');
  report.baseline={...baseline,roles:undefined};

  const previousPath=path.join(root,'.local-tools/native17-recovery-report.json');
  let reuse=false;
  if(existsSync(previousPath)){
    const previous=JSON.parse(readFileSync(previousPath,'utf8'));
    const previousArchive=path.resolve(root,previous.backupArchive||'.local-tools/missing');
    if(previous.projectRef===ref&&previousArchive.startsWith(backupDir+path.sep)&&existsSync(previousArchive)
      &&previous.backupSha256&&Date.now()-Date.parse(previous.startedAt)<3600000
      &&createHash('sha256').update(readFileSync(previousArchive)).digest('hex')===previous.backupSha256){
      archive=previousArchive;reuse=true;
    }
  }
  // The official CLI emits temporary libpq environment assignments for pg_dump.
  // Capture them only in memory: never execute the shell script or print/save it.
  if(!reuse){
  const script=official(['db','dump','--linked','--project-ref',ref,'--dry-run']);
  const env={...process.env,PGSSLMODE:'require',PGCONNECT_TIMEOUT:'20'};
  for(const name of ['PGHOST','PGPORT','PGUSER','PGPASSWORD','PGDATABASE']){
    const m=script.match(new RegExp('^(?:export\\s+)?'+name+'=(.*)$','m'));
    if(!m)throw new Error('Official backup environment assignment missing: '+name);
    let value=m[1].trim();
    if(value.startsWith('"')&&value.endsWith('"'))value=value.slice(1,-1).replace(/\\([\\$"`])/g,'$1');
    else if(value.startsWith("'")&&value.endsWith("'"))value=value.slice(1,-1).replaceAll("'\\''", "'");
    env[name]=value;
  }
  if(!/\.supabase\.(com|co)$/.test(env.PGHOST)||env.PGDATABASE!=='postgres')throw new Error('Unexpected official backup target.');
  remotePassword=env.PGPASSWORD;
  command(path.join(tools,'pg_dump.exe'),['--role=postgres','--format=custom','--no-owner','--schema=public','--schema=auth','--schema=storage','--schema=extensions','--file',archive],{env,timeout:180000});
  }
  report.backupSha256=createHash('sha256').update(readFileSync(archive)).digest('hex');
  report.backupBytes=readFileSync(archive).length;
  report.backupArchive=path.relative(root,archive).replaceAll('\\','/');
  const listing=command(path.join(tools,'pg_restore.exe'),['--list',archive]);
  if(!listing.includes('auth')||!listing.includes('storage'))throw new Error('Archive omits required baseline schemas.');
  console.log('Created native PostgreSQL 17 logical archive; restoring to isolated local databases.');
  if(!existsSync(path.join(cluster,'PG_VERSION')))
    command(path.join(tools,'initdb.exe'),['-D',cluster,'-U','postgres','-A','trust','--no-locale','-E','UTF8']);
  const status=spawnSync(path.join(tools,'pg_ctl.exe'),['-D',cluster,'status'],{encoding:'utf8',windowsHide:true});
  if(status.status!==0){
    const child=spawn(path.join(tools,'pg_ctl.exe'),['-D',cluster,'-l',path.join(cluster,'server.log'),'-o','-h 127.0.0.1 -p 55439','-w','start'],{
      cwd:root,windowsHide:true,detached:true,stdio:'ignore',
    });
    child.unref();
    let ready=false;
    for(let attempt=0;attempt<30;attempt++){
      const probe=spawnSync(path.join(tools,'pg_isready.exe'),['-h','127.0.0.1','-p','55439'],{windowsHide:true,stdio:'ignore',timeout:1000});
      if(probe.status===0){ready=true;break;}
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,500);
    }
    if(!ready)throw new Error('Isolated PostgreSQL server did not become ready; inspect the ignored server log.');
  }
  for(const role of baseline.roles){
    if(role.name==='postgres')continue;
    const q='"'+role.name.replaceAll('"','""')+'"';
    const present=local(`select count(*) from pg_roles where rolname='${role.name.replaceAll("'","''")}';`).trim();
    if(present==='0')local(`create role ${q} nologin ${role.bypassrls?'bypassrls':'nobypassrls'};`);
  }
  const restoreDb=`onit_restore_${runId}`;
  restore(restoreDb);
  const restored=JSON.parse(local(`select json_build_object('auth_users',(select count(*) from auth.users),
    'storage_objects',(select count(*) from storage.objects),'buckets',(select count(*) from storage.buckets));`,restoreDb).trim());
  if(restored.auth_users||restored.storage_objects||restored.buckets)throw new Error('Restored baseline counts mismatch.');
  report.backupVerified=true;
  report.restoredDatabase=restoreDb;
  console.log('PASS recovery: native archive restored without errors; baseline Auth/Storage counts match.');

  const validationDb=`onit_validate_${runId}`;
  restore(validationDb);
  report.validationDatabase=validationDb;
  for(const file of readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()){
    local(readFileSync(path.join(root,'supabase/migrations',file),'utf8'),validationDb);
    report.migrationsValidated.push(file);
    console.log('PASS native PostgreSQL 17 migration:',file);
  }
  const seed=readFileSync(path.join(root,'supabase/seed.sql'),'utf8');
  local(seed,validationDb);local(seed,validationDb);
  const fixture=readFileSync(path.join(root,'supabase/fixtures/catalogue-development.sql'),'utf8');
  for(const file of readdirSync(path.join(root,'supabase/tests')).filter(f=>f.endsWith('.sql')).sort()){
    const source=readFileSync(path.join(root,'supabase/tests',file),'utf8');
    local(source.replace('begin;',`begin;\n${fixture}`),validationDb);
    const assertions=(source.match(/select pg_temp\.assert_true\(/g)||[]).length;
    report.tests.push({file,assertions,passed:true});
    console.log(`PASS native PostgreSQL 17 ${file}: ${assertions} assertions`);
  }
  report.applicationTables=Number(local(`select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r';`,validationDb).trim());
  report.validationPassed=true;
}catch(error){
  report.error=error.message;
  console.error(error.message);
  process.exitCode=1;
}finally{
  report.completedAt=new Date().toISOString();
  mkdirSync(path.join(root,'.local-tools'),{recursive:true});
  writeFileSync(path.join(root,'.local-tools/native17-recovery-report.json'),JSON.stringify(report,null,2)+'\n');
  // Never persist the temporary CLI password/environment or dump script.
  remotePassword='';
}
