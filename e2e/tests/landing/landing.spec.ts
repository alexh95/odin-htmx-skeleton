import { readFileSync } from 'node:fs';
import path from 'node:path';
import { expect, test } from '../../fixtures';

// The starter's own page (PLAN §15.5): the witnesses, the catalog's profiles and features, and
// the init-command builder, whose answer is a fragment.

const T = { tag: '@landing' };
const catalog = JSON.parse(readFileSync(path.join(__dirname, '../../../docs/catalog.json'), 'utf8'));

test.describe('landing', T, () => {
  test('the root shows the catalog: every profile and every feature', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('odin-htmx-starter');
    for (const p of catalog.profiles) await expect(page.locator('tr', { hasText: p.name }).first()).toBeVisible();
    for (const f of catalog.features) await expect(page.locator(`#feature-${f.name}`)).toContainText(f.name);
    await expect(page.locator('.landing-card h3')).toContainText(['lab', 'minimal', 'streams', 'skeleton', 'full']);
    await expect(page.locator('#init-command pre code')).toHaveText('odin run tools/init -- my-app --features home,notes,about');
  });

  test('the builder answers each change with the command and what it pulls in', async ({ page }) => {
    await page.goto('/');
    await page.locator('input[name=name]').fill('acme-crm');
    for (const f of ['home', 'notes', 'about']) await page.locator(`input[name=f-${f}]`).uncheck();
    await page.locator('input[name=f-dashboard]').check();
    await expect(page.locator('#init-command pre code')).toHaveText('odin run tools/init -- acme-crm --features dashboard');
    await expect(page.locator('#init-command')).toContainText('Pulled in: contacts');
    await expect(page.locator('#init-command')).toContainText('on the sqlite store');
    await page.locator('select[name=store]').selectOption('memory');
    await expect(page.locator('#init-command .landing-problems')).toContainText('contacts has no memory store: use --store sqlite');
  });

  test('the builder escapes what it is sent and takes only the catalog\'s names', async ({ request }) => {
    const res = await request.get('/landing/command?name=%3Cb%3Ex&f-notes=1&f-%3Cscript%3E=1&store=%3Ci%3E');
    expect(res.status()).toBe(200);
    const html = await res.text();
    // A refused name never reaches the command offered for copying (M3-05); no --store: not a member.
    expect(html).toContain('odin run tools/init -- &lt;name&gt; --features notes</code>');
    expect(html).not.toContain('<b>');
    expect(html).not.toContain('&lt;b&gt;x');
    expect(html).toContain('the name is lower-case letters');
  });

  test('the lab index moved to /lab, and the nav names both', { tag: '@lab' }, async ({ page }) => {
    await page.goto('/');
    const nav = page.getByRole('navigation', { name: 'Primary' });
    await expect(nav.getByRole('link', { name: 'Starter' })).toHaveAttribute('aria-current', 'page');
    await nav.getByRole('link', { name: 'Lab', exact: true }).click();
    await expect(page).toHaveURL(/\/lab$/);
    await expect(page.locator('.lab-card')).toHaveCount(4);
  });
});
