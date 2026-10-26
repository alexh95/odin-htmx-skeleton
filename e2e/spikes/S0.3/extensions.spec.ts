import type { Page } from '@playwright/test';
import { expect, post, publish, sleep, startServer, stats, stopServer, test, uid } from './server';

// The three stream extensions of htmx 4.0.0 in the engine, against the spike server, used the way
// PLAN §9.1 says pages will: what each one swaps, the stream headers, and reconnects where the
// plan states them. Every test also asserts no CSP violation and no uncaught page error.

// htmx 4.0.0 rejects "signal is aborted without reason" when an SSE stream closes (04 §4.2;
// fixed on four-dev, #4098). Matched by exact text, so an upstream fix shows up here.
const KNOWN_PAGE_ERRORS = ['signal is aborted without reason'];

const RECORDED = [
  'htmx:sse:after:connection', 'htmx:sse:after:message', 'htmx:sse:close', 'htmx:sse:error',
  'htmx:ws:after:connection', 'htmx:ws:close', 'htmx:ws:error',
  'htmx:multipart:after:connection', 'htmx:multipart:after:part', 'htmx:multipart:close', 'htmx:multipart:error',
  'resync',
];

type Rec = { name: string; t: number; code?: number; reason?: string; event?: string; id?: string; data?: string };

let pageErrors: string[] = [];
let consoleErrors: string[] = [];

test.beforeEach(async ({ page }) => {
  await page.addInitScript((names) => {
    const w = window as unknown as { __csp: string[]; __ev: unknown[] };
    w.__csp = []; w.__ev = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(`${e.violatedDirective} ${e.blockedURI}`));
    for (const name of names) {
      document.addEventListener(name, (e) => {
        const d = (e as CustomEvent).detail ?? {};
        w.__ev.push({ name, t: Math.round(performance.now()), code: d.code, reason: d.reason, event: d.message?.event, id: d.message?.id ?? d.id, data: d.message?.data ?? d.data });
      });
    }
  }, RECORDED);
  pageErrors = []; consoleErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
});

test.afterEach(async ({ page }, info) => {
  const csp = await page.evaluate(() => (window as unknown as { __csp: string[] }).__csp).catch(() => []);
  if (consoleErrors.length) info.annotations.push({ type: 'console errors', description: consoleErrors.join(' | ') });
  const known = pageErrors.filter((e) => KNOWN_PAGE_ERRORS.includes(e));
  if (known.length) info.annotations.push({ type: 'known page errors', description: known.join(' | ') });
  expect(csp, 'CSP violations').toEqual([]);
  expect(pageErrors.filter((e) => !KNOWN_PAGE_ERRORS.includes(e)), 'uncaught page errors').toEqual([]);
});

const recorded = (page: Page, name: string) =>
  page.evaluate((name) => (window as unknown as { __ev: Rec[] }).__ev.filter((e) => e.name === name), name);
const wsCloseCodes = async (page: Page) => (await recorded(page, 'htmx:ws:close')).map((e) => e.code);

// An unnamed event's payload: an OOB append to the page's live log (PLAN §9.1).
const art = (id: string | number, text = `msg ${id}`) =>
  `<div hx-swap-oob="beforeend:#feed"><article id="m-${id}">${text}</article></div>`;

test.describe('hx-sse', () => {
  test('the layout stream swaps unnamed events as OOB into a live log, in order, with the stream headers', async ({ page, srv }) => {
    const t = uid('t');
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/p/live?t=${t}&tag=${uid('g')}`);
    const h = await (await resp).allHeaders();
    expect(h['content-type']).toBe('text/event-stream');
    expect(h['cache-control']).toBe('no-cache');
    expect(h['x-accel-buffering']).toBe('no');
    for (const i of [1, 2, 3]) await publish(srv.port, t, art(i));
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2', 'msg 3']);
    await expect(page.locator('#live')).toBeEmpty();
    const msgs = await recorded(page, 'htmx:sse:after:message');
    expect(msgs.map((m) => m.event)).toEqual(['', '', '']);
  });

  test('a quiet stream opens at once: the server\'s first comment line resolves the fetch in every engine', async ({ page }) => {
    // Without it WebKit resolved the stream only at the first heartbeat (19.5 s in one run).
    await page.goto(`/p/live?t=${uid('t')}&tag=${uid('g')}`);
    await expect.poll(async () => (await recorded(page, 'htmx:sse:after:connection')).length, { timeout: 2000 }).toBe(1);
    expect(await recorded(page, 'htmx:sse:after:message')).toHaveLength(0);
  });

  test('a CR in a payload reaches hx-sse\'s parser as data, never as a field', async ({ page, srv }) => {
    const t = uid('t');
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/p/live?t=${t}&tag=${uid('g')}`);
    await resp;
    await publish(srv.port, t, art('cr', 'before\revent: injected\r\nid: 999\nafter'));
    await expect(page.locator('#m-cr')).toContainText('event: injected');
    await expect(page.locator('#m-cr')).toContainText('after');
    const msgs = await recorded(page, 'htmx:sse:after:message');
    expect(msgs).toHaveLength(1);
    expect(msgs[0].event).toBe('');
    expect(msgs[0].id).not.toBe('999');
  });

  test('Last-Event-ID: when the server ends the stream, hx-sse reconnects and the ring fills the gap once', async ({ page, srv }) => {
    const t = uid('t'), tag = uid('g');
    const lei: (string | undefined)[] = [];
    page.on('request', (r) => { if (r.url().includes('/events?')) lei.push(r.headers()['last-event-id']); });
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/p/live?t=${t}&tag=${tag}`);
    await resp;
    await publish(srv.port, t, art(1));
    await publish(srv.port, t, art(2));
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    const lastId = (await recorded(page, 'htmx:sse:after:message')).at(-1)!.id!;
    await post(srv.port, `/admin/close?t=${t}`, '');
    await publish(srv.port, t, art(3)); // during the client's backoff: only the replay can bring it
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2', 'msg 3']);
    await expect.poll(() => lei.length).toBe(2);
    expect(lei).toEqual([undefined, lastId]);
    const st = await stats(srv.port);
    expect(st.connects[tag]).toBe(2);
    expect(st.seen[tag][1]).toContain(`last-event-id=${lastId}`);
    expect((await recorded(page, 'htmx:sse:close')).length).toBe(0); // reconnected, not closed
  });

  test('`after`: the page\'s render-time cursor replays what was published before the stream connected', async ({ page, srv }) => {
    const t = uid('t'), tag = uid('g');
    const s = await stats(srv.port);
    const cursor = `${s.epoch}-${s.seq}`;
    await publish(srv.port, t, art(1));
    await publish(srv.port, t, art(2));
    await page.goto(`/p/live?t=${t}&tag=${tag}&after=${cursor}`);
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    expect((await stats(srv.port)).seen[tag]).toEqual([`last-event-id= after=${cursor}`]);
  });

  test('resync: a cursor from another epoch gets the named event, which refetches; nothing is swapped', async ({ page }) => {
    const t = uid('t');
    await page.goto(`/p/live?t=${t}&tag=${uid('g')}&after=1-1`);
    await expect(page.locator('#refetch .refetched')).toHaveText(`refetched ${t}`);
    const rs = await recorded(page, 'resync');
    expect(rs).toHaveLength(1);
    expect(rs[0].data).toBe(t);
    await expect(page.locator('#live')).toBeEmpty();
    await expect(page.locator('#feed')).toBeEmpty();
  });

  test('an hx-post answered with a stream appends each event in order (the bot pattern)', async ({ page }) => {
    await page.goto(`/p/live?t=${uid('t')}&tag=${uid('g')}`);
    await page.locator('#ask').click();
    await expect(page.locator('#tokens b')).toHaveText(['tick 1', 'tick 2', 'tick 3']);
  });
});

test.describe('hx-ws', () => {
  test('both ways: hx-ws:send sends JSON, the room gets escaped OOB HTML, a JSON envelope routes to its target', async ({ page, browser, srv }) => {
    const room = uid('room');
    const sent: string[] = [];
    page.on('websocket', (ws) => ws.on('framesent', (f) => sent.push(String(f.payload))));
    await page.goto(`/p/chat?room=${room}&tag=${uid('g')}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    const other = await browser.newContext({ baseURL: srv.base });
    const pb = await other.newPage();
    await pb.goto(`/p/chat?room=${room}&tag=${uid('g')}`);
    await expect(pb.locator('#ws-status .hello')).toHaveText('connected 1');

    await page.locator('#message').fill('hi <b>there</b>');
    await page.locator('#send').click();
    for (const p of [page, pb]) await expect(p.locator('#chat p')).toHaveText(['hi <b>there</b>']);
    expect(await page.locator('#chat b').count()).toBe(0);
    expect(new URL(page.url()).pathname).toBe('/p/chat'); // the form did not submit natively
    const out = JSON.parse(sent.find((s) => s.includes('there'))!);
    expect(out.message).toBe('hi <b>there</b>');
    expect(out.headers['HX-Request']).toBe('true');
    await other.close();
  });

  const CODES: [number, boolean][] = [[1011, true], [1012, true], [1013, true], [1014, true], [1008, false], [1009, false]];
  for (const [code, reconnects] of CODES) {
    test(`a server close with ${code} ${reconnects ? 'reconnects' : 'stops the client for good'}`, async ({ page, srv }) => {
      const room = uid('room'), tag = uid('g');
      let sockets = 0;
      page.on('websocket', () => sockets++);
      await page.goto(`/p/chat?room=${room}&tag=${tag}`);
      await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
      await post(srv.port, `/admin/close?t=${room}&code=${code}`, '');
      await expect.poll(() => wsCloseCodes(page)).toContain(code);
      expect((await wsCloseCodes(page))[0]).toBe(code);
      if (reconnects) {
        await expect(page.locator('#ws-status .hello')).toHaveText('connected 2', { timeout: 6000 });
        expect(sockets).toBe(2);
      } else {
        await sleep(2500); // a first retry would come 350-650 ms after the close
        expect(sockets).toBe(1);
        expect((await stats(srv.port)).connects[`ws:${tag}`]).toBe(1);
      }
    });
  }

  test('a message over 64 KiB from hx-ws:send closes 1009, and the client stays closed', async ({ page, srv }) => {
    const room = uid('room'), tag = uid('g');
    let sockets = 0;
    page.on('websocket', () => sockets++);
    await page.goto(`/p/chat?room=${room}&tag=${tag}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await page.locator('#message').fill('x'.repeat(70_000));
    await page.locator('#send').click();
    await expect.poll(() => wsCloseCodes(page)).toEqual([1009]);
    await sleep(2500);
    expect(sockets).toBe(1);
    expect((await stats(srv.port)).connects[`ws:${tag}`]).toBe(1);
  });
});

test.describe('hx-multipart', () => {
  test('one request: each part swaps into its own target as it arrives, before the stream ends', async ({ page }) => {
    let finished = false;
    page.on('requestfinished', (r) => { if (r.url().includes('/multipart?')) finished = true; });
    await page.goto('/p/mp');
    const resp = page.waitForResponse((r) => r.url().includes('/multipart?'));
    await page.locator('#build').click();
    const h = await (await resp).allHeaders();
    expect(h['content-type']).toMatch(/^multipart\/mixed; boundary=/);
    expect(h['cache-control']).toBe('no-cache');
    expect(h['x-accel-buffering']).toBe('no');
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 3');
    expect(await page.locator('#mp-default .part').count()).toBe(0); // part 3 is 600 ms away
    await expect(page.locator('#mp-b .part')).toHaveText(['part 2 of 3']);
    await expect(page.locator('#mp-default .part')).toHaveText('part 3 of 3');
    expect(finished).toBe(false); // the closing boundary is 1.5 s behind part 3: its Content-Length let it swap
    await expect.poll(() => finished, { timeout: 5000 }).toBe(true);
  });

  test('a response whose first part is slow resolves at once: the preamble resolves the fetch in every engine', async ({ page }) => {
    // Without it WebKit resolved the response only with the first part (4.3 s for a 4 s part).
    await page.goto('/p/mp');
    await page.locator('#slow').click();
    await expect.poll(async () => (await recorded(page, 'htmx:multipart:after:connection')).length, { timeout: 1500 }).toBe(1);
    expect(await recorded(page, 'htmx:multipart:after:part')).toHaveLength(0);
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 1', { timeout: 6000 }); // part 1 names #mp-a
  });

  test('hx-multipart:connect: reconnects carry HX-Last-Part-ID, no gap or duplicate, HX-Trigger closes it', async ({ page, srv }) => {
    const tag = uid('g');
    const lpi: string[] = [];
    page.on('request', (r) => { if (r.url().includes('/mp/count')) lpi.push(r.headers()['hx-last-part-id'] ?? ''); });
    await page.goto(`/p/mp?tag=${tag}&count=1`);
    await expect(page.locator('#counts .count')).toHaveText(['1', '2', '3', '4', '5', '6'], { timeout: 10_000 });
    await sleep(2000);
    expect(lpi).toEqual(['', '2', '4']);
    expect((await stats(srv.port)).connects[tag]).toBe(3);
    const closes = await recorded(page, 'htmx:multipart:close');
    expect(closes.map((c) => c.reason)).toEqual(['part']);
  });
});

test('the page contract: one layout SSE stream and one socket on one page, under the strict CSP', async ({ page, srv }) => {
  const tag = uid('g'), room = uid('room');
  const streams: string[] = [];
  page.on('response', (r) => { if (r.headers()['content-type']?.includes('text/event-stream')) streams.push(r.url()); });
  let sockets = 0;
  page.on('websocket', () => sockets++);
  await page.goto(`/?tag=${tag}&room=${room}`);
  await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
  await expect.poll(() => streams.length).toBe(1);
  await publish(srv.port, `notice:${tag}`, art(1));
  await expect(page.locator('#feed article')).toHaveText(['msg 1']);
  await page.locator('#message').fill('hello room');
  await page.locator('#send').click();
  await expect(page.locator('#chat p')).toHaveText(['hello room']);
  await page.locator('#build').click();
  await expect(page.locator('#mp-default .part')).toHaveText('part 3 of 3');
  expect(streams).toHaveLength(1);
  expect(sockets).toBe(1);
});

test('drain and restart: the socket gets 1012, then both streams come back on the new process, SSE by resync', async ({ page }) => {
  test.slow();
  const tag = uid('g'), room = uid('room');
  const s1 = await startServer();
  let s2: Awaited<ReturnType<typeof startServer>> | undefined;
  try {
    let sockets = 0;
    page.on('websocket', () => sockets++);
    const lei: (string | undefined)[] = [];
    page.on('request', (r) => { if (r.url().includes('/events?')) lei.push(r.headers()['last-event-id']); });
    await page.goto(`${s1.base}/?tag=${tag}&room=${room}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await publish(s1.port, `notice:${tag}`, art(1));
    await expect(page.locator('#feed article')).toHaveText(['msg 1']);
    const oldId = (await recorded(page, 'htmx:sse:after:message')).at(-1)!.id!;

    await stopServer(s1); // F-9's drain: the socket's on_shutdown sends 1012
    await expect.poll(async () => (await wsCloseCodes(page))[0]).toBe(1012);
    s2 = await startServer(s1.port);

    await expect(page.locator('#refetch .refetched')).toHaveText('refetched notice', { timeout: 30_000 });
    await expect.poll(async () => (await stats(s2!.port)).connects[`ws:${tag}`] ?? 0, { timeout: 30_000 }).toBe(1);
    expect(lei.at(-1)).toBe(oldId); // the old epoch's cursor, answered with resync
    await publish(s2.port, `notice:${tag}`, art(2));
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    await page.locator('#message').fill('after the restart');
    await page.locator('#send').click();
    await expect(page.locator('#chat p')).toHaveText(['after the restart']);
    expect(sockets).toBeGreaterThanOrEqual(2);
  } finally {
    if (s2) await stopServer(s2);
    await stopServer(s1);
  }
});
