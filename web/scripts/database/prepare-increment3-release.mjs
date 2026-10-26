// Read-only hosted inspection and logical recovery rehearsal. Never applies hosted SQL.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import path from 'node:path';
const ref='utoxjlsvqfmmzsjruzsm';
const bin=path.resolve('.local-tools/postgres17/pgsql/bin');
const cli=path.resolve('node_modules/supabase/dist/supabase.js');
const out=process.argv[2];
if(!out||!path.isAbsolute(out))throw Error('Provide an absolute secure backup directory outside the Git repository.');
const gitRoot=path.resolve('..'); if(path.resolve(out)===gitRoot||path.resolve(out).startsWith(gitRoot+path.sep))throw Error('Backup must be outside Git repository');
const id=Date.now(),report={projectRef:ref,startedAt:new Date().toISOString(),hostedWrites:false};
let secret='';
function run(exe,args,options={}){const r=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:180000,maxBuffer:64*1024*1024,...options});if(r.error||r.status!==0)throw Error((r.error?.message||r.stderr||'Command failed').replaceAll(secret||'__NO_SECRET__','[REDACTED]').slice(0,1500));return r.stdout;}
function official(args){return run(process.execPath,[cli,...args]);}
function remote(sql){const file=path.resolve('.local-tools/increment3-release-readonly.sql');writeFileSync(file,"set timezone='UTC';\n"+sql);const raw=official(['db','query','--linked','--project-ref',ref,'--file',file,'--output','json']);return JSON.parse(raw.slice(raw.indexOf('{'))).rows;}
const env={...process.env,PGHOST:'127.0.0.1',PGPORT:'55439',PGUSER:'postgres',PGDATABASE:'postgres',PGSSLMODE:'disable',PGOPTIONS:'-c timezone=UTC'};delete env.PGPASSWORD;
function local(sql,db){return run(path.join(bin,'psql.exe'),['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',db],{env,input:sql}).trim();}
const digest=`select coalesce(jsonb_object_agg(schema_name||'.'||table_name,stats),'{}') as digest from (select n.nspname schema_name,c.relname table_name, jsonb_build_object('rls',c.relrowsecurity) stats from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r') t`;
const signature=`select jsonb_build_object(
 'columns',(select jsonb_agg(row(schemaname,tablename,attname,typ,required,def)::text order by schemaname,tablename,num) from (select n.nspname schemaname,c.relname tablename,a.attname,format_type(a.atttypid,a.atttypmod) typ,a.attnotnull required,pg_get_expr(d.adbin,d.adrelid) def,a.attnum num from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname in ('public','private') and c.relkind='r' and a.attnum>0 and not a.attisdropped) q),
 'constraints',(select jsonb_agg(row(n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid))::text order by n.nspname,c.relname,k.conname) from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private')),
 'indexes',(select jsonb_agg(indexdef order by schemaname,indexname) from pg_indexes where schemaname in ('public','private')),
 'policies',(select jsonb_agg(row(schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check)::text order by schemaname,tablename,policyname) from pg_policies where schemaname in ('public','private','storage')),
 'functions',(select jsonb_agg(pg_get_functiondef(p.oid) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','app_private') and p.prokind='f'),
 'triggers',(select jsonb_agg(pg_get_triggerdef(t.oid) order by n.nspname,c.relname,t.tgname) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and (n.nspname in ('public','private') or (n.nspname='auth' and t.tgname like '%profile%')))) as signature`;
try{
 const projects=JSON.parse(official(['projects','list','--output','json']));const project=projects.find(p=>p.id===ref);
 if(project?.name!=='OnIt'||project.status!=='ACTIVE_HEALTHY')throw Error('Target identity/health mismatch');
 report.project={ref,name:project.name,status:project.status};
 report.version=remote("select current_setting('server_version') as version")[0].version;
 report.history=remote('select version,name from supabase_migrations.schema_migrations order by version');
 const files=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort();
 if(files.length!==22||report.history.length!==17||report.history.some((h,i)=>h.version!==files[i].slice(0,14)))throw Error('Migration history mismatch');
 if(!report.version.startsWith('17.'))throw Error('PostgreSQL major mismatch');
 report.inventory=remote(readFileSync('supabase/inspection/predeployment_catalog.sql','utf8'))[0].inventory;
 if(report.inventory.application_tables.length!==93)throw Error('Unexpected baseline tables');
 report.security=remote("select has_schema_privilege('anon','private','USAGE') as anon_private,has_schema_privilege('authenticated','private','USAGE') as user_private,(select count(*) from pg_tables where schemaname in ('public','private') and not rowsecurity) as missing_rls")[0];
 if(report.security.anon_private||report.security.user_private||report.security.missing_rls)throw Error('Baseline security gate failed');
 const remoteSignature=remote(signature)[0].signature;
 mkdirSync(out,{recursive:true});
 const script=official(['db','dump','--linked','--project-ref',ref,'--dry-run']);
 const remoteEnv={...process.env,PGSSLMODE:'require',PGCONNECT_TIMEOUT:'20'};
 for(const key of ['PGHOST','PGPORT','PGUSER','PGPASSWORD','PGDATABASE']){const match=script.match(new RegExp('^(?:export\\s+)?'+key+'=(.*)$','m'));if(!match)throw Error('Missing backup connection environment');let value=match[1].trim();if(value.startsWith('"')&&value.endsWith('"'))value=value.slice(1,-1).replace(/\\([\\$"`])/g,'$1');else if(value.startsWith("'")&&value.endsWith("'"))value=value.slice(1,-1).replaceAll("'\\''","'");remoteEnv[key]=value;}
 secret=remoteEnv.PGPASSWORD;
 if(!/\.supabase\.(com|co)$/.test(remoteEnv.PGHOST)||remoteEnv.PGDATABASE!=='postgres')throw Error('Unexpected backup connection target');
 const archive=path.join(out,`pre-increment3-${id}.dump`);
 const schemas=['public','private','app_private','auth','storage','extensions','supabase_migrations'];
 run(path.join(bin,'pg_dump.exe'),['--role=postgres','--format=custom','--no-owner',...schemas.map(s=>'--schema='+s),'--file',archive],{env:remoteEnv});
 report.backup={archive,sha256:createHash('sha256').update(readFileSync(archive)).digest('hex'),bytes:readFileSync(archive).length,schemas,scope:'Logical database schemas and rows; excludes Storage binaries, global roles, Vault, platform settings and managed PITR.'};
 function restore(db,file){run(path.join(bin,'createdb.exe'),['-T','template0',db],{env});const toc=run(path.join(bin,'pg_restore.exe'),['--list',file]).split('\n').map(l=>/ SCHEMA - public /.test(l)?';'+l:l).join('\n');const list=path.join(out,db+'.list');writeFileSync(list,toc);run(path.join(bin,'pg_restore.exe'),['--exit-on-error','--no-owner','--use-list',list,'-d',db,file],{env});}
 const restored='onit_release_restore_'+id;restore(restored,archive);
 if(!isDeepStrictEqual(JSON.parse(local(signature,restored)),remoteSignature))throw Error('Backup restored catalog differs from hosted catalog');
 report.backup.restoreVerified=true;
 const original=JSON.parse(readFileSync('.local-tools/native17-recovery-report.json','utf8'));
 const baseline='onit_release_baseline_'+id;restore(baseline,path.resolve(original.backupArchive));
 for(const file of files.slice(0,17))local(readFileSync('supabase/migrations/'+file,'utf8'),baseline);
 local(readFileSync('supabase/seed.sql','utf8'),baseline);
 if(local(signature,baseline)!==local(signature,restored))throw Error('Hosted schema drift detected against replayed deployed 17-migration baseline');
 report.drift='No application definition drift against replayed deployed 17-migration baseline';
 report.phase1Rows={};
 const rowSql="select jsonb_object_agg(key,jsonb_build_object('count',count,'hash',hash)) as rows from ("+report.inventory.application_tables.map(({schema,name})=>`select '${schema}.${name}' as key,count(*)::text as count,md5(coalesce(string_agg(row_json,'' order by row_json collate "C"),'')) as hash from (select to_jsonb(t)::text row_json from "${schema}"."${name}" t) s`).join(' union all ')+') q';
 report.phase1Rows=remote(rowSql)[0].rows;
 if(!isDeepStrictEqual(JSON.parse(local(rowSql,restored)),report.phase1Rows))throw Error('Backup row verification failed');
 for(const file of files.slice(17))local(readFileSync('supabase/migrations/'+file,'utf8'),restored);
 report.upgrade=JSON.parse(local(digest,restored));if(Object.keys(report.upgrade).length!==115||Object.values(report.upgrade).some(v=>!v.rls))throw Error('Restored upgrade security gate failed');
 report.passed=true;console.log('PASS hosted identity/history/security, logical backup restore and row verification, deployed 17-migration baseline drift comparison and five-migration restored upgrade.');
}catch(e){report.error=e.message;console.error(e.message);process.exitCode=1;}
finally{writeFileSync('docs/database/phase-2-increment-3-predeployment.json',JSON.stringify(report,null,2)+'\n');}
