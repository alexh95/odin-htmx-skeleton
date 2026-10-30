import http from 'k6/http';
import { check } from 'k6';
import { MAIN, P95, P99 } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @ops @accounts-accounts
//
// Houston's admin on /admin/ops (M5): the test admin, signed in once per VU, reads the page in
// each refresh mode, polls the panel (its render, then a 304 or the next render), and holds the
// multipart stream a moment. panel.js is the same for the nick identity's admin.
export const options = build();
options.noCookiesReset = true; // the admin's session stays
delete options.thresholds['http_req_failed{phase:load}'];
delete options.thresholds['http_req_duration{phase:load}'];
options.thresholds['http_req_failed{phase:load,held:no}'] = ['rate<0.01'];
options.thresholds['http_req_duration{phase:load,held:no}'] = [`p(95)<${P95}`, `p(99)<${P99}`];
options.scenarios.warmup.gracefulStop = '6s';
export const handleSummary = summarize('houston-ops');

const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };
const MODES = ['sse', 'poll', 'multipart'];

export default async function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /login', held: 'no' }, responseCallback: http.expectedStatuses(303, 503) });
    check(r, { 'admin signed in': (x) => x.status === 303 });
  }
  const mode = MODES[__ITER % MODES.length];
  const page = http.get(`${MAIN}/admin/ops?mode=${mode}`, { tags: { name: 'GET /admin/ops', held: 'no' } });
  check(page, { 'ops page 200': (r) => r.status === 200 && r.body.includes('id="ops-store"') });
  const p = http.get(`${MAIN}/admin/ops/panel`, { tags: { name: 'GET /admin/ops/panel', held: 'no' } });
  check(p, { 'panel 200 and a tag': (r) => r.status === 200 && r.headers['Hx-Ptag'] !== undefined });
  const again = http.get(`${MAIN}/admin/ops/panel`, { headers: { 'HX-PTag': p.headers['Hx-Ptag'] || '0' }, tags: { name: 'GET /admin/ops/panel', held: 'no' }, responseCallback: http.expectedStatuses(200, 304) });
  check(again, { 'panel again: 304, or the next render': (r) => r.status === 304 || r.status === 200 });
  await http.asyncRequest('GET', `${MAIN}/admin/ops/parts`, null, { timeout: '300ms', tags: { name: 'GET /admin/ops/parts', held: 'yes' } });
}
