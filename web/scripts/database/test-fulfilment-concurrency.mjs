import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

/** Actual concurrent transactions, exclusively in a fresh loopback fixture database. */
export async function testFulfilmentConcurrency({ bin, env, database, sql }) {
  if (env.PGHOST !== '127.0.0.1' || !/^onit_phase2_\d+$/.test(database)) throw Error('Disposable loopback database required');
  const source = readFileSync('supabase/tests/008_service_fulfilment.sql', 'utf8');
  const helpers = source.slice(source.indexOf('create function pg_temp.actor'), source.indexOf('set local role authenticated;select pg_temp.actor(3);')).replace('pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text),', '');
  let fixture = source.slice(source.indexOf('select pg_temp.actor(6);insert into execution_ids'), source.indexOf('select pg_sleep(15.2)'));
  // Reuse the exercised workflow, with separate idempotency keys and a new order.
  fixture = fixture.replaceAll('synthetic-', 'race-').replaceAll('room-one', 'race-one').replaceAll('room-two', 'race-two');
  // Omit assertions which refer to the original completed work; their equivalents run in 008.
  fixture = fixture.split('\n').filter(line => !line.includes('pg_temp.assert_true')).join('\n');
  fixture = fixture.split('\n').map(line => line.includes("values('task1'") ? line.replace("'end',public.read_work_order((select id from execution_ids where key='work'))->>'end'", "'end',(public.read_work_order((select id from execution_ids where key='work'))->>'start')::timestamptz+interval '30 minutes'") : line.includes("values('task2'") ? line.replace("'start',public.read_work_order((select id from execution_ids where key='work'))->>'start'", "'start',(public.read_work_order((select id from execution_ids where key='work'))->>'start')::timestamptz+interval '30 minutes'") : line).join('\n');
  sql(`begin;create temporary table execution_ids(key text primary key,id uuid);grant all on execution_ids to authenticated;
    insert into execution_ids select 'service',v.id from public.service_versions v join public.services s on s.id=v.service_id where s.code='home-cleaning';
    insert into execution_ids select 'zone',id from public.service_zones where code='synthetic-personnel-zone';

    ${helpers}set local role authenticated;${fixture}commit;`);
  const work = sql("select id from private.work_orders where code='race-cleaning'").trim();
  const task = sql(`select id from private.work_tasks where work_order_id='${work}' and code='race-one'`).trim();
  assert.match(work, /^[\da-f-]{36}$/);
  let connections = 0;
  const actors = { manager: 'd1000000-0000-0000-0000-000000000003', checker: 'd1000000-0000-0000-0000-000000000004', worker: 'd1000000-0000-0000-0000-000000000001', customer: 'a1000000-0000-0000-0000-000000000001' };
  function connection(command, actor = actors.manager) {
    connections++;
    return new Promise((resolve, reject) => {
      const child = spawn(path.join(bin, 'psql.exe'), ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-d', database], { env, windowsHide: true });
      let stdout = '', stderr = '';
      const timer = setTimeout(() => { child.kill(); reject(Error('Execution concurrency timeout')); }, 60000);
      child.stdout.on('data', data => stdout += data); child.stderr.on('data', data => stderr += data); child.on('error', reject);
      child.on('close', status => { clearTimeout(timer); resolve({ status, stdout: stdout.trim(), stderr }); });
      child.stdin.end(`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub','${actor}',true);end$$;${command};select pg_sleep(0.3);commit;`);
    });
  }
  const encode = value => `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;
  const revisions = () => JSON.parse(sql(`select json_build_object('expected_revision',w.revision,'task_revision',t.revision) from private.work_orders w join private.work_tasks t on t.work_order_id=w.id where t.id='${task}'`));
  const command = (action, data = {}, key = crypto.randomUUID()) => `select public.fulfilment_command('${work}','${action}',${encode({ ...revisions(), task_id: task, reason: 'Synthetic concurrent execution', ...data })},'${key}')`;
  const accept = command('accept_task', {}, 'execution-accept-idempotent');
  const duplicates = await Promise.all([connection(accept, actors.worker), connection(accept, actors.worker)]);
  assert.ok(duplicates.every(row => row.status === 0), JSON.stringify(duplicates)); assert.equal(duplicates[0].stdout, duplicates[1].stdout);
  await new Promise(resolve => setTimeout(resolve, 16000));
  const mobilisation = command('progress', { state: 'mobilising' });
  const race = await Promise.all([connection(mobilisation, actors.worker), connection(mobilisation.replace(/'[^']+'\)$/, `'${crypto.randomUUID()}')`), actors.worker)]);
  assert.equal(race.filter(row => row.status === 0).length, 1, JSON.stringify(race)); assert.ok(race.some(row => /40001/.test(row.stderr)));
  const provider = command('progress', { state: 'en_route' }), staff = command('suspend');
  const competing = await Promise.all([connection(provider, actors.worker), connection(staff)]);
  assert.equal(competing.filter(row => row.status === 0).length, 1, JSON.stringify(competing)); assert.ok(competing.some(row => /40001/.test(row.stderr)));
  if (sql(`select status from private.work_orders where id='${work}'`).trim() === 'suspended') assert.equal((await connection(command('resume'))).status, 0);
  const sla = sql(`select id from private.sla_tracks where work_order_id='${work}' and target='task_completion' order by id limit 1`).trim();
  const extension = new Date(Date.now() + 7200000).toISOString();
  const slaRequest = await connection(command('request_exception', { kind: 'sla_extension', proposal: { sla_id: sla, new_due: extension }, valid_until: new Date(Date.now() + 600000).toISOString() })); assert.equal(slaRequest.status, 0, slaRequest.stderr);
  const selfApproval = await connection(command('decide_exception', { id: slaRequest.stdout, approve: true })); assert.notEqual(selfApproval.status, 0); assert.match(selfApproval.stderr, /42501/);
  assert.equal((await connection(command('decide_exception', { id: slaRequest.stdout, approve: true }), actors.checker)).status, 0);
  const extensionResult = await connection(command('apply_sla_exception', { exception_id: slaRequest.stdout })); assert.equal(extensionResult.status, 0, extensionResult.stderr);
  assert.equal(sql(`select due_at='${extension}'::timestamptz from private.sla_tracks where id='${sla}'`).trim(), 't');
  assert.equal((await connection(command('suspend'))).status, 0);
  assert.equal(sql(`select count(*) from private.sla_tracks where work_order_id='${work}' and status='running'`).trim(), '0', 'Authorised suspension pauses running deadlines');
  assert.equal((await connection(command('resume'))).status, 0);
  assert.equal(sql(`select count(*) from private.sla_tracks where work_order_id='${work}' and status='paused'`).trim(), '0', 'Revalidated resume restores paused deadlines');
  const planBefore = sql(`select plan_revision from private.work_orders where id='${work}'`).trim();
  const exceptionData = { kind: 'substitution', proposal: { task_id: task, worker_id: 'd1000000-0000-0000-0000-000000000002' }, valid_until: new Date(Date.now() + 600000).toISOString() };
  const requested = await connection(command('request_exception', exceptionData)); assert.equal(requested.status, 0, requested.stderr);
  const exception = requested.stdout;
  const approved = await connection(command('decide_exception', { id: exception, approve: true }), actors.checker); assert.equal(approved.status, 0, approved.stderr);
  const substitute = await connection(command('substitute', { exception_id: exception })); assert.notEqual(substitute.status, 0); assert.match(substitute.stderr, /23514/);
  assert.equal(sql(`select plan_revision from private.work_orders where id='${work}'`).trim(), planBefore);
  assert.equal(sql(`select count(*) from private.provider_capacity_reservations capacity join private.assignment_resources resource on resource.reservation_id=capacity.id join private.assignment_offers offer on offer.id=resource.offer_id join private.work_orders work on work.proposal_id=offer.proposal_id where work.id='${work}' and capacity.status='assigned'`).trim(), '2', 'Failed substitution preserves every allocation');
  const replacement = sql(`select resource_id from private.work_tasks where work_order_id='${work}' and code='race-two'`).trim();
  const transfer = await connection(command('request_exception', { kind: 'substitution', proposal: { task_id: task, resource_id: replacement, worker_id: 'd1000000-0000-0000-0000-000000000002' }, valid_until: new Date(Date.now() + 600000).toISOString() })); assert.equal(transfer.status, 0, transfer.stderr);
  assert.equal((await connection(command('decide_exception', { id: transfer.stdout, approve: true }), actors.checker)).status, 0);
  const reassigned = await connection(command('task_reassign', { exception_id: transfer.stdout })); assert.equal(reassigned.status, 0, reassigned.stderr);
  assert.equal(sql(`select resource_id='${replacement}'::uuid and execution_round=2 from private.work_tasks where id='${task}'`).trim(), 't');
  const revokedRead = await connection(`select public.read_work_order('${work}')`, actors.worker); assert.notEqual(revokedRead.status, 0); assert.match(revokedRead.stderr, /42501/);
  assert.equal(sql(`select count(*) from private.provider_capacity_reservations capacity join private.assignment_resources resource on resource.reservation_id=capacity.id join private.assignment_offers offer on offer.id=resource.offer_id join private.work_orders work on work.proposal_id=offer.proposal_id where work.id='${work}' and capacity.status='assigned'`).trim(), '1', 'Approved task reassignment releases an entirely unused old resource');
  const order = sql(`select order_id from private.work_orders where id='${work}'`).trim();
  const caseData = { work_order_id: work, category: 'delay', severity: 'minor', priority: 'normal', description: 'Synthetic concurrent delay case', reason: 'Concurrent complaint' };
  const reportCase = `select public.execution_case_command('${order}','report',${encode(caseData)},'execution-case-idempotent')`;
  const cases = await Promise.all([connection(reportCase, actors.customer), connection(reportCase, actors.customer)]);
  assert.ok(cases.every(row => row.status === 0), JSON.stringify(cases)); assert.equal(cases[0].stdout, cases[1].stdout);
  const caseId = cases[0].stdout;
  const update = action => `select public.execution_case_command('${order}','${action}',${encode({ id: caseId, expected_revision: 1, reason: 'Concurrent investigation' })},'${crypto.randomUUID()}')`;
  const decisions = await Promise.all([connection(update('acknowledge')), connection(update('investigate'), actors.checker)]);
  assert.equal(decisions.filter(row => row.status === 0).length, 1); assert.ok(decisions.some(row => /40001/.test(row.stderr)));
  const cancellation = await connection(command('request_exception', { kind: 'cancel_work', proposal: {}, valid_until: new Date(Date.now() + 600000).toISOString() })); assert.equal(cancellation.status, 0, cancellation.stderr);
  assert.equal((await connection(command('decide_exception', { id: cancellation.stdout, approve: true }), actors.checker)).status, 0);
  const cancel = await connection(command('cancel_work', { exception_id: cancellation.stdout })); assert.equal(cancel.status, 0, cancel.stderr);
  assert.equal(sql(`select count(*) from private.provider_capacity_reservations capacity join private.assignment_resources resource on resource.reservation_id=capacity.id join private.assignment_offers offer on offer.id=resource.offer_id join private.work_orders work on work.proposal_id=offer.proposal_id where work.id='${work}' and capacity.status='assigned'`).trim(), '0');
  console.log('PASS execution concurrency: idempotent acceptance/case, competing progress/suspension/investigation, failed substitution rollback and approved cancellation release.');
  return { checks: 13, connections, realOverlap: true, failedSubstitutionPreservedResources: true, cancellationReleasedResources: true, independentSlaExtension: true, suspensionDeadlineControl: true, successfulTaskReassignment: true, formerPersonnelAccessRevoked: true };
}
