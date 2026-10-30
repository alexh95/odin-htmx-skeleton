import { test, expect, DASHBOARD } from '../../fixtures';

// The dashboard's cards are counted from the store, captions included: no
// placeholder trend ("+4 this week") beside a live number. API-only (reads
// the HTML, no browser).
test.describe('dashboard', { tag: ['@dashboard', '@contacts'] }, () => {
  test('every figure and caption comes from the store', async ({ request }) => {
    const home = await (await request.get(DASHBOARD)).text();
    const card = (label: string) => {
      const m = home.match(new RegExp(`stat-label">${label}</span></div><div class="stat-value" data-count="(\\d+)">\\d+</div><div class="stat-foot"><span class="stat-delta">([^<]*)<`));
      expect(m, label).toBeTruthy();
      return { value: Number(m![1]), caption: m![2] };
    };
    const total = card('Total contacts');
    const active = card('Active');

    // The total is the table's count, and the active share is computed from both.
    const data = await (await request.get('/data')).text();
    expect(total.value).toBe(Number(data.match(/<span class="muted">(\d+) contacts?<\/span>/)![1]));
    expect(active.caption).toBe(`${Math.floor((active.value * 100) / total.value)}% of all`);
    expect(home).not.toMatch(/this week|of base/);
  });
});
