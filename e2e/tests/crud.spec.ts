import { test, expect } from '../fixtures';

test.describe('data table + CRUD', () => {
  test('create, cycle status, then delete a row', async ({ page }) => {
    page.on('dialog', (d) => d.accept()); // delete uses hx-confirm

    await page.goto('/data');
    await page.locator('details.add summary').click();

    const unique = `E2E ${Date.now()}`;
    await page.locator('.add-form input[name="name"]').fill(unique);
    await page.locator('.add-form input[name="email"]').fill('e2e.row@example.dev');
    await page.locator('.add-form').getByRole('button', { name: 'Add' }).click();

    const row = page.locator('#contact-tbody tr', { hasText: unique });
    await expect(row).toBeVisible();
    await expect(page.locator('#toasts .toast')).toBeVisible();

    // New contacts land as Invited; cycling advances the status badge.
    await expect(row.locator('.badge')).toContainText('Invited');
    await row.getByRole('button', { name: 'Cycle status' }).click();
    await expect(row.locator('.badge')).toContainText('Disabled');

    await row.getByRole('button', { name: 'Delete' }).click();
    await expect(row).toHaveCount(0);
  });

  test('deleting a missing id is a 404 and changes nothing', async ({ request }) => {
    const res = await request.delete('/contacts/999999');
    expect(res.status()).toBe(404);
  });

  test('sort header toggles direction', async ({ page }) => {
    await page.goto('/data');
    const nameSort = () => page.getByRole('button', { name: 'Name', exact: true });

    // Default sort is name asc; clicking cycles asc -> desc -> asc.
    // toHaveAttribute auto-waits for each htmx table swap to land (a raw
    // getAttribute read can race the swap).
    await expect(nameSort()).toHaveAttribute('data-dir', 'asc');
    await nameSort().click();
    await expect(nameSort()).toHaveAttribute('data-dir', 'desc');
    await nameSort().click();
    await expect(nameSort()).toHaveAttribute('data-dir', 'asc');
  });

  test('pagination swaps the table region', async ({ page }) => {
    await page.goto('/data');
    const pager = page.locator('.pager');
    await expect(pager).toBeVisible();
    await pager.getByRole('button', { name: '2', exact: true }).click();
    await expect(page.locator('.page.is-current')).toHaveText('2');
  });

  test('filter narrows the rows without a full reload', async ({ page }) => {
    await page.goto('/data');
    await page.locator('.filter input[name="q"]').pressSequentially('grace');
    await expect(page.locator('#contact-tbody tr', { hasText: 'Grace' })).toBeVisible();
    await expect(page.locator('#contact-tbody tr')).not.toHaveCount(0);
  });

  test('clicking a contact opens the detail drawer with activity + related', async ({ page }) => {
    await page.goto('/data');
    const name = await page.locator('.c-open .c-name-text strong').first().textContent();
    await page.locator('.c-open').first().click();

    const drawer = page.locator('.drawer-detail');
    await expect(drawer).toBeVisible();
    await expect(drawer.locator('.detail-id h2')).toHaveText(name!.trim());
    await expect(drawer.getByRole('heading', { name: 'Activity' })).toBeVisible();
    await expect(drawer.locator('.timeline li')).toHaveCount(5);

    // a related contact drills into its own detail
    const related = drawer.locator('.related-item').first();
    if (await related.count()) {
      const relName = await related.locator('strong').textContent();
      await related.click();
      await expect(page.locator('.drawer-detail .detail-id h2')).toHaveText(relName!.trim());
    }

    // close empties the overlay
    await page.locator('.detail-close').click();
    await expect(page.locator('.drawer-detail')).toHaveCount(0);
  });
});
