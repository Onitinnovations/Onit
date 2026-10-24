import { readFile, readdir } from 'node:fs/promises';
import { localSql as sql, root } from './local-client.mjs';

const command = process.argv[2];
if (!['seed', 'test'].includes(command)) throw new Error('Usage: node scripts/database/local.mjs seed|test');
try {
  // Verify complete migration history before running tests against the fixed local container.
  const migrations = (await readdir(`${root}/supabase/migrations`)).filter(f => /^\d{14}_[a-z_]+\.sql$/.test(f)).sort();
  const applied = new Set(sql('select version from supabase_migrations.schema_migrations;').trim().split(/\s+/));
  for (const migration of migrations) {
    if (!applied.has(migration.slice(0, 14))) throw new Error(`Missing local migration ${migration}; run npm run db:migrate:local first.`);
  }
  if (command === 'seed') {
    sql(await readFile(`${root}/supabase/seed.sql`, 'utf8'));
    console.log('Reference seed applied to the fixed disposable local Supabase container.');
  } else {
    const files = (await readdir(`${root}/supabase/tests`)).filter(f => f.endsWith('.sql')).sort();
    const fixture = await readFile(`${root}/supabase/fixtures/catalogue-development.sql`, 'utf8');
    for (const file of files) {
      const source = (await readFile(`${root}/supabase/tests/${file}`, 'utf8')).replace('begin;',`begin;\n${fixture}`);
      sql(source);
      console.log(`PASS local Supabase SQL: ${file}`);
    }
    console.log('Local SQL checks passed. HTTP and concurrency suites are separate acceptance requirements.');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
