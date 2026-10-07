import { test, expect } from '../fixtures';

// Avatar initials are user input like the rest of a name. They used to be cut
// byte by byte and written raw, so a name starting with '<' broke the DOM and
// every non-ASCII initial came out as half a character. Contacts are the demo's;
// the starter has no avatars, so this skips there.
const form = { 'content-type': 'application/x-www-form-urlencoded' };

test.describe('escaping', () => {
  test.beforeEach(async ({ request }) => {
    test.skip((await request.get('/data')).status() !== 200, 'demo contacts');
  });

  test('avatar initials are escaped, not markup', async ({ page, request }) => {
    const name = '<img src=x id=avatar-probe onerror=alert(1)>';
    const res = await request.post('/contacts', { headers: form, data: `name=${encodeURIComponent(name)}&email=probe@example.dev` });
    expect(res.status()).toBe(200);

    await page.goto('/data?q=avatar-probe');
    const row = page.locator('#contact-tbody tr', { hasText: 'avatar-probe' });
    await expect(row.locator('.avatar')).toHaveText('<s');
    await expect(page.locator('#avatar-probe')).toHaveCount(0);
  });

  test('a non-ASCII initial is a whole character', async ({ page, request }) => {
    const res = await request.post('/contacts', { headers: form, data: `name=${encodeURIComponent('Émile Zola')}&email=emile@example.dev` });
    expect(res.status()).toBe(200);

    await page.goto('/data?q=Zola');
    const row = page.locator('#contact-tbody tr', { hasText: 'Zola' });
    await expect(row.locator('.avatar')).toHaveText('ÉZ');
  });
});
