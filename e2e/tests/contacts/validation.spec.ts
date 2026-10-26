import { test, expect } from '../../fixtures';

// A refused submit is a 422. The ResetOnSuccess behaviour resets its form only
// after a 2xx, so the user's input survives a rejection, and htmx 4 swaps the
// 422 body either into the form's normal target or, through hx-status:422, into
// an error slot. The contacts forms here; the note form's in notes/.
const form = { 'content-type': 'application/x-www-form-urlencoded' };

test.describe('validation errors (422)', { tag: '@contacts' }, () => {
  test.describe('contacts', () => {
    test('a refused /forms submit shows the reason and keeps every field', { tag: '@gallery' }, async ({ page }) => {
      await page.goto('/forms');
      await page.locator('input[name="name"]').fill('Grace Typed');
      // The browser's type=email accepts this; the server's check does not.
      await page.locator('input[name="email"]').fill('grace@localhost');
      await page.locator('textarea[name="notes"]').fill('keep me');

      const submitted = page.waitForResponse((r) => r.url().endsWith('/forms/submit'));
      await page.getByRole('button', { name: 'Create contact' }).click();
      expect((await submitted).status()).toBe(422);

      await expect(page.locator('#form-result .result-err')).toContainText('valid email');
      await expect(page.locator('input[name="name"]')).toHaveValue('Grace Typed');
      await expect(page.locator('input[name="email"]')).toHaveValue('grace@localhost');
      await expect(page.locator('textarea[name="notes"]')).toHaveValue('keep me');
    });

    test('a refused add lands in the form\'s error slot, keeps the input, and a fix clears it', async ({ page }) => {
      await page.goto('/data');
      await page.locator('details.add summary').click();
      const add = page.locator('.add-form');
      const rows = await page.locator('#contact-tbody tr').count();

      await add.locator('input[name="name"]').fill('Slot Tester');
      await add.locator('input[name="email"]').fill('slot@localhost');
      await add.getByRole('button', { name: 'Add' }).click();

      await expect(page.locator('#add-error')).toContainText('valid email');
      await expect(add.locator('input[name="name"]')).toHaveValue('Slot Tester');
      await expect(page.locator('#contact-tbody tr')).toHaveCount(rows); // nothing appended

      await add.locator('input[name="email"]').fill('slot@example.dev');
      await add.getByRole('button', { name: 'Add' }).click();
      await expect(page.locator('#contact-tbody tr', { hasText: 'Slot Tester' })).toBeVisible();
      await expect(page.locator('#add-error')).toBeEmpty();
      await expect(add.locator('input[name="name"]')).toHaveValue('');
    });

    test('a refused drawer edit comes back as typed, with the reason', async ({ page }) => {
      await page.goto('/data');
      const stored = (await page.locator('.c-open .c-name-text strong').first().textContent())!.trim();
      await page.locator('.c-open').first().click();
      await page.locator('.drawer-detail').getByRole('button', { name: 'Edit', exact: true }).click();

      const edit = page.locator('.detail-edit');
      await edit.locator('input[name="name"]').fill('Typed But Refused');
      await edit.locator('input[name="email"]').fill('refused@localhost');
      await edit.getByRole('button', { name: 'Save' }).click();

      await expect(edit.locator('.form-error')).toContainText('valid email');
      await expect(edit.locator('input[name="name"]')).toHaveValue('Typed But Refused');
      await expect(edit.locator('input[name="email"]')).toHaveValue('refused@localhost');
      await expect(page.locator('.drawer-detail .detail-id h2')).toHaveText(stored); // nothing saved
    });

    test('the write endpoints answer 422 to bad input', { tag: '@gallery' }, async ({ request }) => {
      const create = await request.post('/contacts', { headers: form, data: 'name=&email=a@b.co' });
      expect(create.status()).toBe(422);
      expect(await create.text()).toContain('Name is required');

      const submit = await request.post('/forms/submit', { headers: form, data: 'name=Grace&email=grace@localhost' });
      expect(submit.status()).toBe(422);

      // A contact of its own: the worker's store is shared, so a seeded row may be gone.
      const made = await request.post('/contacts', { headers: form, data: 'name=Edit+Target&email=edit.target@example.dev' });
      const id = (await made.text()).match(/id="contact-(\d+)"/)![1];
      const edit = await request.post(`/contacts/${id}`, { headers: form, data: 'name=%20&email=a@b.co' });
      expect(edit.status()).toBe(422);
      expect(await (await request.get(`/contacts/${id}`)).text()).not.toContain('a@b.co');
    });
  });
});
