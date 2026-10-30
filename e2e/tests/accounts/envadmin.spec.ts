import { test, expect } from '../../fixtures';
import { ADMIN } from '../../helpers/accounts';

// The envadmin identity (PLAN §17.1): the one admin from ACCOUNTS_ADMIN_HASH signs in with the
// password alone and keeps a signed cookie; a changed cookie is a Guest; sign-out forgets it.
// No hosted profile builds it: the nightly runs this on a generated --identity envadmin project.
const T = { tag: ['@accounts-envadmin'] };

test.describe('envadmin', T, () => {
  test('the admin signs in with the password, and is the admin until signing out', async ({ page, context }) => {
    await page.goto('/login');
    await page.locator('#password').fill('not-the-password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.locator('#login-error')).toContainText("isn't the password");

    await page.goto('/login?next=/step-up');
    await page.locator('#password').fill(ADMIN.password);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL((u) => u.pathname === '/step-up'); // an Account_Self page: the admin's
    const [cookie] = (await context.cookies()).filter((c) => c.name === 'admin');
    expect(cookie.httpOnly).toBe(true);
    await page.goto('/login');
    await expect(page.getByRole('heading', { name: `Signed in as ${ADMIN.username}` })).toBeVisible();

    // The MAC's first character changed: a guest, and the cookie cleared.
    const mac = cookie.value.slice(cookie.value.lastIndexOf('.') + 1);
    await context.addCookies([{ ...cookie, value: cookie.value.slice(0, -mac.length) + (mac[0] === 'A' ? 'B' : 'A') + mac.slice(1) }]);
    expect((await page.request.get('/step-up', { maxRedirects: 0 })).status()).toBe(302);
    await context.addCookies([cookie]);
    await page.goto('/login');
    await page.getByRole('button', { name: 'Sign out' }).click();
    await page.waitForURL((u) => u.pathname === '/');
    expect((await context.cookies()).filter((c) => c.name === 'admin')).toEqual([]);
  });
});
