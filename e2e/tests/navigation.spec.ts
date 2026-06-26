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

  test('theme toggle flips data-theme and persists across reload', async ({ page }) => {
    await page.goto('/');
    const html = page.locator('html');
    await expect(html).toHaveAttribute('data-theme', 'dark');
    await page.locator('.theme-toggle').click();
    await expect(html).toHaveAttribute('data-theme', 'light');
    await page.reload();
    await expect(html).toHaveAttribute('data-theme', 'light');
  });
});
