import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer, stopServer, get, post, type Server } from '../helpers/server';

// The backup runbook in docs/DATA.md, end to end: write a row to a file DB,
// back it up with `<bin> --backup` while the server is still running, then
// restore by starting a server on the copy. Shared by the demo and the
// --minimal starter. API-only (no browser); starts its own servers.
test('a backup taken under a live server restores with the data in it', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-backup-'));
  const live = path.join(dir, 'data.db');
  const copy = path.join(dir, 'backup.db');
  let srv: Server | undefined;
  try {
    srv = await startServer(test.info().config, { DB_PATH: live });
    const demo = (await get(srv.port, '/data')).status === 200;
    const marker = `Backup ${Date.now()}`;
    const made = demo
      ? await post(srv.port, '/contacts', `name=${encodeURIComponent(marker)}&email=backup@example.dev`)
      : await post(srv.port, '/notes', `body=${encodeURIComponent(marker)}`);
    expect(made.status).toBe(200);

    // The same binary the server runs, whatever init renamed it to.
    const bin = srv.proc.spawnfile;
    const backup = (dest: string) =>
      execFileSync(bin, ['--backup', dest], { env: { ...process.env, DB_PATH: live }, stdio: 'pipe' });
    backup(copy);
    expect(existsSync(copy)).toBe(true);
    expect(() => backup(copy)).toThrow(); // never overwrites a file

    await stopServer(srv);
    srv = await startServer(test.info().config, { DB_PATH: copy });
    const page = demo ? `/api/search?q=${encodeURIComponent(marker)}` : '/';
    expect((await get(srv.port, page)).body).toContain(marker);
  } finally {
    if (srv) await stopServer(srv);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
