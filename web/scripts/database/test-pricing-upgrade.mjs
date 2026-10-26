import { readFileSync,readdirSync } from 'node:fs';

/** Replay real Increment 1 fixtures before applying Increment 2. Local only. */
export function testPricingUpgrade({run,env,archive,listPath,maxMigration}) {
 if(env.PGHOST!=='127.0.0.1'||env.PGUSER!=='postgres')throw new Error('Upgrade replay requires isolated loopback PostgreSQL.');
 const database='onit_upgrade_'+Date.now();
 run('createdb',['-T','template0',database]);
 run('pg_restore',['--no-owner','--exit-on-error','--use-list',listPath,'-d',database,archive]);
 const files=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')&&(!maxMigration||f<maxMigration)).sort();
 const read=file=>readFileSync('supabase/migrations/'+file,'utf8');
 const first=files.filter(file=>file<'20261025000300');
 const added=files.filter(file=>file>='20261025000300');
 const seed=readFileSync('supabase/seed.sql','utf8');
 const fixture=readFileSync('supabase/fixtures/catalogue-development.sql','utf8');
 const tests=readFileSync('supabase/tests/003_service_transactions.sql','utf8').replace('begin;',`begin;\n${fixture}`).replace(/rollback;\s*$/,'commit;');
 const snapshot=`
 create temporary table before_versions as select id,to_jsonb(v) snapshot from public.quotation_versions v where status='accepted';
 create temporary table before_lines as select li.id,to_jsonb(li) snapshot from public.quotation_line_items li join before_versions v on v.id=li.quotation_version_id;
 create temporary table before_requests as select id,to_jsonb(r) snapshot from public.service_requests r;
 `;
 const verify=`
 grant select on before_versions to authenticated;
 set role authenticated;
 select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',false);
 select public.decide_quotation((select id from before_versions limit 1),'accept');
 reset role;
 do $$ begin
 if not exists(select 1 from before_versions) then raise exception 'Upgrade fixture contains no accepted quotations';end if;
 if exists(select 1 from before_versions b left join public.quotation_versions v on v.id=b.id where v.id is null or b.snapshot is distinct from to_jsonb(v)-'money_scale') then raise exception 'Accepted quotation changed during upgrade';end if;
 if exists(select 1 from before_lines b left join public.quotation_line_items li on li.id=b.id where li.id is null or b.snapshot is distinct from to_jsonb(li)-'money_scale') then raise exception 'Accepted line changed during upgrade';end if;
 if exists(select 1 from before_requests b left join public.service_requests r on r.id=b.id where r.id is null or b.snapshot is distinct from to_jsonb(r)) then raise exception 'Request changed during upgrade';end if;
 if exists(select 1 from public.quotation_versions v join before_versions b on b.id=v.id where v.money_scale<>2) then raise exception 'Historical scale changed';end if;
 if has_function_privilege('authenticated','app_private.decide_quotation_increment1(uuid,text)','EXECUTE') then raise exception 'Legacy bypass accessible';end if;
 end $$;
 select 'UPGRADE_OK:'||json_build_object('acceptedVersions',(select count(*) from before_versions),'acceptedLines',(select count(*) from before_lines),'requests',(select count(*) from before_requests),'checks',6)::text;
 `;
 const output=run('psql',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',database],first.map(read).join('\n')+'\n'+seed+'\n'+tests+'\n'+snapshot+added.map(read).join('\n')+'\n'+verify);
 const line=output.split(/\r?\n/).find(line=>line.startsWith('UPGRADE_OK:'));
 if(!line)throw new Error('Upgrade verification produced no result.');
 const result=JSON.parse(line.slice('UPGRADE_OK:'.length));
 console.log('PASS Increment 1 upgrade: accepted snapshots, lines, requests, currency scale and legacy permission preserved.');
 return {passed:true,database,...result};
}
