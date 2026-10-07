import { test, expect } from '../fixtures';

// The starter's second page. Its copy is yours to replace, so what's checked is
// the wiring every page shares: it renders as the current nav item, the nav
// reaches it with a boosted swap, and its repository link agrees with the
// structured data.
test.describe('about', () => {
  test('renders as the current nav page', async ({ page }) => {
    const res = await page.goto('/about');
    expect(res?.status()).toBe(200);
    await expect(page.locator('main h1')).toBeVisible();
    await expect(page.locator('.nav-link[aria-current="page"]')).toHaveAttribute('href', '/about');
    await expect(page).toHaveTitle(/^About · /);
  });

  test('the nav reaches it without a full page load', async ({ page }) => {
    await page.goto('/');
    // A boosted link swaps the body; a full load would wipe this.
    await page.evaluate(() => ((window as any).__stayed = true));
    await page.locator('.nav-link[href="/about"]').click();
    await expect(page).toHaveURL(/\/about$/);
    await expect(page.locator('.nav-link[aria-current="page"]')).toHaveAttribute('href', '/about');
    expect(await page.evaluate(() => (window as any).__stayed)).toBe(true);
  });

  test('links the repository the structured data names', async ({ request }) => {
    const html = await (await request.get('/about')).text();
    const ld = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
    const code = ld.find((d) => d['@type'] === 'SoftwareSourceCode');
    expect(code, 'a SoftwareSourceCode block').toBeTruthy();
    expect(html).toContain(`href="${code.codeRepository}"`);
  });
});
