import { test, expect } from '../../fixtures';
import { startServer, stopServer, get } from '../../helpers/server';
import { leave, member, uid } from '../../helpers/members';

// The nick identity (PLAN §17.1; ANSWERS round 9): a nickname at /login, kept in a
// signed cookie, makes a LAN client a member; off the LAN there is no form, and
// chat says it is open on the LAN.
const T = { tag: ['@accounts-nick', '@chat'] };

test.describe('nick', T, () => {
  test('a visitor picks a nickname and lands where they were going, a member', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!, 'Ann Lee');
    await ann.page.goto('/login?next=/chat');
    await expect(ann.page.getByRole('heading', { name: 'You are Ann Lee' })).toBeVisible();
    await ann.page.locator('#nick').fill('Ann L.');
    await ann.page.getByRole('button', { name: 'Use this nickname' }).click();
    await ann.page.waitForURL('**/chat');
    await expect(ann.page.locator('.chat-rooms')).toContainText('Lobby');
    expect(ann.errors).toEqual([]);
    await leave(ann);
  });

  test('a refused nickname stays as typed, with the reason', async ({ page }) => {
    await page.goto('/login');
    await page.locator('#nick').fill('<b>no</b>');
    await page.getByRole('button', { name: 'Use this nickname' }).click();
    await expect(page.locator('#nick-error')).toContainText('letters, digits');
    await expect(page.locator('#nick')).toHaveValue('<b>no</b>');
    await expect(page).toHaveURL(/\/login$/);
  });

  test('a guest is sent to /login from a room, and /chat tells them to pick a nickname', async ({ page }) => {
    await page.goto('/chat');
    await expect(page.locator('.chat-lan')).toContainText('Pick a nickname');
    await page.goto('/chat/r/lobby');
    await expect(page).toHaveURL(/\/login/);
  });

  test('a tampered cookie is a guest, and signing out forgets the nickname', async ({ browser, baseURL }) => {
    const bob = await member(browser, baseURL!, uid('bob'));
    const [cookie] = (await bob.context.cookies()).filter((c) => c.name === 'nick');
    // The header itself: WebKit's cookie jar reports every cookie's SameSite as None.
    const set = (await bob.context.request.post('/login', { form: { nick: bob.name }, maxRedirects: 0 })).headers()['set-cookie'];
    expect(set).toMatch(/HttpOnly/);
    expect(set).toMatch(/SameSite=Lax/);

    // The MAC's first character changed (its last only carries padding bits).
    const parts = cookie.value.split('.');
    parts[3] = (parts[3][0] === 'A' ? 'B' : 'A') + parts[3].slice(1);
    await bob.context.addCookies([{ ...cookie, value: parts.join('.') }]);
    await bob.page.goto('/chat');
    await expect(bob.page.locator('.chat-lan')).toBeVisible();

    await bob.context.addCookies([cookie]);
    await bob.page.goto('/login');
    await bob.page.getByRole('button', { name: 'Sign out' }).click();
    await bob.page.waitForURL((u) => u.pathname === '/');
    expect((await bob.context.cookies()).filter((c) => c.name === 'nick')).toEqual([]);
    await leave(bob);
  });

  test('off the LAN there is no nickname to pick', async ({ browser }) => {
    const config = test.info().config;
    const s = await startServer(config, { LAN_CIDRS: '10.0.0.0/8' });
    try {
      const login = await get(s.port, '/login');
      expect(login.body).toContain('Chat is open on the LAN');
      expect(login.body).not.toContain('id="nick"');
      const context = await browser.newContext({ baseURL: `http://127.0.0.1:${s.port}` });
      const res = await context.request.post('/login', { form: { nick: 'eve' } });
      expect(res.status()).toBe(403);
      await context.close();
    } finally {
      await stopServer(s);
    }
  });
});
