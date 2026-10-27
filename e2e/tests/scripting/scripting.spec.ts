import type { Page } from '@playwright/test';
import { BUILD, expect, test } from '../../fixtures';

// The nonce class (PLAN §12.2, §12.3): /scripting's pages load the Scripting bundle (hx-csp
// first) under a per-response nonce CSP with no 'self', and code in markup runs only on an
// element that carries the page's nonce. Every interaction here raises no CSP violation.

async function watch(page: Page) {
  await page.addInitScript(() => {
    const w = window as any;
    w.__csp = [];
    w.__strip = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(`${e.effectiveDirective} ${e.blockedURI} ${e.sourceFile}:${e.lineNumber}`));
    document.addEventListener('htmx:security:strip', (e) => w.__strip.push((e.target as Element).id));
  });
}
const recorded = (page: Page) => page.evaluate(() => ({ csp: (window as any).__csp as string[], strip: (window as any).__strip as string[] }));

test.describe('the nonce class', { tag: '@scripting' }, () => {
  test('each response gets its own nonce: in the policy, on the scripts, on every htmx element', async ({ page, request }) => {
    const a = (await request.get('/scripting')).headers();
    const b = (await request.get('/scripting')).headers();
    const nonce = (h: Record<string, string>) => /script-src 'nonce-([A-Za-z0-9_-]+=*)' 'sha256-[A-Za-z0-9+/=]+';/.exec(h['content-security-policy'])?.[1];
    expect(nonce(a)!.length).toBeGreaterThanOrEqual(22);
    expect(nonce(a)).not.toBe(nonce(b));
    expect(a['content-security-policy']).not.toContain("'self' 'sha256");
    expect(a['cache-control']).toBe('no-store');

    const res = await page.goto('/scripting');
    const n = nonce(res!.headers());
    const seen = await page.evaluate(() => ({
      // The scripts the browser runs; text/hyperscript is fetched by hyperscript, not run.
      scripts: [...document.querySelectorAll('script[src]:not([type="text/hyperscript"])')].map((s) => (s as HTMLScriptElement).nonce),
      stamped: [...document.querySelectorAll('[hx-get],[hx-post],[hx-on\\:click]')].map((e) => e.getAttribute('hx-nonce')),
      marker: document.documentElement.outerHTML.includes('<%N%>'),
    }));
    expect(seen.scripts.length).toBeGreaterThan(0);
    for (const s of seen.scripts) expect(s).toBe(n);
    for (const s of seen.stamped) expect(s).toBe(n);
    expect(seen.marker).toBe(false);
  });

  test('a nonced hx-get, the button its answer carries, hx-on, a trigger filter and a js: value all run', async ({ page }) => {
    await watch(page);
    await page.goto('/scripting');
    await page.locator('#get-nonced').click();
    await expect(page.locator('#out-get .scripting-hello')).toHaveText('hello-nonced');
    // The answer's own nonce was rewritten to the page's, so its button is live.
    await page.locator('#again-nonced').click();
    await expect(page.locator('#out-get #hello-nonced-again')).toHaveText('hello-nonced-again');

    await page.locator('#on-click').click();
    await expect(page.locator('#on-click')).toHaveText('hx-on ran');

    await page.locator('#filtered').click({ modifiers: ['Alt'] });
    await page.waitForTimeout(300);
    await expect(page.locator('#out-filter')).toBeEmpty();
    await page.locator('#filtered').click();
    await expect(page.locator('#out-filter .scripting-hello')).toHaveText('hello-filtered');

    await page.locator('#js-vals').click();
    await expect(page.locator('#out-js .scripting-hello')).toHaveText('hello-js-42');
    expect(await recorded(page)).toEqual({ csp: [], strip: [] });
  });

  test('a boosted link into the class loads the page whole, under its own policy', async ({ page }) => {
    await page.goto('/lab/streams/blank');
    const [res] = await Promise.all([page.waitForResponse((r) => new URL(r.url()).pathname === '/scripting' && r.request().resourceType() === 'document'), page.locator('nav a[href="/scripting"]').first().click()]);
    expect(res.headers()['content-security-policy']).toContain("script-src 'nonce-");
    await page.locator('#on-click').click();
    await expect(page.locator('#on-click')).toHaveText('hx-on ran');
  });
});

test.describe('/scripting/live', { tag: '@scripting' }, () => {
  const cards = BUILD.client === 'hyperscript' ? ['js', 'hs', 'live'] : ['js', 'live'];

  test('the password rules tick the same way in all three builds', async ({ page }) => {
    await watch(page);
    await page.goto('/scripting/live');
    if (cards.includes('hs')) await expect(page.locator('#pw-hs-card')).toHaveAttribute('data-hyperscript-powered', /.*/);
    for (const c of cards) {
      const card = page.locator(`#pw-${c}-card`);
      const field = page.locator(`#pw-${c}`);
      await field.fill('short1');
      await expect(card.locator('.scripting-pw-score'), c).toHaveText('2 of 4');
      await expect(card.locator('li[data-rule="digit"]'), c).toHaveClass(/\bok\b/);
      await expect(card.locator('li[data-rule="len"]'), c).not.toHaveClass(/\bok\b/);
      await field.fill('Password12345');
      await expect(card.locator('.scripting-pw-score'), c).toHaveText('3 of 4');
      await expect(card.locator('li[data-rule="word"]'), c).not.toHaveClass(/\bok\b/);
      await field.fill('Correct-Horse-9');
      await expect(card.locator('.scripting-pw-score'), c).toHaveText('4 of 4');
    }
    expect(await recorded(page)).toEqual({ csp: [], strip: [] });
  });

  test('hs-include sends the hyperscript card\'s score with its request', async ({ page }) => {
    test.skip(BUILD.client !== 'hyperscript', 'the vanilla client runs no hyperscript');
    await page.goto('/scripting/live');
    await expect(page.locator('#pw-hs-card')).toHaveAttribute('data-hyperscript-powered', /.*/);
    await page.locator('#pw-hs').fill('Correct-Horse-9');
    await expect(page.locator('#pw-hs-card .scripting-pw-score')).toHaveText('4 of 4');
    await page.locator('#pw-hs-ask').click();
    await expect(page.locator('#pw-hs-heard')).toHaveText('The server heard 4 of 4.');
  });
});

test.describe('/scripting/tt', { tag: '@scripting' }, () => {
  test('Trusted Types: htmx swaps and hx-live binds through the htmx policy, and no hyperscript loads', async ({ page }) => {
    await watch(page);
    const res = await page.goto('/scripting/tt');
    expect(res!.headers()['content-security-policy']).toContain("; require-trusted-types-for 'script'; trusted-types htmx");
    expect(await page.evaluate(() => typeof (window as any)._hyperscript)).toBe('undefined');
    expect(await page.locator('script[type="text/hyperscript"]').count()).toBe(0);
    await page.locator('#tt-get').click();
    await expect(page.locator('#tt-out .scripting-hello')).toHaveText('hello-tt');
    await page.locator('#tt-in').fill('four');
    await expect(page.locator('#tt-count')).toHaveText('4 characters');
    // Escape clears the overlay without writing a sink the policy guards.
    await page.keyboard.press('Escape');
    expect(await recorded(page)).toEqual({ csp: [], strip: [] });
  });
});
