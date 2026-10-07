import { test, expect } from '../fixtures';
import type { APIRequestContext } from '@playwright/test';

// What the demo's writes store. Contacts are the demo's, so this skips on the
// starter. API-only (no browser).
const form = { 'content-type': 'application/x-www-form-urlencoded' };

async function contact(request: APIRequestContext, q: string) {
  const found = await (await request.get(`/api/search?q=${encodeURIComponent(q)}`)).json();
  expect(found).toHaveLength(1);
  return found[0];
}

test.describe('writes', () => {
  test.beforeEach(async ({ request }) => {
    test.skip((await request.get('/data')).status() !== 200, 'demo contacts');
  });

  test('status cycles concurrently without losing a step', async ({ request }) => {
    const name = `Cycler ${Date.now()}`;
    const made = await request.post('/contacts', { headers: form, data: `name=${encodeURIComponent(name)}&email=cycler@example.dev` });
    const id = (await made.text()).match(/id="contact-(\d+)"/)![1];
    expect((await contact(request, name)).status).toBe('Invited');

    // Many at once: a read-then-write cycle lets two of them read the same
    // status and write the same next one. Invited + 31 steps = Disabled. (The
    // old window was microseconds wide, so this states the contract more than
    // it catches the race.)
    const cycles = await Promise.all(
      Array.from({ length: 31 }, () => request.post(`/contacts/${id}`, { headers: form, data: 'action=cycle' })),
    );
    for (const r of cycles) expect(r.status()).toBe(200);
    expect((await contact(request, name)).status).toBe('Disabled');
  });
});
