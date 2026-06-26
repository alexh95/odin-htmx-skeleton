import http from 'k6/http';
import { check } from 'k6';
import { BASE, term } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// A realistic blend: ~90% reads (page loads, live search, JSON) against ~10%
// writes (create + delete). This is the number that best reflects real traffic —
// the pure-endpoint scenarios bound it from either side. Per-request URL tags
// keep the slow writes from hiding inside the fast reads in the summary.
export const options = build();
export const handleSummary = summarize('mixed');

const ID = /hx-delete="\/contacts\/(\d+)"/;

export default function () {
  const roll = Math.random();
  if (roll < 0.1) {
    // write: create then delete, keeping the store steady
    const created = http.post(
      `${BASE}/contacts`,
      { name: `Mix ${__VU}-${__ITER}`, email: `mix${__VU}.${__ITER}@example.com`, role: 'Member' },
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, tags: { op: 'write' } },
    );
    check(created, { 'create 200': (r) => r.status === 200 });
    const m = ID.exec(created.body || '');
    if (m) http.del(`${BASE}/contacts/${m[1]}`, null, { tags: { op: 'write' } });
  } else if (roll < 0.45) {
    const r = http.get(`${BASE}/`, { tags: { op: 'page' } });
    check(r, { 'home 200': (x) => x.status === 200 });
  } else if (roll < 0.75) {
    const r = http.get(`${BASE}/search?q=${encodeURIComponent(term())}`, { tags: { op: 'search' } });
    check(r, { 'search 200': (x) => x.status === 200 });
  } else {
    const r = http.get(`${BASE}/api/search?q=${encodeURIComponent(term())}`, { tags: { op: 'api' } });
    check(r, { 'api 200': (x) => x.status === 200 });
  }
}
