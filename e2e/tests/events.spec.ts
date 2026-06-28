import { test, expect } from '@playwright/test';
import { spawnServer, get, del, waitHealthy, stop } from '../helpers/server';

// Events are interactions BETWEEN contacts (events.actor_id/target_id → contacts,
// ON DELETE CASCADE). This uses a dedicated :memory: server because it deletes a
// seeded contact — keeping it off the shared per-worker store other tests use.
test('deleting a contact cascades to its interactions (FK)', async () => {
  const port = 8320 + test.info().parallelIndex;
  const proc = spawnServer(test.info().config, port); // DB_PATH unset → :memory:
  try {
    await waitHealthy(port);

    // Contact 1's activity timeline links to other contacts via the events join.
    const before = await get(port, '/contacts/1');
    expect(before.status).toBe(200);
    const partners = [...before.body.matchAll(/class="tl-who"[^>]*hx-get="\/contacts\/(\d+)"/g)].map((m) => Number(m[1]));
    expect(partners.length).toBeGreaterThan(0);

    // Delete one partner; the events it shared with contact 1 cascade away.
    const partner = partners[0];
    expect((await del(port, `/contacts/${partner}`)).status).toBe(200);

    const after = await get(port, '/contacts/1');
    const afterCount = [...after.body.matchAll(/class="tl-who"/g)].length;
    expect(afterCount).toBeLessThan(partners.length); // interactions removed
    expect(after.body).not.toContain(`hx-get="/contacts/${partner}"`); // partner gone from the timeline
  } finally {
    await stop(proc);
  }
});
