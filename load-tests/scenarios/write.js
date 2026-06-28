import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The mutating path. Each iteration creates a contact, edits it, and deletes it,
// so the store stays roughly steady within a run instead of growing without bound
// (the run scripts also start a fresh server per run for a clean baseline — see
// load-tests/PLAN.md, "The write path needs care"). This exercises POST /contacts
// (create), POST /contacts/:id (full edit), and DELETE /contacts/:id on a contact
// we own, keeping the dataset stable.
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
  const id = m[1];

  const edited = http.post(
    `${BASE}/contacts/${id}`,
    { name: `Edited ${__VU}-${__ITER}`, email: `ed${__VU}.${__ITER}@example.com`, role: 'Manager', status: 'Active', score: '70' },
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
  );
  check(edited, { 'edit 200': (r) => r.status === 200 }, { kind: 'roundtrip' });

  const del = http.del(`${BASE}/contacts/${id}`);
  check(del, { 'delete 200': (r) => r.status === 200 }, { kind: 'roundtrip' });
}
