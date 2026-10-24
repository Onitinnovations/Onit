import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('../../', import.meta.url));
const db = new PGlite(); // In-memory only. Cannot connect to any remote database.
try {
  await db.exec(await readFile(`${root}/scripts/database/embedded-bootstrap.sql`, 'utf8'));
  const migrations = (await readdir(`${root}/supabase/migrations`)).filter(f => f.endsWith('.sql')).sort();
  for (const migration of migrations) {
    await db.exec(await readFile(`${root}/supabase/migrations/${migration}`, 'utf8'));
    console.log(`Applied to disposable embedded PostgreSQL: ${migration}`);
  }
  const seed = await readFile(`${root}/supabase/seed.sql`, 'utf8');
  await db.exec(seed);
  await db.exec(seed); // Reference seed must be repeatable.
  const [{areas,roles,countries,services,zones}] = (await db.query(`select
    (select count(*)::int from public.service_areas) as areas,
    (select count(*)::int from private.roles) as roles,
    (select count(*)::int from public.countries) as countries,
    (select count(*)::int from public.services) as services,
    (select count(*)::int from public.service_zones) as zones`)).rows;
  assert.deepEqual({areas,roles,countries,services,zones},{areas:4,roles:7,countries:1,services:0,zones:0});
  console.log('PASS reference seed: 5 count assertions after two passes; no invented services/zones.');
  const tests = (await readdir(`${root}/supabase/tests`)).filter(f => f.endsWith('.sql')).sort();
  const fixture = await readFile(`${root}/supabase/fixtures/catalogue-development.sql`, 'utf8');
  for (const test of tests) {
    const source = (await readFile(`${root}/supabase/tests/${test}`, 'utf8')).replace('begin;',`begin;\n${fixture}`);
    const results = await db.exec(source);
    const assertions = results.flatMap(r => r.rows).filter(r => r.assert_true);
    console.log(`PASS ${test}: ${assertions.length} assertions`);
  }
  if (process.argv.includes('--dictionary')) {
    const { writeDictionary } = await import('./write-dictionary.mjs');
    await writeDictionary(db, root);
  }
  if (process.argv.includes('--types')) {
    const { writeTypes } = await import('./write-types.mjs');
    await writeTypes(db, root);
  }
  console.log('Embedded SQL/RLS checks passed. Supabase Auth/Storage HTTP and concurrent-connection tests remain separate requirements.');
} catch (error) {
  console.error('Database verification failed:', error.message);
  if (error.detail) console.error(error.detail);
  if (error.where) console.error(error.where);
  process.exitCode = 1;
} finally {
  await db.close();
}
