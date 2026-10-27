import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @compat
//
// The compatibility layers' pages on their own bundles, the htmx-2-era form's
// save and refusal (a 422 by design, which that page's htmx never swaps), and
// the two pings.
export const options = build();
export const handleSummary = summarize('compat');

const REFUSED = { tags: { name: 'POST /compat/htmx2/save' }, responseCallback: http.expectedStatuses(422) };

export default function () {
  for (const p of ['/compat', '/compat/htmx2', '/compat/alpine']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'page 200': (x) => x.status === 200 });
  }
  const ok = http.post(`${BASE}/compat/htmx2/save`, { name: `load ${__VU}` }, { tags: { name: 'POST /compat/htmx2/save' } });
  check(ok, { 'saved': (r) => r.status === 200 && (r.body || '').includes('Saved load') });
  const no = http.post(`${BASE}/compat/htmx2/save`, { name: '' }, REFUSED);
  check(no, { 'refused 422': (r) => r.status === 422 });
  for (const p of ['/compat/htmx2/ping', '/compat/alpine/ping']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'pong': (x) => x.status === 200 && (x.body || '').includes('pong') });
  }
}
