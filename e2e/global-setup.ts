import type { FullConfig } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

// Resolve app/ relative to this config's location (not cwd or rootDir, which is
// the testDir). configFile is the absolute path to playwright.config.ts.
export function appDirFrom(config: FullConfig): string {
  const e2eDir = config.configFile ? path.dirname(config.configFile) : process.cwd();
  return path.resolve(e2eDir, '..', 'app');
}

// Build the binary once, before any worker starts. Each worker then spawns its
// own copy on its own port (see fixtures.ts), so the in-memory stores are
// isolated and the suite can run fully in parallel.
export default function globalSetup(config: FullConfig) {
  const appDir = appDirFrom(config);
  const isWin = process.platform === 'win32';
  const out = isWin ? 'bin\\demo.exe' : 'bin/demo';

  mkdirSync(path.join(appDir, 'bin'), { recursive: true });
  try {
    if (isWin) execFileSync('cmd', ['/c', path.join(appDir, 'prepare.bat')], { cwd: appDir, stdio: 'inherit' });
    else execFileSync('sh', [path.join(appDir, 'prepare.sh')], { cwd: appDir, stdio: 'inherit' });
  } catch {
    console.warn('[global-setup] prepare failed (continuing — deps may already be present)');
  }

  execFileSync('odin', ['build', 'src', `-out:${out}`, '-warnings-as-errors'], {
    cwd: appDir,
    stdio: 'inherit',
  });
}
