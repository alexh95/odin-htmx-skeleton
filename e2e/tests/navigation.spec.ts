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

  test('primary nav is boosted: swaps in place (no full reload) and updates the title', async ({ page }) => {
    await page.goto('/');
    // Tag the live window. A full document navigation discards it; a boosted
    // (AJAX + pushState) swap keeps the same document, so it survives the click.
    await page.evaluate(() => { (window as Window & { __alive?: number }).__alive = 1; });

    await page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'Forms' }).click();
    await expect(page).toHaveURL('/forms');
    await expect(page.getByRole('heading', { name: 'Forms & validation', level: 1 })).toBeVisible();
    await expect(page).toHaveTitle(/^Forms · /); // title updated from the response's <title>
    expect(await page.evaluate(() => (window as Window & { __alive?: number }).__alive)).toBe(1);
  });

  test('toasts still auto-retire after a boosted navigation (swap-safe observer)', async ({ page }) => {
    await page.goto('/');
    // Boost over to the components page, then raise a toast on the swapped-in body.
    await page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'Components' }).click();
    await expect(page).toHaveURL('/components');
    await page.getByRole('button', { name: 'Success toast' }).click();
    const toast = page.locator('#toasts .toast');
    await expect(toast).toBeVisible();
    // The retire observer must have survived the body swap (it watches document.body).
    await expect(toast).toHaveCount(0, { timeout: 7000 });
  });

  test('a toast survives a boosted navigation (hx-preserve, not wiped mid-flight)', async ({ page }) => {
    await page.goto('/components');
    await page.getByRole('button', { name: 'Success toast' }).click();
    const toast = page.locator('#toasts .toast');
    await expect(toast).toBeVisible();
    // Navigate away via the boosted nav before the toast auto-retires; #toasts is
    // hx-preserve'd, so the live toast rides through the body swap.
    await page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'Forms' }).click();
    await expect(page).toHaveURL('/forms');
    await expect(toast).toBeVisible();
  });

  test('about page links to the source on GitHub', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'About' }).click();
    await expect(page).toHaveURL('/about');
    await expect(page.getByRole('heading', { name: 'About this project', level: 1 })).toBeVisible();
    const gh = page.getByRole('link', { name: /View on GitHub/ });
    await expect(gh).toHaveAttribute('href', /^https:\/\/github\.com\//);
    await expect(gh).toHaveAttribute('target', '_blank');
    await expect(gh).toHaveAttribute('rel', /noopener/);
  });

  test('ping button swaps in a live reading', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Ping server' }).click();
    await expect(page.locator('#ping-slot .ping-ok')).toContainText('200 OK');
  });

  test('dashboard stat card drills into the filtered data view', async ({ page }) => {
    await page.goto('/');
    await page.locator('.stat-link', { hasText: 'Active' }).click();
    await expect(page).toHaveURL(/\/data\?status=Active/);
    const badges = page.locator('#contact-tbody tr td .badge');
    await expect(badges.first()).toContainText('Active');
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

  test('components showroom swatch jumps to a style + scheme', async ({ page }) => {
    await page.goto('/components');
    const html = page.locator('html');
    const swatch = page.locator('.showroom-swatches .swatch[data-sw-style="terminal"][data-sw-scheme="green"]');
    await swatch.click();
    await expect(html).toHaveAttribute('data-style', 'terminal');
    await expect(html).toHaveAttribute('data-scheme', 'green');
    await expect(swatch).toHaveAttribute('aria-pressed', 'true');
    await page.reload();
    await expect(html).toHaveAttribute('data-style', 'terminal');
    await expect(html).toHaveAttribute('data-scheme', 'green');
  });
});
