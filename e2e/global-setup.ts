import type { FullConfig } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

// Resolve app/ relative to this config's location (not cwd or rootDir, which is
// the testDir). configFile is the absolute path to playwright.config.ts.
export function appDirFrom(config: FullConfig): string {
  const e2eDir = config.configFile ? path.dirname(config.configFile) : process.cwd();
  return path.resolve(e2eDir, '..', 'app');
}

// The binary global-setup builds and helpers/server.ts starts, relative to app/.
export const BIN = process.platform === 'win32' ? 'bin\\demo.exe' : 'bin/demo';

// Whether prepare's outputs are in place and match its current pins (read from
// prepare.sh; prepare.bat pins the same): htmx by its SHA-256, the SQLite source
// by the stamp prepare writes beside it, and a library built after that source.
function prepared(appDir: string): boolean {
  const at = (p: string) => path.join(appDir, p);
  const pins = readFileSync(at('prepare.sh'), 'utf8');
  const pin = (name: string) => pins.match(new RegExp(`^${name}=(\\w+)`, 'm'))?.[1];
  const lib = at(process.platform === 'win32' ? 'vendor/sqlite/sqlite3.lib' : 'vendor/sqlite/sqlite3.a');
  try {
    const htmx = createHash('sha256').update(readFileSync(at('static/htmx.min.js'))).digest('hex');
    const stamp = readFileSync(at('vendor/sqlite/.stamp'), 'utf8').trim();
    return htmx === pin('HTMX_SHA256') && stamp === pin('SQLITE_SHA256')
      && statSync(lib).mtimeMs >= statSync(at('vendor/sqlite/sqlite3.c')).mtimeMs
      && existsSync(at('odin-http/server.odin'));
  } catch {
    return false; // something is missing
  }
}

// Build the binary once, before any worker starts. Each worker then spawns its
// own copy on its own port (see fixtures.ts), so the in-memory stores are
// isolated and the suite can run fully in parallel.
export default function globalSetup(config: FullConfig) {
  const appDir = appDirFrom(config);

  mkdirSync(path.join(appDir, 'bin'), { recursive: true });
  // prepare runs only when there's work for it: prepare.bat refuses to start
  // without cl.exe on PATH even when nothing needs compiling, and CI restores
  // these outputs from a cache. When it does run, its failure stops the suite.
  if (!prepared(appDir)) {
    try {
      if (process.platform === 'win32') execFileSync('cmd', ['/c', path.join(appDir, 'prepare.bat')], { cwd: appDir, stdio: 'inherit' });
      else execFileSync('sh', [path.join(appDir, 'prepare.sh')], { cwd: appDir, stdio: 'inherit' });
    } catch {
      throw new Error('[global-setup] prepare failed: see its output above. On Windows it needs cl.exe, so run it from an x64 Native Tools prompt.');
    }
  }

  execFileSync('odin', ['build', 'src', `-out:${BIN}`, '-warnings-as-errors'], {
    cwd: appDir,
    stdio: 'inherit',
  });
}
