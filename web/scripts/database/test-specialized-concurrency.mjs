import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert/strict';

export async function testSpecializedConcurrency({ bin, env, database, sql, run }) {
  if (env.PGHOST !== '127.0.0.1' || !/^onit_(phase2|specialized_focus)_\d+$/.test(database)) throw Error('Disposable loopback database required');
  const templateDatabase=database;let raceDatabase=database;let query=sql;
  const databases = {};let connections = 0;
  const actor = { worker: 'd1000000-0000-0000-0000-000000000001', otherWorker: 'd1000000-0000-0000-0000-000000000002', manager: 'd1000000-0000-0000-0000-000000000003', checker: 'd1000000-0000-0000-0000-000000000004', customer: 'a1000000-0000-0000-0000-000000000001' };
  const encode = value => `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;
  function connection(query, profile) {
    connections++;
    return new Promise((resolve, reject) => {
      const child = spawn(path.join(bin, 'psql.exe'), ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-d', raceDatabase], { env, windowsHide: true });
      let stdout = '', stderr = '';
      const timer = setTimeout(() => { child.kill(); reject(Error('Specialised concurrency deadline')); }, 60000);
      child.stdout.on('data', chunk => stdout += chunk); child.stderr.on('data', chunk => stderr += chunk); child.on('error', reject);
      child.on('close', status => { clearTimeout(timer); resolve({ status, stdout: stdout.trim(), stderr }); });
      child.stdin.end(`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub','${profile}',true);end$$;${query};select pg_sleep(0.25);commit;`);
    });
  }
  const command = (operation, action, data, revision) => `select public.service_operation_command('${operation}','${action}',${encode({ ...data, expected_revision: revision, reason: 'Synthetic specialised race' })},'${crypto.randomUUID()}')`;
  const current = operation => Number(query(`select revision from private.service_operations where id='${operation}'`).trim());
  function fixture(stage, marker) {
    const source = readFileSync(`supabase/tests/specialized/${stage}.sql`, 'utf8');
    const end = source.indexOf(marker);
    assert.ok(end > 0, 'Reviewed concurrency fixture boundary exists');
    raceDatabase='onit_specialized_focus_'+Date.now();databases[stage]=raceDatabase;run('createdb',['-T',templateDatabase,raceDatabase]);
    query=source=>run('psql',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',raceDatabase],source).trim();
    query(source.slice(0, end) + '\nreset role;commit;');
  }
  async function oneWinner(commands) {
    const results = await Promise.all(commands.map(([query, profile]) => connection(query, profile)));
    assert.equal(results.filter(row => row.status === 0).length, 1, JSON.stringify(results));
    assert.ok(results.some(row => /40001/.test(row.stderr)), JSON.stringify(results));
    return results;
  }
  fixture('construction', "select pg_temp.actor(7);select pg_temp.assert_true");
  const construction = query("select id from private.service_operations where kind='construction'").trim();
  const milestone = query(`select id from private.construction_milestones where operation_id='${construction}' and code='M1'`).trim();
  let revision = current(construction);
  await oneWinner([[command(construction, 'milestone.accept', { id: milestone }, revision), actor.customer], [command(construction, 'milestone.accept', { id: milestone }, revision), actor.customer]]);
  assert.equal(query(`select count(*) from private.construction_milestones where id='${milestone}' and customer_approved_by is not null`).trim(), '1');
  assert.equal(query(`select count(*) from private.execution_history where action='specialized.milestone.accept' and subject_id='${milestone}'`).trim(), '1');
  console.log('PASS concurrent milestone acknowledgement: one revision and one immutable event.');

  fixture('procurement', "select pg_temp.actor(3);insert into execution_ids values('case'");
  const procurement = query("select id from private.service_operations where kind='procurement'").trim();
  const receipt = query(`select id from private.procurement_receipts where operation_id='${procurement}'`).trim();
  const line = query(`select id from private.procurement_receipt_lines where receipt_id='${receipt}'`).trim();
  const evidence = query(`select proof.id from private.execution_evidence proof join private.work_tasks task on task.id=proof.task_id join private.operation_tasks link on link.task_id=task.id where link.operation_id='${procurement}' and link.purpose='procurement_receiving'`).trim();
  revision = current(procurement);
  const receiptData = { id: receipt, evidence_id: evidence, lines: [{ id: line, accepted: '6.0000', rejected: '0.0000', condition: { accepted: true } }] };
  await oneWinner([[command(procurement, 'receipt.inspect', receiptData, revision), actor.manager], [command(procurement, 'receipt.inspect', receiptData, revision), actor.checker]]);
  assert.equal(query(`select count(*) from private.supplier_performance_observations where receipt_id='${receipt}'`).trim(), '3');
  assert.equal(query(`select accepted_quantity from private.procurement_receipt_lines where id='${line}'`).trim(), '6.0000');
  const duplicate = await connection(command(procurement, 'receipt.inspect', receiptData, current(procurement)), actor.manager);
  assert.notEqual(duplicate.status, 0); assert.match(duplicate.stderr, /42501/);
  console.log('PASS concurrent goods inspection: one actual receipt and exactly three sourced observations.');

  fixture('field', "insert into execution_ids values('submission1',");
  const field = query("select id from private.service_operations where kind='field_campaign'").trim();
  const location = query(`select id from private.field_campaign_locations where operation_id='${field}' and external_reference='shop-A'`).trim();
  const response = query(`select response.id from private.execution_submissions response join private.field_campaign_locations location on location.task_id=response.task_id where location.id='${location}' and response.phase='execution' and response.status='submitted'`).trim();
  revision = current(field);
  await oneWinner([[command(field, 'field.submit', { location_id: location, submission_id: response }, revision), actor.worker], [command(field, 'field.submit', { location_id: location, submission_id: response }, revision), actor.worker]]);
  assert.equal(query(`select count(*) from private.field_campaign_submissions where location_id='${location}'`).trim(), '1');
  const submission = query(`select id from private.field_campaign_submissions where location_id='${location}'`).trim();
  revision = current(field);
  await oneWinner([[command(field, 'field.review', { id: submission, approve: true }, revision), actor.manager], [command(field, 'field.review', { id: submission, approve: false }, revision), actor.manager]]);
  const forbidden = await connection(command(field, 'field.submit', { location_id: location, submission_id: response }, current(field)), actor.otherWorker);
  assert.notEqual(forbidden.status, 0); assert.match(forbidden.stderr, /42501/);
  console.log('PASS concurrent field submissions/reviews: one submission, one outcome and other-worker denial.');
  return { passed: true, databases, checks: 10, connections, milestoneWinners: 1, receiptWinners: 1, submissionWinners: 1, reviewWinners: 1 };
}
