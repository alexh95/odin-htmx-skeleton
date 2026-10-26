import { BUILD, expect, test } from '../../fixtures';

// Each profile's header set (PLAN §12.2): minimal sends exactly the skeleton's; every other
// profile adds Permissions-Policy, COOP and CORP (X35); streams, lab and full also ask browsers to
// report CSP violations to /csp-report. Never COEP, and no HSTS over http (NPM sends it, from
// stage 2). Route flags add to the base: .Stream's headers are the lab specs', .Private's and
// .Nonce_Csp's the pages' that carry them.

const REPORTING = ['streams', 'lab', 'full'];

test.describe('header sets', { tag: '@platform' }, () => {
  test('the profile sends its own set, on every kind of response', async ({ request }) => {
    const standard = BUILD.profile !== 'minimal';
    const reporting = REPORTING.includes(BUILD.profile);
    for (const path of ['/', '/static/app.css', '/healthz', '/no-such-page']) {
      const h = (await request.get(path)).headers();
      expect(h['permissions-policy'], path).toBe(standard ? 'camera=(), microphone=(), geolocation=()' : undefined);
      expect(h['cross-origin-opener-policy'], path).toBe(standard ? 'same-origin' : undefined);
      expect(h['cross-origin-resource-policy'], path).toBe(standard ? 'same-origin' : undefined);
      expect(h['reporting-endpoints'], path).toBe(reporting ? 'csp="/csp-report"' : undefined);
      expect(h['content-security-policy'].endsWith('; report-to csp'), path).toBe(reporting);
      expect(h['cross-origin-embedder-policy'], path).toBeUndefined();
      expect(h['strict-transport-security'], path).toBeUndefined();
      expect(h['x-version'], path).toBeTruthy();
    }
  });

  test('the social card and favicons may be fetched by other sites\' previews', async ({ request }) => {
    test.skip(BUILD.profile === 'minimal', 'minimal sends no CORP at all');
    for (const path of ['/static/og.png', '/favicon.ico', '/static/favicon.svg']) {
      expect((await request.get(path)).headers()['cross-origin-resource-policy'], path).toBe('cross-origin');
    }
  });

  test('/csp-report takes a browser\'s report where the profile asks for them, and is a 404 elsewhere', async ({ request }) => {
    const report = [{ type: 'csp-violation', url: 'http://x/', body: { blockedURL: 'inline', effectiveDirective: 'script-src-elem' } }];
    const res = await request.post('/csp-report', {
      headers: { 'content-type': 'application/reports+json', 'Sec-Fetch-Site': 'same-origin' },
      data: JSON.stringify(report),
    });
    expect(res.status()).toBe(REPORTING.includes(BUILD.profile) ? 204 : 404);
  });
});
