import { expect, test } from '../../fixtures';

// What the test harness itself does under the CSP (research 11 §7.1; PLAN §19, harness-csp),
// on the hash policy's home page: which Playwright calls the policy exempts and which it
// doesn't, so no spec mistakes a harness exemption for the app's behaviour. This is also
// the Firefox proof, which CI runs (Firefox can't start on the dev PC).

test.describe('harness-csp', { tag: '@platform' }, () => {
  test('addInitScript runs under the policy', async ({ page }) => {
    await page.addInitScript(() => { (window as any).__init = 'ran'; });
    await page.goto('/');
    expect(await page.evaluate(() => (window as any).__init)).toBe('ran');
  });

  test('page.evaluate is exempt from the eval ban, as a function or a string', async ({ page }) => {
    await page.goto('/');
    expect(await page.evaluate(() => new Function('return 7')())).toBe(7);
    expect(await page.evaluate('eval("6 * 7")')).toBe(42);
  });

  test('code an evaluate leaves for a later task is not: eval there is refused', async ({ page }) => {
    await page.goto('/');
    const outcome = await page.evaluate(() => new Promise<string>((resolve) => setTimeout(() => {
      try { resolve(String(new Function('return 7')())); } catch (e) { resolve((e as Error).name); }
    })));
    expect(outcome).toBe('EvalError');
  });

  test('a click from evaluate runs an hx-on handler the policy refuses to a locator click', async ({ page }) => {
    await page.goto('/');
    const inject = (id: string) => page.evaluate((id) => {
      const b = document.createElement('button');
      b.id = id;
      b.type = 'button';
      b.textContent = 'x';
      b.setAttribute('hx-on:click', "this.textContent = 'ran'");
      document.querySelector('main')!.append(b);
      (window as any).htmx.process(b);
    }, id);
    await inject('from-evaluate');
    await page.evaluate(() => (document.getElementById('from-evaluate') as HTMLButtonElement).click());
    // The false pass: a spec that clicks this way would "see" the handler work.
    await expect(page.locator('#from-evaluate')).toHaveText('ran');
    await inject('from-locator');
    await page.locator('#from-locator').click();
    await page.waitForTimeout(200);
    await expect(page.locator('#from-locator')).toHaveText('x');
  });

  test('addScriptTag: inline content throws, a same-origin URL runs', async ({ page }) => {
    await page.goto('/');
    await expect(page.addScriptTag({ content: 'window.__inline = 1' })).rejects.toThrow();
    expect(await page.evaluate(() => (window as any).__inline)).toBeUndefined();
    const src = await page.locator('script[src*="app."]').first().getAttribute('src');
    await page.addScriptTag({ url: src! });
  });
});
