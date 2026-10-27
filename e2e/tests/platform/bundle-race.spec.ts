import type { Page } from '@playwright/test';
import { BUILD, expect, test } from '../../fixtures';

// The bundle race (PLAN §12.1; research 04 §2.3, 11 §3; spike S0.10), on the binary: a
// deferred htmx initialises on a setTimeout, so an extension in a later file could miss the
// initial DOM, and a `<form hx-ws:send>` would then submit natively. One bundle can't lose
// that race. Every /static/ asset is held 400 ms here, and hyperscript, which loads after
// the bundle, 400 ms more, so it lands after htmx has initialised. The separate-files control
// that proves the delay reproduces the race is the spike's (docs/spikes/S0.10.md).

const DELAY = 400;

async function open(page: Page, path: string) {
  await page.route('**/static/**', async (route) => {
    const late = route.request().url().includes('/_hyperscript.');
    await new Promise((r) => setTimeout(r, late ? 2 * DELAY : DELAY));
    await route.continue();
  });
  await page.addInitScript(() => {
    const w = window as any;
    w.__csp = [];
    w.__strip = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(`${e.effectiveDirective} ${e.blockedURI}`));
    document.addEventListener('htmx:security:strip', (e) => w.__strip.push((e.target as Element).id));
  });
  const encodings: Record<string, string> = {};
  page.on('response', (r) => {
    const p = new URL(r.url()).pathname;
    if (p.startsWith('/static/')) encodings[p] = r.headers()['content-encoding'] ?? 'identity';
  });
  await page.goto(path);
  return encodings;
}

async function bundleCameCompressed(page: Page, encodings: Record<string, string>) {
  const src = await page.locator('script[src*="/static/"]').evaluateAll((ss) => ss.map((s) => s.getAttribute('src')!)).then((ss) => ss[0]);
  test.info().annotations.push({ type: 'encoding', description: `${src} ${encodings[src]}` });
  expect(['br', 'gzip']).toContain(encodings[src]);
}

test.describe('bundle-race', { tag: '@platform' }, () => {
  test('Main bundle: the socket, the SSE stream and multipart wire, and hx-ws:send never navigates', { tag: '@lab' }, async ({ page, request }) => {
    const tag = `race-${test.info().project.name}-${Date.now()}`;
    const encodings = await open(page, `/lab/streams?tag=${tag}&room=${tag}`);
    const start = page.url();
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await request.post(`/lab/publish?t=lab.feed:${tag}`, { form: { id: 'r1', text: 'raced' } });
    await expect(page.locator('#feed #m-r1')).toHaveText('raced');
    await page.locator('#message').fill('hi');
    await page.locator('#send').click();
    await expect(page.locator('#chat p').last()).toHaveText('hi');
    expect(page.url()).toBe(start);
    await page.locator('#build').click();
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 3');
    expect(await page.evaluate(() => (window as any).__csp)).toEqual([]);
    await bundleCameCompressed(page, encodings);
  });

  test('Scripting bundle under the nonce CSP: hx-csp was live at init, the streams wired', { tag: '@scripting' }, async ({ page }) => {
    const encodings = await open(page, '/scripting/streams');
    for (const t of ['sse', 'ws', 'mp']) await expect(page.locator(`#${t}-box button`)).toHaveCount(4);
    await page.locator('#ws-page').click();
    await expect(page.locator('#ws-out .scripting-hello')).toHaveText('hello-ws-page');
    const rec = await page.evaluate(() => ({ csp: (window as any).__csp, strip: (window as any).__strip }));
    expect(rec.csp).toEqual([]);
    expect([...rec.strip].sort()).toEqual(['mp-none', 'mp-own', 'sse-none', 'sse-own', 'ws-none', 'ws-own']);
    await bundleCameCompressed(page, encodings);
  });

  test('hyperscript, loaded last, still registered hs-include with htmx', { tag: '@scripting' }, async ({ page }) => {
    test.skip(BUILD.client !== 'hyperscript', 'the vanilla client loads no hyperscript');
    await open(page, '/scripting/live');
    await expect(page.locator('#pw-hs-card')).toHaveAttribute('data-hyperscript-powered', /.*/); // installed, though it loads last
    await page.locator('#pw-hs').fill('Correct-Horse-9');
    await expect(page.locator('#pw-hs-card .scripting-pw-score')).toHaveText('4 of 4');
    await page.locator('#pw-hs-ask').click();
    await expect(page.locator('#pw-hs-heard')).toHaveText('The server heard 4 of 4.');
    expect(await page.evaluate(() => (window as any).__csp)).toEqual([]);
  });
});
