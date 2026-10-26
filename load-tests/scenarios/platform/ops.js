import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @platform
//
// What operators and the crawlers' owners poll: the three probes, /metrics, the
// notices, the favicon and the two ownership proofs. All are answered from
// memory, but the probes walk the module table and /metrics renders every
// counter, so a probe that started to cost something shows here. run.sh gives
// the server a bearer token and passes it as METRICS_TOKEN; without one /metrics
// is a 404. An ownership proof is a 404 where the profile sets no token, and
// the IndexNow path asked for here is never the key, which costs the same as
// the hit.
export const options = build();
export const handleSummary = summarize('ops');

const MAYBE = { responseCallback: http.expectedStatuses(200, 404) };
const AUTH = __ENV.METRICS_TOKEN ? { headers: { Authorization: `Bearer ${__ENV.METRICS_TOKEN}` } } : MAYBE;

export default function () {
  for (const p of ['/healthz', '/livez', '/readyz', '/licenses', '/favicon.ico']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'probe 200': (x) => x.status === 200 });
  }
  const m = http.get(`${BASE}/metrics`, { ...AUTH, tags: { name: 'GET /metrics' } });
  check(m, { 'metrics answered': (r) => r.status === 200 || (!__ENV.METRICS_TOKEN && r.status === 404) });
  for (const p of ['/BingSiteAuth.xml', '/0123456789abcdef.txt']) {
    const r = http.get(`${BASE}${p}`, { ...MAYBE, tags: { name: `GET ${p}` } });
    check(r, { 'proof answered': (x) => x.status === 200 || x.status === 404 });
  }
}
