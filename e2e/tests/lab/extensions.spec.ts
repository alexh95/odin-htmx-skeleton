import type { Page } from '@playwright/test';
import { expect, test } from '../../fixtures';
import { startServer, stopServer, type Server } from '../../helpers/server';
import { closeTopic, get, publish, sleep, stats, uid } from './streams';

// The three stream extensions of htmx 4.0.0 in the engine, against the lab's pages on
// platform/stream and platform/hub, used the way PLAN §9.1 says pages are: what each one swaps,
// the stream headers, and reconnects where the plan states them (spike S0.3's 20 browser checks,
// the page contract, and drain and restart). Every test also asserts no CSP violation and no
// uncaught page error.

const T = { tag: '@lab' };

// htmx 4.0.0 rejects "signal is aborted without reason" when an SSE stream closes (04 §4.2;
// fixed on four-dev, #4098). Matched by exact text, so an upstream fix shows up here.
const KNOWN_PAGE_ERRORS = ['signal is aborted without reason'];

// The stream headers a page's response carries. NPM's nginx (the e2e-proxy job; it adds
// X-Served-By) acts on X-Accel-Buffering and doesn't pass it on, as nginx does every X-Accel-*.
function streamHeaders(h: Record<string, string>) {
  expect(h['cache-control']).toBe('no-cache, no-transform');
  if (!h['x-served-by']) expect(h['x-accel-buffering']).toBe('no');
}

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
  if (info.status === 'skipped') return; // a build without the lab: nothing ran
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

// The /events requests a page made, with the Last-Event-ID each carried.
function eventsRequests(page: Page) {
  const seen: { url: string; lei?: string }[] = [];
  page.on('request', (r) => { if (r.url().includes('/events?')) seen.push({ url: r.url(), lei: r.headers()['last-event-id'] }); });
  return seen;
}

test.describe('hx-sse', T, () => {
  test('the layout stream swaps unnamed events as OOB into a live log, in order, with the stream headers', async ({ page, server }) => {
    const key = uid('t');
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/lab/streams/live?t=${key}`);
    const h = await (await resp).allHeaders();
    expect(h['content-type']).toBe('text/event-stream');
    streamHeaders(h);
    for (const i of [1, 2, 3]) await publish(server.port, key, String(i));
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2', 'msg 3']);
    await expect(page.locator('#live')).toBeEmpty();
    const msgs = await recorded(page, 'htmx:sse:after:message');
    expect(msgs.map((m) => m.event)).toEqual(['', '', '']);
  });

  test('a quiet stream opens at once: the server\'s first comment line resolves the fetch in every engine', async ({ page }) => {
    // Without it WebKit resolved the stream only at the first heartbeat (19.5 s in one run).
    await page.goto(`/lab/streams/live?t=${uid('t')}`);
    await expect.poll(async () => (await recorded(page, 'htmx:sse:after:connection')).length, { timeout: 2000 }).toBe(1);
    expect(await recorded(page, 'htmx:sse:after:message')).toHaveLength(0);
  });

  test('a CR in a payload reaches hx-sse\'s parser as data, never as a field', async ({ page, server }) => {
    const key = uid('t');
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/lab/streams/live?t=${key}`);
    await resp;
    await publish(server.port, key, 'cr', 'before\revent: injected\r\nid: 999\nafter');
    await expect(page.locator('#m-cr')).toContainText('event: injected');
    await expect(page.locator('#m-cr')).toContainText('after');
    const msgs = await recorded(page, 'htmx:sse:after:message');
    expect(msgs).toHaveLength(1);
    expect(msgs[0].event).toBe('');
    expect(msgs[0].id).not.toBe('999');
  });

  test('Last-Event-ID: when the server ends the stream, hx-sse reconnects and the ring fills the gap once', async ({ page, server }) => {
    const key = uid('t');
    const reqs = eventsRequests(page);
    const resp = page.waitForResponse((r) => r.url().includes('/events?'));
    await page.goto(`/lab/streams/live?t=${key}`);
    await resp;
    await publish(server.port, key, '1');
    await publish(server.port, key, '2');
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    const lastId = (await recorded(page, 'htmx:sse:after:message')).at(-1)!.id!;
    await closeTopic(server.port, `lab.feed:${key}`);
    await publish(server.port, key, '3'); // during the client's backoff: only the replay can bring it
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2', 'msg 3']);
    await expect.poll(() => reqs.length).toBe(2);
    // The kick's `kicked` event carries no id, so the reconnect resumes from the last message's.
    expect(reqs.map((r) => r.lei)).toEqual([undefined, lastId]);
    expect((await recorded(page, 'htmx:sse:close')).length).toBe(0); // reconnected, not closed
  });

  test('`after`: the page\'s render-time cursor replays what was published before the stream connected', async ({ page, server }) => {
    const key = uid('t');
    const reqs = eventsRequests(page);
    const cursor = (await stats(server.port)).cursor;
    await publish(server.port, key, '1');
    await publish(server.port, key, '2');
    await page.goto(`/lab/streams/live?t=${key}&after=${cursor}`);
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    expect(reqs).toHaveLength(1);
    expect(reqs[0].url).toContain(`after=${cursor}`);
    expect(reqs[0].lei).toBeUndefined();
  });

  test('resync: a cursor from another epoch gets the named event, which refetches; nothing is swapped', async ({ page }) => {
    const key = uid('t');
    await page.goto(`/lab/streams/live?t=${key}&after=1-1`);
    await expect(page.locator('#refetch .refetched')).toHaveText(`refetched ${key}`);
    const rs = await recorded(page, 'resync');
    expect(rs).toHaveLength(1);
    expect(rs[0].data).toBe(`lab.feed:${key}`);
    await expect(page.locator('#live')).toBeEmpty();
    await expect(page.locator('#feed article')).toHaveCount(0);
  });

  test('an hx-post answered with a stream appends each event in order (the bot pattern)', async ({ page }) => {
    await page.goto(`/lab/streams/live?t=${uid('t')}`);
    await page.locator('#ask').click();
    await expect(page.locator('#tokens b')).toHaveText(['tick 1', 'tick 2', 'tick 3']);
  });
});

test.describe('hx-ws', T, () => {
  test('both ways: hx-ws:send sends JSON, the room gets escaped OOB HTML, a JSON envelope routes to its target', async ({ page, browser, baseURL }) => {
    const room = uid('room');
    const sent: string[] = [];
    page.on('websocket', (ws) => ws.on('framesent', (f) => sent.push(String(f.payload))));
    await page.goto(`/lab/streams/chat?room=${room}&tag=${uid('g')}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    const other = await browser.newContext({ baseURL });
    const pb = await other.newPage();
    await pb.goto(`/lab/streams/chat?room=${room}&tag=${uid('g')}`);
    await expect(pb.locator('#ws-status .hello')).toHaveText('connected 1');

    await page.locator('#message').fill('hi <b>there</b>');
    await page.locator('#send').click();
    for (const p of [page, pb]) await expect(p.locator('#chat p')).toHaveText(['hi <b>there</b>']);
    expect(await page.locator('#chat b').count()).toBe(0);
    expect(new URL(page.url()).pathname).toBe('/lab/streams/chat'); // the form did not submit natively
    const out = JSON.parse(sent.find((s) => s.includes('there'))!);
    expect(out.message).toBe('hi <b>there</b>');
    expect(out.headers['HX-Request']).toBe('true');
    await other.close();
  });

  const CODES: [number, boolean][] = [[1011, true], [1012, true], [1013, true], [1014, true], [1008, false], [1009, false]];
  for (const [code, reconnects] of CODES) {
    test(`a server close with ${code} ${reconnects ? 'reconnects' : 'stops the client for good'}`, async ({ page, server }) => {
      const room = uid('room'), tag = uid('g');
      let sockets = 0;
      page.on('websocket', () => sockets++);
      await page.goto(`/lab/streams/chat?room=${room}&tag=${tag}`);
      await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
      await closeTopic(server.port, `lab.room:${room}`, code);
      await expect.poll(() => wsCloseCodes(page)).toContain(code);
      expect((await wsCloseCodes(page))[0]).toBe(code);
      if (reconnects) {
        await expect(page.locator('#ws-status .hello')).toHaveText('connected 2', { timeout: 6000 });
        expect(sockets).toBe(2);
      } else {
        await sleep(2500); // a first retry would come 350-650 ms after the close
        expect(sockets).toBe(1);
        expect((await stats(server.port)).connects[`ws:${tag}`]).toBe(1);
      }
    });
  }

  test('a message over 64 KiB from hx-ws:send closes 1009, and the client stays closed', async ({ page, server }) => {
    const room = uid('room'), tag = uid('g');
    let sockets = 0;
    page.on('websocket', () => sockets++);
    await page.goto(`/lab/streams/chat?room=${room}&tag=${tag}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await page.locator('#message').fill('x'.repeat(70_000));
    await page.locator('#send').click();
    await expect.poll(() => wsCloseCodes(page)).toEqual([1009]);
    await sleep(2500);
    expect(sockets).toBe(1);
    expect((await stats(server.port)).connects[`ws:${tag}`]).toBe(1);
  });
});

test.describe('hx-multipart', T, () => {
  test('one request: each part swaps into its own target as it arrives, before the stream ends', async ({ page }) => {
    let finished = false;
    page.on('requestfinished', (r) => { if (r.url().includes('/lab/multipart?')) finished = true; });
    await page.goto('/lab/streams/mp');
    const resp = page.waitForResponse((r) => r.url().includes('/lab/multipart?'));
    await page.locator('#build').click();
    const h = await (await resp).allHeaders();
    expect(h['content-type']).toMatch(/^multipart\/mixed; boundary=/);
    streamHeaders(h);
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 3');
    expect(await page.locator('#mp-default .part').count()).toBe(0); // part 3 is 600 ms away
    await expect(page.locator('#mp-b .part')).toHaveText(['part 2 of 3']);
    await expect(page.locator('#mp-default .part')).toHaveText('part 3 of 3');
    expect(finished).toBe(false); // the closing boundary is 1.5 s behind part 3: its Content-Length let it swap
    await expect.poll(() => finished, { timeout: 5000 }).toBe(true);
  });

  test('a response whose first part is slow resolves at once: the preamble resolves the fetch in every engine', async ({ page }) => {
    // Without it WebKit resolved the response only with the first part (4.3 s for a 4 s part).
    await page.goto('/lab/streams/mp');
    await page.locator('#slow').click();
    await expect.poll(async () => (await recorded(page, 'htmx:multipart:after:connection')).length, { timeout: 1500 }).toBe(1);
    expect(await recorded(page, 'htmx:multipart:after:part')).toHaveLength(0);
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 1', { timeout: 6000 }); // part 1 names #mp-a
  });

  test('hx-multipart:connect: reconnects carry HX-Last-Part-ID, no gap or duplicate, HX-Trigger closes it', async ({ page, server }) => {
    const tag = uid('g');
    const lpi: string[] = [];
    page.on('request', (r) => { if (r.url().includes('/lab/mp/count')) lpi.push(r.headers()['hx-last-part-id'] ?? ''); });
    await page.goto(`/lab/streams/mp?tag=${tag}&count=1`);
    await expect(page.locator('#counts .count')).toHaveText(['1', '2', '3', '4', '5', '6'], { timeout: 10_000 });
    await sleep(2000);
    expect(lpi).toEqual(['', '2', '4']);
    expect((await stats(server.port)).connects[tag]).toBe(3);
    const closes = await recorded(page, 'htmx:multipart:close');
    expect(closes.map((c) => c.reason)).toEqual(['part']);
  });
});

test('the page contract: one layout SSE stream and one socket on one page, under the strict CSP', T, async ({ page, server }) => {
  const tag = uid('g'), room = uid('room');
  const streams: string[] = [];
  page.on('response', (r) => { if (r.headers()['content-type']?.includes('text/event-stream')) streams.push(r.url()); });
  let sockets = 0;
  page.on('websocket', () => sockets++);
  await page.goto(`/lab/streams?tag=${tag}&room=${room}`);
  await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
  await expect.poll(() => streams.length).toBe(1);
  await publish(server.port, tag, '1');
  await expect(page.locator('#feed article')).toHaveText(['msg 1']);
  await page.locator('#message').fill('hello room');
  await page.locator('#send').click();
  await expect(page.locator('#chat p')).toHaveText(['hello room']);
  await page.locator('#build').click();
  await expect(page.locator('#mp-default .part')).toHaveText('part 3 of 3');
  expect(streams).toHaveLength(1);
  expect(sockets).toBe(1);
});

// Starts the drain a signal would: a child on Windows gets no SIGTERM, so there it takes a
// -define:TEST_ROUTES=true build's /__test/shutdown (E2E_BUILD_FLAGS); false when neither works.
async function drain(s: Server): Promise<boolean> {
  const exited = new Promise<void>((r) => s.proc.once('exit', () => r()));
  if (process.platform === 'win32') {
    if ((await get(s.port, '/__test/shutdown')).status !== 200) return false;
  } else {
    s.proc.kill('SIGTERM');
  }
  await Promise.race([exited, sleep(10_000)]);
  return true;
}

test('drain and restart: the socket gets 1012, then both streams come back on the new process, SSE by resync', T, async ({ page }) => {
  test.slow();
  const tag = uid('g'), room = uid('room');
  const config = test.info().config;
  const s1 = await startServer(config);
  let s2: Server | undefined;
  try {
    let sockets = 0;
    page.on('websocket', () => sockets++);
    const reqs = eventsRequests(page);
    const base = `http://127.0.0.1:${s1.port}`;
    await page.goto(`${base}/lab/streams?tag=${tag}&room=${room}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await publish(s1.port, tag, '1');
    await expect(page.locator('#feed article')).toHaveText(['msg 1']);
    const oldId = (await recorded(page, 'htmx:sse:after:message')).at(-1)!.id!;

    if (!await drain(s1)) {
      s1.proc.kill();
      test.skip(true, 'Windows needs a TEST_ROUTES build to drain a child (E2E_BUILD_FLAGS=-define:TEST_ROUTES=true)');
    }
    await expect.poll(async () => (await wsCloseCodes(page))[0]).toBe(1012); // F-9's drain: on_shutdown sends 1012
    s2 = await startServer(config, {}, s1.port);

    await expect(page.locator('#refetch .refetched')).toHaveText(`refetched ${tag}`, { timeout: 30_000 });
    await expect.poll(async () => (await stats(s2!.port)).connects[`ws:${tag}`] ?? 0, { timeout: 30_000 }).toBe(1);
    expect(reqs.at(-1)?.lei).toBe(oldId); // the old epoch's cursor, answered with resync
    await publish(s2.port, tag, '2');
    await expect(page.locator('#feed article')).toHaveText(['msg 1', 'msg 2']);
    await page.locator('#message').fill('after the restart');
    await page.locator('#send').click();
    await expect(page.locator('#chat p')).toHaveText(['after the restart']);
    expect(sockets).toBeGreaterThanOrEqual(2);
  } finally {
    if (s2) await stopServer(s2);
    if (s1.proc.exitCode === null) s1.proc.kill();
  }
});
