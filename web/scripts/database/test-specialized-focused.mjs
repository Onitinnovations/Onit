import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

// Focused development only. Final release still requires a fresh complete replay.
const stage = process.argv[2] ?? 'laundry';
if (!['laundry', 'construction', 'procurement', 'field'].includes(stage)) throw Error('Known domain stage required');
const baseline = JSON.parse(readFileSync('docs/database/phase-2-fulfilment-test-results.json', 'utf8'));
if (!baseline.passed || baseline.postgres !== '17.11' || !/^onit_phase2_\d+$/.test(baseline.database)) throw Error('Passing native Increment 5 baseline required');
for (const [file, hash] of Object.entries(baseline.migrationHashes)) if (createHash('sha256').update(readFileSync('supabase/migrations/' + file)).digest('hex') !== hash) throw Error('Increment 5 changed');
const env = { ...process.env, PGHOST: '127.0.0.1', PGPORT: '55439', PGUSER: 'postgres', PGSSLMODE: 'disable' }; delete env.PGPASSWORD;
const bin = path.resolve('.local-tools/postgres17/pgsql/bin');
const database = 'onit_specialized_focus_' + Date.now();
function run(tool, args, input) {
  const result = spawnSync(path.join(bin, tool + '.exe'), args, { env, input, encoding: 'utf8', windowsHide: true, timeout: 360000, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw Error(result.error?.message || result.stderr);
  return result.stdout;
}
const files = readdirSync('supabase/migrations').filter(file => file.endsWith('.sql') && file >= '20261029000000').sort();
const sources = new Map(files.map(file => ['supabase/migrations/' + file, readFileSync('supabase/migrations/' + file, 'utf8')]));
const fixturePath = `supabase/tests/specialized/${stage}.sql`;
sources.set('supabase/fixtures/specialized/execution-test-helpers.sql', readFileSync('supabase/fixtures/specialized/execution-test-helpers.sql', 'utf8'));
sources.set(fixturePath, readFileSync(fixturePath, 'utf8'));
const hashes = Object.fromEntries([...sources].map(([file, source]) => [file, createHash('sha256').update(source).digest('hex')]));
const report = { stage, database, startedAt: new Date().toISOString(), postgres: baseline.postgres, focusedOnly: true, hostedWrites: false, migrations: [], sourceHashes: hashes, assertions: 0, passed: false };
try {
  run('createdb', ['-T', baseline.database, database]);
  for (const file of files) {
    run('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', database], sources.get('supabase/migrations/' + file));
    report.migrations.push(file); console.log('PASS draft', file);
  }
  const source = sources.get(fixturePath);
  run('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', database], source);
  report.assertions = (source.match(/select pg_temp\.assert_true\(/g) ?? []).length;
  for (const [file, hash] of Object.entries(hashes)) if (createHash('sha256').update(readFileSync(file)).digest('hex') !== hash) throw Error('Focused candidate changed during validation; rerun exact files');
  report.passed = true; console.log(`PASS ${stage}: ${report.assertions} focused assertions`);
} catch (error) { report.error = error.message; console.error(error.message); process.exitCode = 1; }
finally { report.completedAt = new Date().toISOString(); writeFileSync(`docs/database/phase-2-specialized-${stage}-tests.json`, JSON.stringify(report, null, 2) + '\n'); }
