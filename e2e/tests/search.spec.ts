import { test, expect, type Page } from '@playwright/test';

// The global active-search lives in the top bar (aria-label "Search contacts")
// and swaps a results panel into #search-results. Its HTMX trigger is keyup, so
// we type with pressSequentially (fill() wouldn't emit key events).
const box = '#search-results';
const searchbox = (page: Page) => page.getByRole('searchbox', { name: 'Search contacts' });

test.describe('active search', () => {
  test('typing shows highlighted matches', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await expect(page.locator(`${box} mark`).first()).toBeVisible();
    await expect(page.locator(`${box} .search-list li`).first()).toContainText('Grace', {
      ignoreCase: true,
    });
  });

  test('clicking a result lands on /data with the query', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await page.locator(`${box} .search-list li a`).first().click();
    await expect(page).toHaveURL(/\/data\?q=/);
  });

  test('clearing the query collapses the dropdown', async ({ page }) => {
    const input = searchbox(page);
    await page.goto('/');
    await input.pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await input.press('ControlOrMeta+A');
    await input.press('Backspace');
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });

  test('Escape dismisses the dropdown', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });

  test('outside click dismisses the dropdown', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    // Click well inside the page body (away from the sticky header / search).
    await page.getByRole('heading', { name: 'Dashboard', level: 1 }).click();
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });
});
