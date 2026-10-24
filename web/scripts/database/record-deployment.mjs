import { readFileSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const recovery=JSON.parse(readFileSync('.local-tools/native17-recovery-report.json','utf8'));
const hosted=JSON.parse(readFileSync('docs/database/hosted-verification.json','utf8'));
const api=JSON.parse(readFileSync('docs/database/hosted-api-verification.json','utf8'));
if(!recovery.backupVerified||!recovery.validationPassed||hosted.migrations.length!==12||api.checks.some(check=>!check.passed))throw new Error('Incomplete deployment evidence.');
for(const line of readFileSync('docs/database/deployment-candidate.sha256','utf8').trim().split(/\r?\n/)){
  const [hash,file]=line.split(/\s+/,2);
  if(createHash('sha256').update(readFileSync(file)).digest('hex')!==hash)throw new Error('Deployment candidate changed: '+file);
}
const migrations=recovery.migrationsValidated.map(file=>`- [${file}](../../supabase/migrations/${file})`).join('\n');
const report=`# OnIt Phase 1 hosted deployment — completed

Verified 2026-10-24, Africa/Lagos. The founder's safe deployment authorisation was used. No reset, destructive reconciliation, data deletion, AWS deployment or unrelated hosted object replacement was performed.

| Result | Evidence |
| --- | --- |
| Target | **OnIt**, project reference \`utoxjlsvqfmmzsjruzsm\`, organisation \`eomxnfczgtmqltntxhjj\`, region \`eu-west-1\`, ACTIVE_HEALTHY. Exact configured application hostname matched; no separate production/test label is asserted. |
| PostgreSQL | **17.11**, verified remotely and matched by native local PostgreSQL 17.11. |
| Initial inventory | No public/private/app_private application objects, migration history, Auth users, Storage objects/buckets or Vault secrets. Provider-managed Auth/Storage objects retained. No application naming conflicts. |
| Recovery | Native custom-format logical archive of public/Auth/Storage/extensions, **${recovery.backupBytes} bytes**, successfully restored into a new isolated PostgreSQL 17.11 database; baseline counts verified. Archive: \`${recovery.backupArchive}\` (ignored local file). SHA-256: \`${recovery.backupSha256}\`. This is a verified predeployment logical recovery artifact, not a managed physical/PITR backup or complete recreation of Supabase services/roles. Backup API listed no usable managed recovery point; archive must be retained securely. |
| Migrations | All **12** applied through official CLI; none previously present. Final dry run: upToDate=true, pending migrations=[]. Candidate hashes matched before report. |
| Tables | **79**, comprising **45 public / 34 private**; all have RLS enabled. |
| Security | **48** application policies; zero unvalidated constraints, disabled guards, unsafe definer search paths, public SECURITY DEFINER functions or PUBLIC execution grants on internal functions. Neither anon nor authenticated has private-schema USAGE. Private/helper API schema requests return HTTP406; anonymous customer read returns401. |
| Storage | Seven private sensitive-document buckets and one separate public marketing-assets bucket; actual settings verified. |
| Reference data | Nigeria, NGN, Lagos State, four approved draft service areas, seven baseline roles/permissions and safe disabled settings. No users, employees, customers, services, prices, packages or operational zones created. |
| Application | Public anon configuration corrected locally without logging keys; Auth settings and public catalogue HTTP200. Catalogue remains draft, so anonymous catalogue results are empty by design. Official public-schema TypeScript types generated from hosted project. |
| Phase 2 | Hosted foundation is ready for Phase 2 development. Booking/dispatch/provider allocation/payment/wallet workflows remain outside Phase 1. |

## Applied migration inventory

${migrations}

## Commands and validation

1. Official CLI project/branch/backup inspection and read-only catalog inventory verified target and empty application baseline.
2. \`powershell -File scripts/database/setup-native-postgres.ps1\`: portable official EDB PostgreSQL17.11 archive verified against publisher SHA-256; no Windows service/boot changes. Docker remained unavailable, so it was bypassed using native tools.
3. \`node scripts/database/native17-recovery-validate.mjs\`: backup, successful restore rehearsal, all12 migrations, seed twice and **126 SQL assertions passed** against the restored actual Auth/Storage baseline on17.11. Covers Auth provisioning, individual/corporate isolation, staff/provider/supplier access, unauthorised writes, privileges and configuration integrity. Fixtures ran only locally in rollback transactions.
4. \`node node_modules/supabase/dist/supabase.js db push --linked --project-ref utoxjlsvqfmmzsjruzsm --skip-vault --dry-run\`: exact12 pending. Same command with \`--yes\` replacing \`--dry-run\`: all12 successfully applied. No forced migration-history repair.
5. \`node node_modules/supabase/dist/supabase.js db query --linked --project-ref utoxjlsvqfmmzsjruzsm --file supabase/seed.sql --output json\`: seed applied separately, successfully.
6. \`node scripts/database/verify-hosted-deployment.mjs\`: catalog/security checks and five hosted HTTP checks passed; generated types via official \`gen types typescript --project-id utoxjlsvqfmmzsjruzsm --schema public\`.
7. Final official migration dry run: no pending migrations.
8. \`node node_modules/typescript/bin/tsc --noEmit\` and \`node node_modules/eslint/bin/eslint.js .\`: both passed, exit0. \`git diff --check\` passed (Windows line-ending notices only).

## Failures resolved and remaining limits

Initial native restore collided with the already-existing public schema in a fresh disposable database; restore now skips only that schema-creation TOC entry, preserving all content/ACL entries. Initial native backup needed SET ROLE postgres for managed schema access; corrected. Initial lint scanned downloaded pgAdmin dependencies; ignored local tooling is now excluded from ESLint and the full app lint rerun passed. Earlier invalid zero-byte backup is not used. No failed hosted migration occurred.

Authenticated customer/corporate/provider/supplier isolation was tested with SQL roles and synthetic identities on the isolated PostgreSQL17.11 replay; no synthetic accounts were inserted hosted. Real signed-in browser flows, Storage upload/download HTTP, concurrent clients, hosted recovery execution and complete Supabase Docker-stack tests were not run. Actual hosted policies/grants and anonymous API boundaries were verified. Ongoing automated managed backup/PITR and secure off-machine backup retention still require operational setup; no paid plan was enabled.

Evidence: [hosted catalog](hosted-verification.json), [API checks](hosted-api-verification.json), [predeployment inventory](hosted-predeployment-inventory.json), [candidate hashes](deployment-candidate.sha256), [Phase 1 implementation inventory](phase-1-report.md). Recovery execution details remain in ignored \`.local-tools/native17-recovery-report.json\`; archive contains sensitive operational metadata and must not be committed.

The local .env.local public anon value was updated; no secret/service-role key was exposed or committed. No Next.js feedback candidate was observed.
`;
writeFileSync('docs/database/hosted-deployment-report.md',report);
for(const file of ['docs/database/implementation-status.md','docs/database/phase-1-report.md','docs/database/phase-1-deployment.md']){
  const old=readFileSync(file,'utf8');
  const notice='> **Current hosted status (2026-10-24): Phase 1 deployed and verified on OnIt, PostgreSQL 17.11. All 12 migrations applied; 79 tables have RLS. Native backup restore and 126 SQL assertions passed. Official hosted types and app checks passed. See [hosted deployment report](hosted-deployment-report.md). Earlier blocked-readiness statements below are historical and superseded.\n\n';
  writeFileSync(file,notice+old);
}
console.log('Recorded verified hosted deployment; candidate hashes unchanged.');
