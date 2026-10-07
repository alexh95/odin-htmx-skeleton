import { test, expect } from '../fixtures';

// Layout defaults a fork inherits the moment it adds markup: a bare checkbox
// keeps its natural size, and the starter's note list sits flush with its input,
// newest note first. Shared by the demo and the --minimal starter.
test.describe('style defaults', () => {
  test('a bare checkbox or radio is not stretched to the full width', async ({ page }) => {
    await page.goto('/');
    const widths = await page.evaluate(() => {
      const main = document.querySelector('main')!;
      const probe = (type: string) => {
        const el = document.createElement('input');
        el.type = type;
        main.prepend(el);
        const w = el.getBoundingClientRect().width;
        el.remove();
        return w;
      };
      return { checkbox: probe('checkbox'), radio: probe('radio'), text: probe('text') };
    });
    expect(widths.checkbox).toBeLessThan(40);
    expect(widths.radio).toBeLessThan(40);
    expect(widths.text).toBeGreaterThan(200); // text inputs still fill their field
  });

  test('a range input keeps its own track styling', async ({ page }) => {
    await page.goto('/');
    const padding = await page.evaluate(() => {
      const el = document.createElement('input');
      el.type = 'range';
      document.querySelector('main')!.prepend(el);
      return getComputedStyle(el).paddingLeft;
    });
    expect(padding).toBe('0px');
  });

  test('the starter lists notes flush with the form, newest first', async ({ page, request }) => {
    test.skip((await request.get('/data')).status() === 200, 'starter page');
    await page.goto('/');
    const list = page.locator('#note-list');
    expect(await list.evaluate((el) => getComputedStyle(el).paddingLeft)).toBe('0px');
    // Among the seeded notes the welcome one is the newest, so it comes first.
    // (Other specs may have added newer notes above them on this worker's store.)
    const notes = await list.locator('.note-body').allTextContents();
    const at = (s: string) => notes.findIndex((n) => n.includes(s));
    expect(at('Welcome')).toBeGreaterThanOrEqual(0);
    expect(at('Welcome')).toBeLessThan(at('Notes live in SQLite'));
  });
});
