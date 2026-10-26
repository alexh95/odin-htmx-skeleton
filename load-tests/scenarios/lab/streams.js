import http from 'k6/http';
import { check } from 'k6';
import { setTimeout } from 'k6/timers';
import { BASE, P95, P99 } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @lab
//
// Streams that end, measured whole: a three-event SSE answer (the bot's shape),
// a two-part multipart response and one step of the resumable multipart feed,
// and the hub's /events subscribe on a topic of the VU's own, which the close
// that follows ends with `kicked` (stock k6 returns from an SSE request only when
// the stream ends, PLAN §19.1.7: fan-out is tools/streamload's).
export const options = build();
// The latency gate is on the requests that end on their own; /events is held
// open until the close that follows it, by design.
delete options.thresholds['http_req_duration{phase:load}'];
options.thresholds['http_req_duration{phase:load,held:no}'] = [`p(95)<${P95}`, `p(99)<${P99}`];
// An iteration cut off mid-await (the warmup's gracefulStop is 0s) leaves its VU's
// later awaits stalled in k6 2.0, so the warmup's last iterations are let finish.
options.scenarios.warmup.gracefulStop = '6s';
export const handleSummary = summarize('streams');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export default async function () {
  const t = http.get(`${BASE}/lab/sse/tick?n=3&ms=0`, { tags: { name: 'GET /lab/sse/tick', held: 'no' } });
  check(t, { 'tick: 3 events': (r) => r.status === 200 && (r.body.match(/^id: /gm) || []).length === 3 });
  const tp = http.post(`${BASE}/lab/sse/tick?n=1&ms=0`, null, { tags: { name: 'POST /lab/sse/tick', held: 'no' } });
  check(tp, { 'tick by POST': (r) => r.status === 200 });
  const m = http.get(`${BASE}/lab/multipart?n=2&ms=0`, { tags: { name: 'GET /lab/multipart', held: 'no' } });
  check(m, { 'multipart: 2 parts': (r) => r.status === 200 && (r.body.match(/HX-Part-ID/g) || []).length === 2 });
  const c = http.get(`${BASE}/lab/mp/count?n=2&max=1000&ms=0`, { headers: { 'HX-Last-Part-ID': String(__ITER % 900) }, tags: { name: 'GET /lab/mp/count', held: 'no' } });
  check(c, { 'feed step: 2 counts': (r) => r.status === 200 && (r.body.match(/class="count"/g) || []).length === 2 });

  const key = `load-${__VU}-${__ITER}`;
  const ev = http.asyncRequest('GET', `${BASE}/events?t=lab.feed:${key}`, null, { timeout: '5s', tags: { name: 'GET /events', held: 'yes' } });
  await sleep(50); // the subscription is in before the close
  const k = http.post(`${BASE}/lab/close?t=lab.feed:${key}`, null, { tags: { name: 'POST /lab/close', held: 'no' } });
  check(k, { 'close 204': (r) => r.status === 204 });
  const e = await ev;
  check(e, { 'events: kicked': (r) => r.status === 200 && (r.body || '').includes('event: kicked') });
}
