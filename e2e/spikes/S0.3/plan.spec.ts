import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import { HOST, LEG } from './env';
import { expect, get, publish, sleep, sse, stats, test, uid } from './server';

// What PLAN §8.2 and §9 state about the streams beyond 03's checks, at the protocol level.

test('every stream route sends X-Accel-Buffering: no and Cache-Control: no-cache (PLAN §8.2)', async ({ srv }) => {
  for (const p of ['/events?t=x', '/sse/bus', '/sse/tick?n=1&ms=10', '/multipart?n=1&ms=10', '/mp/count?n=1&max=1']) {
    const h = await new Promise<Record<string, string | string[] | undefined>>((res, rej) => {
      const req = http.get({ host: HOST, port: srv.port, path: p }, (r) => { res(r.headers); r.destroy(); });
      req.on('error', rej);
    });
    expect(h['x-accel-buffering'], p).toBe('no');
    expect(h['cache-control'], p).toBe('no-cache');
    expect(h['transfer-encoding'], p).toBe('chunked');
  }
});

test('ids are the hub sequence `<epoch>-<seq>`; a foreign epoch gets `event: resync` whose id moves the cursor to now (PLAN §9.3)', async ({ srv }) => {
  const t = uid('t');
  const evs = await sse(srv.port, `/events?t=${t}&after=1-1`, { count: 1, ms: 2000 });
  const s = await stats(srv.port);
  expect(evs[0]).toEqual({ id: `${s.epoch}-${evs[0].id!.split('-')[1]}`, event: 'resync', data: t });
  // The resync's id is a cursor of this epoch: resuming from it replays from the ring.
  await publish(srv.port, t, '<p>after the resync</p>');
  const again = await sse(srv.port, `/events?t=${t}`, { count: 1, ms: 2000, headers: { 'Last-Event-ID': evs[0].id! } });
  expect(again.map((e) => e.data)).toEqual(['<p>after the resync</p>']);
});

test('a gap older than the ring gets `event: resync`, not a partial replay (PLAN §9.3)', async ({ srv }) => {
  const t = uid('t');
  const s = await stats(srv.port);
  const old = `${s.epoch}-${s.seq}`;
  for (let i = 0; i < 260; i++) await publish(srv.port, t, `<p>${i}</p>`); // RING is 256
  const evs = await sse(srv.port, `/events?t=${t}`, { count: 1, ms: 2000, headers: { 'Last-Event-ID': old } });
  expect(evs[0]?.event).toBe('resync');
});

// PLAN §9.4: "the consumer is closed as Too_Slow: SSE ends, WS closes 1013". platform/stream closes
// with 1013 when the next frame would pass the stream's cap, and ends the stream with a 2 s deadline
// (F-1's stream_end(s, deadline)): a peer that reads again in time gets the close frame last; one
// that never does is cut off as Too_Slow.
async function slowSocket(srv: { port: number }, room: string) {
  const key = crypto.randomBytes(16).toString('base64');
  const s = net.connect(srv.port, HOST);
  await new Promise((r) => s.on('connect', r));
  s.write(`GET /ws/chat?room=${room} HTTP/1.1
Host: x
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: ${key}
Sec-WebSocket-Version: 13

`);
  await sleep(300);
  s.pause();
  // In parallel: against the WSL build each publish crosses WSL's port relay, and 200 in a row
  // took longer than the 2 s deadline, so the reader came back after the cut.
  const chunk = '<p>' + 'x'.repeat(60000) + '</p>';
  for (let i = 0; i < 200; i += 50) await Promise.all(Array.from({ length: 50 }, () => publish(srv.port, room, chunk)));
  return s;
}

test('a slow WebSocket consumer that reads again gets close 1013 (PLAN §9.4)', async ({ srv }) => {
  const s = await slowSocket(srv, uid('room'));
  await sleep(500);
  // Read everything that is left and look for a close frame at the end.
  let buf = Buffer.alloc(0);
  s.on('data', (d) => { buf = Buffer.concat([buf, d]); });
  s.resume();
  await new Promise((r) => { s.on('close', r); setTimeout(r, 5000); });
  const tail = buf.subarray(Math.max(0, buf.length - 4));
  expect([...tail]).toEqual([0x88, 0x02, 1013 >> 8, 1013 & 255]);
});

test('a slow WebSocket consumer that never reads is cut off at the deadline (PLAN §9.4)', async ({ srv }) => {
  // WSL's port relay keeps reading the socket on the client's behalf, so from Windows a peer that
  // stops reading can't be made: the server flushes and ends normally. The Windows leg covers it.
  test.skip(LEG === 'wsl', "WSL's relay reads for the client");
  const before = (await stats(srv.port)).ended.Too_Slow;
  const s = await slowSocket(srv, uid('room'));
  const closed = new Promise<number>((r) => { const t0 = Date.now(); s.on('close', () => r(Date.now() - t0)); });
  await sleep(3000);
  expect((await stats(srv.port)).ended.Too_Slow).toBeGreaterThan(before);
  s.resume();
  expect(await Promise.race([closed, sleep(3000).then(() => -1)])).toBeGreaterThanOrEqual(0);
});
