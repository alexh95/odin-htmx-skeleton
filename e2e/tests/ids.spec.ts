import { test, expect } from '../fixtures';
import type { APIRequestContext } from '@playwright/test';

// Row ids are 64-bit end to end. Binding them as 32-bit used to reduce an id
// mod 2^32, so /contacts/4294967297 read contact #1, and an id past 64 bits
// wrapped too. Once a fork adds ownership checks, "check N, act on N mod 2^32"
// is an authorization bypass. Contacts are the demo's; the starter has no id
// routes, so this spec skips there.
//
// Each test makes its own contact: the worker's store is shared, and another
// spec may already have deleted any seeded row.
async function newContact(request: APIRequestContext): Promise<number> {
  const res = await request.post('/contacts', {
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    data: `name=Id+Probe+${Date.now()}&email=id.probe@example.dev`,
  });
  expect(res.status()).toBe(200);
  return Number((await res.text()).match(/id="contact-(\d+)"/)![1]);
}

test.describe('ids', () => {
  test.beforeEach(async ({ request }) => {
    test.skip((await request.get('/data')).status() !== 200, 'demo routes');
  });

  test('an id 2^32 past a real one is its own (missing) row', async ({ request }) => {
    const id = await newContact(request);
    expect((await request.get(`/contacts/${id}`)).status()).toBe(200);
    expect((await request.get(`/contacts/${id + 2 ** 32}`)).status()).toBe(404);
  });

  test('a delete 2^32 past a real id touches nothing', async ({ request }) => {
    const id = await newContact(request);
    expect((await request.delete(`/contacts/${id + 2 ** 32}`)).status()).toBe(404);
    expect((await request.get(`/contacts/${id}`)).status()).toBe(200);
  });

  test('an id that overflows 64 bits, a zero or a non-number is rejected', async ({ request }) => {
    for (const id of ['18446744073709551617', '9223372036854775808', '0', 'abc', '1x']) {
      expect((await request.get(`/contacts/${id}`)).status(), id).toBe(404);
    }
  });
});
