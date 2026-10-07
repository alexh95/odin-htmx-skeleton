import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The starter's one write path: POST /notes inserts a row and renders its <li>.
// There's no delete, so the table grows for the length of a run; the driver
// starts a fresh :memory: server per run, so every run begins from the seed.
export const options = build();
export const handleSummary = summarize('notes');

export default function () {
  const res = http.post(
    `${BASE}/notes`,
    { body: `load ${__VU}-${__ITER}` },
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
  );
  check(res, {
    'note 200': (r) => r.status === 200,
    'returns the new note': (r) => (r.body || '').includes('class="note"'),
  });
}
