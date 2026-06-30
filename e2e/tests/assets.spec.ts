import { test, expect } from '../fixtures';

// Contract-level checks for the things curl can see: the asset strategy
// (embedded htmx vs on-disk CSS), the health probe, and the plain JSON API.
test.describe('assets & API', () => {
  test('healthz is 200 ok', async ({ request }) => {
    const res = await request.get('/healthz');
    expect(res.status()).toBe(200);
    expect((await res.text()).trim()).toBe('ok');
  });

  test('htmx is the embedded copy (JS, ~36 KB)', async ({ request }) => {
    const res = await request.get('/static/htmx.min.js');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('javascript');
    const body = (await res.body()).toString();
    expect(body.length).toBeGreaterThan(25_000); // real htmx 4 (~36 KB), not a 404/empty
    expect(body.startsWith('var htmx=')).toBe(true);
  });

  test('app.css is served (embedded)', async ({ request }) => {
    const res = await request.get('/static/app.css');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('css');
  });

  test('static assets are cacheable: ETag + Cache-Control + 304', async ({ request }) => {
    const res = await request.get('/static/htmx.min.js');
    expect(res.headers()['cache-control'] ?? '').toContain('max-age');
    const etag = res.headers()['etag'];
    expect(etag).toBeTruthy();

    const revalidated = await request.get('/static/htmx.min.js', {
      headers: { 'If-None-Match': etag },
    });
    expect(revalidated.status()).toBe(304);
  });

  test('path traversal is blocked', async ({ request }) => {
    const res = await request.get('/static/%2e%2e%2froutes.odin', { maxRedirects: 0 });
    expect(res.status()).toBe(404);
  });

  test('JSON API returns matching contacts', async ({ request }) => {
    const res = await request.get('/api/search?q=grace');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('json');
    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);
    expect(body.length).toBeGreaterThan(0);
    expect(body[0]).toHaveProperty('name');
    expect(body[0]).toHaveProperty('email');
  });
});
