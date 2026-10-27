import type { Page } from '@playwright/test';
import { expect, test } from '../../fixtures';

// The negative canary (PLAN §19, csp-enforced; research 11 §7.3): the policy really refuses
// what it should, so csp-clean's zero means something. Under the hash CSP an hx-on handler
// needs eval and is refused; in the nonce class an htmx element without the page's nonce is
// stripped. The markup is injected the way an escaping mistake would put it, and clicked
// through a locator, which, unlike a click from page.evaluate, runs under the policy (11 §7.1).

async function record(page: Page) {
  await page.addInitScript(() => {
    const w = window as any;
    w.__csp = [];
    w.__strip = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(e.effectiveDirective));
    document.addEventListener('htmx:security:strip', (e) => w.__strip.push((e.target as Element).id));
  });
}

test.describe('csp-enforced', { tag: '@platform' }, () => {
  test('the hash CSP refuses an injected hx-on: the handler never runs', async ({ page }) => {
    await record(page);
    await page.goto('/');
    await page.evaluate(() => {
      const b = document.createElement('button');
      b.id = 'canary';
      b.type = 'button';
      b.textContent = 'canary';
      b.setAttribute('hx-on:click', "this.textContent = 'ran'");
      document.querySelector('main')!.append(b);
      (window as any).htmx.process(b);
    });
    await page.locator('#canary').click();
    await expect.poll(() => page.evaluate(() => (window as any).__csp as string[])).toContain('script-src');
    await expect(page.locator('#canary')).toHaveText('canary');
  });

  test('the nonce class strips an injected, unnonced hx-get', { tag: '@scripting' }, async ({ page }) => {
    await record(page);
    await page.goto('/scripting');
    await page.evaluate(() => {
      const slot = document.createElement('div');
      document.querySelector('main')!.append(slot);
      (window as any).htmx.swap({ target: slot, swap: 'innerHTML', text: '<button id="u-get" type="button" hx-get="/scripting/hello?v=u" hx-target="#u-out">u</button><div id="u-out"></div>' });
    });
    await expect.poll(() => page.evaluate(() => (window as any).__strip as string[])).toEqual(['u-get']);
    await expect(page.locator('#u-get')).not.toHaveAttribute('hx-get', /.*/);
    await page.locator('#u-get').click();
    await page.waitForTimeout(300);
    await expect(page.locator('#u-out')).toBeEmpty();
    expect(await page.evaluate(() => (window as any).__csp)).toEqual([]);
  });
});
