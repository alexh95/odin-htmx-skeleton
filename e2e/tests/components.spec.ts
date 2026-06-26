import { test, expect } from '@playwright/test';

test.describe('components gallery', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/components');
  });

  test('tabs swap the panel and move the selected state', async ({ page }) => {
    const activity = page.getByRole('tab', { name: 'Activity' });
    await activity.click();
    await expect(page.locator('#tabpanel')).toContainText('Recent activity');
    await expect(activity).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByRole('tab', { name: 'Overview' })).toHaveAttribute(
      'aria-selected',
      'false',
    );
  });

  test('accordion expands a closed item', async ({ page }) => {
    const second = page.locator('details.acc').nth(1);
    await expect(second).not.toHaveAttribute('open', /.*/);
    await second.locator('summary').click();
    await expect(second).toHaveAttribute('open', /.*/);
  });

  test('toast appears then auto-dismisses', async ({ page }) => {
    await page.getByRole('button', { name: 'Success toast' }).click();
    const toast = page.locator('#toasts .toast');
    await expect(toast).toBeVisible();
    // app.js retires each toast ~3.6s after it lands.
    await expect(toast).toHaveCount(0, { timeout: 8000 });
  });

  test.describe('modal dialog', () => {
    test('outside (backdrop) click keeps it open with its field intact', async ({ page }) => {
      await page.getByRole('button', { name: 'Open dialog' }).click();
      const modal = page.locator('.modal');
      await expect(modal).toBeVisible();

      // Regression: a stray backdrop click must NOT discard a half-typed field.
      await modal.getByRole('textbox').fill('keep@me.dev');
      await page.locator('.backdrop').click({ position: { x: 6, y: 6 } });
      await expect(modal).toBeVisible();
      await expect(modal.getByRole('textbox')).toHaveValue('keep@me.dev');
    });

    test('× closes it', async ({ page }) => {
      await page.getByRole('button', { name: 'Open dialog' }).click();
      await expect(page.locator('.modal')).toBeVisible();
      await page.locator('.modal').getByRole('button', { name: 'Close' }).click();
      await expect(page.locator('.modal')).toHaveCount(0);
    });
  });

  test('drawer opens and the backdrop click closes it', async ({ page }) => {
    await page.getByRole('button', { name: 'Open drawer' }).click();
    await expect(page.locator('.drawer')).toBeVisible();
    await page.locator('.backdrop').click({ position: { x: 6, y: 6 } });
    await expect(page.locator('.drawer')).toHaveCount(0);
  });
});
