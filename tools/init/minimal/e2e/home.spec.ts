import { test, expect } from '../fixtures';

// The starter's one page: health, the notes list, and adding a note over HTMX.
// Grow this alongside your app — every endpoint gets a behaviour test here.
test.describe('home', () => {
  test('healthz is 200 ok', async ({ request }) => {
    const res = await request.get('/healthz');
    expect(res.status()).toBe(200);
    expect((await res.text()).trim()).toBe('ok');
  });

  test('home renders the seeded notes', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Your app', level: 1 })).toBeVisible();
    await expect(page.locator('#note-list .note').first()).toBeVisible();
  });

  test('adding a note appends it over HTMX (no reload) and resets the form', async ({ page }) => {
    await page.goto('/');
    const input = page.locator('.add-note input[name="body"]');
    const body = 'a note from the e2e run';
    await input.fill(body);
    await page.getByRole('button', { name: 'Add' }).click();
    // Newest first (afterbegin swap).
    await expect(page.locator('#note-list .note').first()).toContainText(body);
    await expect(input).toHaveValue(''); // data-reset-on-success cleared it
  });

  test('the page links a fingerprinted, immutable CSS URL', async ({ request }) => {
    const html = await (await request.get('/')).text();
    const href = html.match(/\/static\/app\.[0-9a-f]+\.css/)?.[0];
    expect(href).toBeTruthy();
    const res = await request.get(href!);
    expect(res.status()).toBe(200);
    expect(res.headers()['cache-control'] ?? '').toContain('immutable');
  });
});
