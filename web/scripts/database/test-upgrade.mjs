import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { readFile,readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const db=new PGlite();
try {
  await db.exec(await readFile(`${root}/scripts/database/embedded-bootstrap.sql`,'utf8'));
  const migrations=(await readdir(`${root}/supabase/migrations`)).filter(f=>f.endsWith('.sql')).sort();
  for(const file of migrations.filter(f=>f<'20261024000700')) await db.exec(await readFile(`${root}/supabase/migrations/${file}`,'utf8'));
  await db.exec(await readFile(`${root}/supabase/seed.sql`,'utf8'));
  await db.exec(await readFile(`${root}/supabase/fixtures/catalogue-development.sql`,'utf8'));
  await db.exec(`insert into public.service_booking_fields(service_version_id,field_key,label,field_type,position)
    select v.id,'legacy','Existing published field','text',0 from public.service_versions v
    join public.services s on s.id=v.service_id where s.code='laundry';
    update public.service_areas set status='published' where code='home-utilities';
    update public.service_families set status='published' where code='laundry';
    update public.services set status='published' where code='laundry';
    update public.service_versions set status='published',published_at=now() where service_id=(select id from public.services where code='laundry');`);
  const before=(await db.query('select id,label,field_key from public.service_booking_fields')).rows;
  for(const file of migrations.filter(f=>f>='20261024000700')) await db.exec(await readFile(`${root}/supabase/migrations/${file}`,'utf8'));
  const after=(await db.query('select id,label,field_key from public.service_booking_fields')).rows;
  assert.deepEqual(after,before,'Additive form backfill must preserve identity and historical field content');
  await db.exec('set role anon;');
  const visible=(await db.query('select label from public.service_booking_fields')).rows;
  assert.equal(visible.length,1,'Previously published field remains visible after schema backfill');
  assert.equal(visible[0].label,'Existing published field');
  await db.exec('reset role;');
  const schemas=(await db.query('select status from public.service_booking_schemas where status=\'published\'')).rows;
  assert.equal(schemas.length,1,'Publication state retained across migration upgrade');
  console.log('PASS incremental upgrade: 4 assertions; legacy published content, IDs, visibility and schema state preserved.');
} catch(error) {
  console.error('Upgrade verification failed:',error.message);
  process.exitCode=1;
} finally { await db.close(); }
