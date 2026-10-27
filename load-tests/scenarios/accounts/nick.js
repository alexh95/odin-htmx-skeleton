import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/nick.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @accounts-nick
//
// The nickname form: the page, a pick (a signed cookie, then the redirect, not
// followed), the page again as the member it made, and signing out.
export const options = build();
export const handleSummary = summarize('nick');

export default function () {
  const page = http.get(`${BASE}/login`, { tags: { name: 'GET /login' } });
  check(page, { 'login page 200': (r) => r.status === 200 && r.body.includes('id="nick"') });
  const pick = signIn(`load ${__VU}`);
  check(pick, { 'pick: 303 and a cookie': (r) => r.status === 303 && (r.headers['Set-Cookie'] || '').startsWith('nick=') });
  const again = http.get(`${BASE}/login`, { tags: { name: 'GET /login' } });
  check(again, { 'a member now': (r) => r.body.includes(`You are load ${__VU}`) });
  const out = http.post(`${BASE}/logout`, null, { headers: FORM, redirects: 0, tags: { name: 'POST /logout' } });
  check(out, { 'logout 303': (r) => r.status === 303 });
}
