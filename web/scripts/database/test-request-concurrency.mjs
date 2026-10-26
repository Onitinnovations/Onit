import { spawn,spawnSync } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert/strict';

export async function testRequestConcurrency({bin,env,database}) {
 if(env.PGHOST!=='127.0.0.1'||!/^onit_phase2_\d+$/.test(database))throw new Error('Concurrency fixtures require the disposable local database.');
 const exe=path.join(bin,'psql.exe');
 const args=['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',database];
 function connection(source){return new Promise((resolve,reject)=>{
  const child=spawn(exe,args,{env,windowsHide:true,stdio:['pipe','pipe','pipe']});
  let out='';let err='';
  const timer=setTimeout(()=>{child.kill();reject(new Error('Concurrency test timed out.'));},15000);
  child.stdout.on('data',chunk=>out+=chunk);child.stderr.on('data',chunk=>err+=chunk);
  child.on('error',error=>{clearTimeout(timer);reject(error);});
  child.on('close',code=>{clearTimeout(timer);resolve({code,out,err});});child.stdin.end(source);
 });}
 const session="begin; set local role authenticated; select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);";
 const create=`select public.create_service_request('a2000000-0000-0000-0000-000000000001',
 (select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='home-cleaning'),
 'a3000000-0000-0000-0000-000000000001','{}','concurrent-create-1');`;
 const results=await Promise.all([connection(session+create+'select pg_sleep(0.3); commit;'),connection(session+create+'commit;')]);
 for(const result of results)assert.equal(result.code,0,result.err);
 const ids=results.map(result=>result.out.match(/[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}/gi)?.at(-1));
 assert.ok(ids[0]);assert.equal(ids[0],ids[1]);
 const requestId=ids[0];
 const amendments=await Promise.all([
  connection(session+`select public.change_service_request('${requestId}',1,'amend','{"details":[{"bedrooms":1,"property":"flat"}]}');select pg_sleep(0.3);commit;`),
  connection(session+`select public.change_service_request('${requestId}',1,'amend','{"details":[{"bedrooms":2,"property":"flat"}]}');commit;`),
 ]);
 assert.equal(amendments.filter(result=>result.code===0).length,1);
 assert.ok(amendments.find(result=>result.code!==0)?.err.includes('stale request revision'));
 const count=spawnSync(exe,args,{env,windowsHide:true,encoding:'utf8',input:`select count(*) from private.transaction_commands where command='create_request' and idempotency_key='concurrent-create-1';`});
 assert.equal(count.status,0,count.stderr);assert.equal(count.stdout.trim(),'1');
 const submitted=await connection(session+`select public.change_service_request('${requestId}',2,'submit');commit;`);
 assert.equal(submitted.code,0,submitted.err);
 const staffSession="begin; set local role authenticated; select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);";
 const reviewed=await connection(staffSession+`select public.review_service_request('${requestId}',3);commit;`);
 assert.equal(reviewed.code,0,reviewed.err);
 const quote=(price,key)=>`select public.prepare_quotation('${requestId}',(select id from public.currencies where code='NGN'),now()+interval '1 day','Synthetic race',
 '[{"description":"Synthetic","kind":"service","quantity":"1","unit_price":"${price}"}]','${key}');`;
 const revisions=await Promise.all([
  connection(staffSession+quote('5','concurrent-quote-1')+'select pg_sleep(0.3);commit;'),
  connection(staffSession+quote('6','concurrent-quote-2')+'commit;'),
 ]);
 for(const result of revisions)assert.equal(result.code,0,result.err);
 const revisionCount=spawnSync(exe,args,{env,windowsHide:true,encoding:'utf8',input:`select json_build_object('versions',count(*),'live',count(*) filter(where v.status='draft'),'superseded',count(*) filter(where v.status='superseded'),'maximum',max(v.version)) from public.quotation_versions v join public.quotations q on q.id=v.quotation_id where q.request_id='${requestId}';`});
 assert.equal(revisionCount.status,0,revisionCount.stderr);
 assert.deepEqual(JSON.parse(revisionCount.stdout.trim()),{versions:2,live:1,superseded:1,maximum:2});
 console.log('PASS concurrency: idempotent create, stale amendment and serialized quotation revisions.');
 return {passed:true,checks:['two simultaneous creates return one UUID','two simultaneous amendments produce one winner','one idempotency row','two simultaneous quotation revisions preserve both versions and one live proposal'],connections:10};
}
