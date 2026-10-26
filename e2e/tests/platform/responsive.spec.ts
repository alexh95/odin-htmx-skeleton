import { test, expect } from '../../fixtures';

// Regression: the topbar (brand · nav · search · picker) used to force a
// page-wide horizontal scroll on a phone, and the data table clipped its
// columns. Assert no page-level horizontal overflow at a phone viewport.
const PHONE = { width: 390, height: 844 };

// Each page with the feature that serves it.
for (const [path, feature] of [['/', 'platform'], ['/data', 'contacts'], ['/forms', 'gallery'], ['/components', 'gallery'], ['/about', 'about']]) {
  test(`no horizontal overflow at 390px — ${path}`, { tag: ['@platform', `@${feature}`] }, async ({ page }) => {
    await page.setViewportSize(PHONE);
    await page.goto(path);
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
}
