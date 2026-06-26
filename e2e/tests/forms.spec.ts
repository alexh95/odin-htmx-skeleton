import { test, expect } from '@playwright/test';

test.describe('forms & validation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/forms');
  });

  test('email validates inline', async ({ page }) => {
    const email = page.locator('input[name="email"]');
    const msg = page.locator('.field-msg');

    await email.fill('not-an-email');
    await email.blur();
    await expect(msg).toContainText("doesn't look like an email");

    await email.fill('grace@example.dev');
    await email.blur();
    await expect(msg).toContainText('Looks good');
  });

  test('name and email survive email validation (regression)', async ({ page }) => {
    const name = page.locator('input[name="name"]');
    const email = page.locator('input[name="email"]');

    await name.fill('Ada Lovelace');
    await email.fill('ada@example.dev');
    await email.blur();
    await expect(page.locator('.field-msg')).toContainText('Looks good');

    // The bug: the email field's afterRequest bubbled to the form and reset it.
    await expect(name).toHaveValue('Ada Lovelace');
    await expect(email).toHaveValue('ada@example.dev');
  });

  test('range slider paints --fill to match the value (regression)', async ({ page }) => {
    const slider = page.locator('input[name="score"]');
    await slider.evaluate((el: HTMLInputElement) => {
      el.value = '25';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const fill = await slider.evaluate((el) => el.style.getPropertyValue('--fill'));
    expect(fill).toBe('25%');
    await expect(page.locator('.out')).toHaveText('25'); // <output>, not an input

  });

  test('submit creates a contact, raises a toast, and resets the form', async ({ page }) => {
    const name = page.locator('input[name="name"]');
    const unique = `Form Tester ${Date.now()}`;
    await name.fill(unique);
    await page.locator('input[name="email"]').fill('form.tester@example.dev');
    await page.getByRole('button', { name: 'Create contact' }).click();

    await expect(page.locator('#form-result .result-ok')).toContainText('Contact created');
    await expect(page.locator('#form-result')).toContainText(unique);
    await expect(page.locator('#toasts .toast')).toBeVisible();
    // Form resets only on its own successful submit.
    await expect(name).toHaveValue('');
  });
});
