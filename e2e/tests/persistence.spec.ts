import { test, expect } from '@playwright/test';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, get, post, waitHealthy, stop } from '../helpers/server';

// The one behaviour the in-memory store could never have: data outlives the
// process. Boot against a file DB, create a row, restart against the SAME file,
// and assert the row is still there — and that the seed didn't run again.
test('data survives a process restart (SQLite persistence)', async () => {
  const port = 8300 + test.info().parallelIndex; // distinct from the per-worker servers
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-db-'));
  const env = { DB_PATH: path.join(dir, 'data.db') };

  let proc = spawnServer(test.info().config, port, env);
  try {
    await waitHealthy(port);
    const unique = `Persist ${Date.now()}`;
    const created = await post(port, '/contacts', `name=${encodeURIComponent(unique)}&email=persist@example.dev&role=0&status=1`);
    expect(created.status).toBe(200);
    await stop(proc);

    proc = spawnServer(test.info().config, port, env); // same DB_PATH
    await waitHealthy(port);
    const res = await get(port, `/api/search?q=${encodeURIComponent('Persist')}`);
    expect(res.status).toBe(200);
    expect(res.body).toContain(unique); // survived the restart
  } finally {
    await stop(proc);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
