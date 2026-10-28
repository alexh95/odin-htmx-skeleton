import * as net from 'node:net';
import { test, expect } from '../../fixtures';

// What the router answers outside the happy path: a known path with the wrong
// method, a path nothing serves, and the charset every text response declares.
// Every profile. API-only (no browser).
test.describe('routing', { tag: '@platform' }, () => {
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

  // F-24: a HEAD runs as a GET and answers its heading alone. A body sent anyway sits on the
  // keep-alive connection, where the next response is read from (Caddy logged it as an
  // unsolicited response).
  test('a HEAD answers headers only, and the connection serves the next request', async ({ server }) => {
    const got = await new Promise<string>((resolve) => {
      const sock = net.connect(server.port, '127.0.0.1', () =>
        sock.write('HEAD / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\nGET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'));
      let buf = '';
      sock.setTimeout(5000, () => sock.destroy());
      sock.on('data', (d) => { buf += d; });
      sock.on('close', () => resolve(buf));
    });
    const head = got.slice(0, got.indexOf('\r\n\r\n') + 4);
    expect(head).toMatch(/^HTTP\/1\.1 200 /);
    expect(head.toLowerCase()).toMatch(/content-length: [1-9]/); // the GET's length, as RFC 9110 allows
    const next = got.slice(head.length);
    expect(next).toMatch(/^HTTP\/1\.1 200 /); // not the page's HTML
    expect(next.endsWith('\r\n\r\nok')).toBe(true);
  });

  test('text responses declare UTF-8', async ({ request }) => {
    expect((await request.get('/')).headers()['content-type']).toBe('text/html; charset=utf-8');
    expect((await request.get('/robots.txt')).headers()['content-type']).toBe('text/plain; charset=utf-8');
  });
});
