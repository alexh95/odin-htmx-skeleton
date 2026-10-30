import { execFileSync } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { test, expect, BUILD } from '../../fixtures';
import { appDirFrom, BIN } from '../../global-setup';
import { mainHost, TWO_HOSTS } from '../../helpers/server';
import { ADMIN } from '../../helpers/accounts';

// CSRF and cross-site WebSocket hijacking (PLAN §17.3, 07 §5.6), over every row of
// `bin --routes --json` on every host, with a signed-in admin's cookie riding along as a
// browser's would: every write a foreign page sends is refused 403 before its body is read, and
// no upgrade with a foreign Origin becomes a WebSocket. The guard runs before the route is found,
// so nothing here reaches a handler.

type Route = { host: string; id: string; method: string; pattern: string; flags: string[] };

const ACCOUNTS = BUILD.identity === 'accounts';
const EVIL = 'https://evil.example';

const sample = (pattern: string) =>
  pattern
    .replace(/\(([^)]*)\)/g, (_, inner: string) => (inner.includes('%d') ? '999999' : inner.includes('%x') ? 'abcdef' : 'x'))
    .replace(/%(.)/g, '$1');

const hostFor = (h: string, port: number) => (h === 'main' ? mainHost(port) : `127.0.0.1:${port}`);

function send(port: number, opts: http.RequestOptions, body = ''): Promise<{ status: number; body: string; cookie: string }> {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, agent: false, ...opts }, (res) => {
      let b = '';
      res.on('data', (d) => (b += d));
      res.on('end', () => {
        const sid = (res.headers['set-cookie'] ?? []).map((c) => c.split(';')[0]).find((c) => c.startsWith('sid='));
        resolve({ status: res.statusCode ?? 0, body: b, cookie: sid ?? '' });
      });
    });
    req.on('error', reject);
    req.setTimeout(5000, () => req.destroy(new Error(`${opts.method} ${opts.path}: no answer`)));
    req.end(body);
  });
}

// An upgrade with a foreign Origin: 101 is a hijacked socket; anything else is an answer.
function upgrade(port: number, url: string, host: string, cookie: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port, path: url, agent: false,
      headers: {
        host, origin: EVIL, connection: 'Upgrade', upgrade: 'websocket', 'sec-websocket-version': '13',
        'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==', ...(cookie ? { cookie } : {}),
      },
    });
    req.on('upgrade', (_res, sock) => {
      sock.destroy();
      resolve(101);
    });
    req.on('response', (res) => {
      resolve(res.statusCode ?? 0);
      req.destroy();
    });
    req.on('error', (e) => ((e as any).code === 'ECONNRESET' ? undefined : reject(e)));
    req.setTimeout(5000, () => req.destroy(new Error(`${url}: no answer`)));
    req.end();
  });
}

test.describe('cross-site', { tag: '@platform' }, () => {
  test('every write a foreign page sends is refused, on every host, signed in or not', async ({ server }) => {
    const routes: Route[] = JSON.parse(execFileSync(path.join(appDirFrom(test.info().config), BIN), ['--routes', '--json'], { encoding: 'utf8' }));
    let cookie = '';
    if (ACCOUNTS) {
      const form = new URLSearchParams({ username: ADMIN.username, password: ADMIN.password }).toString();
      const r = await send(server.port, {
        path: '/login', method: 'POST',
        headers: { host: mainHost(server.port), 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(form) },
      }, form);
      expect(r.status).toBe(303);
      cookie = r.cookie;
    }
    const writes = routes.filter((r) => r.method !== 'Get');
    expect(writes.length).toBeGreaterThan(0);
    for (const r of writes) {
      for (const h of TWO_HOSTS ? ['main', 'lab'] : ['main']) {
        for (const forged of [{ 'sec-fetch-site': 'cross-site' }, { 'sec-fetch-site': 'same-site' }, { origin: EVIL }]) {
          const body = 'x=1';
          const got = await send(server.port, {
            path: sample(r.pattern), method: r.method.toUpperCase(),
            headers: {
              host: hostFor(h, server.port), 'content-type': 'application/x-www-form-urlencoded',
              'content-length': body.length, ...(cookie ? { cookie } : {}), ...forged,
            },
          }, body);
          expect({ status: got.status, body: got.body }, `${r.id} on ${h}, ${JSON.stringify(forged)}`)
            .toEqual({ status: 403, body: 'Cross-site request refused.' });
        }
      }
    }
  });

  test('no upgrade with a foreign Origin becomes a WebSocket', async ({ server }) => {
    const routes: Route[] = JSON.parse(execFileSync(path.join(appDirFrom(test.info().config), BIN), ['--routes', '--json'], { encoding: 'utf8' }));
    const streams = routes.filter((r) => r.method === 'Get' && r.flags.includes('Stream'));
    test.skip(streams.length === 0, 'no streams');
    let refused = 0;
    for (const r of streams) {
      const status = await upgrade(server.port, sample(r.pattern), hostFor(r.host, server.port), '');
      expect(status, `${r.id} (${r.host})`).not.toBe(101);
      if (status === 403) refused++;
    }
    // The lab's public WebSocket rows answered with the 403 of a foreign Origin (an SSE row answers its
    // own way; a member's socket, chat's, refuses a guest at the gate first).
    if (BUILD.features.includes('lab')) expect(refused).toBeGreaterThan(0);
  });
});
