import { test, expect } from '../../fixtures';
import { post, startServer, stopServer, TWO_HOSTS } from '../../helpers/server';

// The public demo's cap (PLAN §11.6, X38): where a profile mounts contacts as a demo for anyone
// (full's lab host, CONTACTS_CAP), a create past the cap is refused with the reason, as a
// validation error is; the skeleton never caps. API-only.
test.describe('contacts demo', { tag: '@contacts' }, () => {
  test.skip(!TWO_HOSTS, 'contacts is capped only where full mounts it as its lab host\'s demo');

  test('a create past CONTACTS_CAP is refused, and says the demo starts over', async () => {
    const s = await startServer(test.info().config, { CONTACTS_CAP: '21' }); // the seed is 20
    try {
      const form = (n: string) => `name=${n}&email=${n}%40example.dev`;
      expect((await post(s.port, '/contacts', form('Last'))).status).toBe(200);
      const over = await post(s.port, '/contacts', form('Over'));
      expect(over.status).toBe(422);
      expect(over.body).toContain('21 contacts at most');
    } finally {
      await stopServer(s);
    }
  });
});
