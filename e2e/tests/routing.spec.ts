import { test, expect } from '../fixtures';

// What the router answers outside the happy path: a known path with the wrong
// method, a path nothing serves, and the charset every text response declares.
// Shared by the demo and the --minimal starter. API-only (no browser).
test.describe('routing', () => {
  test('a known path with the wrong method is a 405 that says what is allowed', async ({ request }) => {
    const res = await request.put('/');
    expect(res.status()).toBe(405);
    expect(res.headers()['allow']).toBe('GET, HEAD');
  });

  test('an unknown path is a 404 page in the site layout', async ({ request }) => {
    const res = await request.get('/no-such-page');
    expect(res.status()).toBe(404);
    expect(res.headers()['content-type']).toBe('text/html; charset=utf-8');
    const html = await res.text();
    expect(html).toContain('<h1>Page not found</h1>');
    expect(html).toContain('class="topbar"'); // the real layout, nav and all
  });

  test('an htmx request for an unknown path gets a bare 404, nothing to swap in', async ({ request }) => {
    const res = await request.get('/no-such-page', { headers: { 'HX-Request': 'true' } });
    expect(res.status()).toBe(404);
    expect(await res.text()).toBe('');
  });

  test('text responses declare UTF-8', async ({ request }) => {
    expect((await request.get('/')).headers()['content-type']).toBe('text/html; charset=utf-8');
    expect((await request.get('/robots.txt')).headers()['content-type']).toBe('text/plain; charset=utf-8');
  });
});
