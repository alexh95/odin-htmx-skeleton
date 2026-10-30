import http from 'node:http';
import { test, expect, PROXY } from '../../fixtures';

// Through the proxy in front of the server (E2E_PROXY: CI's e2e-proxy job, the stack Caddyfile alone
// and NPM's nginx in front of it; PLAN §20.1, §20.4): streams pass as they are written, raw. A proxy
// that buffered would hand the ticks over at the end, and one that compressed would hold an encoder
// per stream (S0.8); the server's `Cache-Control: no-transform` and `X-Accel-Buffering: no` are what
// keep both off. Skipped without a proxy: the other lab specs cover the same streams direct.

// The lab's own origin through the proxy: a two-host build's lab host (E2E_PROXY_LAB), else the one.
const LAB = process.env.E2E_PROXY_LAB || PROXY;

type Timed = { status: number; headers: http.IncomingHttpHeaders; body: string; times: number[] };

// A GET through the proxy, with the time each chunk arrived.
function through(path: string): Promise<Timed> {
  const url = new URL(path, LAB);
  return new Promise((resolve, reject) => {
    const t0 = performance.now();
    const req = http.get(url, (r) => {
      const chunks: Buffer[] = [];
      const times: number[] = [];
      r.on('data', (c) => { chunks.push(c); times.push(Math.round(performance.now() - t0)); });
      r.on('end', () => resolve({ status: r.statusCode ?? 0, headers: r.headers, body: Buffer.concat(chunks).toString(), times }));
    });
    req.on('error', reject);
    req.setTimeout(15_000, () => req.destroy(new Error('timeout')));
  });
}

test.describe('streams through the proxy @lab', () => {
  test.skip(!PROXY, 'no E2E_PROXY: the streams are covered direct');

  test('SSE ticks arrive as they are written, uncompressed', async () => {
    const r = await through('/lab/sse/tick?n=4&ms=400');
    expect(r.status).toBe(200);
    expect(r.headers['content-type']).toContain('text/event-stream');
    expect(r.headers['content-encoding']).toBeUndefined();
    expect(r.headers['cache-control']).toContain('no-transform');
    expect(r.body.match(/^data: /gm)?.length).toBe(4);
    // The first tick lands about 400 ms in, long before the last (about 1.6 s): not held to the end.
    expect(r.times[0]).toBeLessThan(r.times[r.times.length - 1] - 600);
  });

  test('multipart parts arrive as they are written, uncompressed', async () => {
    const r = await through('/lab/multipart?n=3&ms=500');
    expect(r.status).toBe(200);
    expect(r.headers['content-type']).toContain('multipart/mixed');
    expect(r.headers['content-encoding']).toBeUndefined();
    expect(r.times[0]).toBeLessThan(r.times[r.times.length - 1] - 600);
  });

  test('a page passes through', async () => {
    const r = await through('/lab');
    expect(r.status).toBe(200);
    expect(r.body).toContain('<html');
  });

  test('a socket echoes through the proxy', async () => {
    const url = new URL('/lab/ws/echo', LAB);
    url.protocol = 'ws:';
    const ws = new WebSocket(url);
    const got = await new Promise<string>((resolve, reject) => {
      ws.onopen = () => ws.send('through the proxy');
      ws.onmessage = (e) => resolve(String(e.data));
      ws.onerror = () => reject(new Error('socket error'));
      setTimeout(() => reject(new Error('no echo in 5 s')), 5000);
    });
    ws.close();
    expect(got).toBe('through the proxy');
  });
});
