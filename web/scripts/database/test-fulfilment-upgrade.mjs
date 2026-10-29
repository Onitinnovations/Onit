import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';

export function testFulfilmentUpgrade({ run, env, archive, listPath, maxMigration = "20261029000000", expectedTables = 142 }) {
  if (env.PGHOST !== '127.0.0.1') throw Error('Loopback upgrade rehearsal required');
  const database = 'onit_execution_upgrade_' + Date.now();
  run('createdb', ['-T', 'template0', database]);
  run('pg_restore', ['--no-owner', '--exit-on-error', '--use-list', listPath, '-d', database, archive]);
  const sql = source => run('psql', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', database], source).trim();
  const files = readdirSync('supabase/migrations').filter(file => file.endsWith('.sql') && file < maxMigration).sort();
  for (const file of files.filter(file => file < '20261028000000')) sql(readFileSync('supabase/migrations/' + file, 'utf8'));
  sql(readFileSync('supabase/seed.sql', 'utf8'));
  const fixture = readFileSync('supabase/fixtures/catalogue-development.sql', 'utf8');
  for (const file of ['003_service_transactions.sql', '005_provider_network.sql', '006_personnel_resources.sql', '007_orders_dispatch.sql']) {
    sql(readFileSync('supabase/tests/' + file, 'utf8').replace('begin;', 'begin;\n' + fixture).replace(/rollback;\s*$/, 'commit;'));
  }
  // Original-column multisets remain inside this disposable database, never in evidence files.
  sql(`create table public._synthetic_upgrade_snapshot(schema_name text,table_name text,columns text[],original_rows jsonb);
    do $$declare relation record;columns text[];rows jsonb;begin
    for relation in select schemaname,tablename from pg_tables where schemaname in ('public','private') and tablename<>'_synthetic_upgrade_snapshot' order by schemaname,tablename loop
      select array_agg(attname::text order by attnum) into columns from pg_attribute where attrelid=format('%I.%I',relation.schemaname,relation.tablename)::regclass and attnum>0 and not attisdropped;
      execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from %I.%I t',relation.schemaname,relation.tablename) into rows;
      insert into public._synthetic_upgrade_snapshot values(relation.schemaname,relation.tablename,columns,rows);
    end loop;end$$;`);
  assert.equal(sql('select count(*) from public._synthetic_upgrade_snapshot'), '126');
  for (const file of files.filter(file => file >= '20261028000000')) sql(readFileSync('supabase/migrations/' + file, 'utf8'));
  const result = JSON.parse(sql(`select json_agg(json_build_object('schema',schema_name,'table',table_name,'rows',jsonb_array_length(original_rows))) from public._synthetic_upgrade_snapshot`));
  sql(`do $$declare snapshot record;missing bigint;begin
    for snapshot in select * from public._synthetic_upgrade_snapshot loop
      execute format('select count(*) from (select jsonb_array_elements($1) except all select (select jsonb_object_agg(key,value) from jsonb_each(to_jsonb(t)) where key=any($2)) from %I.%I t) missing',snapshot.schema_name,snapshot.table_name) into missing using snapshot.original_rows,snapshot.columns;
      if missing<>0 then raise exception 'Existing rows changed in %.%: %',snapshot.schema_name,snapshot.table_name,missing;end if;
    end loop;end$$;`);
  sql('drop table public._synthetic_upgrade_snapshot');
  assert.equal(sql("select count(*) from pg_tables where schemaname in ('public','private') and rowsecurity"), String(expectedTables));
  console.log('PASS Increment 4 upgrade: original-column row multisets preserved across all 126 baseline tables.');
  return { passed: true, database, checks: 3, tablesCompared: 126, originalRowsCompared: result.reduce((sum, table) => sum + table.rows, 0), tablesAfter: expectedTables };
}
