import { expect, test, type Page } from '@playwright/test';
import type { Layout } from './server';

// The bundle race (04 §2.3, 11 §3; PLAN §12.1). A deferred htmx initialises on a setTimeout, so an
// extension in a later file can miss the initial DOM: a `<form hx-ws:send>` then submits natively and
// `hx-ws:connect`, `hx-sse:connect` and `hx-multipart:connect` never wire. One bundle can't lose that
// race. Every /static/ asset is held 400 ms here; a file that loads after the core (hyperscript, or an
// extension in the control) a further 400 ms, so it lands after htmx has initialised.
//
// Nine cases per engine: three page layouts, three runs each. The control loads the same extensions
// as separate deferred files and is expected to fail.

const DELAY = 400;
const base = () => process.env.S010_URL!;
const names = () => JSON.parse(process.env.S010_NAMES!) as Record<string, string>;

const LAYOUTS: { layout: Layout; title: string; hs: boolean }[] = [
  { layout: 'main', title: 'Main bundle, vanilla client', hs: false },
  { layout: 'main-hs', title: 'Main bundle + hyperscript', hs: true },
  { layout: 'scripting-hs', title: 'Scripting bundle + hyperscript, nonce CSP', hs: true },
];

interface Rec {
  csp: string[];
  strip: string[];
}

async function open(page: Page, layout: Layout): Promise<Record<string, string>> {
  const late = (url: string) => url.includes('/_hyperscript.') || url.includes('/static/sep/ext/');
  await page.route('**/static/**', async (route) => {
    await new Promise((r) => setTimeout(r, late(route.request().url()) ? 2 * DELAY : DELAY));
    await route.continue();
  });
  await page.addInitScript(() => {
    const w = window as unknown as { __rec: Rec };
    w.__rec = { csp: [], strip: [] };
    document.addEventListener('securitypolicyviolation', (e) => w.__rec.csp.push(`${e.effectiveDirective} ${e.blockedURI}`));
    document.addEventListener('htmx:security:strip', (e) => w.__rec.strip.push((e.target as Element).id));
  });
  const encodings: Record<string, string> = {};
  page.on('response', (r) => {
    if (r.url().includes('/static/')) encodings[new URL(r.url()).pathname] = r.headers()['content-encoding'] ?? 'identity';
  });
  await page.goto(`${base()}/page/${layout}`);
  return encodings;
}

for (const l of LAYOUTS) {
  for (const run of [1, 2, 3]) {
    test(`${l.title}, run ${run}`, async ({ page }) => {
      const encodings = await open(page, l.layout);
      const start = page.url();

      // The connects fired: each extension wired the initial DOM.
      await expect(page.locator('#ws-open')).toHaveCount(1);
      await expect(page.locator('#sse-ok')).toHaveCount(1);
      await expect(page.locator('#mp-ok')).toHaveCount(1);

      // The hx-ws:send form didn't navigate: the extension took the submit.
      await page.locator('#wsbtn').click();
      await expect(page.locator('#ws-echo')).toHaveText('hi');
      expect(page.url()).toBe(start);

      // hs-include's data arrived: hyperscript registered it with htmx, though it loaded last.
      if (l.hs) {
        await page.locator('#hs').click();
        await expect(page.locator('#echoed')).toHaveText('count=7');
      }

      // No CSP violation; on the nonce page hx-csp was live at init and stripped the one unnonced element.
      const rec = await page.evaluate(() => (window as unknown as { __rec: Rec }).__rec);
      expect(rec.csp).toEqual([]);
      expect(rec.strip).toEqual(l.layout === 'scripting-hs' ? ['unnonced'] : []);

      // The bundle came precompressed, in whichever encoding the engine asked for.
      const bundle = `/static/${l.layout === 'scripting-hs' ? names().scripting : names().main}`;
      test.info().annotations.push({ type: 'encoding', description: `${bundle} ${encodings[bundle]}` });
      expect(['br', 'gzip']).toContain(encodings[bundle]);
    });
  }
}

test('control: the same extensions as separate deferred files lose the race', async ({ page }) => {
  // D19 rejects this layout. If it ever passes, the delay no longer reproduces the race, and the
  // nine cases above prove nothing.
  test.fail();
  await open(page, 'separate');
  await page.waitForTimeout(1500);
  const seen = async (sel: string) => (await page.locator(sel).count()) === 1;
  const observed = { wsOpen: await seen('#ws-open'), sse: await seen('#sse-ok'), multipart: await seen('#mp-ok'), navigated: false };
  await page.locator('#wsbtn').click();
  await page.waitForTimeout(500);
  observed.navigated = page.url().includes('msg=');
  test.info().annotations.push({ type: 'observed', description: JSON.stringify(observed) });
  expect(observed).toEqual({ wsOpen: true, sse: true, multipart: true, navigated: false });
});
