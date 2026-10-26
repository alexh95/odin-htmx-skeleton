import { expect, test } from '../../fixtures';

// The lab's index: at /lab, and as the profile's root until landing takes it (M3). Each card
// opens a contract page, and each page carries its one layout stream or socket.

const T = { tag: '@lab' };

test.describe('the lab index', T, () => {
  test('/lab links every contract page, and so does the root, whose canonical is the root', async ({ page }) => {
    for (const [path, canonical] of [['/lab', '/lab'], ['/', '/']]) {
      await page.goto(path);
      await expect(page.locator('.lab-card h2')).toHaveText(['All three on one page', 'hx-sse', 'hx-ws', 'hx-multipart']);
      const hrefs = await page.locator('.lab-card').evaluateAll((as) => as.map((a) => a.getAttribute('href')));
      expect(hrefs).toEqual(['/lab/streams', '/lab/streams/live', '/lab/streams/chat', '/lab/streams/mp']);
      expect(new URL(await page.locator('link[rel=canonical]').getAttribute('href') ?? '').pathname).toBe(canonical);
    }
  });

  test('a card opens its page: the live page carries the layout stream, the chat page a socket', async ({ page }) => {
    await page.goto('/lab');
    await page.locator('.lab-card', { hasText: 'hx-sse' }).click();
    await expect(page).toHaveURL(/\/lab\/streams\/live$/);
    await expect(page.locator('#live')).toHaveAttribute('hx-sse:connect', /^\/events\?t=lab\.feed:live&after=\d+-\d+$/);
    await page.goto('/lab');
    await page.locator('.lab-card', { hasText: 'hx-ws' }).click();
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
  });
});
