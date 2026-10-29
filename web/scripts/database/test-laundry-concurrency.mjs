import { readFileSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import path from 'node:path';

export async function testLaundryConcurrency({ bin, env, database, sql }) {
  if (env.PGHOST !== '127.0.0.1' || !/^onit_(specialized_focus|phase2)_\d+$/.test(database)) throw Error('Isolated focused database required');
  const source = readFileSync('supabase/tests/specialized/laundry.sql', 'utf8');
  sql(source.slice(0, source.indexOf("insert into execution_ids values('pickup-transfer'")) + '\nreset role;commit;');
  const operation = sql("select id from private.service_operations where primary_order_id=(select result_id from private.transaction_commands where command='order_command' and idempotency_key='laundry-order')").trim();
  const task = sql("select id from private.work_tasks where code='pickup' and work_order_id=(select result_id from private.transaction_commands where command='fulfilment_command' and idempotency_key='laundry-work')").trim();
  const resource = sql(`select resource_id from private.work_tasks where id='${task}'`).trim();
  const balance = sql(`select balance.id from private.laundry_custody_balances balance join private.laundry_items item on item.id=balance.item_id where item.operation_id='${operation}' and item.reference='SYNTHETIC-SHIRTS-1' and balance.customer_holder`).trim();
  const evidence = sql(`select evidence.id from private.execution_evidence evidence where evidence.task_id='${task}'`).trim();
  for (const id of [operation, task, resource, balance, evidence]) assert.match(id, /^[\da-f-]{36}$/);
  let connections = 0;
  function connection(query, actor = 'a1000000-0000-0000-0000-000000000001') {
    connections++;
    return new Promise((resolve, reject) => {
      const child = spawn(path.join(bin, 'psql.exe'), ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-d', database], { env, windowsHide: true });
      let stdout = '', stderr = '';
      const timer = setTimeout(() => { child.kill(); reject(Error('Laundry race timeout')); }, 60000);
      child.stdout.on('data', data => stdout += data); child.stderr.on('data', data => stderr += data); child.on('error', reject);
      child.on('close', status => { clearTimeout(timer); resolve({ status, stdout: stdout.trim(), stderr }); });
      child.stdin.end(`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub','${actor}',true);end$$;${query};select pg_sleep(0.25);commit;`);
    });
  }
  const encode = data => `'${JSON.stringify(data).replaceAll("'", "''")}'::jsonb`;
  const revision = () => Number(sql(`select revision from private.service_operations where id='${operation}'`).trim());
  const command = (action, data, key = crypto.randomUUID()) => `select public.service_operation_command('${operation}','${action}',${encode({ ...data, expected_revision: revision(), reason: 'Synthetic laundry race' })},'${key}')`;
  const proposal = { resource_id: resource, to_customer: false, evidence_id: evidence, lines: [{ balance_id: balance, units: 3 }] };
  const one = command('custody.propose', proposal), two = command('custody.propose', proposal);
  const proposals = await Promise.all([connection(one), connection(two)]);
  assert.equal(proposals.filter(result => result.status === 0).length, 1, JSON.stringify(proposals));
  assert.ok(proposals.some(result => /40001/.test(result.stderr)));
  const transfer = proposals.find(result => result.status === 0).stdout;
  const excessive = await connection(command('custody.propose', proposal)); assert.notEqual(excessive.status, 0); assert.match(excessive.stderr, /23514/);
  assert.equal(sql(`select count(*) from private.laundry_custody_transfers where operation_id='${operation}'`).trim(), '1', 'Failed reservation rolls back the transfer header and every line');
  const send = command('custody.send', { id: transfer }, 'laundry-race-send');
  const sends = await Promise.all([connection(send), connection(send)]); assert.ok(sends.every(result => result.status === 0), JSON.stringify(sends)); assert.equal(sends[0].stdout, sends[1].stdout);
  assert.equal(sql(`select units from private.laundry_custody_balances where id='${balance}'`).trim(), '4');
  const worker = 'd1000000-0000-0000-0000-000000000001';
  const start = new Date(sql(`select starts_at from private.work_tasks where id='${task}'`).trim());
  await new Promise(resolve => setTimeout(resolve, Math.max(0, start.getTime() - Date.now()) + 20));
  const workAction = actionData => {
    const current = JSON.parse(sql(`select json_build_object('expected_revision',work.revision,'task_revision',task.revision) from private.work_tasks task join private.work_orders work on work.id=task.work_order_id where task.id='${task}'`));
    const work = sql(`select work_order_id from private.work_tasks where id='${task}'`).trim();
    return `select public.fulfilment_command('${work}','${actionData.action}',${encode({ ...current, task_id: task, ...actionData.data, reason: 'Synthetic attended custody' })},'${crypto.randomUUID()}')`;
  };
  for (const actionData of [{ action: 'accept_task', data: {} }, ...['mobilising', 'en_route', 'arrived'].map(state => ({ action: 'progress', data: { state } })), { action: 'attendance', data: { kind: 'check_in' } }]) {
    const result = await connection(workAction(actionData), worker); assert.equal(result.status, 0, result.stderr);
  }
  const line = sql(`select id from private.laundry_transfer_items where transfer_id='${transfer}'`).trim();
  const receiveData = { id: transfer, lines: [{ id: line, units: 3 }] };
  const responseOne = command('custody.receive', receiveData), responseTwo = command('custody.receive', receiveData);
  const receivers = await Promise.all([connection(responseOne, worker), connection(responseTwo, worker)]);
  assert.equal(receivers.filter(result => result.status === 0).length, 1, JSON.stringify(receivers)); assert.ok(receivers.some(result => /40001/.test(result.stderr)));
  assert.equal(sql(`select count(*) from private.laundry_custody_events where transfer_id='${transfer}' and action='received'`).trim(), '1');
  assert.equal(sql(`select sum(units) from private.laundry_custody_balances where operation_id='${operation}'`).trim(), '8');
  assert.equal(sql(`select units from private.laundry_custody_balances where id='${balance}'`).trim(), '1');
  const repeated = await connection(command('custody.receive', receiveData), worker); assert.notEqual(repeated.status, 0); assert.match(repeated.stderr, /42501/);
  const unrelated = await connection(`select public.read_service_operation('${operation}')`, 'a1000000-0000-0000-0000-000000000002'); assert.notEqual(unrelated.status, 0); assert.match(unrelated.stderr, /42501/);
  console.log('PASS custody concurrency: exclusive quantity reservation, idempotent dispatch, one receiver, conservation and customer isolation.');
  return { passed: true, checks: 8, connections, quantityWinners: 1, acknowledgementWinners: 1, exactGoodsCount: 8 };
}

if (process.argv[1]?.endsWith('test-laundry-concurrency.mjs')) {
  const focus = JSON.parse(readFileSync('docs/database/phase-2-specialized-laundry-tests.json', 'utf8'));
  if (!focus.passed) throw Error('Passing focused Laundry scenario required');
  const bin = path.resolve('.local-tools/postgres17/pgsql/bin');
  const env = { ...process.env, PGHOST: '127.0.0.1', PGPORT: '55439', PGUSER: 'postgres', PGSSLMODE: 'disable' }; delete env.PGPASSWORD;
  const sql = source => {
    const result = spawnSync(path.join(bin, 'psql.exe'), ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', focus.database], { env, input: source, encoding: 'utf8', windowsHide: true, timeout: 180000 });
    if (result.status !== 0) throw Error(result.stderr); return result.stdout;
  };
  const report = await testLaundryConcurrency({ bin, env, database: focus.database, sql });
  writeFileSync('docs/database/phase-2-laundry-concurrency.json', JSON.stringify(report, null, 2) + '\n');
}
