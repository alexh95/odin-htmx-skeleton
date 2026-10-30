import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @audit @accounts-accounts
//
// The audit log's reads (PLAN §17.7): the page, the next page by keyset, and the CSV export,
// as the test admin, signed in once per VU (each sign-in is itself an entry). k6 is loopback,
// which run.sh's server counts as the LAN, so the LAN-only rows answer.
const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

// A check that fails is a run that measured the wrong page (a lost session lands on /login).
export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the sign-in on a VU's first iteration stays (k6 empties the jar each one)
export const handleSummary = summarize('audit');

export default function () {
  if (__ITER === 0) {
    const r = http.post(`${BASE}/login`, { username: 'admin', password: 'e2e-and-load-only-password' }, {
      headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: http.expectedStatuses(303, 503),
    });
    check(r, { 'signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${BASE}/admin/audit?action=accounts.`, { tags: { name: 'GET /admin/audit' } });
  const first = /id="audit-(\d+)"/.exec(page.body || '');
  check(page, { 'audit page 200 with entries': (r) => r.status === 200 && first !== null });
  const rows = http.get(`${BASE}/admin/audit/rows?action=accounts.&before=${first ? first[1] : 0}`, { tags: { name: 'GET /admin/audit/rows' } });
  check(rows, { 'rows 200': (r) => r.status === 200 });
  const csv = http.get(`${BASE}/admin/audit/export?actor=admin`, { tags: { name: 'GET /admin/audit/export' } });
  check(csv, { 'csv 200, an attachment': (r) => r.status === 200 && (r.headers['Content-Disposition'] || '').startsWith('attachment') });
}
