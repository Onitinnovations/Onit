import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';

// Continue an interrupted fresh replay only when its implementation and every
// previously passing test are byte-identical. Changed migrations require a fresh run.
const reportPath = 'docs/database/phase-2-specialized-test-results.json';
const report = JSON.parse(readFileSync(reportPath, 'utf8'));
if (report.passed || report.postgres !== '17.11' || !/^onit_phase2_\d+$/.test(report.database) || report.migrations.length !== 48) throw Error('Interrupted exact fresh candidate required');
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const files = readdirSync('supabase/migrations').filter(file => file.endsWith('.sql')).sort();
if (!isDeepStrictEqual(files, report.migrations)) throw Error('Migration inventory changed; start a fresh replay');
for (const [file, expected] of Object.entries(report.migrationHashes)) if (hash('supabase/migrations/' + file) !== expected) throw Error('Implementation changed; start a fresh replay');
const passedTests = new Set(report.tests.filter(test => test.passed).map(test => 'supabase/tests/' + test.file));
const changedUnpassedTests = [];
for (const [file, expected] of Object.entries(report.testHashes)) {
  if (hash(file) === expected) continue;
  if (passedTests.has(file) || !/^supabase\/tests\/specialized\/(construction|procurement|field)\.sql$/.test(file)) throw Error('Previously passing test/helper changed; start a fresh replay');
  changedUnpassedTests.push(file); report.testHashes[file] = hash(file);
}
const bin = path.resolve('.local-tools/postgres17/pgsql/bin');
const env = { ...process.env, PGHOST: '127.0.0.1', PGPORT: '55439', PGUSER: 'postgres', PGDATABASE: 'postgres', PGSSLMODE: 'disable' }; delete env.PGPASSWORD;
function run(tool, args, input) {
  const result = spawnSync(path.join(bin, tool + '.exe'), args, { env, input, encoding: 'utf8', windowsHide: true, timeout: 360000, maxBuffer: 64 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw Error(result.error?.message || result.stderr); return result.stdout;
}
const sqlFor = database => source => run('psql', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', database], source).trim();
const sql = sqlFor(report.database);
report.attempts ??= [];
report.attempts.push({ endedAt: report.completedAt, error: report.error, passedSuites: report.tests.filter(test => test.passed).length });
delete report.error; delete report.completedAt;
try {
  const baseline = JSON.parse(readFileSync('docs/database/phase-2-fulfilment-test-results.json', 'utf8'));
  if (!baseline.passed || baseline.migrations.length !== 32 || !/^onit_phase2_\d+$/.test(baseline.database)) throw Error('Verified Increment 5 baseline required');
  for (const [file, expected] of Object.entries(baseline.migrationHashes)) if (hash('supabase/migrations/' + file) !== expected) throw Error('Preserved Increment 5 changed');
  const schemaCheck = 'onit_specialized_focus_' + Date.now(); run('createdb', ['-T', baseline.database, schemaCheck]);
  const schemaSql = sqlFor(schemaCheck);
  for (const file of files.filter(file => file >= '20261029000000')) schemaSql(readFileSync('supabase/migrations/' + file, 'utf8'));
  const signature = readFileSync('supabase/inspection/application_signature.sql', 'utf8');
  if (!isDeepStrictEqual(JSON.parse(sql(signature)), JSON.parse(schemaSql(signature)))) throw Error('Interrupted database differs from exact candidate definitions');
  if (sql("select count(*) from private.service_operations") !== '0') throw Error('Unexpected committed specialised fixture before suite continuation');
  report.continuation = { resumedAt: new Date().toISOString(), originalFreshReplayRetained: true, schemaCheckDatabase: schemaCheck, definitionMatch: true, changedUnpassedTests, reason: 'Larger synthetic assignment windows; no migration or passing test changed.' };
  for (const stage of ['laundry', 'construction', 'procurement', 'field']) {
    const file = 'specialized/' + stage + '.sql';
    if (report.tests.some(test => test.file === file && test.passed)) continue;
    const source = readFileSync('supabase/tests/' + file, 'utf8'); sql(source);
    const assertions = (source.match(/select pg_temp\.assert_true\(/g) ?? []).length;
    report.tests.push({ file, assertions, passed: true }); console.log('PASS', file, assertions, 'assertions');
  }
  report.concurrencyDatabases ??= {};
  async function concurrency(key, module, exported) {
    if (report[key]) return;
    const database = 'onit_phase2_' + Date.now(); run('createdb', ['-T', report.database, database]);
    const test = (await import(module))[exported];
    report[key] = await test({ bin, env, database, sql: sqlFor(database), run });
    report.concurrencyDatabases[key] = database;
  }
  await concurrency('concurrency', './test-request-concurrency.mjs', 'testRequestConcurrency');
  await concurrency('providerConcurrency', './test-provider-concurrency.mjs', 'testProviderConcurrency');
  await concurrency('orderConcurrency', './test-order-concurrency.mjs', 'testOrderConcurrency');
  await concurrency('fulfilmentConcurrency', './test-fulfilment-concurrency.mjs', 'testFulfilmentConcurrency');
  await concurrency('laundryConcurrency', './test-laundry-concurrency.mjs', 'testLaundryConcurrency');
  report.laundryConcurrency.database = report.concurrencyDatabases.laundryConcurrency;
  await concurrency('specializedConcurrency', './test-specialized-concurrency.mjs', 'testSpecializedConcurrency');
  const recovery = JSON.parse(readFileSync('.local-tools/native17-recovery-report.json', 'utf8'));
  const archive = path.resolve(recovery.backupArchive), listPath = path.resolve('.local-tools/' + report.database + '.list');
  if (!recovery.backupVerified || hash(archive) !== recovery.backupSha256) throw Error('Recovery baseline changed');
  if (!report.upgrade) report.upgrade = (await import('./test-pricing-upgrade.mjs')).testPricingUpgrade({ run, env, archive, listPath, maxMigration: '99999999999999' });
  if (!report.providerUpgrade) report.providerUpgrade = (await import('./test-order-upgrade.mjs')).testOrderUpgrade({ run, env, archive, listPath, maxMigration: '99999999999999', expectedTables: 180 });
  if (!report.orderUpgrade) report.orderUpgrade = (await import('./test-fulfilment-upgrade.mjs')).testFulfilmentUpgrade({ run, env, archive, listPath, maxMigration: '99999999999999', expectedTables: 180 });
  if (!report.fulfilmentUpgrade) report.fulfilmentUpgrade = (await import('./test-specialized-upgrade.mjs')).testSpecializedUpgrade({ run, env, candidateDatabase: report.database });
  for (const [file, expected] of Object.entries(report.migrationHashes)) if (hash('supabase/migrations/' + file) !== expected) throw Error('Candidate changed during continuation');
  for (const [file, expected] of Object.entries(report.testHashes)) if (hash(file) !== expected) throw Error('Tests changed during continuation');
  if (sql("select count(*) from pg_tables where schemaname in('public','private') and rowsecurity") !== '180') throw Error('Final RLS count changed');
  report.passed = true;
  writeFileSync('docs/database/phase-2-specialized-candidate.sha256', Object.entries(report.migrationHashes).map(([file, expected]) => `${expected}  supabase/migrations/${file}`).join('\n') + '\n');
  console.log('PASS complete candidate: fresh replay retained, every historical/domain suite, concurrency and upgrade check completed.');
} catch (error) { report.error = error.message; process.exitCode = 1; console.error(error.message); }
finally { report.completedAt = new Date().toISOString(); writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n'); }
