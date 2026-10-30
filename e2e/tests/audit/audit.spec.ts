import { readFileSync } from 'node:fs';
import { test, expect } from '../../fixtures';
import { startServer, stopServer, type Server } from '../../helpers/server';
import { ADMIN, signIn } from '../../helpers/accounts';

// The audit log (PLAN §17.7): accounts' sign-ins land in it, /admin/audit filters it by actor
// and action prefix, scrolls it a page at a time and exports the filter as CSV. Admins only,
// from the LAN. Each test counts entries, so each runs on a server of its own.
const T = { tag: ['@audit', '@accounts-accounts'] };

async function own(env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, `http://127.0.0.1:${s.port}`);
  } finally {
    await stopServer(s);
  }
}

const form = (password = ADMIN.password) => ({ form: { username: ADMIN.username, password }, maxRedirects: 0 });

// An entry is queued as the sign-in answers, so it lands a moment after: reload until the log holds `n`.
async function holds(page: import('@playwright/test').Page, n: number) {
  await expect.poll(async () => {
    const lines = (await (await page.context().request.get('/admin/audit/export')).text()).trim().split('\r\n');
    return lines.length - 1;
  }).toBe(n);
  await page.reload();
}

test.describe('audit', T, () => {
  test('a guest is sent to sign in, and off the LAN the log is not there', async ({ request }) => {
    const guest = await request.get('/admin/audit', { maxRedirects: 0 });
    expect(guest.status()).toBe(302);
    expect(guest.headers()['location']).toBe('/login');
    await own({ LAN_CIDRS: '10.0.0.0/8' }, async (_, base) => {
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      expect((await request.get(`${base}/admin/audit`, { maxRedirects: 0 })).status()).toBe(404);
    });
  });

  test('sign-ins and wrong passwords are logged, and the filters find them', async ({ browser, request }) => {
    await own({}, async (_, base) => {
      expect((await request.post(`${base}/login`, form('wrong-wrong-wrong'))).status()).toBe(422);
      for (let i = 0; i < 2; i++) expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      const { context, page } = await signIn(browser, base, '/admin/audit');
      await holds(page, 4);
      await expect(page.locator('.audit-row')).toHaveCount(4);
      await expect(page.locator('.audit-row').first()).toContainText('accounts.sign_in');
      await expect(page.locator('.audit-row').last()).toContainText('accounts.sign_in_failed');

      await page.locator('input[name="action"]').fill('accounts.sign_in_failed');
      await page.getByRole('button', { name: 'Filter' }).click();
      await expect(page).toHaveURL(/action=accounts\.sign_in_failed/);
      await expect(page.locator('.audit-row')).toHaveCount(1);
      await expect(page.locator('.audit-row')).toContainText('user #1');

      await page.goto(`/admin/audit?actor=${ADMIN.username.toUpperCase()}`); // any case
      await expect(page.locator('.audit-row')).toHaveCount(3);
      await page.goto('/admin/audit?actor=nobody');
      await expect(page.locator('.audit-empty')).toBeVisible();
      await context.close();
    });
  });

  test('the log scrolls a page at a time, and exports the filter as CSV', async ({ browser, request }) => {
    await own({}, async (_, base) => {
      for (let i = 0; i < 60; i++) expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      const { context, page } = await signIn(browser, base, '/admin/audit');
      await holds(page, 61);
      await expect(page.locator('.audit-row')).toHaveCount(50);
      await page.locator('.audit-more').scrollIntoViewIfNeeded();
      await expect(page.locator('.audit-row')).toHaveCount(61);
      await expect(page.locator('.audit-more')).toHaveCount(0);
      const ids = await page.locator('.audit-row').evaluateAll((rows) => rows.map((r) => Number(r.id.slice(6))));
      expect(ids).toEqual([...ids].sort((a, b) => b - a)); // newest first, none twice

      const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Export CSV' }).click()]);
      expect(download.suggestedFilename()).toBe('audit.csv');
      const lines = readFileSync((await download.path())!, 'utf8').trim().split('\r\n');
      expect(lines[0]).toBe('id,at,actor_id,actor,action,target_kind,target_id,reason,client,meta');
      expect(lines.length).toBe(62);
      expect(lines[1]).toMatch(/^61,\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,1,admin,accounts\.sign_in,session,0,,[0-9a-f]{16},$/);
      await context.close();
    });
  });
});
