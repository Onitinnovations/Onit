import {writeFile} from 'node:fs/promises';
const descriptions={
  "order_policies": "Independently approved effective service-version commercial and matching configuration; no operational defaults.",
  "service_orders": "Canonical account/branch-owned order and controlled pre-fulfilment state, exact schedule and verified coverage.",
  "order_commercial_versions": "Append-only accepted quotation links and currency-aware customer commercial snapshots; one order per accepted quote.",
  "order_authorizations": "Revision-bound independent external payment evidence, corporate terms or commercial exception decisions; not a payment ledger.",
  "order_changes": "Customer or staff amendments/rescheduling/cancellation proposals and independent decisions; preserves original intent.",
  "order_history": "Append-only actor/reason/permission/correlation and complete order metadata snapshots for every command.",
  "dispatch_candidates": "Append-only explainable eligibility/ranking snapshots tied to the order revision and approved policy.",
  "dispatch_proposals": "Exclusive all-or-nothing dispatch bundle, expiry, independent manual preference override and confirmation.",
  "assignment_offers": "Explicit addressed contractual-provider response; multiple companies may participate in one bundle.",
  "assignment_resources": "Immutable executing-person and existing provider/human reservation links; not a second capacity system.",
  "dispatch_escalations": "Restricted dispatch failures/exceptions and authorised resolution history."
};
descriptions.operational_events='Existing append-only outbox, extended with a typed order FK and provider-or-order domain constraint.';
descriptions.operational_event_deliveries='Existing lease/retry receipts, extended with explicit system-generated provenance and nullable creator only for system rows.';
const immutable=new Set(['order_commercial_versions','order_history','dispatch_candidates','assignment_resources','operational_events']);
const esc=value=>String(value??'').replaceAll('|','\\|').replaceAll('\n',' ');
export async function writeOrderDictionary(db,root){
 let md='# Increment 4 order/dispatch dictionary — local candidate\n\nGenerated from the successfully replayed PostgreSQL 17 catalog. The 11 new tables and two reused outbox tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increment-4-report.md). No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.\n\n';
 const names=Object.keys(descriptions);
 let erd='# Orders and Dispatch — physical FK graph\n\nLocal candidate. Actor/creator references are documented in the dictionary but omitted from this graph. Existing provider, human resource, quotation and customer references are reused.\n\n```mermaid\nflowchart LR\n';
 for(const name of names){
  const table=(await db.query(`select c.oid::int as oid,c.relrowsecurity as rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='${name}'`)).rows[0];
  if(!table?.rls)throw Error('Provider dictionary requires all expected RLS tables');
  const columns=(await db.query(`select a.attname as name,format_type(a.atttypid,a.atttypmod) as type,a.attnotnull as required,pg_get_expr(d.adbin,d.adrelid) as default_value from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=${table.oid} and a.attnum>0 and not a.attisdropped order by a.attnum`)).rows;
  const constraints=(await db.query(`select conname as name,contype as type,pg_get_constraintdef(oid) as definition from pg_constraint where conrelid=${table.oid} order by conname`)).rows;
  const indexes=(await db.query(`select indexdef as definition from pg_indexes where schemaname='private' and tablename='${name}' order by indexname`)).rows;
  const foreign=(await db.query(`select n.nspname as parent_schema,c.relname as parent from pg_constraint k join pg_class c on c.oid=k.confrelid join pg_namespace n on n.oid=c.relnamespace where k.conrelid=${table.oid} and k.contype='f'`)).rows;
  md+=`## private.${name}\n\n${descriptions[name]}\n\nOwner: ${name.startsWith('operational_')?'OnIt platform operations':'OnIt service operations'}. Lifecycle: ${immutable.has(name)?'append-only; mutation/deletion rejected by trigger':'retained; command-controlled lifecycle and audit; no ordinary client writes'}. RLS: enabled, default deny; privileged server maintenance remains trusted.\n\n| Column | Type | Required | Default |\n| --- | --- | --- | --- |\n`;
  for(const c of columns)md+=`| ${esc(c.name)} | ${esc(c.type)} | ${c.required?'yes':'no'} | ${esc(c.default_value)} |\n`;
  md+='\nConstraints (including FKs, unique and CHECK):\n\n';for(const c of constraints)md+=`- ${esc(c.name)}: ${esc(c.definition)}\n`;
  md+='\nIndexes:\n\n';for(const i of indexes)md+=`- ${esc(i.definition)}\n`;
  md+='\n';erd+=`    private_${name}["private.${name}"]\n`;
  for(const f of foreign)if(f.parent!=='profiles')erd+=`    private_${name} --> ${f.parent_schema}_${f.parent}["${f.parent_schema}.${f.parent}"]\n`;
 }
 erd+='```\n';
 await writeFile(root+'/docs/database/phase-2-increment-4-dictionary.md',md.trimEnd()+'\n');
 await writeFile(root+'/docs/database/phase-2-increment-4-erd.md',erd.trimEnd()+'\n');
 console.log('Generated order/dispatch dictionary and FK graph from 11 new and two reused secured tables.');
}
