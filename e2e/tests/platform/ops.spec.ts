import { test, expect } from '../fixtures';
import { startServer, stopServer, get } from '../helpers/server';

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

  // logfmt (PLAN §10.4): the route as registered, the status, the time in µs, a
  // request id, and never the query, which can hold what a user typed.
  test('a request writes one access-log line', async () => {
    const srv = await startServer(test.info().config);
    try {
      await get(srv.port, '/about?q=not-logged');
      await expect.poll(srv.output).toMatch(/ev=req id=\S+ m=GET route="GET \/about" st=200 us=\d+/);
      expect(srv.output()).not.toContain('not-logged');
      expect(srv.output()).toMatch(/ev=serving profile=\S+ version=\S+/);
    } finally {
      await stopServer(srv);
    }
  });
});
