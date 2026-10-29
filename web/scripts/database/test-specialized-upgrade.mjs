import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { isDeepStrictEqual } from 'node:util';

export function testSpecializedUpgrade({ run, env, candidateDatabase }) {
  if (env.PGHOST !== '127.0.0.1') throw Error('Isolated loopback upgrade required');
  const baseline = JSON.parse(readFileSync('docs/database/phase-2-fulfilment-test-results.json', 'utf8'));
  if (!baseline.passed || baseline.migrations.length !== 32 || !/^onit_phase2_\d+$/.test(baseline.database)) throw Error('Preserved passing Increment 5 baseline required');
  for (const [file, hash] of Object.entries(baseline.migrationHashes)) assert.equal(createHash('sha256').update(readFileSync('supabase/migrations/' + file)).digest('hex'), hash);
  const database = 'onit_specialized_upgrade_' + Date.now();
  run('createdb', ['-T', baseline.database, database]);
  const sql = source => run('psql', ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', database], source).trim();
  sql(`create table public._synthetic_specialized_snapshot(schema_name text,table_name text,columns text[],original_rows jsonb);
    do $$declare relation record;columns text[];rows jsonb;begin
    for relation in select schemaname,tablename from pg_tables where schemaname in ('public','private') and tablename<>'_synthetic_specialized_snapshot' order by schemaname,tablename loop
      select array_agg(attname::text order by attnum) into columns from pg_attribute where attrelid=format('%I.%I',relation.schemaname,relation.tablename)::regclass and attnum>0 and not attisdropped;
      execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from %I.%I t',relation.schemaname,relation.tablename) into rows;
      insert into public._synthetic_specialized_snapshot values(relation.schemaname,relation.tablename,columns,rows);
    end loop;end$$;`);
  assert.equal(sql('select count(*) from public._synthetic_specialized_snapshot'), '142');
  const originalRows = Number(sql('select sum(jsonb_array_length(original_rows)) from public._synthetic_specialized_snapshot'));
  for (const file of readdirSync('supabase/migrations').filter(file => file.endsWith('.sql') && file >= '20261029000000').sort()) sql(readFileSync('supabase/migrations/' + file, 'utf8'));
  sql(`do $$declare snapshot record;missing bigint;begin
    for snapshot in select * from public._synthetic_specialized_snapshot loop
      execute format('select count(*) from (select jsonb_array_elements($1) except all select (select jsonb_object_agg(key,value) from jsonb_each(to_jsonb(t)) where key=any($2)) from %I.%I t) missing',snapshot.schema_name,snapshot.table_name) into missing using snapshot.original_rows,snapshot.columns;
      if missing<>0 then raise exception 'Increment 5 rows changed in %.%: %',snapshot.schema_name,snapshot.table_name,missing;end if;
    end loop;end$$;`);
  sql('drop table public._synthetic_specialized_snapshot');
  assert.equal(sql("select count(*) from pg_tables where schemaname in ('public','private') and rowsecurity"), '180');
  assert.equal(sql("select count(*) from private.user_role_assignments assignment join private.role_permissions grant_row on grant_row.role_id=assignment.role_id join private.permissions permission on permission.id=grant_row.permission_id where permission.code like 'specialized.%' or permission.code in('procurement.source','procurement.approve','supplier.portal')"), '0');
  if(!/^onit_phase2_\d+$/.test(candidateDatabase??''))throw Error('Validated fresh candidate database required for upgrade definition comparison');
  const signature=readFileSync('supabase/inspection/application_signature.sql','utf8');
  assert.ok(isDeepStrictEqual(JSON.parse(sql(signature)),JSON.parse(run('psql',['-X','-q','-t','-A','-v','ON_ERROR_STOP=1','-d',candidateDatabase],signature))), 'Fresh and Increment 5 upgrade application definitions must match exactly');
  console.log('PASS Increment 5 upgrade: 142 original-column row multisets preserved; no automatic operational grants.');
  return { passed: true, database, checks: 4, definitionMatch: true, tablesCompared: 142, originalRowsCompared: originalRows, tablesAfter: 180 };
}
