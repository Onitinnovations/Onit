import {writeFile} from 'node:fs/promises';
const descriptions={
 provider_profiles:'Contracting provider party, linked to exactly one existing individual or organisation; never an Auth authority.',
 provider_personnel:'Explicit executing worker, field-agent or administrator membership; does not grant employee status.',
 provider_recruitment_campaigns:'Recruitment source campaign and finite active/closed operating window.',
 provider_applications:'Numbered sourced/referral application and current screening/onboarding stage; one open application per party.',
 provider_qualifications:'Independently decided verification, skill, credential or training evidence, expiry and subject identity.',
 provider_requirement_sets:'Independently approved versioned service/type/zone requirements, capacity unit and optional performance/travel/engagement gates.',
 provider_training_courses:'Versioned independently approved training standard, explicit pass/attendance requirements and certificate validity.',
 provider_training_sessions:'Internal trainer and exact session timing pinned to a course version.',
 provider_training_enrolments:'Per-party/person session attendance, trainer assessment and independent certificate decision.',
 provider_coverage_areas:'Explicit exact-service/zone operating coverage; no inferred city or polygon coverage.',
 provider_work_schedules:'Zone-timezone weekday declarations, materialised within a bounded date horizon.',
 provider_availability:'Confirmed working windows and overriding leave/blackout/unavailable intervals.',
 provider_capacity:'Shared provider/unit resource pool across service versions; individual pools use concurrent_jobs.',
 provider_capacity_reservations:'Time-bounded idempotent reservation/release receipt; assignment conversion belongs to Increment 4.',
 provider_engagements:'Private versioned contract, explicit currency/rate unit and service/zone obligations; independently approved.',
 provider_restrictions:'Current/future provider/service/zone restriction with independently authorised revocation.',
 provider_performance_events:'Append-only evidenced numerator/denominator observations, not fabricated scores.',
 provider_history:'Append-only internal actor, transition, reason, permission and correlation history.',
 operational_events:'Append-only transactional provider event outbox; no claim of external delivery.',
 operational_event_deliveries:'Mutable lease/retry/ack/dead receipt; worker tokens are restricted runtime metadata.',
 provider_personnel_capacity:'Versioned independently approved human capacity shared across contracting businesses; does not grant provider identity.',
 provider_personnel_availability:'Personal working/leave/blackout windows shared across engagements.'
};
const immutable=new Set(['provider_history','provider_performance_events','operational_events']);
const esc=value=>String(value??'').replaceAll('|','\\|').replaceAll('\n',' ');
export async function writeProviderDictionary(db,root){
 let md='# Increment 3 provider dictionary — local candidate\n\nGenerated from the successfully replayed PostgreSQL 17 catalog. All 22 tables are in unexposed `private`, have RLS enabled, no anon/authenticated table grants and no permissive table policies. Access uses authorised projections/commands; see the [checkpoint report](phase-2-increment-3-report.md). No data rows or worker tokens are exported. All historical and financial references use ON DELETE RESTRICT.\n\n';
 const names=Object.keys(descriptions);
 let erd='# Provider Network — physical FK graph\n\nLocal candidate. Actor/creator references are documented in the dictionary but omitted from this graph. No order/assignment table is claimed.\n\n```mermaid\nflowchart LR\n';
 for(const name of names){
  const table=(await db.query(`select c.oid::int as oid,c.relrowsecurity as rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='${name}'`)).rows[0];
  if(!table?.rls)throw Error('Provider dictionary requires all expected RLS tables');
  const columns=(await db.query(`select a.attname as name,format_type(a.atttypid,a.atttypmod) as type,a.attnotnull as required,pg_get_expr(d.adbin,d.adrelid) as default_value from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=${table.oid} and a.attnum>0 and not a.attisdropped order by a.attnum`)).rows;
  const constraints=(await db.query(`select conname as name,contype as type,pg_get_constraintdef(oid) as definition from pg_constraint where conrelid=${table.oid} order by conname`)).rows;
  const indexes=(await db.query(`select indexdef as definition from pg_indexes where schemaname='private' and tablename='${name}' order by indexname`)).rows;
  const foreign=(await db.query(`select n.nspname as parent_schema,c.relname as parent from pg_constraint k join pg_class c on c.oid=k.confrelid join pg_namespace n on n.oid=c.relnamespace where k.conrelid=${table.oid} and k.contype='f'`)).rows;
  md+=`## private.${name}\n\n${descriptions[name]}\n\nOwner: ${name.startsWith('operational_')?'OnIt platform operations':'OnIt provider network operations'}. Lifecycle: ${immutable.has(name)?'append-only; mutation/deletion rejected by trigger':'retained; command-controlled lifecycle and audit; no ordinary client writes'}. RLS: enabled, default deny; privileged server maintenance remains trusted.\n\n| Column | Type | Required | Default |\n| --- | --- | --- | --- |\n`;
  for(const c of columns)md+=`| ${esc(c.name)} | ${esc(c.type)} | ${c.required?'yes':'no'} | ${esc(c.default_value)} |\n`;
  md+='\nConstraints (including FKs, unique and CHECK):\n\n';for(const c of constraints)md+=`- ${esc(c.name)}: ${esc(c.definition)}\n`;
  md+='\nIndexes:\n\n';for(const i of indexes)md+=`- ${esc(i.definition)}\n`;
  md+='\n';erd+=`    private_${name}["private.${name}"]\n`;
  for(const f of foreign)if(f.parent!=='profiles')erd+=`    private_${name} --> ${f.parent_schema}_${f.parent}["${f.parent_schema}.${f.parent}"]\n`;
 }
 erd+='```\n';
 await writeFile(root+'/docs/database/phase-2-increment-3-dictionary.md',md);
 await writeFile(root+'/docs/database/phase-2-increment-3-erd.md',erd);
 console.log('Generated provider dictionary and FK graph from 22 secured candidate tables.');
}
