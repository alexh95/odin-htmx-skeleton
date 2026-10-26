import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @notes
//
// The notes card's one write: POST /notes stores a note and renders its <li>.
// There's no delete, so the store grows for the length of a run (the memory
// store keeps its newest 500); the driver starts a fresh server per run, so
// every run begins from the seed.
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
