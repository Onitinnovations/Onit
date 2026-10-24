import { spawnSync } from 'node:child_process';
import { mkdir, writeFile, rename, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
// Invoke the pinned package entrypoint without shell interpolation or redirection.
const cli = fileURLToPath(new URL('../../node_modules/supabase/dist/supabase.js', import.meta.url));
const result = spawnSync(process.execPath, [cli, 'gen', 'types', 'typescript', '--local', '--schema', 'public'], {
  cwd: root, encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 32 * 1024 * 1024,
});
if (result.error || result.status !== 0 || !result.stdout?.includes('export type Database')) {
  console.error(result.error?.message || result.stderr || 'Type generation failed or returned invalid output; existing types were preserved.');
  process.exitCode = 1;
} else {
  await mkdir(`${root}/types`, { recursive: true });
  const temporary = `${root}/types/database.generated.ts.tmp`;
  try {
    await writeFile(temporary, result.stdout, 'utf8');
    await rename(temporary, `${root}/types/database.generated.ts`);
    console.log('Generated public-schema types from local Supabase.');
  } finally {
    await rm(temporary, { force: true });
  }
}
