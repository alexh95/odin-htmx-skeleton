import { spawn, type ChildProcess } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import type { FullConfig } from '@playwright/test';
import { appDirFrom } from '../global-setup';

// Helpers for tests that manage their OWN server process (a dedicated DB),
// instead of the shared per-worker :memory: server in fixtures.ts. Used by the
// persistence (file DB across a restart) and events-cascade (isolated :memory:)
// specs. The binary is built once in global-setup.ts.

export type Resp = { status: number; body: string };

export function spawnServer(config: FullConfig, port: number, env: NodeJS.ProcessEnv = {}): ChildProcess {
  const appDir = appDirFrom(config);
  const bin = path.join(appDir, process.platform === 'win32' ? 'bin\\demo.exe' : 'bin/demo');
  return spawn(bin, [], { cwd: appDir, env: { ...process.env, PORT: String(port), ...env } });
}

function request(opts: http.RequestOptions, body?: string): Promise<Resp> {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', ...opts }, (res) => {
      let b = '';
      res.on('data', (d) => (b += d));
      res.on('end', () => resolve({ status: res.statusCode ?? 0, body: b }));
    });
    req.on('error', reject);
    req.setTimeout(3000, () => req.destroy(new Error('request timeout')));
    req.end(body);
  });
}

export const get = (port: number, p: string) => request({ port, path: p, method: 'GET' });
export const del = (port: number, p: string) => request({ port, path: p, method: 'DELETE' });
export const post = (port: number, p: string, form: string) =>
  request(
    {
      port, path: p, method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(form) },
    },
    form,
  );

export async function waitHealthy(port: number, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try { if ((await get(port, '/healthz')).status === 200) return; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error(`server on :${port} did not become healthy`);
}

export function stop(proc: ChildProcess): Promise<void> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null) return resolve();
    proc.on('exit', () => resolve());
    proc.kill();
    setTimeout(resolve, 3000); // fallback so cleanup never hangs
  });
}
