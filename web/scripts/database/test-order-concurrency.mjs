import {spawn} from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert/strict';

/** Fixtures and writes are confined to a newly created loopback test database. */
export async function testOrderConcurrency({bin,env,database,sql}){
 if(env.PGHOST!=='127.0.0.1'||!/^onit_phase2_\d+$/.test(database))throw Error('Disposable local database required');
 let connections=0;
 function connection(source,actor='d1000000-0000-0000-0000-000000000003',worker=false){
  connections++;
  return new Promise((resolve,reject)=>{
   const child=spawn(path.join(bin,'psql.exe'),['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-d',database],{env,windowsHide:true});let stdout='',stderr='';
   const timer=setTimeout(()=>{child.kill();reject(Error('Order concurrency connection timed out'));},25000);
   child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);child.on('error',reject);
   child.on('close',status=>{clearTimeout(timer);resolve({status,stdout:stdout.trim(),stderr});});
   child.stdin.end(`begin;set local role ${worker?'service_role':'authenticated'};do $$begin perform set_config('request.jwt.claim.sub','${worker?'':actor}',true);perform set_config('request.jwt.claim.role','${worker?'service_role':'authenticated'}',true);end$$;${source};select pg_sleep(0.2);commit;`);
  });
 }
 const ok=async(source,actor,worker)=>{const r=await connection(source,actor,worker);assert.equal(r.status,0,r.stderr);return r.stdout;};
 const encode=x=>`'${JSON.stringify(x).replaceAll("'","''")}'::jsonb`;
 const key=()=>crypto.randomUUID();
 const customer='a1000000-0000-0000-0000-000000000001',checker='d1000000-0000-0000-0000-000000000004';
 const parties=['d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002'];
 const admins=['e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002'];
 const humans=['d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002'];
 const zone=sql("select id from public.service_zones where code='synthetic-personnel-zone'").trim();
 const service=sql("select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-personnel-work'").trim();
 const quote=n=>sql(`select v.id from private.transaction_commands t join public.quotations q on q.request_id=t.result_id join public.quotation_versions v on v.quotation_id=q.id and v.status='accepted' where t.command='create_request' and t.idempotency_key='synthetic-order-request-race-${n}'`).trim();
 const schedule={zone_id:zone,start:new Date(Date.now()+86400000).toISOString(),end:new Date(Date.now()+90000000).toISOString(),reason:'Synthetic order concurrency'};
 const create=(n,k,extra={})=>`select public.create_service_order('${quote(n)}',${encode({...schedule,...extra})},'${k}')`;
 const duplicates=await Promise.all([connection(create('one','order-create-race'),customer),connection(create('one','order-create-race'),customer)]);
 assert.ok(duplicates.every(r=>r.status===0),JSON.stringify(duplicates));assert.equal(duplicates[0].stdout,duplicates[1].stdout);
 const orders=[duplicates[0].stdout,await ok(create('two','order-second-create'),customer)];
 assert.equal(sql("select count(*) from private.transaction_commands where command='order_command' and idempotency_key='order-create-race'").trim(),'1');
 const mismatch=await connection(create('one','order-create-race',{start:new Date(Date.now()+86500000).toISOString()}),customer);assert.notEqual(mismatch.status,0);assert.match(mismatch.stderr,/23505/);
 const oc=(id,action,data={})=>`select public.order_command('${id}','${action}',${encode({expected_revision:1,reason:'Synthetic concurrent order test',...data})},'${key()}')`;
 const dc=(id,action,data={},k=key())=>`select public.dispatch_command('${id}','${action}',${encode({expected_revision:1,reason:'Synthetic concurrent dispatch test',...data})},'${k}')`;
 for(const id of orders)await ok(oc(id,'release'),checker);
 const matching=async(id,party)=>JSON.parse(await ok(`select public.match_order('${id}',${encode(humans.map(worker_id=>({provider_id:party,worker_id,units:'5'})))})`)).map(c=>c.id);
 const candidates=await Promise.all(orders.map((id,i)=>matching(id,parties[i])));
 const proposals=await Promise.all(orders.map((id,i)=>connection(dc(id,'propose',{candidates:candidates[i]}))));
 assert.equal(proposals.filter(r=>r.status===0).length,1,'Only one contracting business may reserve both humans');
 assert.ok(proposals.some(r=>r.stderr.includes('23514')),JSON.stringify(proposals));
 const winner=proposals.findIndex(r=>r.status===0),order=orders[winner],proposal=proposals[winner].stdout;
 assert.equal(sql(`select count(*) from private.assignment_resources a join private.assignment_offers f on f.id=a.offer_id where f.proposal_id='${proposal}'`).trim(),'2');
 assert.equal(sql(`select count(*) from private.dispatch_proposals where order_id='${orders[1-winner]}'`).trim(),'0','Failed bundle rolls back its proposal and every resource');
 const offer=sql(`select id from private.assignment_offers where proposal_id='${proposal}'`).trim();
 const responses=await Promise.all([connection(dc(order,'respond',{offer_id:offer,accept:true}),admins[winner]),connection(dc(order,'respond',{offer_id:offer,accept:true}),admins[winner])]);
 assert.equal(responses.filter(r=>r.status===0).length,1);assert.ok(responses.some(r=>r.stderr.includes('40001')));
 const confirmations=await Promise.all([connection(dc(order,'confirm',{id:proposal})),connection(dc(order,'confirm',{id:proposal}))]);
 assert.equal(confirmations.filter(r=>r.status===0).length,1);assert.ok(confirmations.some(r=>r.stderr.includes('23514')));
 assert.equal(sql(`select count(*) from private.provider_capacity_reservations r join private.assignment_resources a on a.reservation_id=r.id join private.assignment_offers f on f.id=a.offer_id where f.proposal_id='${proposal}' and r.status='assigned'`).trim(),'2');
 await ok(dc(order,'reassign'));
 for(const human of humans)assert.equal(Number(sql(`select app_private.personnel_used('${human}','${schedule.start}','${schedule.end}')`).trim()),0);
 const stale=await connection(dc(order,'respond',{offer_id:offer,accept:true}),admins[winner]);assert.notEqual(stale.status,0);assert.match(stale.stderr,/42501|40001/);
 // A real clock expiration, not a mocked payment or a mutation of offer timestamps.
 const policy=sql(`select id from private.order_policies where service_version_id='${service}' and status='approved'`).trim();
 await ok(`select public.order_policy_command('retire',${encode({id:policy})},'${key()}')`,checker);
 const shortPolicy=await ok(`select public.order_policy_command('prepare',${encode({service_version_id:service,version:4,valid_from:new Date(Date.now()-1000).toISOString(),payment_gate:'no_upfront_payment',offer_seconds:30,performance_weight:'2',workload_weight:'1'})},'${key()}')`);
 await ok(`select public.order_policy_command('approve',${encode({id:shortPolicy})},'${key()}')`,checker);
 const expiredOrder=await ok(create('three','order-expiry-create'),customer);await ok(oc(expiredOrder,'release'),checker);
 const shortCandidates=await matching(expiredOrder,parties[0]);
 const shortProposal=await ok(dc(expiredOrder,'propose',{candidates:shortCandidates}));
 const shortOffer=sql(`select id from private.assignment_offers where proposal_id='${shortProposal}'`).trim();
 await new Promise(resolve=>setTimeout(resolve,31000));
 const expiredResponse=await connection(dc(expiredOrder,'respond',{offer_id:shortOffer,accept:true}),admins[0]);assert.notEqual(expiredResponse.status,0);assert.match(expiredResponse.stderr,/40001/);
 for(const human of humans)assert.equal(Number(sql(`select app_private.personnel_used('${human}','${schedule.start}','${schedule.end}')`).trim()),0,'Logical expiry frees human capacity before a worker sweep');
 const ordinarySweep=await connection('select public.expire_dispatch_offers(25)');assert.notEqual(ordinarySweep.status,0);assert.match(ordinarySweep.stderr,/42501/);
 assert.equal(await ok('select public.expire_dispatch_offers(25)',undefined,true),'1');
 assert.equal(await ok('select public.expire_dispatch_offers(25)',undefined,true),'0','Expiry sweep retry is idempotent');
 assert.equal(sql(`select count(*) from private.order_history where order_id='${expiredOrder}' and actor_type='system_worker' and actor_id is null`).trim(),'1');
 assert.equal(sql(`select status from private.dispatch_proposals where id='${shortProposal}'`).trim(),'expired');
 const rejection=await ok(dc(expiredOrder,'propose',{candidates:await matching(expiredOrder,parties[0])}));
 const rejectedOffer=sql(`select id from private.assignment_offers where proposal_id='${rejection}'`).trim();
 await ok(dc(expiredOrder,'respond',{offer_id:rejectedOffer,accept:false}),admins[0]);
 assert.equal(sql(`select status from private.dispatch_proposals where id='${rejection}'`).trim(),'rejected');
 for(const human of humans)assert.equal(Number(sql(`select app_private.personnel_used('${human}','${schedule.start}','${schedule.end}')`).trim()),0);
 console.log('PASS orders: duplicate creation, receipt conflicts, competing two-human allocations, responses, confirmation, release, real expiry and rejection.');
 return {checks:11,connections,duplicateOrders:1,multiPersonAllocationWinners:1,responseWinners:1,assignmentWinners:1,realExpirySeconds:31,systemExpiryReceipts:1};
}
