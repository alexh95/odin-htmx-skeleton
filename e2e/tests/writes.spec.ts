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

  test('/forms keeps every field it posts, an empty optional one as ""', async ({ request }) => {
    // Notes left empty and the switch off: the optional text column must store
    // "" (a NULL would break its NOT NULL), and the unticked box isn't posted.
    const quiet = `Quiet ${Date.now()}`;
    let res = await request.post('/forms/submit', {
      headers: form,
      data: `name=${encodeURIComponent(quiet)}&email=quiet@example.dev&role=Engineer&status=Active&score=40&notes=`,
    });
    expect(res.status()).toBe(200);
    expect(await contact(request, quiet)).toMatchObject({ notes: '', notify: false, score: 40, status: 'Active' });

    const chatty = `Chatty ${Date.now()}`;
    res = await request.post('/forms/submit', {
      headers: form,
      data: `name=${encodeURIComponent(chatty)}&email=chatty@example.dev&notes=Met+at+the+meetup&notify=on`,
    });
    expect(res.status()).toBe(200);
    const c = await contact(request, chatty);
    expect(c).toMatchObject({ notes: 'Met at the meetup', notify: true });
    expect(await (await request.get(`/contacts/${c.id}`)).text()).toContain('Met at the meetup'); // the drawer shows it
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
