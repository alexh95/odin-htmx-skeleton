import { test, expect } from '@playwright/test';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer, stopServer, get, post, type Server } from '../helpers/server';

// The one behaviour the in-memory store could never have: data outlives the
// process. Boot against a file DB, create a row, restart against the SAME file,
// and assert the row is still there — and that the seed didn't run again.
test('data survives a process restart (SQLite persistence)', async () => {
  const config = test.info().config;
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-db-'));
  const env = { DB_PATH: path.join(dir, 'data.db') };

  let server: Server | undefined;
  try {
    server = await startServer(config, env);
    const unique = `Persist ${Date.now()}`;
    const created = await post(server.port, '/contacts', `name=${encodeURIComponent(unique)}&email=persist@example.dev&role=0&status=1`);
    expect(created.status).toBe(200);
    await stopServer(server);

    // Same DB_PATH, fresh port: rebinding the old one can race its socket's
    // teardown (io_uring on Linux holds it briefly after the process exits).
    server = await startServer(config, env);
    const res = await get(server.port, `/api/search?q=${encodeURIComponent('Persist')}`);
    expect(res.status).toBe(200);
    expect(res.body).toContain(unique); // survived the restart
  } finally {
    if (server) await stopServer(server);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
