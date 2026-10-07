import { test, expect } from '../fixtures';

// The table pages in SQL and the pager shows a window, not a button per page
// (2,864 of them at 20k rows). The JSON API is capped. Contacts are the demo's;
// the starter skips this.
const form = { 'content-type': 'application/x-www-form-urlencoded' };

test.describe('paging', () => {
  test.beforeEach(async ({ request }) => {
    test.skip((await request.get('/data')).status() !== 200, 'demo contacts');
  });

  test('a long result shows a windowed pager that still reaches every page', async ({ page, request }) => {
    const tag = `Pager${Date.now()}`;
    for (let i = 0; i < 80; i++) {
      // Zero-padded, so name order is creation order.
      const res = await request.post('/contacts', { headers: form, data: `name=${tag}+${String(i).padStart(2, '0')}&email=p${i}@example.dev` });
      expect(res.status()).toBe(200);
    }

    await page.goto(`/data?q=${tag}`);
    const pager = page.locator('.pager');
    await expect(page.locator('.table-meta')).toContainText('80 contacts');
    // 80 rows / 7 a page = 12 pages: 1 2 3 … 12, not twelve buttons.
    await expect(pager.locator('.page:not([disabled])', { hasText: /^\d+$/ })).toHaveText(['1', '2', '3', '12']);
    await expect(pager.locator('.page-gap')).toHaveCount(1);

    await pager.getByRole('button', { name: '12', exact: true }).click();
    await expect(pager.locator('.page.is-current')).toHaveText('12');
    await expect(page.locator('#contact-tbody tr')).toHaveCount(80 - 11 * 7);
    await expect(page.locator('#contact-tbody tr').last()).toContainText(`${tag} 79`);

    await pager.getByRole('button', { name: '10', exact: true }).click();
    await expect(pager.locator('.page:not([disabled])', { hasText: /^\d+$/ })).toHaveText(['1', '8', '9', '10', '11', '12']);
    await expect(page.locator('#contact-tbody tr').first()).toContainText(`${tag} 63`);
  });

  test('the JSON API returns at most 100 rows', async ({ request }) => {
    for (let i = 0; i < 110; i++) {
      await request.post('/contacts', { headers: form, data: `name=ApiCap+${i}&email=cap${i}@example.dev` });
    }
    expect(await (await request.get('/api/search?q=ApiCap')).json()).toHaveLength(100);
  });
});
