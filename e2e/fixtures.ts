import { test as base, expect } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { appDirFrom } from './global-setup';

// One server per worker, on its own port, so each worker gets an isolated
// in-memory store — that's what lets the suite run fully in parallel. The
// binary is built once in global-setup.ts; here we only spawn it.
async function waitForHealth(port: number, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ok = await new Promise<boolean>((resolve) => {
      const req = http.get({ host: '127.0.0.1', port, path: '/healthz' }, (res) => {
        res.resume();
        resolve(res.statusCode === 200);
      });
      req.on('error', () => resolve(false));
      req.setTimeout(500, () => {
        req.destroy();
        resolve(false);
      });
    });
    if (ok) return;
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error(`server on :${port} did not become healthy in ${timeoutMs}ms`);
}

export const test = base.extend<object, { server: { port: number } }>({
  server: [
    async ({}, use, workerInfo) => {
      const appDir = appDirFrom(workerInfo.config);
      const isWin = process.platform === 'win32';
      const bin = path.join(appDir, isWin ? 'bin\\demo.exe' : 'bin/demo');
      const port = 8200 + workerInfo.parallelIndex; // bounded by worker count

      const proc: ChildProcess = spawn(bin, [String(port)], { cwd: appDir, stdio: 'ignore' });
      try {
        await waitForHealth(port);
        await use({ port });
      } finally {
        proc.kill();
      }
    },
    { scope: 'worker' },
  ],

  // Point page + request at this worker's server.
  baseURL: async ({ server }, use) => {
    await use(`http://127.0.0.1:${server.port}`);
  },
});

export { expect };
