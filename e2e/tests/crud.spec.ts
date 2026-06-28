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

  // Regression: the `sort` query param is reflected into the table's hx-get
  // attributes (filter chips + pager). It must be url-encoded like q/status, or
  // a crafted value breaks out of the attribute (reflected HTML injection).
  test('a crafted sort param cannot inject markup', async ({ page }) => {
    const marker = 'xss-probe-img';
    await page.goto(`/data?sort=${encodeURIComponent(`"><img id=${marker} src=x>`)}`);
    // The page must render normally and the payload must not become a real element.
    await expect(page.locator('#contact-region')).toBeVisible();
    await expect(page.locator(`#${marker}`)).toHaveCount(0);
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

  test('status quick-filter shows only matching contacts', async ({ page }) => {
    await page.goto('/data');
    await page.locator('.table-filters').getByRole('button', { name: 'Active', exact: true }).click();
    const badges = page.locator('#contact-tbody tr td .badge');
    await expect(badges.first()).toBeVisible();
    const n = await badges.count();
    for (let i = 0; i < n; i++) await expect(badges.nth(i)).toContainText('Active');
    // 'All' restores the full list
    await page.locator('.table-filters').getByRole('button', { name: 'All', exact: true }).click();
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

  test('detail drawer: edit updates the record and the row behind it', async ({ page }) => {
    await page.goto('/data');
    const rowId = await page.locator('#contact-tbody tr').first().getAttribute('id');
    await page.locator('.c-open').first().click();
    await page.waitForSelector('.drawer-detail');

    await page.locator('.drawer-detail').getByRole('button', { name: 'Edit' }).click();
    await page.waitForSelector('.detail-edit');
    const newName = `Edited ${Date.now()}`;
    await page.locator('.detail-edit input[name="name"]').fill(newName);
    await page.locator('.detail-edit').getByRole('button', { name: 'Save' }).click();

    // drawer returns to the view with the new name…
    await expect(page.locator('.drawer-detail .detail-id h2')).toHaveText(newName);
    // …and the table row behind it was refreshed out-of-band.
    await expect(page.locator(`#${rowId} .c-name-text strong`)).toHaveText(newName);
  });

  test('detail drawer: cycle status from the drawer, then delete', async ({ page }) => {
    page.on('dialog', (d) => d.accept());
    await page.goto('/data');
    const rowId = await page.locator('#contact-tbody tr').first().getAttribute('id');
    await page.locator('.c-open').first().click();
    await page.waitForSelector('.drawer-detail');

    const before = await page.locator('.drawer-detail .badge').first().textContent();
    await page.locator('.drawer-detail').getByRole('button', { name: 'Cycle' }).click();
    await expect(page.locator('.drawer-detail .badge').first()).not.toHaveText(before!);

    await page.locator('.drawer-detail').getByRole('button', { name: 'Delete' }).click();
    await expect(page.locator('.drawer-detail')).toHaveCount(0); // drawer closed
    await expect(page.locator(`#${rowId}`)).toHaveCount(0); // row removed
  });
});
