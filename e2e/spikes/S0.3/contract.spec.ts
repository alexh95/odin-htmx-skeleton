import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import type { Page } from '@playwright/test';
import { HOST } from './env';
import { epochOf, expect, get, post, publish, seqOf, sleep, sse, stats, test, uid, wsRaw } from './server';

// 03's 29 contract checks (03 §10.2; the prototype's test.mjs), one test each, numbered as
// test.mjs runs them. Checks 9-12 and 25 open their sockets with the page's own WebSocket, so the
// engine under test speaks to the server; the rest are protocol-level and open sockets from Node.

// The browser's WebSocket, opened from a page this server served (so it carries this Origin and
// runs under the page's CSP).
async function onPage(page: Page) {
  await page.goto('/p/blank');
}

test.describe('SSE', () => {
  test('03#01 sse/tick: 200, text/event-stream, chunked', async ({ srv }) => {
    const r = await get(srv.port, '/sse/tick?n=5&ms=200');
    expect(r.status).toBe(200);
    expect(r.headers['content-type']).toBe('text/event-stream');
    expect(r.headers['transfer-encoding']).toBe('chunked');
  });

  test('03#02 sse/tick: 5 events spread over ~1 s (streamed, not buffered)', async ({ srv }) => {
    const r = await get(srv.port, '/sse/tick?n=5&ms=200');
    expect((r.body.match(/^id: /gm) || []).length).toBe(5);
    expect(r.times.at(-1)!).toBeGreaterThanOrEqual(900);
    test.info().annotations.push({ type: 'chunk times ms', description: r.times.join(',') });
  });

  test('03#03 keep-alive: the next request reuses the socket after a stream ends', async ({ srv }) => {
    const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
    await get(srv.port, '/sse/tick?n=2&ms=50', { agent });
    const r = await get(srv.port, '/healthz', { agent });
    agent.destroy();
    expect(r.body).toBe('ok');
    expect(r.reused).toBe(true);
  });

  test('03#04 sse/bus: beats from the producer thread (not a loop) arrive', async ({ srv }) => {
    const evs = await sse(srv.port, '/sse/bus', { count: 3, ms: 4000 });
    expect(evs).toHaveLength(3);
    for (const e of evs) expect(e.data).toMatch(/beat \d+/);
  });

  test('03#05 sse/bus: Last-Event-ID resumes right after the given id', async ({ srv }) => {
    const evs = await sse(srv.port, '/sse/bus', { count: 3, ms: 4000 });
    expect(evs.length).toBeGreaterThan(0);
    const first = evs[0].id!;
    const replay = await sse(srv.port, '/sse/bus', { count: 2, ms: 3000, headers: { 'Last-Event-ID': first } });
    expect(epochOf(replay[0]?.id)).toBe(epochOf(first));
    expect(seqOf(replay[0]?.id)).toBe(seqOf(first) + 1);
  });

  test.describe('publish to 8 subscribers', () => {
    let hits: ({ event?: string; data: string } | undefined)[] = [];
    let status = 0;
    const token = uid('post');
    test.beforeAll(async ({ workerSrv }) => {
      const subs = Array.from({ length: 8 }, () => sse(workerSrv.port, '/sse/bus', { count: 50, ms: 2000 }));
      await sleep(400);
      status = await post(workerSrv.port, '/publish', `<p>${token}\r\nevent: injected</p>`);
      hits = (await Promise.all(subs)).map((evs) => evs.find((e) => e.data.includes(token)));
    });

    test('03#06 publish: 204', async () => {
      expect(status).toBe(204);
    });
    test('03#07 publish: all 8 subscribers got it', async () => {
      expect(hits.every(Boolean)).toBe(true);
    });
    test('03#08 sse framing: a CR in the payload cannot inject a field', async () => {
      for (const e of hits) {
        expect(e?.event).toBeUndefined();
        expect(e?.data).toContain("event: injected");
      }
    });
  });
});

test.describe('WebSocket through the engine', () => {
  test('03#09 ws/echo: text round-trip (UTF-8)', async ({ page }) => {
    await onPage(page);
    const echoed = await page.evaluate(() => new Promise((res) => {
      const ws = new WebSocket(`ws://${location.host}/ws/echo`);
      ws.onopen = () => ws.send('héllo ✓');
      ws.onmessage = (m) => { res(m.data); ws.close(); };
      ws.onerror = () => res('error');
      setTimeout(() => res('timeout'), 4000);
    }));
    expect(echoed).toBe('héllo ✓');
  });

  test('03#10 ws/echo: a 70 kB binary message (cap 64 KiB) closes 1009', async ({ page }) => {
    await onPage(page);
    const code = await page.evaluate(() => new Promise((res) => {
      const ws = new WebSocket(`ws://${location.host}/ws/echo`);
      ws.binaryType = 'arraybuffer';
      ws.onopen = () => ws.send(new Uint8Array(70000).fill(7));
      ws.onmessage = () => res('echoed');
      ws.onclose = (e) => res(e.code);
      setTimeout(() => res('timeout'), 4000);
    }));
    expect(code).toBe(1009);
  });

  test('03#11 ws/echo: 60 kB binary round-trip', async ({ page }) => {
    await onPage(page);
    const n = await page.evaluate(() => new Promise((res) => {
      const ws = new WebSocket(`ws://${location.host}/ws/echo`);
      ws.binaryType = 'arraybuffer';
      ws.onopen = () => ws.send(new Uint8Array(60000).fill(9));
      ws.onmessage = (m) => { const a = new Uint8Array(m.data); res(a.length === 60000 && a.every((x) => x === 9) ? a.length : -1); ws.close(); };
      setTimeout(() => res('timeout'), 4000);
    }));
    expect(n).toBe(60000);
  });

  test('03#12 ws: the client\'s close 1000 is echoed', async ({ page }) => {
    await onPage(page);
    const r = await page.evaluate(() => new Promise((res) => {
      const ws = new WebSocket(`ws://${location.host}/ws/echo`);
      ws.onopen = () => ws.close(1000, 'bye');
      ws.onclose = (e) => res({ code: e.code, clean: e.wasClean });
      setTimeout(() => res('timeout'), 4000);
    }));
    expect(r).toEqual({ code: 1000, clean: true });
  });
});

test.describe('WebSocket protocol edges', () => {
  test('03#13 handshake: 101 and the right Sec-WebSocket-Accept', async ({ srv }) => {
    const w = await wsRaw(srv.port, '/ws/echo');
    expect(w.status).toBe(101);
    expect(w.acceptOk).toBe(true);
    w.s.destroy();
  });

  test.describe('a ping between fragments', () => {
    let f1: Awaited<ReturnType<Awaited<ReturnType<typeof wsRaw>>['next']>>;
    let f2: typeof f1;
    test.beforeAll(async ({ workerSrv }) => {
      const w = await wsRaw(workerSrv.port, '/ws/echo');
      w.send(0x1, 'he', { fin: false }); w.send(0x9, 'p'); w.send(0x0, 'llo');
      f1 = await w.next(); f2 = await w.next();
      w.s.destroy();
    });
    test('03#14 ws: a ping between fragments gets a pong, then the reassembled message', async () => {
      expect(f1?.op).toBe(0xA);
      expect(f1?.payload.toString()).toBe('p');
      expect(f2?.op).toBe(0x1);
      expect(f2?.payload.toString()).toBe('hello');
    });
    test('03#15 ws: server frames are unmasked', async () => {
      expect(f1?.masked).toBe(false);
      expect(f2?.masked).toBe(false);
    });
  });

  const closes: [string, (w: Awaited<ReturnType<typeof wsRaw>>) => void, number][] = [
    ['03#16 ws: an unmasked client frame closes 1002', (w) => w.send(0x1, 'x', { mask: false }), 1002],
    ['03#17 ws: invalid UTF-8 in a text frame closes 1007', (w) => w.send(0x1, Buffer.from([0xff, 0xfe])), 1007],
    ['03#18 ws: RSV1 without an extension closes 1002', (w) => w.send(0x1, 'a', { rsv: 0x40 }), 1002],
    ['03#19 ws: a continuation with nothing to continue closes 1002', (w) => w.send(0x0, 'a'), 1002],
    ['03#20 ws: a close with the reserved code 1005 closes 1002', (w) => w.send(0x8, Buffer.from([0x03, 0xed])), 1002],
  ];
  for (const [name, act, code] of closes) {
    test(name, async ({ srv }) => {
      const w = await wsRaw(srv.port, '/ws/echo');
      act(w);
      const f = await w.next();
      expect(f?.op).toBe(8);
      expect(f?.code).toBe(code);
      await w.closed;
    });
  }

  test('03#21 handshake: a foreign Origin gets 403', async ({ srv }) => {
    const w = await wsRaw(srv.port, '/ws/echo', { Origin: 'http://evil.example' });
    expect(w.status).toBe(403);
    w.s.destroy();
  });

  test('03#22 handshake: the own Origin (SITE_URL) gets 101', async ({ srv }) => {
    const w = await wsRaw(srv.port, '/ws/echo', { Origin: srv.base });
    expect(w.status).toBe(101);
    w.s.destroy();
  });

  test('03#23 handshake: version 8 gets 426 and Sec-WebSocket-Version: 13', async ({ srv }) => {
    const w = await wsRaw(srv.port, '/ws/echo', { 'Sec-WebSocket-Version': '8' });
    expect(w.status).toBe(426);
    expect(w.head).toMatch(/sec-websocket-version: 13/i);
    w.s.destroy();
  });

  test('03#24 ws: frames pipelined in the handshake\'s packet are processed', async ({ srv }) => {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(srv.port, HOST);
    const m = Buffer.from([1, 2, 3, 4]);
    const p = Buffer.from('early').map((x, i) => x ^ m[i & 3]);
    const frame = Buffer.concat([Buffer.from([0x81, 0x80 | 5]), m, p]);
    const reply = await new Promise((res) => {
      let data = Buffer.alloc(0);
      s.on('connect', () => s.write(Buffer.concat([Buffer.from(`GET /ws/echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`), frame])));
      s.on('data', (d) => { data = Buffer.concat([data, d]); if (data.includes('early')) res(true); });
      setTimeout(() => res(false), 3000);
    });
    s.destroy();
    expect(reply).toBe(true);
  });
});

test('03#25 ws/chat: one socket\'s hx-ws JSON reaches all 8 sockets as escaped OOB HTML', async ({ page }) => {
  await onPage(page);
  const room = uid('room');
  const msgs = await page.evaluate((room) => new Promise<unknown[]>((res) => {
    const socks = Array.from({ length: 8 }, () => new WebSocket(`ws://${location.host}/ws/chat?room=${room}`));
    const got: unknown[] = new Array(8).fill(null);
    let open = 0;
    socks.forEach((s, i) => {
      s.onmessage = (m) => { got[i] = m.data; if (got.every((x) => x !== null)) { socks.forEach((x) => x.close()); res(got); } };
      s.onopen = () => {
        if (++open === 8) socks[3].send(JSON.stringify({ message: '<script>hi</script>', headers: { 'HX-Request': 'true' } }));
      };
    });
    setTimeout(() => res(got), 5000);
  }), room);
  for (const m of msgs) expect(m).toBe('<div id="chat" hx-swap-oob="beforeend"><p>&lt;script&gt;hi&lt;/script&gt;</p></div>');
});

test.describe('multipart', () => {
  test('03#26 multipart: Content-Type multipart/mixed with a boundary', async ({ srv }) => {
    const r = await get(srv.port, '/multipart?n=3');
    expect(r.headers['content-type']).toMatch(/^multipart\/mixed; boundary=[\x21-\x7e]{1,70}$/);
  });

  test('03#27 multipart: 3 parts with HX-Part-ID, then the closing boundary, spread over time', async ({ srv }) => {
    const r = await get(srv.port, '/multipart?n=3');
    const boundary = /boundary=(\S+)/.exec(r.headers['content-type'] ?? '')![1];
    expect((r.body.match(/HX-Part-ID/g) || []).length).toBe(3);
    expect(r.body.startsWith(`\r\n--${boundary}\r\n`)).toBe(true); // a CRLF preamble, then the first part
    expect(r.body.endsWith(`\r\n--${boundary}--\r\n`)).toBe(true);
    expect(r.body).not.toMatch(/[^\r]\n/); // CRLF framing: no bare LF anywhere
    expect(r.times.at(-1)!).toBeGreaterThanOrEqual(250);
    test.info().annotations.push({ type: 'chunk times ms', description: r.times.join(',') });
  });
});

test.describe('fan-out and limits', () => {
  test('03#28 a slow consumer is dropped as Too_Slow; the server keeps serving', async ({ srv }) => {
    const topic = uid('slow');
    const before = (await stats(srv.port)).ended.Too_Slow;
    const slow = net.connect(srv.port, HOST);
    await new Promise((r) => slow.on('connect', r));
    slow.write(`GET /events?t=${topic} HTTP/1.1\r\nHost: x\r\n\r\n`);
    slow.pause();
    await sleep(300);
    const chunk = '<p>' + 'x'.repeat(60000) + '</p>';
    for (let i = 0; i < 200; i++) await publish(srv.port, topic, chunk);
    await sleep(500);
    const after = await stats(srv.port);
    slow.destroy();
    expect(after.ended.Too_Slow).toBeGreaterThan(before);
    expect((await get(srv.port, '/healthz')).body).toBe('ok');
  });

  test('03#29 fan-out spans more than one event loop', async ({ srv }) => {
    // Windows IOCP hands every connection to one loop (03 §2.1, §10.4); the claim is the Linux leg's (R3).
    test.fail(srv.os === 'windows', 'Windows puts every connection on one loop');
    const token = uid('fan');
    const subs = Array.from({ length: 8 }, () => sse(srv.port, '/sse/bus', { count: 50, ms: 1500 }));
    await sleep(400);
    const n = await stats(srv.port);
    await publish(srv.port, 'bus', `<p>${token}</p>`);
    const got = await Promise.all(subs);
    expect(got.every((evs) => evs.some((e) => e.data.includes(token)))).toBe(true);
    expect(n.loops_with_subs).toBeGreaterThan(1);
  });
});
