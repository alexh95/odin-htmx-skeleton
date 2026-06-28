import { test, expect } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import http from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { appDirFrom } from '../global-setup';

// This test manages its own server processes (not the per-worker :memory: server
// from fixtures.ts) so it can point two successive boots at the SAME file DB.

function get(port: number, p: string): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: p }, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => resolve({ status: res.statusCode ?? 0, body }));
    });
    req.on('error', reject);
    req.setTimeout(2000, () => req.destroy(new Error('GET timeout')));
  });
}

function post(port: number, p: string, form: string): Promise<{ status: number }> {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: '127.0.0.1', port, path: p, method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(form) },
      },
      (res) => { res.resume(); res.on('end', () => resolve({ status: res.statusCode ?? 0 })); },
    );
    req.on('error', reject);
    req.end(form);
  });
}

async function waitHealthy(port: number, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try { if ((await get(port, '/healthz')).status === 200) return; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error(`server on :${port} did not become healthy`);
}

function stop(proc: ChildProcess): Promise<void> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null) return resolve();
    proc.on('exit', () => resolve());
    proc.kill();
    setTimeout(resolve, 3000); // fallback so cleanup never hangs
  });
}

// The one behaviour the in-memory store could never have: data outlives the
// process. Boot against a file DB, create a row, restart against the SAME file,
// and assert the row is still there — and that the seed didn't run again.
test('data survives a process restart (SQLite persistence)', async () => {
  const appDir = appDirFrom(test.info().config);
  const bin = path.join(appDir, process.platform === 'win32' ? 'bin\\demo.exe' : 'bin/demo');
  const port = 8300 + test.info().parallelIndex; // distinct from the per-worker servers
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-db-'));
  const env = { ...process.env, DB_PATH: path.join(dir, 'data.db'), PORT: String(port) };

  let proc = spawn(bin, [], { cwd: appDir, env });
  try {
    await waitHealthy(port);
    const unique = `Persist ${Date.now()}`;
    const created = await post(port, '/contacts', `name=${encodeURIComponent(unique)}&email=persist@example.dev&role=0&status=1`);
    expect(created.status).toBe(200);
    await stop(proc);

    proc = spawn(bin, [], { cwd: appDir, env }); // same DB_PATH
    await waitHealthy(port);
    const res = await get(port, `/api/search?q=${encodeURIComponent('Persist')}`);
    expect(res.status).toBe(200);
    expect(res.body).toContain(unique); // survived the restart
  } finally {
    await stop(proc);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
