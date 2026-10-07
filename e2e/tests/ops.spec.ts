import { test, expect } from '../fixtures';
import { spawnServer, waitHealthy, get, stop } from '../helpers/server';

// What an operator gets from the binary: a version on every response, a health
// check that covers the store, and one access-log line per request. Shared by
// the demo and the --minimal starter. API-only (no browser).
test.describe('operations', () => {
  test('every response names the build, /healthz included', async ({ request }) => {
    for (const path of ['/', '/healthz']) {
      expect((await request.get(path)).headers()['x-version'], path).toMatch(/\S/);
    }
    const health = await request.get('/healthz');
    expect(health.status()).toBe(200);
    expect((await health.text()).trim()).toBe('ok'); // the CI smoke test and Fly compare it verbatim
  });

  test('a request writes one access-log line', async () => {
    const port = 8400 + test.info().parallelIndex;
    const proc = spawnServer(test.info().config, port);
    let out = '';
    proc.stdout?.on('data', (d) => (out += d));
    proc.stderr?.on('data', (d) => (out += d));
    try {
      await waitHealthy(port);
      await get(port, '/about?q=not-logged');
      await expect.poll(() => out).toMatch(/GET \/about 200 \d+\.\d+ms/);
      expect(out).not.toContain('not-logged'); // the query can hold what a user typed
      expect(out).toMatch(/version \S+, store :memory:/);
    } finally {
      await stop(proc);
    }
  });
});
