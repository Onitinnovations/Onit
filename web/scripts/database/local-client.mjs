import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const root = fileURLToPath(new URL('../../', import.meta.url));
const container = 'supabase_db_onit-foundation';
const dockerHost = process.env.DOCKER_HOST;
if (dockerHost && !dockerHost.startsWith('npipe:') && !dockerHost.startsWith('unix:')) {
  throw new Error('Refusing a potentially remote DOCKER_HOST. Use a local Docker engine.');
}
// Pin a local socket; a selected SSH/TCP Docker context must never redirect tests.
const localEngine = process.platform === 'win32'
  ? 'npipe:////./pipe/dockerDesktopLinuxEngine'
  : (dockerHost?.startsWith('unix:') ? dockerHost : 'unix:///var/run/docker.sock');
const localEnvironment = { ...process.env, DOCKER_HOST: localEngine };
delete localEnvironment.DOCKER_CONTEXT;
const candidates = process.platform === 'win32' ? [
  path.join(process.env.LOCALAPPDATA || '', 'Programs/DockerDesktop/resources/bin/docker.exe'),
  path.join(process.env.ProgramFiles || '', 'Docker/Docker/resources/bin/docker.exe'),
  'docker',
] : ['docker'];
const docker = candidates.find(candidate => spawnSync(candidate, ['--version'], {
  encoding: 'utf8', windowsHide: true,
}).status === 0);
if (!docker) throw new Error('Docker CLI not found. Start Docker Desktop and retry.');

export function localSql(input) {
  const result = spawnSync(docker, ['--host',localEngine,'exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-q', '-t', '-A'], {
    cwd: root, input, env:localEnvironment, encoding: 'utf8', windowsHide: true, timeout: 20000, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || 'Local database command failed');
  return result.stdout;
}

export function cli(args) {
  const entry = fileURLToPath(new URL('../../node_modules/supabase/dist/supabase.js', import.meta.url));
  const result = spawnSync(process.execPath, [entry, ...args], {
    cwd: root, env:localEnvironment, encoding: 'utf8', windowsHide: true, timeout: 20000, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || 'Local Supabase command failed');
  return result.stdout;
}
