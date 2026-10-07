import { spawn, type ChildProcess } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import type { FullConfig } from '@playwright/test';
import { appDirFrom, BIN } from '../global-setup';

// Starts and talks to the server under test. fixtures.ts gives each worker one;
// specs that need their own (a file DB, a store they may wreck) start one here.
// The binary is built once in global-setup.ts.

export type Server = { port: number; proc: ChildProcess };
export type Resp = { status: number; body: string };

// A port nothing listens on, picked by the OS. A fixed base can't promise that:
// two runs at once collide, and on Windows a second server binds a taken port
// without an error while the first keeps answering, so a stale build gets tested.
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address() as net.AddressInfo;
      probe.close(() => resolve(port));
    });
  });
}

// The env is pinned, not inherited: the server prefers PORT over argv, and an
// exported DB_PATH would aim the suite's deletes at a real database. An empty
// BIND_ALL/SITE_URL reads as unset, so the server stays on loopback with its
// built-in canonical origin. `env` overrides (a spec's own DB_PATH).
export async function startServer(config: FullConfig, env: NodeJS.ProcessEnv = {}): Promise<Server> {
  const appDir = appDirFrom(config);
  const port = await freePort();
  const proc = spawn(path.join(appDir, BIN), [], {
    cwd: appDir,
    env: { ...process.env, PORT: String(port), DB_PATH: ':memory:', BIND_ALL: '', SITE_URL: '', ...env },
  });
  // Kept so a failed start shows the server's own error (an io_uring/seccomp
  // abort, a DB it can't open) instead of a bare health timeout.
  let log = '';
  proc.stdout?.on('data', (d) => (log += d));
  proc.stderr?.on('data', (d) => (log += d));

  const deadline = Date.now() + 20_000;
  while (proc.exitCode === null && proc.signalCode === null && Date.now() < deadline) {
    try {
      if ((await get(port, '/healthz')).status === 200) return { port, proc };
    } catch { /* not listening yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  const why = proc.exitCode !== null || proc.signalCode !== null
    ? `exited early (code=${proc.exitCode}, signal=${proc.signalCode})`
    : 'did not become healthy in 20 s';
  proc.kill();
  throw new Error(`server on :${port} ${why}\n--- server output ---\n${log || '(none)'}`);
}

export function stopServer({ proc }: Server): Promise<void> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null || proc.signalCode !== null) return resolve();
    const giveUp = setTimeout(resolve, 3000); // so cleanup never hangs
    proc.once('exit', () => {
      clearTimeout(giveUp);
      resolve();
    });
    proc.kill();
  });
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
