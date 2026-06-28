import { test, expect } from '../fixtures';

test.describe('navigation', () => {
  test('dashboard renders with stat cards', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Dashboard', level: 1 })).toBeVisible();
    await expect(page.locator('.stat')).toHaveCount(4);
    await expect(page.getByRole('button', { name: 'Ping server' })).toBeVisible();
  });

  for (const { label, path, heading } of [
    { label: 'Components', path: '/components', heading: 'Components' },
    { label: 'Forms', path: '/forms', heading: 'Forms & validation' },
    { label: 'Data & CRUD', path: '/data', heading: 'Data & CRUD' },
  ]) {
    test(`nav link "${label}" routes and marks itself current`, async ({ page }) => {
      await page.goto('/');
      // Scope to the primary nav — dashboard tiles reuse the same link text.
      await page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: label }).click();
      await expect(page).toHaveURL(path);
      await expect(page.getByRole('heading', { name: heading, level: 1 })).toBeVisible();
      const active = page.locator(`.nav-link[href="${path}"]`);
      await expect(active).toHaveAttribute('aria-current', 'page');
    });
  }

  test('ping button swaps in a live reading', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Ping server' }).click();
    await expect(page.locator('#ping-slot .ping-ok')).toContainText('200 OK');
  });

  test('theme picker switches scheme and persists across reload', async ({ page }) => {
    await page.goto('/');
    const html = page.locator('html');
    // SSR default is Modern · Midnight.
    await expect(html).toHaveAttribute('data-style', 'modern');
    await expect(html).toHaveAttribute('data-scheme', 'midnight');

    // Open the picker and choose the Daylight scheme.
    await page.locator('.picker > summary').click();
    await page.locator('.swatch[data-pick-scheme="daylight"]').click();
    await expect(html).toHaveAttribute('data-scheme', 'daylight');
    // Active swatch is marked.
    await expect(page.locator('.swatch[data-pick-scheme="daylight"]')).toHaveAttribute('aria-pressed', 'true');

    // Persists across reload (restored by the pre-paint script, no flash).
    await page.reload();
    await expect(html).toHaveAttribute('data-scheme', 'daylight');
    await expect(html).toHaveAttribute('data-style', 'modern');
  });

  test('theme picker switches style and reveals that style\'s schemes', async ({ page }) => {
    await page.goto('/');
    const html = page.locator('html');
    await page.locator('.picker > summary').click();

    // Switch to a different style; the scheme falls back to that style's first.
    await page.locator('.chip[data-pick-style="skeuo"]').click();
    await expect(html).toHaveAttribute('data-style', 'skeuo');
    await expect(html).toHaveAttribute('data-scheme', 'aqua');

    // Its swatch row is now revealed and selectable; modern's is hidden.
    await expect(page.locator('.picker-schemes[data-for="skeuo"]')).toBeVisible();
    await expect(page.locator('.picker-schemes[data-for="modern"]')).toBeHidden();
    await page.locator('.swatch[data-pick-scheme="graphite"]').click();
    await expect(html).toHaveAttribute('data-scheme', 'graphite');

    await page.reload();
    await expect(html).toHaveAttribute('data-style', 'skeuo');
    await expect(html).toHaveAttribute('data-scheme', 'graphite');
  });
});
