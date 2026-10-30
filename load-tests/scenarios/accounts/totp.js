import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @accounts-accounts
//
// Two-step sign-in's routes, without turning it on (every VU is the one test admin, so the
// account's state stays put): the setup page, a step-up by password (an argon verify), a wrong
// enrolment code, a code step with no pending sign-in, new codes and off while it is off.
// The refusals are the answers expected here, 422s.
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };
const ok = (...codes) => http.expectedStatuses(...codes);
const post = (path, body, ...codes) => http.post(`${MAIN}${path}`, body, { headers: FORM, redirects: 0, tags: { name: `POST ${path}` }, responseCallback: ok(...codes) });

// Step-ups wait for argon; a check that fails is a run that measured the wrong page.
export const options = build({ 'http_req_duration{phase:load}': ['p(99)<5000'], 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the sign-in on a VU's first iteration stays (k6 empties the jar each one)
export const handleSummary = summarize('totp');

export default function () {
  if (__ITER === 0) {
    const r = post('/login', { username: 'admin', password: 'e2e-and-load-only-password' }, 303, 503);
    check(r, { 'signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${MAIN}/accounts/totp`, { tags: { name: 'GET /accounts/totp' } });
  check(page, { 'setup page': (r) => r.status === 200 && r.body.includes('totp-secret') });
  check(http.get(`${MAIN}/step-up?next=/accounts/totp`, { tags: { name: 'GET /step-up' } }), { 'step-up page': (r) => r.status === 200 });
  check(post('/step-up', { secret: 'e2e-and-load-only-password', next: '/accounts/totp' }, 303, 503), { 'stepped up': (r) => r.status === 303 || r.status === 503 });
  check(post('/accounts/totp', { secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', code: '000000' }, 422), { 'wrong code 422': (r) => r.status === 422 });
  check(post('/login/code', { pending: 'x', code: '000000' }, 422), { 'no pending 422': (r) => r.status === 422 });
  check(post('/accounts/totp/codes', null, 422), { 'codes while off 422': (r) => r.status === 422 });
  check(post('/accounts/totp/off', null, 303), { 'off 303': (r) => r.status === 303 });
}
