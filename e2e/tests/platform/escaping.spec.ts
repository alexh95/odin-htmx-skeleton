import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Page } from '@playwright/test';
import { BUILD, expect, test } from '../../fixtures';

// Markup never carries code (D22, PLAN §12.4, §19.1.5): on every page of the sitemap, every
// `_` is a lone `install <Name>` and every `data-behave` is a vanilla twin's name from
// platform/html's BEHAVIOURS table. On the hyperscript client, the gate in app.js refuses to
// initialise anything else, so an injected `_` or `text/hyperscript` script never runs, while
// the behaviours keep working.

// The table's vanilla names, read from its one definition.
function vanillaNames(): string[] {
  const src = readFileSync(path.join(__dirname, '..', '..', '..', 'app', 'platform', 'html', 'behave.odin'), 'utf8');
  return [...src.matchAll(/=\s*\{"[A-Za-z]+",\s*"([a-z-]+)"\}/g)].map((m) => m[1]);
}

async function sitemapPaths(page: Page): Promise<string[]> {
  const body = await (await page.request.get('/sitemap.xml')).text();
  return [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}

test.describe('behaviours in markup', { tag: '@platform' }, () => {
  test('every _ is a lone install and every data-behave a twin\'s name, on every sitemap page', async ({ page }) => {
    const names = vanillaNames();
    expect(names).toContain('tabs');
    for (const p of await sitemapPaths(page)) {
      await page.goto(p);
      const found = await page.evaluate(() => ({
        hs: [...document.querySelectorAll('[_]')].map((e) => e.getAttribute('_') ?? ''),
        vanilla: [...document.querySelectorAll('[data-behave]')].map((e) => e.getAttribute('data-behave') ?? ''),
      }));
      for (const src of found.hs) expect(src, p).toMatch(/^install [A-Z]\w*$/);
      for (const name of found.vanilla) expect(names, `${p}: data-behave="${name}"`).toContain(name);
      if (BUILD.client === 'hyperscript') expect(found.vanilla, p).toEqual([]);
      else expect(found.hs, p).toEqual([]);
    }
  });

  test('the hyperscript gate refuses an injected _ and an injected script, and keeps the behaviours', async ({ page }) => {
    test.skip(BUILD.client !== 'hyperscript', 'the vanilla client runs no hyperscript');
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto('/');
    await page.waitForFunction(() => typeof (window as any)._hyperscript === 'function');
    await page.evaluate(() => {
      const d = document.createElement('div');
      d.innerHTML = '<button id="inj" _="on click put \'PWNED\' into me">x</button>'
        + '<p id="inj2"></p><script type="text/hyperscript">on load put \'PWNED\' into #inj2 end</script>'
        + '<button id="ok" _="install CopyText" data-copy="copied">c</button>';
      document.querySelector('main')!.append(d);
      (window as any).htmx.process(d);
    });
    await page.locator('#inj').click();
    await page.waitForTimeout(300);
    await expect(page.locator('#inj')).toHaveText('x');
    await expect(page.locator('#inj2')).toBeEmpty();
    expect(await page.locator('#inj').getAttribute('data-hyperscript-powered')).toBeNull();
    // The install beside it initialised: the gate passes behaviours.
    await expect(page.locator('#ok')).toHaveAttribute('data-hyperscript-powered', /.*/);
    expect(errors).toEqual([]);
  });
});
