import { test, expect } from '../fixtures';
import type { APIRequestContext } from '@playwright/test';

// Input limits. Every POST body is capped before routing, and each text field
// has a length limit in the service layer, so one request can't park megabytes
// in the store and in every page that renders it.
//
// Shared by the demo and the --minimal starter: the body cap is checked against
// a route both variants serve, and the field limits against whichever write
// path the variant has.
const form = { 'content-type': 'application/x-www-form-urlencoded' };

async function isDemo(request: APIRequestContext) {
  return (await request.get('/data')).status() === 200;
}

test.describe('input limits', () => {
  test('a body over the cap is refused with 413 before it is read', async ({ request }) => {
    const res = await request.post('/', { headers: form, data: 'x=' + 'a'.repeat(70 * 1024) });
    expect(res.status()).toBe(413);
  });

  test('a body under the cap still reaches the handler', async ({ request }) => {
    // 413 is about size alone: the same POST, small, is routed (and answered by
    // whatever the route says, which for POST / is not a 413).
    const res = await request.post('/', { headers: form, data: 'x=1' });
    expect(res.status()).not.toBe(413);
  });

  test('an over-long field is rejected and nothing is stored', async ({ request }) => {
    if (await isDemo(request)) {
      const name = 'Long' + 'n'.repeat(120); // MAX_NAME is 100
      const res = await request.post('/contacts', { headers: form, data: `name=${name}&email=long@example.dev&role=Engineer` });
      expect(await res.text()).toContain('at most 100 characters');
      const found = await (await request.get('/api/search?q=Longnnnn')).json();
      expect(found).toHaveLength(0);
    } else {
      const body = 'Long' + 'n'.repeat(520); // MAX_NOTE is 500
      await request.post('/notes', { headers: form, data: `body=${body}` });
      expect(await (await request.get('/')).text()).not.toContain(body);
    }
  });
});
