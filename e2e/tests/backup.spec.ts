import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, get, post, waitHealthy, stop } from '../helpers/server';

// The backup runbook in docs/DATA.md, end to end: write a row to a file DB,
// back it up with `<bin> --backup` while the server is still running, then
// restore by starting a server on the copy. Shared by the demo and the
// --minimal starter. API-only (no browser); starts its own servers.
test('a backup taken under a live server restores with the data in it', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-backup-'));
  const live = path.join(dir, 'data.db');
  const copy = path.join(dir, 'backup.db');
  const port = 8420 + test.info().parallelIndex;
  let proc = spawnServer(test.info().config, port, { DB_PATH: live });
  try {
    await waitHealthy(port);
    const demo = (await get(port, '/data')).status === 200;
    const marker = `Backup ${Date.now()}`;
    const made = demo
      ? await post(port, '/contacts', `name=${encodeURIComponent(marker)}&email=backup@example.dev`)
      : await post(port, '/notes', `body=${encodeURIComponent(marker)}`);
    expect(made.status).toBe(200);

    // The same binary the server runs, whatever init renamed it to.
    const bin = proc.spawnfile;
    const backup = (dest: string) =>
      execFileSync(bin, ['--backup', dest], { env: { ...process.env, DB_PATH: live }, stdio: 'pipe' });
    backup(copy);
    expect(existsSync(copy)).toBe(true);
    expect(() => backup(copy)).toThrow(); // never overwrites a file

    await stop(proc);
    proc = spawnServer(test.info().config, port + 20, { DB_PATH: copy });
    await waitHealthy(port + 20);
    const page = demo ? `/api/search?q=${encodeURIComponent(marker)}` : '/';
    expect((await get(port + 20, page)).body).toContain(marker);
  } finally {
    await stop(proc);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
