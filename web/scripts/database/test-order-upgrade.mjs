import {readFileSync,readdirSync} from 'node:fs';
import assert from 'node:assert/strict';

export function testOrderUpgrade({run,env,archive,listPath,maxMigration,expectedTables=126}){
 if(env.PGHOST!=='127.0.0.1')throw Error('Loopback upgrade rehearsal required');
 const database='onit_order_upgrade_'+Date.now();
 run('createdb',['-T','template0',database]);run('pg_restore',['--no-owner','--exit-on-error','--use-list',listPath,'-d',database,archive]);
 const sql=source=>run('psql',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',database],source).trim();
 const files=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')&&(!maxMigration||f<maxMigration)).sort();
 for(const file of files.filter(f=>f<'20261027000000'))sql(readFileSync('supabase/migrations/'+file,'utf8'));
 sql(readFileSync('supabase/seed.sql','utf8'));
 for(const file of ['003_service_transactions.sql','005_provider_network.sql','006_personnel_resources.sql']){
  const source=readFileSync('supabase/tests/'+file,'utf8').replace('begin;','begin;\n'+readFileSync('supabase/fixtures/catalogue-development.sql','utf8')).replace(/rollback;\s*$/,'commit;');sql(source);
 }
 sql(`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);end$$;
 select public.provider_reservation('d3000000-0000-0000-0000-000000000001','reserve',jsonb_build_object('service_version_id',(select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-personnel-work'),'zone_id',(select id from public.service_zones where code='synthetic-personnel-zone'),'worker_id','d1000000-0000-0000-0000-000000000001','units','10','start',now()+interval '1 day','end',now()+interval '25 hours','expires_at',now()+interval '1 hour','purpose_reference','SYNTHETIC-PRE-INCREMENT4-RESERVATION','reason','Synthetic live upgrade reservation'),'synthetic-increment4-upgrade');commit;`);
 const tables=['provider_profiles','provider_personnel','provider_capacity_reservations','provider_history','operational_events','operational_event_deliveries'];
 const digest=()=>tables.map(table=>sql(`select count(*)||':'||md5(coalesce(string_agg(row_json,'' order by row_json collate "C"),'')) from (select (to_jsonb(r)-'order_id'-'system_generated')::text row_json from private.${table} r) q`));
 const before=digest();for(const file of files.filter(f=>f>='20261027000000'))sql(readFileSync('supabase/migrations/'+file,'utf8'));
 assert.deepEqual(digest(),before,'Provider identities, resources, live reservations, history and outbox rows survive the upgrade');
 assert.equal(sql("select count(*) from private.provider_capacity_reservations where purpose_reference='SYNTHETIC-PRE-INCREMENT4-RESERVATION' and status='reserved' and worker_profile_id='d1000000-0000-0000-0000-000000000001'"),'1');
 const result=sql(`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);end$$;select public.provider_eligibility('d3000000-0000-0000-0000-000000000002',(select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-personnel-work'),(select id from public.service_zones where code='synthetic-personnel-zone'),now()+interval '1 day',now()+interval '25 hours','10','d1000000-0000-0000-0000-000000000001')->'reasons' @> '[{"code":"personnel_capacity_exceeded"}]';rollback;`);
 assert.equal(result,'t','A different business still cannot claim a pre-upgrade reserved human');
 assert.equal(sql("select count(*) from pg_tables where schemaname in ('public','private') and rowsecurity"),String(expectedTables));
 console.log('PASS Increment 3 upgrade: six provider/outbox tables preserved and active shared-human reservation retained.');
 return {passed:true,database,checks:4,preservedTables:tables,liveReservationsPreserved:1};
}
