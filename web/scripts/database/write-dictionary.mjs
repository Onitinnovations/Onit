import { writeFile } from 'node:fs/promises';

const esc = value => String(value ?? '—').replaceAll('|', '\\|').replaceAll('\n', ' ');
const immutable = new Set(['audit_logs','activity_events','service_locations','lead_activities','support_messages','customer_feedback','customer_consents','approval_steps']);
const descriptions = {
  service_booking_forms: 'Stable per-service booking form identity; published schemas carry immutable versions.',
  service_booking_schemas: 'Numbered effective form schema pinned to an exact service version.',
  service_booking_field_groups: 'Ordered same-schema groups with bounded repeatable occurrence counts.',
  service_booking_field_dependencies: 'Typed same-schema conditional display graph; cycles and hidden input leakage rejected.',
  service_booking_field_validation_rules: 'Allowlisted type-compatible numeric/length/cardinality validation definitions.',
  corporate_account_branches: 'Typed customer account to canonical organisation location mapping and cost attribution reference.',
  corporate_account_user_branches: 'Revocable branch-specific corporate requester/approver access grants.',
  corporate_billing_profiles: 'Private immutable activated centralized billing identity snapshots; no invoice system.',
  corporate_credit_terms: 'Private versioned payment-day configuration only; no credit balances, limits or execution.',
  countries: 'Country reference codes; only Nigeria is initially seeded.',
  currencies: 'Explicit transaction currency and minor-unit rounding reference; NGN only initially.',
  states: 'Country-scoped state reference; not an exhaustive official geography dataset.',
  cities: 'State-scoped city/operational labels, explicitly distinguished from official geography.',
  local_government_areas: 'State-scoped official LGA reference; no invented LGAs seeded.',
  service_zones: 'Versionable operational coverage labels; unverified Lagos pilot stays draft.',
  organisation_locations: 'Organisation-owned branch/site addresses with scoped unique codes.',
  departments: 'Organisation-scoped department hierarchy for future account and staff scopes.',
  teams: 'Organisation/department-consistent team definitions.',
  team_members: 'Explicit team membership requiring a matching organisation membership.',
  roles: 'Permission bundles with stable unique codes; no role grants from user metadata.',
  permissions: 'Stable action permission definitions maintained by access administrators.',
  role_permissions: 'Unique role-to-permission bridge.',
  user_role_assignments: 'Expiring/revocable role grants with checked global/organisation/team/self scopes.',
  user_preferences: 'User-owned locale/timezone preferences; provisioning command creates defaults.',
  user_devices: 'Private device installation metadata; token secrets stay outside this registry.',
  user_sessions_metadata: 'Private metadata about Auth-issued sessions, never an independent session system.',
  notification_preferences: 'Subject/channel/event notification choices, separate from marketing consent.',
  customer_addresses: 'Canonical account-owned saved address book; no duplicate saved_addresses base table.',
  customer_contacts: 'Account-owned named contact information with at least one contact method.',
  leads: 'Private CRM acquisition record, conversion state and optional canonical customer link.',
  lead_activities: 'Append-only internal chronology of lead communication and conversion activity.',
  opportunities: 'Private sales opportunity linked to a lead/account, with explicit value currency.',
  customer_segments: 'Private CRM segment reference definitions.',
  customer_segment_assignments: 'Unique account-to-segment membership bridge.',
  customer_notes: 'Internal CRM notes, never returned to customers by default.',
  customer_tags: 'Private CRM classification tag definitions.',
  customer_tag_assignments: 'Unique canonical account/tag associations.',
  support_tickets: 'Account-owned support case with retained status and closure timestamp.',
  support_messages: 'Append-only case conversation with explicit internal/customer visibility.',
  customer_feedback: 'Append-only account feedback with bounded rating; future order phase adds typed service links.',
  customer_consents: 'Append-only purpose/policy-version grants and withdrawals with evidence.',
  communication_preferences: 'Account/channel/purpose operational contact choices.',
  service_areas: 'The four plain service-area roots; anonymous reads require publication.',
  service_families: 'Service-area-scoped service grouping and publication boundary.',
  services: 'Stable plain-name service identity, slug and family association.',
  service_variants: 'Version-owned selectable service variants; historical choices remain pinned.',
  service_options: 'Version-owned required/optional service configuration options.',
  service_option_values: 'Typed values constrained to their option and service version.',
  service_requirements: 'Version-owned customer/provider preparation and qualification requirements.',
  service_booking_fields: 'Version-owned typed request intake fields with stable keys and ordering.',
  service_booking_field_options: 'Selectable answer values tied to the exact field/version.',
  service_checklists: 'Version-owned assessment, execution or QA checklist definitions; not publicly exposed.',
  service_checklist_items: 'Required and ordered checks tied to the exact checklist/version.',
  city_service_availability: 'Effective city-level service gate, published only while explicitly enabled.',
  service_exclusions: 'Published-version exclusions retained with historical service terms.',
  service_faqs: 'Version-owned FAQ snapshots; future CMS may link shared FAQ sources without losing historical text.',
  service_media: 'Ordered catalogue media links restricted to clean, reviewed public marketing assets.',
  zone_transport_rates: 'Private explicit currency transport rates; seed contains no invented rates.',
  profiles: 'Neutral application identity linked one-to-one to Supabase Auth.',
  organisations: 'Customer, supplier, provider or internal legal/business entity.',
  organisation_members: 'Approved/expiring/revocable organisation access membership.',
  employee_profiles: 'Minimal internal employment anchor; later HR phase extends this table.',
  customer_profiles: 'Canonical account owned by exactly one individual or organisation.',
  corporate_accounts: 'Corporate customer account approval and commercial access gate.',
  corporate_account_users: 'Explicit account and department access, separate from organisation membership.',
  service_locations: 'Immutable account-owned service address snapshot.',
  service_versions: 'Versioned service specification and configurable payment gate; published content immutable.',
  document_objects: 'Classified ownership and scanning registry for exact Storage bucket/object names.',
  customer_documents: 'Typed account/document link with composite tenant foreign key.',
  audit_logs: 'Append-only access/security event history without copied sensitive row payloads.',
  activity_events: 'Append-only subject-specific, sanitized user activity feed.',
  approval_policies: 'Versioned maker/checker policy configuration; no live approval executor yet.',
  approval_requests: 'Approval routing root; later domains add typed target/version links.',
  approval_steps: 'Append-only independent approval decisions; self-approval blocked by constraint.',
  system_configurations: 'Versioned private non-secret settings; wallet/payout/live email disabled.',
  service_rate_cards: 'Private versioned pricing configuration, never customer-editable.',
  service_pricing_rules: 'Private fixed/unit/assessment pricing inputs with rate-card currency integrity.',
  service_availability: 'Private zone-level approved service availability windows.',
  zone_boundaries_or_coverage: 'Versioned operational city/LGA coverage, not invented official polygons.',
};

export async function writeDictionary(db, root) {
  const tables = (await db.query(`select c.oid::int as oid,n.nspname as schema,c.relname as name,c.relrowsecurity as rls,
    pg_get_userbyid(c.relowner) as owner from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','private') order by n.nspname,c.relname`)).rows;
  let output = '# Implemented foundation data dictionary\n\n';
  output += 'Generated by `npm run db:dictionary` from disposable embedded PostgreSQL catalogs after migrations, two seed passes and security assertions succeed. This documents implemented foundation SQL only; it does not certify Supabase HTTP or production behavior. Planned later-domain tables remain in [schema-inventory.md](schema-inventory.md).\n\n';
  output += 'Physical owner is the trusted migration role (shown below); business ownership and exposure come from subject FKs, grants and policies. Security-definer helpers run as this trusted owner, bypassing owner RLS to avoid recursion; FORCE RLS is deliberately absent. Never grant this role to users or ship service-role credentials.\n\n';
  output += 'All ON DELETE rules below are derived from actual constraints. Mutable rows use the `onit_updated_at` trigger. Historical records are retained with archival/status fields or immutable mutation guards; no general end-user DELETE is granted. Private tables have no browser policy or grants. The generic purpose for any unannotated table is its typed entity role described in the capability inventory.\n\n';
  output += `Implemented base tables: **${tables.length}**. Schemas: public and private; helper functions in app_private.\n\n`;
  for (const table of tables) {
    const columns = (await db.query(`select a.attname as name,format_type(a.atttypid,a.atttypmod) as type,
      a.attnotnull as required,pg_get_expr(d.adbin,d.adrelid) as default_value
      from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
      where a.attrelid=$1 and a.attnum>0 and not a.attisdropped order by a.attnum`, [table.oid])).rows;
    const constraints = (await db.query(`select conname as name,pg_get_constraintdef(oid) as definition
      from pg_constraint where conrelid=$1 order by contype,conname`, [table.oid])).rows;
    const indexes = (await db.query(`select indexname,indexdef from pg_indexes where schemaname=$1 and tablename=$2 order by indexname`, [table.schema,table.name])).rows;
    const policies = (await db.query(`select policyname,roles,cmd,qual,with_check from pg_policies where schemaname=$1 and tablename=$2 order by policyname`, [table.schema,table.name])).rows;
    const grants = (await db.query(`select grantee,privilege_type from information_schema.role_table_grants
      where table_schema=$1 and table_name=$2 and grantee in ('anon','authenticated','service_role') order by grantee,privilege_type`, [table.schema,table.name])).rows;
    const columnGrants = (await db.query(`select grantee,column_name,privilege_type from information_schema.column_privileges
      where table_schema=$1 and table_name=$2 and grantee in ('anon','authenticated') and privilege_type<>'SELECT'
      order by grantee,column_name,privilege_type`, [table.schema,table.name])).rows;
    output += `## ${table.schema}.${table.name}\n\n`;
    output += `${descriptions[table.name] || table.name.replaceAll('_',' ') + ' records; see the capability inventory for domain intent.'}\n\n`;
    output += `Owner: \`${table.owner}\`. RLS: **${table.rls ? 'enabled' : 'DISABLED'}**. Business boundary: ${table.schema === 'private' ? 'private operations with no direct browser access' : columns.some(c=>c.name==='customer_account_id') ? 'customer account and explicit staff permission' : 'subject or publication boundary defined by policies below'}. Lifecycle: ${immutable.has(table.name) ? 'append-only; corrections require new records' : table.name.startsWith('service_') ? 'draft configuration; version-owned content frozen at publication; archive/retire historical versions' : 'mutable with timestamp trigger; archive/revoke where supported, retain referenced history'}.\n\n`;
    output += '| Column | PostgreSQL type | Required | Default |\n| --- | --- | --- | --- |\n';
    output += columns.map(c=>`| ${esc(c.name)} | ${esc(c.type)} | ${c.required?'yes':'no'} | ${esc(c.default_value)} |`).join('\n')+'\n\n';
    output += '| Constraint | Definition (includes foreign keys, uniqueness and deletion rule) |\n| --- | --- |\n';
    output += constraints.map(c=>`| ${esc(c.name)} | ${esc(c.definition)} |`).join('\n')+'\n\n';
    output += '| Index | Definition | Query/integrity purpose |\n| --- | --- | --- |\n';
    output += indexes.map(i=>`| ${esc(i.indexname)} | ${esc(i.indexdef)} | ${i.indexname.startsWith('onit_fk_')?'Referencing-FK joins and parent deletion checks':i.indexdef.includes('UNIQUE')?'Primary/scoped uniqueness and indexed lookup':'Account/subject filtering, time ordering or operational queue filtering'} |`).join('\n')+'\n\n';
    output += '**RLS policies**\n\n';
    if (!policies.length) output += 'No policies: deny by default for non-bypass roles. Authorized server service-role operations only.\n\n';
    else {
      output += '| Policy | Roles | Action | USING | WITH CHECK |\n| --- | --- | --- | --- | --- |\n';
      output += policies.map(p=>`| ${esc(p.policyname)} | ${esc(p.roles)} | ${esc(p.cmd)} | ${esc(p.qual)} | ${esc(p.with_check)} |`).join('\n')+'\n\n';
    }
    output += '**Grants:** '+grants.map(g=>`${esc(g.grantee)}:${esc(g.privilege_type)}`).join(', ')+'.\n\n';
    if(columnGrants.length) output += '**Column write grants:** '+columnGrants.map(g=>`${esc(g.grantee)}:${esc(g.privilege_type)}(${esc(g.column_name)})`).join(', ')+'.\n\n';
  }
  const funcs=(await db.query(`select n.nspname as schema,p.proname as name,pg_get_function_identity_arguments(p.oid) as args,
    p.prosecdef as definer,p.proconfig as config from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','app_private') order by n.nspname,p.proname`)).rows;
  output+='## Functions and RPC boundary\n\n| Function | Identity arguments | Security | Settings |\n| --- | --- | --- | --- |\n';
  output+=funcs.map(f=>`| ${esc(f.schema)}.${esc(f.name)} | ${esc(f.args)} | ${f.definer?'definer (trusted migration owner)':'invoker'} | ${esc(f.config)} |`).join('\n')+'\n';
  await writeFile(`${root}/docs/database/data-dictionary.md`,output,'utf8');
  const fks=(await db.query(`select cn.nspname as child_schema,c.relname as child,pn.nspname as parent_schema,p.relname as parent,
    con.conname as name from pg_constraint con join pg_class c on c.oid=con.conrelid
    join pg_namespace cn on cn.oid=c.relnamespace join pg_class p on p.oid=con.confrelid
    join pg_namespace pn on pn.oid=p.relnamespace
    where con.contype='f' and cn.nspname in ('public','private') order by cn.nspname,c.relname,con.conname`)).rows;
  let erd='# Implemented foundation FK graph\n\nGenerated from actual foundation PostgreSQL foreign keys. Arrows point from child to referenced parent; the data dictionary specifies optionality, composite columns and uniqueness. This is distinct from the [full-platform conceptual ERD](erd.md).\n\n```mermaid\nflowchart LR\n';
  for(const t of tables) erd+=`    ${t.schema}_${t.name}["${t.schema}.${t.name}"]\n`;
  erd+='    auth_users["auth.users (Supabase-managed)"]\n';
  // Keep actor metadata edges in the dictionary so they do not obscure the business graph.
  for(const fk of fks.filter(f=>f.parent!=='profiles' || f.child==='profiles')) {
    erd+=`    ${fk.child_schema}_${fk.child} --> ${fk.parent_schema}_${fk.parent}\n`;
  }
  erd+='```\n\nProfile/created_by/actor foreign keys are omitted from this graph for readability and are fully enumerated in the dictionary.\n';
  await writeFile(`${root}/docs/database/foundation-erd.md`,erd,'utf8');
  console.log(`Generated dictionary from ${tables.length} implemented tables.`);
}
