import http from 'k6/http';
import { check } from 'k6';
import { BASE, P95, P99 } from '../../lib/config.js';
import { signIn } from '../../lib/nick.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @ops @accounts-nick
//
// An admin on /admin/ops (run.sh's server makes loopback admin): the page in each refresh
// mode, the poll (its render, then a 304 for the tag it got, or the next render), and the
// multipart stream held a moment and cut by the client, which k6 can't read to an end. The
// panel is rendered once a second whoever watches: what a viewer costs is these.
export const options = build();
options.noCookiesReset = true; // the nickname picked on a VU's first iteration stays (k6 empties the jar each one)
delete options.thresholds['http_req_failed{phase:load}'];
delete options.thresholds['http_req_duration{phase:load}'];
options.thresholds['http_req_failed{phase:load,held:no}'] = ['rate<0.01'];
options.thresholds['http_req_duration{phase:load,held:no}'] = [`p(95)<${P95}`, `p(99)<${P99}`];
options.scenarios.warmup.gracefulStop = '6s'; // let a cut-off iteration's awaits finish (see lab/streams.js)
export const handleSummary = summarize('panel');

const MODES = ['sse', 'poll', 'multipart'];

export default async function () {
  if (__ITER === 0) signIn(`load ${__VU}`);
  const mode = MODES[__ITER % MODES.length];
  const page = http.get(`${BASE}/admin/ops?mode=${mode}`, { tags: { name: 'GET /admin/ops', held: 'no' } });
  check(page, { 'ops page 200': (r) => r.status === 200 && (r.headers['X-Impl'] || '') === `ops.mode=${mode}` });
  const p = http.get(`${BASE}/admin/ops/panel`, { tags: { name: 'GET /admin/ops/panel', held: 'no' } });
  check(p, { 'panel 200 and a tag': (r) => r.status === 200 && r.headers['Hx-Ptag'] !== undefined });
  const again = http.get(`${BASE}/admin/ops/panel`, { headers: { 'HX-PTag': p.headers['Hx-Ptag'] || '0' }, tags: { name: 'GET /admin/ops/panel', held: 'no' }, responseCallback: http.expectedStatuses(200, 304) });
  check(again, { 'panel again: 304, or the next render': (r) => r.status === 304 || r.status === 200 });
  await http.asyncRequest('GET', `${BASE}/admin/ops/parts`, null, { timeout: '300ms', tags: { name: 'GET /admin/ops/parts', held: 'yes' } });
}
