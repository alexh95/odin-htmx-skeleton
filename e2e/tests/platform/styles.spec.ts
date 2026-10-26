import { test, expect } from '../../fixtures';

// Layout defaults a fork inherits the moment it adds markup: a bare checkbox
// keeps its natural size, a range input its own track. Every profile (the note
// list's layout is in notes/notes.spec.ts).
test.describe('style defaults', { tag: '@platform' }, () => {
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
});
