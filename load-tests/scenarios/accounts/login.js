import http from 'k6/http';
import { check } from 'k6';
import { MAIN, P95, P99 } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @accounts-accounts
//
// A sign-in storm (PLAN §17.1, Q34): every iteration signs in, which is one argon2id
// verify on the pool, then reads its sessions and ends the session, by sign-out or by
// revoking it. The pool answers 503 "busy" past its queue, which is the design, not a
// failure. The gate is on the other pages: argon runs off the loops, so they stay fast
// while it works. run.sh boots the server with the suite's test admin and the limits lifted.
const USER = 'admin';
const PASSWORD = 'e2e-and-load-only-password';
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

export const options = build({
  'http_req_duration{phase:load}': ['p(99)<5000'], // the sign-ins wait for argon: advisory
  'http_req_duration{phase:load,kind:page}': [`p(95)<${P95}`, `p(99)<${P99}`],
});
export const handleSummary = summarize('login');

const page = (name) => ({ tags: { name, kind: 'page' } });
// Houston's pages send report-to: a violation report, once per VU, so the route is measured.
const REPORT = JSON.stringify([{ type: 'csp-violation', url: `${MAIN}/login`, body: { blockedURL: 'inline', effectiveDirective: 'script-src-elem' } }]);

export default function () {
  if (__ITER === 0) {
    const report = http.post(`${MAIN}/csp-report`, REPORT, { headers: { 'Content-Type': 'application/reports+json' }, tags: { name: 'POST /csp-report', kind: 'page' } });
    check(report, { 'report 204': (r) => r.status === 204 });
  }
  const form = http.get(`${MAIN}/login`, page('GET /login'));
  check(form, { 'login page 200': (r) => r.status === 200 && r.body.includes('id="password"') });

  const signIn = http.post(`${MAIN}/login`, { username: USER, password: PASSWORD, next: '/accounts/sessions' }, {
    headers: FORM, redirects: 0, tags: { name: 'POST /login', kind: 'login' },
    responseCallback: http.expectedStatuses(303, 503),
  });
  check(signIn, { 'sign-in: 303, or 503 busy': (r) => r.status === 303 || r.status === 503 });
  if (signIn.status !== 303) return;

  const list = http.get(`${MAIN}/accounts/sessions`, page('GET /accounts/sessions'));
  const mine = /value="([0-9a-f]{64})"><button class="btn btn-outline" type="submit">Sign out here/.exec(list.body || '');
  check(list, { 'sessions 200, this one marked': (r) => r.status === 200 && mine !== null });

  const end = __ITER % 2 === 0 || mine === null
    ? http.post(`${MAIN}/logout`, null, { headers: FORM, redirects: 0, ...page('POST /logout') })
    : http.post(`${MAIN}/accounts/sessions/revoke`, { session: mine[1] }, { headers: FORM, redirects: 0, ...page('POST /accounts/sessions/revoke') });
  check(end, { 'session ended: 303': (r) => r.status === 303 });
}
