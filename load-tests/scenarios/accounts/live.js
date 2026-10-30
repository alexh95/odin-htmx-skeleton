import http from 'k6/http';
import { check } from 'k6';
import { MAIN, P95, P99 } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @accounts-accounts
//
// A member's page and its #live (PLAN §9.1, §17.2.3): the test admin, signed in once per VU,
// loads a page, whose layout names their own topic, and opens /events on it (accounts.user,
// what a revoke ends), held a moment and cut by the client. Stock k6 can't read a stream that
// never ends, so the held one is left out of the gates, as chat_streams.js does.
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the sign-in on a VU's first iteration stays
delete options.thresholds['http_req_failed{phase:load}'];
delete options.thresholds['http_req_duration{phase:load}'];
options.thresholds['http_req_failed{phase:load,held:no}'] = ['rate<0.01'];
options.thresholds['http_req_duration{phase:load,held:no}'] = [`p(95)<${P95}`, `p(99)<${P99}`];
options.scenarios.warmup.gracefulStop = '6s'; // let a cut-off iteration's awaits finish
export const handleSummary = summarize('live');

export default async function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' }, {
      headers: FORM, redirects: 0, tags: { name: 'POST /login', held: 'no' }, responseCallback: http.expectedStatuses(303, 503),
    });
    check(r, { 'signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${MAIN}/accounts/profile`, { tags: { name: 'GET /accounts/profile', held: 'no' } });
  check(page, { 'a member page with its #live': (r) => r.status === 200 && r.body.includes('data-revoke="/login"') });
  await http.asyncRequest('GET', `${MAIN}/events?t=accounts.user:1`, null, { timeout: '300ms', tags: { name: 'GET /events', held: 'yes' } });
}
