import type { Page } from '@playwright/test';
import { expect, proxyNoise, test } from '../../fixtures';

// htmx 4's two compatibility extensions, each on its own page and bundle (PLAN §12.3; research
// 04 §5.15, §5.16). htmx-2-compat puts htmx 2's semantics back on its page only: error
// responses aren't swapped, implicit inheritance is on, the old event names fire.
// hx-alpine-compat, loaded with no Alpine, changes nothing.

async function watch(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !proxyNoise(m.text())) errors.push(m.text()); });
  await page.addInitScript(() => {
    const w = window as any;
    w.__csp = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(`${e.effectiveDirective} ${e.blockedURI}`));
  });
  return errors;
}

test.describe('/compat/htmx2', { tag: '@compat' }, () => {
  test('error responses are left unswapped: 4xx and 5xx join noSwap', async ({ page }) => {
    await watch(page);
    await page.goto('/compat/htmx2');
    expect(await page.evaluate(() => (window as any).htmx.config.noSwap)).toEqual([204, 304, '4xx', '5xx']);
    await page.locator('#h2-name').fill('Ada');
    await page.locator('#h2-save').click();
    await expect(page.locator('#h2-saved')).toHaveText('Saved Ada.');
    // Refused: the server says why with a 422, and htmx 2's semantics drop it.
    const [res] = await Promise.all([page.waitForResponse('**/compat/htmx2/save'), (async () => {
      await page.locator('#h2-name').fill('');
      await page.locator('#h2-save').click();
    })()]);
    expect(res.status()).toBe(422);
    await page.waitForTimeout(300);
    await expect(page.locator('#h2-saved')).toHaveText('Saved Ada.');
    await expect(page.locator('#h2-refused')).toHaveCount(0);
    expect(await page.evaluate(() => (window as any).__csp)).toEqual([]);
  });

  test('a child inherits its parent\'s hx-target, and htmx 2\'s event names fire', async ({ page }) => {
    await page.goto('/compat/htmx2');
    await page.evaluate(() => {
      (window as any).__old = 0;
      document.addEventListener('htmx:afterSwap', () => (window as any).__old++);
    });
    await page.locator('#h2-child').click();
    await expect(page.locator('#h2-inherited #h2-pong')).toHaveText('pong, into the parent\'s target');
    await expect(page.locator('#h2-child')).toHaveText('Ping'); // not swapped into itself
    expect(await page.evaluate(() => (window as any).__old)).toBeGreaterThan(0);
    // compat.js counts the same event on the page.
    await expect(page.locator('#h2-swaps')).not.toHaveText('0');
  });
});

test.describe('/compat/alpine', { tag: '@compat' }, () => {
  test('the extension loads with no Alpine and changes nothing', async ({ page }) => {
    const errors = await watch(page);
    await page.goto('/compat/alpine');
    expect(await page.evaluate(() => typeof (window as any).Alpine)).toBe('undefined');
    await page.locator('#alpine-ping').click();
    await expect(page.locator('#alpine-out #alpine-pong')).toHaveText('pong, unchanged');
    // htmx 4's own semantics hold here: no implicit inheritance, 4xx swapped.
    expect(await page.evaluate(() => (window as any).htmx.config.noSwap)).toEqual([204, 304]);
    expect(errors).toEqual([]);
    expect(await page.evaluate(() => (window as any).__csp)).toEqual([]);
  });
});

test('the compat bundles stay on their pages: the index and the rest of the site run plain htmx 4', { tag: '@compat' }, async ({ page }) => {
  await page.goto('/compat');
  expect(await page.evaluate(() => (window as any).htmx.config.noSwap)).toEqual([204, 304]);
  // A boosted link into a compat page loads it whole, so its bundle and semantics come with it.
  await Promise.all([page.waitForURL('**/compat/htmx2'), page.locator('a[href="/compat/htmx2"]').click()]);
  expect(await page.evaluate(() => (window as any).htmx.config.noSwap)).toEqual([204, 304, '4xx', '5xx']);
});
