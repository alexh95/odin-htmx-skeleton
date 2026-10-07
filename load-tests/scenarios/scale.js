import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The list paths at size. setup() grows the store to SCALE_ROWS contacts (20k
// by default) before the measured window; each iteration then does what a user
// does at that size: a deep, filtered, sorted page of the table, a live-search
// keystroke that matches nothing (the worst case: every row is examined), the
// dashboard, and the JSON API.
//
// Compare it with `list` and `search`, which run on the 20 seeded rows. With
// the filtering, sorting, paging and counting done in SQL the numbers stay in
// the same range; when every request loaded the whole table into Odin they grew
// about a hundredfold (#14).
export const options = Object.assign(build(), { setupTimeout: '300s' });
export const handleSummary = summarize('scale');

const ROWS = parseInt(__ENV.SCALE_ROWS || '20000', 10);
const FORM = { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } };

export function setup() {
  for (let i = 0; i < ROWS; i += 250) {
    const batch = [];
    for (let j = i; j < Math.min(ROWS, i + 250); j++) {
      batch.push(['POST', `${BASE}/contacts`, { name: `Scale ${j}`, email: `scale${j}@example.dev`, role: 'Sales' }, FORM]);
    }
    for (const r of http.batch(batch)) {
      if (r.status !== 200) throw new Error(`setup: POST /contacts returned ${r.status}`);
    }
  }
}

const PAGES = [1, 40, 400, 1400];
const SORTS = ['name', 'email_desc', 'score', 'role_desc'];

export default function () {
  const page = PAGES[Math.floor(Math.random() * PAGES.length)];
  const sort = SORTS[Math.floor(Math.random() * SORTS.length)];
  const res = http.batch([
    ['GET', `${BASE}/contacts?q=scale&status=Invited&sort=${sort}&page=${page}`, null, { tags: { op: 'table' } }],
    ['GET', `${BASE}/search?q=no-such-person`, null, { tags: { op: 'search' } }],
    ['GET', `${BASE}/`, null, { tags: { op: 'dashboard' } }],
    ['GET', `${BASE}/api/search?q=scale+1`, null, { tags: { op: 'api' } }],
  ]);
  for (const r of res) check(r, { 'scale 200': (x) => x.status === 200 });
}
