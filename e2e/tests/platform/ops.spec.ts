import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test, expect, has } from '../../fixtures';
import { appDirFrom, coverageDir } from '../../global-setup';
import { startServer, stopServer, get } from '../../helpers/server';

// What an operator gets from the binary: a version on every response, a health
// check that covers the store, and one access-log line per request. Every
// profile. API-only (no browser).
test.describe('operations', { tag: '@platform' }, () => {
  test('every response names the build, /healthz included', async ({ request }) => {
    for (const path of ['/', '/healthz']) {
      expect((await request.get(path)).headers()['x-version'], path).toMatch(/\S/);
    }
    const health = await request.get('/healthz');
    expect(health.status()).toBe(200);
    expect((await health.text()).trim()).toBe('ok'); // the CI smoke test and Fly compare it verbatim
  });

  // The probes beside /healthz (PLAN §10.4): /livez while every loop ticks,
  // /readyz while every critical module is up, and ?detail for one line each.
  test('the liveness and readiness probes answer ok, readiness with its modules', async ({ request }) => {
    for (const path of ['/livez', '/readyz']) {
      const res = await request.get(path);
      expect(res.status(), path).toBe(200);
      expect(await res.text(), path).toBe('ok');
    }
    const detail = await (await request.get('/readyz?detail')).text();
    expect(detail).toMatch(/^ready\n/);
    if (has('platform-sqlite')) expect(detail).toContain('store ok');
  });

  // Prometheus text for an admin or the bearer in METRICS_TOKEN_FILE, which the
  // harness gives every server it starts (helpers/server.ts reads the per-route
  // counters back through it).
  test('/metrics wants the bearer and counts each route by its id', async ({ request }) => {
    const refused = await request.get('/metrics');
    expect(refused.status()).toBe(401);
    expect(refused.headers()['www-authenticate']).toBe('Bearer');

    await request.get('/healthz');
    const token = readFileSync(path.join(coverageDir(appDirFrom(test.info().config)), '.token'), 'utf8');
    const res = await request.get('/metrics', { headers: { Authorization: `Bearer ${token}` } });
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type']).toBe('text/plain; version=0.0.4; charset=utf-8');
    expect(await res.text()).toMatch(/^app_http_requests_total\{route="GET \/healthz"\} [1-9]\d*$/m);
    const wrong = await request.get('/metrics', { headers: { Authorization: 'Bearer not-the-token' } });
    expect(wrong.status()).toBe(401);
  });

  test('/licenses lists the notices of what the binary contains', async ({ request }) => {
    const res = await request.get('/licenses');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type']).toBe('text/plain; charset=utf-8');
    const body = await res.text();
    expect(body).toMatch(/^THIRD-PARTY NOTICES/);
    expect(body).toContain('Laytan Laats'); // odin-http's MIT notice
    expect(body).toContain('Copyright (c) 2025 Shopify Inc.'); // the one hx-multipart.min.js drops
  });

  // logfmt (PLAN §10.4): the route as registered, the status, the time in µs, a
  // request id, and never the query, which can hold what a user typed.
  test('a request writes one access-log line', { tag: '@about' }, async () => {
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
