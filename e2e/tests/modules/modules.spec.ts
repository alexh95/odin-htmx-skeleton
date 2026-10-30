import { test, expect } from '../../fixtures';
import { startServer, stopServer } from '../../helpers/server';
import { ADMIN, ADMIN_HASH, signIn } from '../../helpers/accounts';

// /admin/modules (PLAN §15.4): what the build is, read-only, for an admin on the LAN; a secret
// is shown only as set.
const T = { tag: ['@modules', '@accounts-accounts'] };

test.describe('modules', T, () => {
  test('the admin sees the build, its routes, its settings and its migrations', async ({ browser, baseURL }) => {
    const { context, page } = await signIn(browser, baseURL!, '/admin/modules');
    await expect(page.locator('#modules-build')).toContainText('full');
    await expect(page.locator('#modules-build')).toContainText('identity');
    await expect(page.locator('#modules-build')).toContainText('modules');
    await expect(page.locator('.module-route', { hasText: 'GET /admin/modules' })).toContainText('Admin_Modules');
    await expect(page.locator('.module-route', { hasText: 'GET /admin/modules' })).toContainText('Lan_Only');
    const hash = page.locator('.module-env', { hasText: 'ACCOUNTS_ADMIN_HASH' });
    await expect(hash).toContainText('set');
    expect(await page.content()).not.toContain(ADMIN_HASH.slice(30)); // never the secret
    await expect(page.locator('.module-migration', { hasText: '0003_reset_codes.sql' })).toContainText('accounts');
    await expect(page.locator('.module-migration', { hasText: '0001_audit.sql' })).toContainText('audit');
    await expect(page.locator('#modules-health')).toContainText('ok');
    await context.close();
  });

  test('a guest is sent to sign in, and off the LAN the page is not there', async ({ request }) => {
    const guest = await request.get('/admin/modules', { maxRedirects: 0 });
    expect(guest.status()).toBe(302);
    const s = await startServer(test.info().config, { LAN_CIDRS: '10.0.0.0/8' });
    try {
      const base = `http://127.0.0.1:${s.port}`;
      expect((await request.post(`${base}/login`, { form: { username: ADMIN.username, password: ADMIN.password }, maxRedirects: 0 })).status()).toBe(303);
      expect((await request.get(`${base}/admin/modules`, { maxRedirects: 0 })).status()).toBe(404);
    } finally {
      await stopServer(s);
    }
  });
});
