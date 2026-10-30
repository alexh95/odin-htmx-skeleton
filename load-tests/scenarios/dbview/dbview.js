import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @dbview @accounts-accounts
//
// The admin on /admin/dbview (M5): the test admin, signed in once per VU, reads the form and
// runs a small read on the query pool (each audited), and a write that is refused before it runs.
export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the admin's session stays
export const handleSummary = summarize('dbview');

const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };
const HX = { ...FORM, 'HX-Request': 'true' };

export default function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: http.expectedStatuses(303, 503) });
    check(r, { 'admin signed in': (x) => x.status === 303 });
  }
  check(http.get(`${MAIN}/admin/dbview`, { tags: { name: 'GET /admin/dbview' } }), { 'form': (r) => r.status === 200 });
  const read = http.post(`${MAIN}/admin/dbview`, { sql: 'SELECT name FROM sqlite_schema ORDER BY name LIMIT 20' }, { headers: HX, tags: { name: 'POST /admin/dbview' }, responseCallback: http.expectedStatuses(200, 503) });
  check(read, { 'a table, or busy': (r) => (r.status === 200 && r.body.includes('dbview-table')) || r.status === 503 });
  const write = http.post(`${MAIN}/admin/dbview`, { sql: 'DELETE FROM audit_log' }, { headers: HX, tags: { name: 'POST /admin/dbview' }, responseCallback: http.expectedStatuses(200, 503) });
  check(write, { 'a write refused': (r) => (r.status === 200 && r.body.includes('only reads')) || r.status === 503 });
}
