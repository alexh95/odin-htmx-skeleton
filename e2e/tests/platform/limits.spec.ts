import { test, expect, has } from '../../fixtures';
import { startServer, stopServer, get, raw } from '../../helpers/server';

// Input limits. Every POST body is capped before routing, and each text field
// has a length limit in the service layer, so one request can't park megabytes
// in the store and in every page that renders it.
//
// The body cap is checked against a route every profile serves, and the field
// limits against whichever write the build has.
const form = { 'content-type': 'application/x-www-form-urlencoded' };

test.describe('input limits', { tag: '@platform' }, () => {
  test('a body over the cap is refused with 413 before it is read', async ({ request }) => {
    const res = await request.post('/', { headers: form, data: 'x=' + 'a'.repeat(70 * 1024) });
    expect(res.status()).toBe(413);
  });

  test('a body under the cap still reaches the handler', async ({ request }) => {
    // 413 is about size alone: the same POST, small, is routed (and answered by
    // whatever the route says, which for POST / is not a 413).
    const res = await request.post('/', { headers: form, data: 'x=1' });
    expect(res.status()).not.toBe(413);
  });

  test('an over-long field is rejected and nothing is stored', async ({ request }) => {
    test.skip(!has('contacts') && !has('notes'), 'no text field to overfill');
    if (has('contacts')) {
      const name = 'Long' + 'n'.repeat(120); // MAX_NAME is 100
      const res = await request.post('/contacts', { headers: form, data: `name=${name}&email=long@example.dev&role=Engineer` });
      expect(res.status()).toBe(422);
      expect(await res.text()).toContain('at most 100 characters');
      const found = await (await request.get('/api/search?q=Longnnnn')).json();
      expect(found).toHaveLength(0);
    } else {
      const body = 'Long' + 'n'.repeat(520); // MAX_NOTE is 500
      const res = await request.post('/notes', { headers: form, data: `body=${body}` });
      expect(res.status()).toBe(422);
      expect(await res.text()).toContain('at most 500 characters');
      expect(await (await request.get('/')).text()).not.toContain(body);
    }
  });

  // odin-http reads Content-Length with strconv.parse_int, which takes a sign and
  // wraps past 64 bits, and a negative length reaches an assert that aborts the
  // whole process. It reads the body after a GET too, to drain a keep-alive
  // connection, so every method is sent, and an Expect: 100-continue, which it
  // used to answer itself. A server of its own: the old behaviour killed it.
  test('a malformed Content-Length is refused with 400 and the server lives', async () => {
    const server = await startServer(test.info().config);
    try {
      for (const value of ['-5', '+5', '9223372036854775808', '18446744073709551617', '1_0', '0x5']) {
        for (const [method, extra] of [['POST', ''], ['GET', ''], ['HEAD', ''], ['POST', 'Expect: 100-continue\r\n']]) {
          const what = `${method} ${extra.trim()} with Content-Length: ${value}`;
          const status = await raw(server.port, `${method} /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n${extra}Content-Length: ${value}\r\n\r\n`);
          expect(status, what).toBe(400);
          expect((await get(server.port, '/healthz')).status, `alive after ${what}`).toBe(200);
        }
      }
      // A well-formed length still frames the request, and an Expect gets the
      // route's answer (405: /healthz is GET only), not a 100 with nothing after.
      expect(await raw(server.port, 'GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n')).toBe(200);
      expect(await raw(server.port, 'POST /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nExpect: 100-continue\r\nContent-Length: 3\r\n\r\nx=1')).toBe(405);
    } finally {
      await stopServer(server);
    }
  });
});
