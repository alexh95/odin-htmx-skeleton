import { test, expect } from '../../fixtures';

// /status (PLAN §15.4): a card per probe, filled by one multipart/parallel response or, with
// ?mode=poll, every 30 s (304 while no state changed). What a probe says beyond its state is
// for admins (ops's panel.spec servers have one); a guest sees states only.
const T = { tag: '@status' };

test.describe('status', T, () => {
  for (const mode of ['parallel', 'poll'] as const) {
    test(`the board fills ${mode === 'poll' ? 'by a poll' : 'from one multipart/parallel response'}`, async ({ page }) => {
      const errors: string[] = [];
      page.on('pageerror', (e) => errors.push(e.message));
      const res = await page.goto(mode === 'poll' ? '/status?mode=poll' : '/status');
      expect(res!.headers()['x-impl']).toBe(`status.mode=${mode}`);
      for (const probe of ['loops', 'process']) {
        await expect(page.locator(`#st-${probe} .status-state`)).toHaveText('ok');
      }
      await expect(page.locator('.status-checking')).toHaveCount(0);
      await expect(page.locator('#st-process')).not.toContainText('version'); // details are an admin's
      expect(errors).toEqual([]);
    });
  }

  test('the parts are multipart/parallel, and a poll with the board\'s tag is a 304', async ({ request }) => {
    const parts = await request.get('/status/parts');
    expect(parts.headers()['content-type']).toMatch(/^multipart\/parallel; boundary=/);
    expect(await parts.text()).toContain('HX-Target: #st-loops');
    const board = await request.get('/status/board');
    const tag = board.headers()['hx-ptag'];
    expect(tag).toMatch(/^\d+$/);
    const again = await request.get('/status/board', { headers: { 'HX-PTag': tag } });
    expect(again.status()).toBe(304);
  });
});
