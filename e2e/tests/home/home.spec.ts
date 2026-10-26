import { test, expect } from '../../fixtures';

// The minimal profile's root: the profile's copy over one card per feature that
// offers one. Health and the fingerprinted CSS are platform/assets.spec.ts's.
test.describe('home', { tag: '@home' }, () => {
  test('home renders its heading and the notes card', { tag: '@notes' }, async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expect(page.locator('#note-list .note').first()).toBeVisible();
  });
});
