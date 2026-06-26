import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The mutating path. Each iteration creates a contact and immediately deletes it,
// so the store stays roughly steady within a run instead of growing without
// bound (the run scripts also start a fresh server per run for a clean baseline —
// see load-tests/PLAN.md, "The write path needs care"). Because the event loop is
// single-threaded, these writes are already serialised; there's no data race to
// chase, only a throughput ceiling to measure.
export const options = build({
  // The delete must find the row we just made; if creates regress to errors the
  // id parse fails and this drops, so gate on it.
  'checks{kind:roundtrip}': ['rate>0.99'],
});
export const handleSummary = summarize('write');

const ID = /hx-delete="\/contacts\/(\d+)"/;

export default function () {
  const created = http.post(
    `${BASE}/contacts`,
    { name: `Load Test ${__VU}-${__ITER}`, email: `lt${__VU}.${__ITER}@example.com`, role: 'Member' },
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
  );
  check(created, { 'create 200': (r) => r.status === 200 });

  const m = ID.exec(created.body || '');
  check(m, { 'create returned a row with an id': (r) => r !== null }, { kind: 'roundtrip' });
  if (!m) return;

  const del = http.del(`${BASE}/contacts/${m[1]}`);
  check(del, { 'delete 200': (r) => r.status === 200 }, { kind: 'roundtrip' });
}
