import { test, expect } from '../fixtures';
import type { Page } from '@playwright/test';

// The security headers every response carries, and the Content-Security-Policy
// actually holding: no inline handlers left to block, the theme pre-paint
// script admitted by its hash, and no violation while the pages are used.
// Shared by the demo and the --minimal starter.

async function sitemapPaths(page: Page): Promise<string[]> {
  const body = await (await page.request.get('/sitemap.xml')).text();
  return [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}

// Records every CSP violation the page reports, from before its first script.
async function watchCsp(page: Page) {
  await page.addInitScript(() => {
    (window as any).__csp = [];
    document.addEventListener('securitypolicyviolation', (e) =>
      (window as any).__csp.push(`${e.violatedDirective} ${e.blockedURI} ${e.sourceFile}:${e.lineNumber}`),
    );
  });
}
const violations = (page: Page) => page.evaluate(() => (window as any).__csp as string[]);

// Writes must come from the site's own pages. Browsers say where a request
// comes from (Sec-Fetch-Site, Origin); one that is cross-site by either is
// refused before its body is read. A client that sends neither isn't a browser
// (these API calls, curl, k6) and passes.
test.describe('cross-site write guard', () => {
  const form = { 'content-type': 'application/x-www-form-urlencoded' };

  test('a cross-site or same-site-but-other-origin write is refused', async ({ request }) => {
    for (const site of ['cross-site', 'same-site']) {
      const res = await request.post('/', { headers: { ...form, 'Sec-Fetch-Site': site }, data: 'x=1' });
      expect(res.status(), site).toBe(403);
    }
    // An older browser without Sec-Fetch-Site still sends Origin.
    const res = await request.post('/', { headers: { ...form, Origin: 'https://evil.example' }, data: 'x=1' });
    expect(res.status()).toBe(403);
    // Reads are never refused, whoever asks.
    expect((await request.get('/', { headers: { 'Sec-Fetch-Site': 'cross-site' } })).status()).toBe(200);
  });

  test('a forged write changes nothing', async ({ request }) => {
    const demo = (await request.get('/data')).status() === 200;
    const [path, data, probe] = demo
      ? ['/contacts', 'name=Forged+Row&email=forged@example.dev', '/api/search?q=Forged']
      : ['/notes', 'body=Forged+note', '/'];
    const res = await request.post(path, {
      headers: { ...form, 'Sec-Fetch-Site': 'cross-site', Origin: 'https://evil.example' },
      data,
    });
    expect(res.status()).toBe(403);
    expect(await (await request.get(probe)).text()).not.toContain('Forged');
  });

  test('a same-origin write passes', async ({ request, baseURL }) => {
    const demo = (await request.get('/data')).status() === 200;
    const [path, data] = demo ? ['/contacts', 'name=Same+Origin&email=same@example.dev'] : ['/notes', 'body=Same+origin'];
    for (const headers of [{ 'Sec-Fetch-Site': 'same-origin' }, { Origin: baseURL! }, {}]) {
      const res = await request.post(path, { headers: { ...form, ...headers }, data });
      expect(res.status(), JSON.stringify(headers)).toBe(200);
    }
  });
});

test.describe('security headers', () => {
  test('every kind of response carries them', async ({ request }) => {
    for (const path of ['/', '/static/app.css', '/healthz', '/no-such-page']) {
      const h = (await request.get(path)).headers();
      expect(h['x-content-type-options'], path).toBe('nosniff');
      expect(h['x-frame-options'], path).toBe('DENY');
      expect(h['referrer-policy'], path).toBe('strict-origin-when-cross-origin');
      const csp = h['content-security-policy'] ?? '';
      expect(csp, path).toContain("frame-ancestors 'none'");
      // Strict for scripts: no 'unsafe-inline', the inline one admitted by hash.
      expect(csp, path).toMatch(/script-src 'self' 'sha256-[A-Za-z0-9+/=]+';/);
      expect(csp, path).not.toMatch(/script-src[^;]*unsafe-inline/);
    }
  });

  test('no page carries an inline event handler', async ({ page }) => {
    for (const path of await sitemapPaths(page)) {
      await page.goto(path);
      const inline = await page.evaluate(() =>
        [...document.querySelectorAll('*')].flatMap((el) =>
          [...el.attributes].filter((a) => /^on[a-z]+$/.test(a.name)).map((a) => `${el.tagName}[${a.name}]`),
        ),
      );
      expect(inline, path).toEqual([]);
    }
  });

  test('the theme pre-paint script runs under the policy', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => {
      localStorage.setItem('style', 'terminal');
      localStorage.setItem('scheme', 'amber');
    });
    await page.reload();
    // Only the inline pre-paint script reads these back; if its hash didn't
    // match, the browser would have refused it and the defaults would show.
    await expect(page.locator('html')).toHaveAttribute('data-style', 'terminal');
    await expect(page.locator('html')).toHaveAttribute('data-scheme', 'amber');
  });

  test('using the pages raises no CSP violation', async ({ page }) => {
    await watchCsp(page);
    for (const path of await sitemapPaths(page)) {
      await page.goto(path);
      expect(await violations(page), path).toEqual([]);
    }

    // The picker is on every page, in both variants.
    await page.goto('/');
    await page.locator('.picker summary').click();
    await page.locator('[data-pick-style="brutal"]').click();
    await expect(page.locator('html')).toHaveAttribute('data-style', 'brutal');
    await page.locator('[data-pick-scheme="acid"]').click();
    await expect(page.locator('html')).toHaveAttribute('data-scheme', 'acid');

    if ((await page.request.get('/components')).status() === 200) {
      await page.goto('/components');
      await page.locator('[data-sw-style="arcade"][data-sw-scheme="pop"]').click();
      await expect(page.locator('html')).toHaveAttribute('data-scheme', 'pop');
      await page.getByRole('tab', { name: 'Security' }).click();
      await expect(page.getByRole('tab', { name: 'Security' })).toHaveAttribute('aria-selected', 'true');
      await page.getByRole('button', { name: 'Success toast' }).click();
      await page.locator('#toasts .toast-x').first().click();
      await expect(page.locator('#toasts .toast:not(.leaving)')).toHaveCount(0);
      await page.getByRole('button', { name: 'Open drawer' }).click();
      await page.locator('.drawer h2').click(); // inside the drawer: must not close it
      await expect(page.locator('.drawer')).toBeVisible();
    }
    expect(await violations(page)).toEqual([]);
  });
});
