import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @lab
//
// The lab's pages and fragments: the index (the profile's root and /lab), the
// contract pages, each rendering its live element and the hub's cursor, the
// resync refetch, a publish to a feed nobody reads (the hub's ring takes it), a
// CSP report (logged at warn, at most 20 a second) and the numbers a spec reads
// back.
export const options = build();
export const handleSummary = summarize('lab');

// A browser's CSP violation report, as the Reporting API posts it.
const REPORT = JSON.stringify([{ type: 'csp-violation', url: `${BASE}/`, body: { blockedURL: 'inline', effectiveDirective: 'script-src-elem' } }]);
const FORM = { headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, tags: { name: 'POST /lab/publish' } };

export default function () {
  for (const p of ['/', '/lab', '/lab/streams', '/lab/streams/live', '/lab/streams/chat', '/lab/streams/mp', '/lab/streams/blank']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'page 200': (x) => x.status === 200 });
  }
  const f = http.get(`${BASE}/lab/feed?t=load`, { tags: { name: 'GET /lab/feed' } });
  check(f, { 'refetch 200': (r) => r.status === 200 && (r.body || '').includes('refetched load') });
  const p = http.post(`${BASE}/lab/publish?t=lab.feed:load-${__VU}`, { id: `m${__ITER}`, text: 'a line nobody reads' }, FORM);
  check(p, { 'publish 204': (r) => r.status === 204 });
  const r = http.post(`${BASE}/csp-report`, REPORT, { headers: { 'Content-Type': 'application/reports+json' }, tags: { name: 'POST /csp-report' } });
  check(r, { 'report 204': (x) => x.status === 204 });
  const s = http.get(`${BASE}/lab/stats`, { tags: { name: 'GET /lab/stats' } });
  check(s, { 'stats json': (r) => r.status === 200 && (r.body || '').startsWith('{"os":') });
}
