import { test, expect } from '../../fixtures';
import { signIn } from '../../helpers/accounts';
import type { Page } from '@playwright/test';

// /admin/dbview (PLAN §15.4, M5): an admin's read-only SQL. One statement that only reads, no
// ATTACH, 2 s at most, 200 rows at most, every query audited. That it never takes the writer's
// lock is the dbview drill's.
const T = { tag: ['@dbview', '@accounts-accounts'] };

async function run(page: Page, sql: string) {
  await page.locator('#dbview-sql').fill(sql);
  await page.getByRole('button', { name: 'Run' }).click();
}

test.describe('dbview', T, () => {
  test('a read answers as a table; a write, two statements and an attach are refused', async ({ browser, baseURL }) => {
    const admin = await signIn(browser, baseURL!, '/admin/dbview');
    try {
      const result = admin.page.locator('#dbview-result');
      await admin.page.getByRole('button', { name: 'Run' }).click(); // the sample: the schema
      await expect(result.locator('.dbview-table th')).toHaveText(['name', 'type']);
      await expect(result.locator('.dbview-table')).toContainText('audit_log');
      await expect(result.locator('.dbview-meta')).toContainText(/\d+ rows in [\d.]+ ms/);

      // Only reads: a write, a transaction or savepoint (which would keep the reader's snapshot and
      // pin the WAL, M5-01), a PRAGMA (applied while preparing) and an attach are all refused.
      for (const sql of ['DELETE FROM audit_log', 'BEGIN', 'SAVEPOINT a', 'PRAGMA cache_size = 1', 'PRAGMA reverse_unordered_selects = 1', "ATTACH 'elsewhere.db' AS x"]) {
        await run(admin.page, sql);
        await expect(result.locator('.dbview-problem'), sql).toContainText('only reads');
      }
      await run(admin.page, "SELECT 1; SELECT 2");
      await expect(result.locator('.dbview-problem')).toHaveText('one statement at a time');
      await run(admin.page, 'SELECT length(randomblob(2000000))');
      await expect(result.locator('.dbview-problem')).toContainText('too big'); // 1 MB a value at most (M5-08)
      await run(admin.page, "SELECT 1;  ");
      await expect(result.locator('.dbview-table td')).toHaveText('1'); // a trailing semicolon is one statement

      await run(admin.page, 'WITH RECURSIVE r(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM r LIMIT 300) SELECT x, NULL AS empty, randomblob(4) AS b FROM r');
      await expect(result.locator('.dbview-meta')).toContainText('200 rows, and more not shown');
      await expect(result.locator('.dbview-table tbody tr').first().locator('td')).toHaveText(['1', 'NULL', '<4 bytes>']);

      await admin.page.goto('/admin/audit?action=dbview.');
      await expect(admin.page.locator('.audit-row').first()).toContainText('dbview.query');
    } finally {
      await admin.context.close();
    }
  });

  test('a query past its 2 s budget is stopped, and an empty or long one is a 422', async ({ browser, baseURL }) => {
    const admin = await signIn(browser, baseURL!, '/admin/dbview');
    try {
      await run(admin.page, 'WITH RECURSIVE r(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM r) SELECT count(*) FROM r');
      await expect(admin.page.locator('.dbview-problem')).toContainText('stopped past the 2 s budget', { timeout: 6000 });
      const h = { 'HX-Request': 'true' };
      expect((await admin.page.request.post('/admin/dbview', { form: { sql: '   ' }, headers: h })).status()).toBe(422);
      expect((await admin.page.request.post('/admin/dbview', { form: { sql: `SELECT '${'x'.repeat(4100)}'` }, headers: h })).status()).toBe(422);
    } finally {
      await admin.context.close();
    }
  });
});
