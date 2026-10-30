import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @modules @accounts-accounts
//
// /admin/modules (PLAN §15.4): every route, env row, limit, health line and migration of the
// build on one page, as the test admin, signed in once per VU. No store read: all of it is
// the platform's, in memory.
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the sign-in on a VU's first iteration stays
export const handleSummary = summarize('modules');

export default function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' }, {
      headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: http.expectedStatuses(303, 503),
    });
    check(r, { 'signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${MAIN}/admin/modules`, { tags: { name: 'GET /admin/modules' } });
  check(page, { 'modules page': (r) => r.status === 200 && r.body.includes('modules-migrations') });
}
