import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { startServer, stopServer } from '../../helpers/server';
import { leave, member, uid, type Member } from '../../helpers/members';

// The bot on its mock (PLAN §14.3, D31): an answer in four frames over either delivery
// (an SSE answer to the form's POST, or a multipart one), Stop, the member's kept
// conversations, and the limits. The harness seeds the mock (BOT_SEED), so the same
// question gets the same answer.
const T = { tag: ['@bot', '@accounts-nick'] };

async function conversation(m: Member): Promise<string> {
  await m.page.goto('/bot');
  await m.page.getByRole('button', { name: 'New conversation' }).click();
  await m.page.waitForURL(/\/bot\/c\/\d+$/);
  return new URL(m.page.url()).pathname;
}

async function ask(page: Page, q: string, delivery: 'sse' | 'multipart') {
  await page.locator('.bot-ask select[name="delivery"]').selectOption(delivery);
  const box = page.locator('.bot-ask textarea');
  await box.fill(q);
  await box.press('Enter');
}

const answers = (page: Page) => page.locator('#c-log article.bot-a');

for (const delivery of ['sse', 'multipart'] as const) {
  test.describe(`the bot over ${delivery}`, T, () => {
    test('an answer streams in, then is rendered with its stats, and the conversation keeps it', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      const path = await conversation(ann);
      await ask(ann.page, 'What are you?', delivery);
      await expect(ann.page.locator('#c-log article.bot-q').first()).toHaveText('What are you?');
      await expect(answers(ann.page).locator('.bot-stop')).toHaveCount(1); // the shell, with Stop
      await expect(answers(ann.page).locator('.bot-stats')).toContainText(/\d+ tokens · first token \d+ ms · \d+ ms/);
      await expect(answers(ann.page).locator('.bot-stop')).toHaveCount(0);
      await expect(ann.page.locator('.bot-ask button[type=submit]')).toBeEnabled();
      if (delivery === 'multipart') await expect(ann.page.locator('#conv-title')).toHaveText('What are you?');
      // The same words live and stored (line breaks around rendered markdown differ between a morph and a page).
      const words = async () => (await answers(ann.page).locator('.bot-body').innerText()).replace(/\s+/g, ' ').trim();
      const said = await words();
      expect(said.length).toBeGreaterThan(10);

      await ann.page.goto(path);
      await expect(ann.page.locator('#conv-title')).toHaveText('What are you?');
      expect(await words()).toBe(said);
      expect(ann.errors).toEqual([]);
      await leave(ann);
    });

    test('Stop ends the answer within 100 ms, and says so', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      await conversation(ann);
      await ask(ann.page, `Tell me a long one ${uid('q')}`, delivery);
      const stop = answers(ann.page).locator('.bot-stop');
      await expect(stop).toBeVisible();
      // Timed in the page, from the click to the rendered answer.
      const ms = await ann.page.evaluate(async () => {
        const log = document.getElementById('c-log')!;
        const button = log.querySelector<HTMLButtonElement>('.bot-stop')!;
        const t0 = performance.now();
        button.click();
        while (!log.lastElementChild!.querySelector('.bot-stats')) {
          if (performance.now() - t0 > 5000) return -1;
          await new Promise((r) => setTimeout(r, 2));
        }
        return performance.now() - t0;
      });
      expect(ms).toBeGreaterThanOrEqual(0);
      expect(ms).toBeLessThan(100);
      await expect(answers(ann.page).locator('.bot-stats')).toContainText('Stopped');
      await leave(ann);
    });
  });
}

test.describe('the bot', T, () => {
  test('the same question gets the same answer (BOT_SEED), and a conversation is its owner\'s alone', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    const mine = await conversation(ann);
    await conversation(bob);
    for (const m of [ann, bob]) {
      await ask(m.page, 'Same question?', 'sse');
      await expect(answers(m.page).locator('.bot-stats')).toBeVisible();
    }
    expect(await answers(bob.page).locator('.bot-body').innerText()).toBe(await answers(ann.page).locator('.bot-body').innerText());
    const res = await bob.page.goto(mine);
    expect(res!.status()).toBe(404);
    await leave(ann, bob);
  });

  test('a member asks one at a time; past the hour\'s questions a toast says when', async ({ browser }) => {
    const config = test.info().config;
    const s = await startServer(config, { BOT_DELAY_MS: '150', BOT_MEMBER_PER_HOUR: '2' });
    const ann = await member(browser, `http://127.0.0.1:${s.port}`);
    try {
      await conversation(ann);
      await ask(ann.page, 'first', 'sse');
      await expect(answers(ann.page).locator('.bot-body')).not.toBeEmpty(); // released: the form is back
      await ask(ann.page, 'second, too soon', 'sse');
      await expect(ann.page.locator('#toasts .toast')).toContainText('One answer at a time');
      await expect(answers(ann.page).locator('.bot-stats')).toBeVisible({ timeout: 15_000 });
      await ask(ann.page, 'second', 'sse');
      await expect(answers(ann.page)).toHaveCount(2);
      await expect(answers(ann.page).nth(1).locator('.bot-stats')).toBeVisible({ timeout: 15_000 });
      await ask(ann.page, 'third', 'sse');
      await expect(ann.page.locator('#toasts .toast').last()).toContainText('2 questions this hour');
    } finally {
      await leave(ann);
      await stopServer(s);
    }
  });

  test('a guest gets the mock, keeps nothing, and is limited per hour', async ({ browser }) => {
    const config = test.info().config;
    const s = await startServer(config, { BOT_GUEST_PER_HOUR: '1' });
    const context = await browser.newContext({ baseURL: `http://127.0.0.1:${s.port}` });
    const page = await context.newPage();
    try {
      const res = await page.goto('/bot');
      expect(res!.headers()['x-impl']).toBe('bot.backend=mock');
      await expect(page.getByRole('link', { name: 'Pick a nickname' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'New conversation' })).toHaveCount(0);
      await ask(page, 'a guest asks', 'multipart');
      await expect(answers(page).locator('.bot-stats')).toBeVisible();
      await ask(page, 'and again', 'sse');
      await expect(page.locator('#toasts .toast')).toContainText('1 questions this hour');
      await page.reload();
      await expect(page.locator('#c-log article')).toHaveCount(0); // kept by no one
    } finally {
      await context.close();
      await stopServer(s);
    }
  });
});
