import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @accounts-accounts
//
// Becoming a member and the admin's side of it (PLAN §17.1): each iteration registers a new
// member (an argon2id hash on the pool; run.sh opens registration), who saves a name and tries
// a wrong reset code; then the test admin, signed in once per VU in a jar of its own, reads
// /admin/accounts and makes each change with a reason: a role, a disable and an enable, a
// reset code, and an invite made and withdrawn. Refusals that are the design (the last admin's
// role, a wrong code) are expected answers.
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };
const PROMPT = { ...FORM, 'HX-Prompt': encodeURI('load test') };
const ok = (...codes) => http.expectedStatuses(...codes);
const PASSWORD = 'a-long-enough-password';

export const options = build({ 'http_req_duration{phase:load}': ['p(99)<5000'], 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the admin's jar keeps its session
export const handleSummary = summarize('members');

const admin = new http.CookieJar();
const post = (path, body, headers, jar, name, ...codes) =>
  http.post(`${MAIN}${path}`, body, { headers, jar, redirects: 0, tags: { name }, responseCallback: ok(...codes) });

export default function () {
  if (__ITER === 0) {
    const r = post('/login', { username: 'admin', password: 'e2e-and-load-only-password' }, FORM, admin, 'POST /login', 303, 503);
    check(r, { 'admin signed in': (x) => x.status === 303 });
  }

  const me = new http.CookieJar();
  check(http.get(`${MAIN}/register`, { jar: me, tags: { name: 'GET /register' } }), { 'join page': (r) => r.status === 200 });
  const name = `m${__VU}x${__ITER}`;
  const joined = post('/register', { username: name, password: PASSWORD, again: PASSWORD }, FORM, me, 'POST /register', 303, 503);
  check(joined, { 'joined: 303 or busy': (r) => r.status === 303 || r.status === 503 });
  if (joined.status === 303) {
    check(http.get(`${MAIN}/accounts/profile`, { jar: me, tags: { name: 'GET /accounts/profile' } }), { 'profile': (r) => r.status === 200 });
    check(post('/accounts/profile', { display: `Member ${name}` }, FORM, me, 'POST /accounts/profile', 200), { 'saved': (r) => r.status === 200 });
    check(post('/accounts/theme', { style: 'modern', scheme: 'houston' }, FORM, me, 'POST /accounts/theme', 204), { 'theme kept': (r) => r.status === 204 });
  }
  check(http.get(`${MAIN}/reset`, { jar: me, tags: { name: 'GET /reset' } }), { 'reset page': (r) => r.status === 200 });
  check(post('/reset', { username: name, code: 'aaaa-bbbb-cccc', password: PASSWORD, again: PASSWORD }, FORM, me, 'POST /reset', 422), { 'wrong code 422': (r) => r.status === 422 });

  const page = http.get(`${MAIN}/admin/accounts`, { jar: admin, tags: { name: 'GET /admin/accounts' } });
  const ids = [...(page.body || '').matchAll(/id="user-(\d+)"/g)].map((x) => x[1]);
  check(page, { 'accounts page': (r) => r.status === 200 && ids.length > 1 });
  const id = ids[ids.length - 1]; // the newest member, never the admin (id 1)
  check(post(`/admin/accounts/${id}/role`, { role: 'Moderator' }, PROMPT, admin, 'POST /admin/accounts/:id/role', 303), { 'role': (r) => r.status === 303 });
  check(post(`/admin/accounts/1/role`, { role: 'Member' }, PROMPT, admin, 'POST /admin/accounts/:id/role', 409), { 'last admin kept': (r) => r.status === 409 });
  check(post(`/admin/accounts/${id}/disable`, null, PROMPT, admin, 'POST /admin/accounts/:id/disable', 303), { 'disabled': (r) => r.status === 303 });
  check(post(`/admin/accounts/${id}/enable`, null, PROMPT, admin, 'POST /admin/accounts/:id/enable', 303), { 'enabled': (r) => r.status === 303 });
  check(post(`/admin/accounts/${id}/reset`, null, PROMPT, admin, 'POST /admin/accounts/:id/reset', 200), { 'reset code': (r) => r.status === 200 && r.body.includes('reset-code') });
  const made = post('/admin/accounts/invites', { role: 'Member', uses: '1', days: '1' }, PROMPT, admin, 'POST /admin/accounts/invites', 200);
  check(made, { 'invite made': (r) => r.status === 200 && r.body.includes('invite-link') });
  const listed = http.get(`${MAIN}/admin/accounts`, { jar: admin, tags: { name: 'GET /admin/accounts' } });
  const hash = /name="invite" value="([0-9a-f]{64})"/.exec(listed.body || '');
  if (hash) {
    check(post('/admin/accounts/invites/delete', { invite: hash[1] }, PROMPT, admin, 'POST /admin/accounts/invites/delete', 303, 404), { 'withdrawn': (r) => r.status === 303 || r.status === 404 });
  }
}
