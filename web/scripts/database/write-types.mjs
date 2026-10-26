import { mkdir, writeFile, rename } from 'node:fs/promises';

const key = value => JSON.stringify(value);
const tsType = type => {
  if (type.endsWith('[]')) return `(${tsType(type.slice(0,-2))})[]`;
  if (['boolean','bool'].includes(type)) return 'boolean';
  if (/^(smallint|integer|bigint|numeric|decimal|real|double precision)/.test(type)) return 'number';
  if (['json','jsonb'].includes(type)) return 'Json';
  if (type==='void') return 'undefined';
  return 'string';
};

// Supabase-compatible public API types derived from the tested PostgreSQL catalog.
// This fallback does not claim to be official CLI output or a hosted schema dump.
export async function writeTypes(db,root,options={}) {
  const tables=(await db.query(`select c.oid::int as oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' order by c.relname`)).rows;
  let out=`// GENERATED from tested ${options.source||'embedded PostgreSQL'} catalogs, not hosted Supabase.\n`;
  out+=`// Regenerate: ${options.command||'npm run db:types:embedded'}. Prefer official Supabase CLI output after deployment.\n`;
  out+='export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];\n\n';
  out+='export type Database = {\n  public: {\n    Tables: {\n';
  for(const table of tables) {
    const columns=(await db.query(`select a.attname,format_type(a.atttypid,a.atttypmod) as type,a.attnotnull,
      a.attgenerated,pg_get_expr(d.adbin,d.adrelid) as default_value from pg_attribute a
      left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
      where a.attrelid=$1 and a.attnum>0 and not a.attisdropped order by a.attnum`,[table.oid])).rows;
    out+=`      ${key(table.relname)}: {\n`;
    for(const mode of ['Row','Insert','Update']) {
      out+=`        ${mode}: {\n`;
      for(const col of columns) {
        const generated=mode!=='Row' && Boolean(col.attgenerated);
        const optional=mode==='Update' || (mode==='Insert' && (generated || !col.attnotnull || col.default_value!==null));
        out+=`          ${key(col.attname)}${optional?'?':''}: ${generated?'never':tsType(col.type)+(col.attnotnull?'':' | null')};\n`;
      }
      out+='        };\n';
    }
    const fks=(await db.query(`select con.conname,p.relname as parent,
      array(select a.attname from unnest(con.conkey) with ordinality x(k,pos)
        join pg_attribute a on a.attrelid=con.conrelid and a.attnum=x.k order by x.pos) as columns,
      array(select a.attname from unnest(con.confkey) with ordinality x(k,pos)
        join pg_attribute a on a.attrelid=con.confrelid and a.attnum=x.k order by x.pos) as referenced,
      exists(select 1 from pg_constraint u where u.conrelid=con.conrelid and u.contype in ('p','u') and u.conkey=con.conkey) as one
      from pg_constraint con join pg_class p on p.oid=con.confrelid join pg_namespace n on n.oid=p.relnamespace
      where con.conrelid=$1 and con.contype='f' and n.nspname='public' order by con.conname`,[table.oid])).rows;
    out+='        Relationships: [\n';
    for(const fk of fks) out+=`          { foreignKeyName: ${key(fk.conname)}; columns: ${JSON.stringify(fk.columns)}; isOneToOne: ${fk.one}; referencedRelation: ${key(fk.parent)}; referencedColumns: ${JSON.stringify(fk.referenced)} },\n`;
    out+='        ];\n      };\n';
  }
  out+='    };\n    Views: { [_ in never]: never };\n    Functions: {\n';
  const functions=(await db.query(`select p.proname,p.proargnames,p.proargtypes::oid[]::int[] as arg_types,p.pronargdefaults,
    format_type(p.prorettype,null) as result from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' order by p.proname`)).rows;
  for(const fn of functions) {
    out+=`      ${key(fn.proname)}: { Args: ${fn.arg_types.length?'{':'Record<PropertyKey, never>'}`;
    for(let i=0;i<fn.arg_types.length;i++) {
      const [{type}]=(await db.query('select format_type($1::oid,null) as type',[fn.arg_types[i]])).rows;
      out+=` ${key(fn.proargnames[i])}${i>=fn.arg_types.length-fn.pronargdefaults?'?':''}: ${tsType(type)};`;
    }
    out+=`${fn.arg_types.length?' }':''}; Returns: ${tsType(fn.result)} };\n`;
  }
  out+='    };\n    Enums: { [_ in never]: never };\n    CompositeTypes: { [_ in never]: never };\n  };\n};\n';
  out+='export type PublicTableName = keyof Database["public"]["Tables"];\n';
  out+='export type TableRow<T extends PublicTableName> = Database["public"]["Tables"][T]["Row"];\n';
  await mkdir(`${root}/types`,{recursive:true});
  const filename=options.filename||'database.generated.ts';
  await writeFile(`${root}/types/${filename}.tmp`,out,'utf8');
  await rename(`${root}/types/${filename}.tmp`,`${root}/types/${filename}`);
  console.log(`Generated public API types from ${tables.length} tested PostgreSQL tables; private schemas excluded.`);
}
