import { test, expect } from '../fixtures';

// Row ids are 64-bit end to end. Binding them as 32-bit used to reduce an id
// mod 2^32, so /contacts/4294967297 read contact #1, and an id past 64 bits
// wrapped too. Once a fork adds ownership checks, "check N, act on N mod 2^32"
// is an authorization bypass. Contacts are the demo's; the starter has no id
// routes, so this spec skips there.
test.describe('ids', () => {
  test.beforeEach(async ({ request }) => {
    test.skip((await request.get('/data')).status() !== 200, 'demo routes');
  });

  test('an id past 32 bits is its own row, not #1', async ({ request }) => {
    expect((await request.get('/contacts/1')).status()).toBe(200);
    expect((await request.get('/contacts/4294967297')).status()).toBe(404);
  });

  test('a delete past 32 bits touches nothing', async ({ request }) => {
    expect((await request.delete('/contacts/4294967298')).status()).toBe(404);
    expect((await request.get('/contacts/2')).status()).toBe(200);
  });

  test('an id that overflows 64 bits, a zero or a non-number is rejected', async ({ request }) => {
    for (const id of ['18446744073709551617', '9223372036854775808', '0', 'abc', '1x']) {
      expect((await request.get(`/contacts/${id}`)).status(), id).toBe(404);
    }
  });
});
