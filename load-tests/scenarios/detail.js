import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// Contact detail drilldown: GET /contacts/:id. Heavier than a list row — a
// repo_get, a derived activity trail, and a same-role scan for related — but no
// full page chrome. Seeded store has ids 1..20.
export const options = build();
export const handleSummary = summarize('detail');

export default function () {
  const id = 1 + Math.floor(Math.random() * 20);
  const res = http.get(`${BASE}/contacts/${id}`);
  check(res, {
    'detail 200': (r) => r.status === 200,
    'detail is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
    'has activity trail': (r) => (r.body || '').includes('Activity'),
  });
}
