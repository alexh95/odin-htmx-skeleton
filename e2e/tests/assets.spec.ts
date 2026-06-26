import { test, expect } from '@playwright/test';

// Contract-level checks for the things curl can see: the asset strategy
// (embedded htmx vs on-disk CSS), the health probe, and the plain JSON API.
test.describe('assets & API', () => {
  test('healthz is 200 ok', async ({ request }) => {
    const res = await request.get('/healthz');
    expect(res.status()).toBe(200);
    expect((await res.text()).trim()).toBe('ok');
  });

  test('htmx is the embedded copy (JS, ~51 KB)', async ({ request }) => {
    const res = await request.get('/static/htmx.min.js');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('javascript');
    expect((await res.body()).byteLength).toBeGreaterThan(40_000);
  });

  test('app.css is served from disk', async ({ request }) => {
    const res = await request.get('/static/app.css');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('css');
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
