import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { LEG, LOCAL_BIN, REPO, SPIKE } from './env';

// The pinned htmx files must be in place (prepare.sh fetches them; the pins are read from it), and
// the local leg's binary is built here. The WSL leg's binary is built inside WSL beforehand.
export default function globalSetup() {
  const pins = readFileSync(path.join(SPIKE, 'prepare.sh'), 'utf8');
  for (const [, file, sum] of pins.matchAll(/^fetch (\S+)\s+([0-9a-f]{64})$/gm)) {
    const at = path.join(SPIKE, 'server', 'static', path.basename(file));
    const got = existsSync(at) ? createHash('sha256').update(readFileSync(at)).digest('hex') : 'missing';
    if (got !== sum) throw new Error(`${file}: ${got} != pinned ${sum}; run docs/spikes/S0.3/prepare.sh`);
  }
  if (LEG !== 'local') return;
  execFileSync('odin', ['build', 'docs/spikes/S0.3/server', '-collection:fork=app/vendor', `-out:${LOCAL_BIN}`,
    '-vet', '-strict-style', '-warnings-as-errors'], { cwd: REPO, stdio: 'inherit' });
}
