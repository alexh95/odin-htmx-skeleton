import type { Page } from '@playwright/test';
import { expect, test } from '../../fixtures';

// hx-csp and streams (research 11 §2.2, PLAN §12.2), on /scripting/streams: each transport
// sends four buttons. hx-csp gates only what htmx core initialises and promotes a fragment's
// nonce only after a request, so a streamed button works only with the page's nonce (which
// the page sent in its connect URL) or by delegation to a nonced ancestor; one with no nonce
// or the stream response's own is stripped. And an unnonced connect is gated only on one of
// the two ways it can reach the page (below). These pin upstream's behaviour, so a change in
// hx-csp or the stream extensions shows up here as a diff.

async function open(page: Page) {
  await page.addInitScript(() => {
    const w = window as any;
    w.__csp = [];
    w.__strip = [];
    document.addEventListener('securitypolicyviolation', (e) => w.__csp.push(`${e.effectiveDirective} ${e.blockedURI}`));
    document.addEventListener('htmx:security:strip', (e) => w.__strip.push((e.target as Element).id));
  });
  await page.goto('/scripting/streams');
}

for (const t of ['sse', 'ws', 'mp']) {
  test(`${t}: the page's nonce and delegation work; no nonce and the stream's own are stripped`, { tag: '@scripting' }, async ({ page }) => {
    await open(page);
    const box = page.locator(`#${t}-box`);
    await expect(box.locator('button')).toHaveCount(4);

    for (const kind of ['none', 'own']) {
      await expect(box.locator(`#${t}-${kind}`), kind).not.toHaveAttribute('hx-get', /.*/);
      await box.locator(`#${t}-${kind}`).click();
    }
    await page.waitForTimeout(300);
    await expect(page.locator(`#${t}-out`)).toBeEmpty();

    await expect(box.locator(`#${t}-page`)).toHaveAttribute('hx-get', `/scripting/hello?v=${t}-page`);
    await box.locator(`#${t}-page`).click();
    await expect(page.locator(`#${t}-out .scripting-hello`)).toHaveText(`hello-${t}-page`);
    await box.locator(`#${t}-act`).click();
    await expect(page.locator(`#${t}-out .scripting-hello`)).toHaveText(`hello-${t}-delegated`);

    const rec = await page.evaluate(() => ({ csp: (window as any).__csp, strip: (window as any).__strip }));
    expect(rec.csp).toEqual([]);
    // The page strips the same two in each transport's box; these are this one's.
    expect(rec.strip.filter((id: string) => id.startsWith(`${t}-`)).sort()).toEqual([`${t}-none`, `${t}-own`]);
  });
}

// An unnonced connect, injected as an escaping mistake would put it (11 §2.2). In 4.0.0 the
// gate holds for one that arrives the way a fragment does, in an htmx swap: before-init
// fires on it and hx-csp strips it. One that other code wrote into the page and handed to
// htmx.process inside a subtree is wired by the extension's after-process hook, which
// checks no nonce, and connects: the gap the rest of the site's hash CSP exists for.
async function inject(page: Page, how: 'swap' | 'subtree', attr: string, t: string) {
  await page.evaluate(([how, attr, t]) => {
    const slot = document.createElement('div');
    slot.id = `slot-${t}`;
    document.querySelector('main')!.append(slot);
    const html = `<div id="inj-${t}" ${attr}="/scripting/streams/${t}"></div>`;
    if (how === 'swap') (window as any).htmx.swap({ target: slot, text: html, swap: 'innerHTML' });
    else {
      slot.innerHTML = html;
      (window as any).htmx.process(slot);
    }
  }, [how, attr, t]);
}

for (const [t, attr] of [['sse', 'hx-sse:connect'], ['ws', 'hx-ws:connect']]) {
  test(`an unnonced ${attr} that arrives in a swap is stripped`, { tag: '@scripting' }, async ({ page }) => {
    await open(page);
    await expect(page.locator(`#${t}-box button`)).toHaveCount(4);
    await inject(page, 'swap', attr, t);
    await expect(page.locator(`#inj-${t}`)).not.toHaveAttribute(attr, /.*/);
    await page.waitForTimeout(500);
    await expect(page.locator(`#inj-${t} button`)).toHaveCount(0);
  });

  test(`an unnonced ${attr} processed inside a subtree still connects (upstream gap, pinned)`, { tag: '@scripting' }, async ({ page }) => {
    await open(page);
    await expect(page.locator(`#${t}-box button`)).toHaveCount(4);
    await inject(page, 'subtree', attr, t);
    await expect(page.locator(`#inj-${t} button`)).toHaveCount(4);
  });
}
