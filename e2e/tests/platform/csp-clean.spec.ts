import type { Page } from '@playwright/test';
import { BUILD, expect, has, test } from '../../fixtures';

// The CSP holds while the pages are used (PLAN §19, csp-clean): no securitypolicyviolation on
// any page the sitemap lists, nor during one interaction per feature, the streams and the
// behaviours included, with trusted input only. The other side, that the policy really
// refuses what it should, is csp-enforced.spec's.

// Records every CSP violation the page reports, from before its first script.
async function watchCsp(page: Page) {
  await page.addInitScript(() => {
    (window as any).__csp = [];
    document.addEventListener('securitypolicyviolation', (e) =>
      (window as any).__csp.push(`${e.violatedDirective} ${e.blockedURI} ${e.sourceFile}:${e.lineNumber}`),
    );
  });
}
const violations = (page: Page) => page.evaluate(() => (window as any).__csp as string[]);
// The record starts over with each document, so a page is checked before leaving it.
const clean = async (page: Page) => expect(await violations(page), new URL(page.url()).pathname).toEqual([]);

async function sitemapPaths(page: Page): Promise<string[]> {
  const body = await (await page.request.get('/sitemap.xml')).text();
  return [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}

test.describe('csp-clean', { tag: '@platform' }, () => {
  test('every sitemap page, the theme picker and the gallery raise no violation', async ({ page }) => {
    await watchCsp(page);
    for (const path of await sitemapPaths(page)) {
      await page.goto(path);
      await clean(page);
    }

    // The picker is on every page, whichever theme the build has.
    await page.goto('/');
    await page.locator('.picker summary').click();
    if (has('platform-full')) {
      await page.locator('[data-pick-style="brutal"]').click();
      await expect(page.locator('html')).toHaveAttribute('data-style', 'brutal');
      await page.locator('[data-pick-scheme="acid"]').click();
      await expect(page.locator('html')).toHaveAttribute('data-scheme', 'acid');
    } else {
      await page.locator('[data-pick-scheme="daylight"]').click();
      await expect(page.locator('html')).toHaveAttribute('data-scheme', 'daylight');
    }
    await clean(page);

    if (has('gallery')) {
      await page.goto('/components');
      await page.locator('[data-sw-style="arcade"][data-sw-scheme="pop"]').click();
      await expect(page.locator('html')).toHaveAttribute('data-scheme', 'pop');
      await page.getByRole('tab', { name: 'Security' }).click();
      await expect(page.getByRole('tab', { name: 'Security' })).toHaveAttribute('aria-selected', 'true');
      await page.getByRole('button', { name: 'Success toast' }).click();
      await page.locator('#toasts .toast-x').first().click();
      await expect(page.locator('#toasts .toast:not(.leaving)')).toHaveCount(0);
      await page.getByRole('button', { name: 'Open drawer' }).click();
      await page.locator('.drawer h2').click(); // inside the drawer: must not close it
      await expect(page.locator('.drawer')).toBeVisible();
      await clean(page);
    }
  });

  test('the streams: an SSE feed, a socket\'s send and a multipart answer', { tag: '@lab' }, async ({ page, request }) => {
    await watchCsp(page);
    const tag = `clean-${test.info().project.name}-${Date.now()}`;
    await page.goto(`/lab/streams?tag=${tag}&room=${tag}`);
    await expect(page.locator('#ws-status .hello')).toHaveText('connected 1');
    await request.post(`/lab/publish?t=lab.feed:${tag}`, { form: { id: 'c1', text: 'over SSE' } });
    await expect(page.locator('#feed #m-c1')).toHaveText('over SSE');
    await page.locator('#message').fill('over the socket');
    await page.locator('#send').click();
    await expect(page.locator('#chat p').last()).toHaveText('over the socket');
    await page.locator('#build').click();
    await expect(page.locator('#mp-a .part')).toHaveText('part 1 of 3');
    await clean(page);
  });

  test('the behaviours on this build\'s client', async ({ page }) => {
    test.skip(!has('notes') && !has('contacts') && !has('scripting'), 'no behaviour to use');
    await watchCsp(page);
    if (has('scripting') && BUILD.client === 'hyperscript') {
      await page.goto('/scripting/live');
      await expect(page.locator('#pw-hs-card')).toHaveAttribute('data-hyperscript-powered', /.*/);
      await page.locator('#pw-hs').fill('Correct-Horse-9');
      await expect(page.locator('#pw-hs-card .scripting-pw-score')).toHaveText('4 of 4');
      await clean(page);
    }
    if (has('notes') && has('home') && !(BUILD.hosts && Object.keys(BUILD.hosts).length > 1)) { // the notes card is home's
      await page.goto('/');
      await page.locator('.add-note input[name="body"]').fill('a clean note');
      await page.getByRole('button', { name: 'Add' }).click();
      await expect(page.locator('#note-list .note').first()).toContainText('a clean note');
      await clean(page);
    }
    if (has('contacts')) {
      await page.goto('/data');
      await page.locator('.filter input[name="q"]').fill('a');
      await page.keyboard.press('Enter'); // SearchBox: Enter never submits
      await expect(page).toHaveURL(/\/data$/);
      await clean(page);
    }
  });

  test('the nonce class and the compat pages, one interaction each', { tag: '@scripting' }, async ({ page }) => {
    await watchCsp(page);
    await page.goto('/scripting');
    await page.locator('#on-click').click();
    await expect(page.locator('#on-click')).toHaveText('hx-on ran');
    await clean(page);
    await page.goto('/scripting/live');
    await page.locator('#pw-live').fill('Correct-Horse-9');
    await expect(page.locator('#pw-live-card .scripting-pw-score')).toHaveText('4 of 4');
    await clean(page);
    await page.goto('/scripting/streams');
    await page.locator('#sse-page').click();
    await expect(page.locator('#sse-out .scripting-hello')).toHaveText('hello-sse-page');
    await clean(page);
    await page.goto('/scripting/tt');
    await page.locator('#tt-get').click();
    await expect(page.locator('#tt-out .scripting-hello')).toHaveText('hello-tt');
    await clean(page);
    if (has('compat')) {
      await page.goto('/compat/htmx2');
      await page.locator('#h2-child').click();
      await expect(page.locator('#h2-pong')).toBeVisible();
      await clean(page);
      await page.goto('/compat/alpine');
      await page.locator('#alpine-ping').click();
      await expect(page.locator('#alpine-pong')).toBeVisible();
      await clean(page);
    }
  });
});
