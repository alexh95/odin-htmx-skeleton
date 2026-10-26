import type { Page } from '@playwright/test';
import { expect, test } from '../../fixtures';
import { uid } from './streams';

// 03's contract checks that open their sockets with the page's own WebSocket (03 §10.2: #09-#12
// and #25; spike S0.3), so the engine under test speaks to the server, from a page this server
// served: it carries this origin and runs under the page's CSP.

const T = { tag: '@lab' };

async function onPage(page: Page) {
  await page.goto('/lab/streams/blank');
}

test.describe('WebSocket through the engine', T, () => {
  test('03#09 ws/echo: text round-trip (UTF-8)', async ({ page }) => {
    await onPage(page);
    const echoed = await page.evaluate(() => new Promise((res) => {
      const ws = new WebSocket(`ws://${location.host}/lab/ws/echo`);
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
      const ws = new WebSocket(`ws://${location.host}/lab/ws/echo`);
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
      const ws = new WebSocket(`ws://${location.host}/lab/ws/echo`);
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
      const ws = new WebSocket(`ws://${location.host}/lab/ws/echo`);
      ws.onopen = () => ws.close(1000, 'bye');
      ws.onclose = (e) => res({ code: e.code, clean: e.wasClean });
      setTimeout(() => res('timeout'), 4000);
    }));
    expect(r).toEqual({ code: 1000, clean: true });
  });

  test('03#25 ws/chat: one socket\'s hx-ws JSON reaches all 8 sockets as escaped OOB HTML', async ({ page }) => {
    await onPage(page);
    const room = uid('room');
    const msgs = await page.evaluate((room) => new Promise<unknown[]>((res) => {
      const socks = Array.from({ length: 8 }, () => new WebSocket(`ws://${location.host}/lab/ws/chat?room=${room}`));
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
});
