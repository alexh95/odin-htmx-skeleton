// Playwright webServer entry: prepare deps, build a fresh binary, then run it.
// Building here (not in globalSetup) guarantees the binary exists before the
// server starts — a fresh process means a clean in-memory store every run.
import { execFileSync, spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(here, '..', 'app');
const isWin = process.platform === 'win32';
const PORT = process.env.E2E_PORT ?? '8137';
const out = isWin ? 'bin\\demo.exe' : 'bin/demo';

mkdirSync(path.join(appDir, 'bin'), { recursive: true });

// Fetch odin-http (submodule) + htmx. Idempotent; tolerate offline if already done.
try {
  if (isWin) execFileSync('cmd', ['/c', 'prepare.bat'], { cwd: appDir, stdio: 'inherit' });
  else execFileSync('sh', ['prepare.sh'], { cwd: appDir, stdio: 'inherit' });
} catch {
  console.warn('[serve] prepare failed (continuing — deps may already be present)');
}

execFileSync('odin', ['build', '.', `-out:${out}`, '-warnings-as-errors'], {
  cwd: appDir,
  stdio: 'inherit',
});

// cwd = appDir so the binary serves static/ from disk (respond_dir is relative).
const srv = spawn(path.join(appDir, out), [PORT], { cwd: appDir, stdio: 'inherit' });
const stop = () => {
  try { srv.kill(); } catch {}
  process.exit(0);
};
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
srv.on('exit', (code) => process.exit(code ?? 0));
