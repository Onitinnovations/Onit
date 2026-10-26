import {spawn} from 'node:child_process';
import path from 'node:path';

export async function testProviderConcurrency({bin,env,database,sql}){
 if(env.PGHOST!=='127.0.0.1'||!/^onit_phase2_\d+$/.test(database))throw Error('Disposable loopback database required');
 const provider=sql("select id from private.provider_profiles where individual_profile_id='c1000000-0000-0000-0000-000000000001'").trim();
 const service=sql("select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-provider-work'").trim();
 const zone=sql("select id from public.service_zones where code='synthetic-provider-zone'").trim();
 function connection(query,worker=false){return new Promise(resolve=>{
  const child=spawn(path.join(bin,'psql.exe'),['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-d',database],{env,windowsHide:true});
  let stdout='',stderr='';child.stdout.on('data',data=>stdout+=data);child.stderr.on('data',data=>stderr+=data);
  child.on('error',error=>resolve({status:1,stderr:error.message,stdout}));child.on('close',status=>resolve({status,stdout:stdout.trim(),stderr}));
  child.stdin.end(`begin;set local role ${worker?'service_role':'authenticated'};do $$begin perform set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);perform set_config('request.jwt.claim.role','${worker?'service_role':'authenticated'}',true);end$$;${query};select pg_sleep(0.25);commit;`);
 });}
 const start=new Date(Date.now()+86400000).toISOString(),end=new Date(Date.now()+90000000).toISOString(),expires=new Date(Date.now()+3600000).toISOString();
 const data={service_version_id:service,zone_id:zone,start,end,expires_at:expires,units:'1',purpose_reference:'SYNTHETIC-CONCURRENCY',reason:'Synthetic reservation race'};
 const reserve=key=>`select public.provider_reservation('${provider}','reserve','${JSON.stringify(data)}'::jsonb,'${key}')`;
 const release=id=>connection(`select public.provider_reservation('${provider}','release',jsonb_build_object('id','${id}','reason','Synthetic race release'),'release-${id}')`);
 const race=await Promise.all([connection(reserve('provider-race-a')),connection(reserve('provider-race-b'))]);
 if(race.filter(r=>r.status===0).length!==1||!race.some(r=>r.stderr.includes('23514')))throw Error('Competing reservations did not enforce capacity');
 const winner=race.find(r=>r.status===0).stdout;
 if((await release(winner)).status!==0)throw Error('Capacity release failed');
 const duplicate=await Promise.all([connection(reserve('provider-duplicate')),connection(reserve('provider-duplicate'))]);
 if(duplicate.some(r=>r.status!==0)||duplicate[0].stdout!==duplicate[1].stdout)throw Error('Concurrent duplicate reservation did not converge');
 const receipts=sql("select count(*) from private.transaction_commands where command='provider_reservation' and idempotency_key='provider-duplicate'").trim();
 if(receipts!=='1')throw Error('Duplicate reservation receipts');
 if((await release(duplicate[0].stdout)).status!==0)throw Error('Duplicate capacity release failed');
 const revision=sql(`select revision from private.provider_profiles where id='${provider}'`).trim();
 const change=key=>`select public.provider_command('${provider}','availability',jsonb_build_object('expected_revision',${revision},'service_version_id','${service}','start','${start}','end','${end}','kind','working','reason','Synthetic revision race'),'${key}')`;
 const changes=await Promise.all([connection(change('provider-change-a')),connection(change('provider-change-b'))]);
 if(changes.filter(r=>r.status===0).length!==1||!changes.some(r=>r.stderr.includes('40001')))throw Error('Provider stale revision race failed');
 const leases=await Promise.all([connection("select public.operational_event_worker('claim','{\"limit\":5,\"lease_seconds\":120,\"max_attempts\":3}')",true),connection("select public.operational_event_worker('claim','{\"limit\":5,\"lease_seconds\":120,\"max_attempts\":3}')",true)]);
 if(leases.some(r=>r.status!==0))throw Error('Concurrent worker claims failed');
 const groups=leases.map(r=>JSON.parse(r.stdout).map(item=>item.id));
 if(groups.some(ids=>ids.length!==5)||groups[0].some(id=>groups[1].includes(id)))throw Error('Concurrent workers received overlapping leases');
 const personnelService=sql("select v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='synthetic-personnel-work'").trim();
 const personnelZone=sql("select id from public.service_zones where code='synthetic-personnel-zone'").trim();
 const parties=['d3000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000002'];
 const workerData={...data,service_version_id:personnelService,zone_id:personnelZone,worker_id:'d1000000-0000-0000-0000-000000000001',units:'10'};
 const humanRace=await Promise.all(parties.map((party,i)=>connection(`select public.provider_reservation('${party}','reserve','${JSON.stringify(workerData)}'::jsonb,'personnel-race-${i}')`)));
 if(humanRace.filter(r=>r.status===0).length!==1||!humanRace.some(r=>r.stderr.includes('23514')))throw Error('Shared human was allocated concurrently by separate businesses');
 const win=humanRace.findIndex(r=>r.status===0);
 if((await connection(`select public.provider_reservation('${parties[win]}','release',jsonb_build_object('id','${humanRace[win].stdout}','reason','Synthetic personnel release'),'personnel-race-release')`)).status!==0)throw Error('Shared human release failed');
 if(sql("select app_private.personnel_used('d1000000-0000-0000-0000-000000000001',now(),now()+interval '3 days')").trim()!=='0')throw Error('Released human capacity retained load');
 console.log('PASS provider concurrency: party/human capacity, idempotency, optimistic revisions and disjoint worker leases.');
 return {checks:7,connections:13,capacityWinners:1,idempotencyReceipts:1,revisionWinners:1,workerLeases:10,crossBusinessHumanWinners:1};
}
