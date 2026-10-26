import http from 'k6/http';
import { check } from 'k6';
import { BASE, term } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The HTMX live-search fragment: filter the store by a query and render the
// matching rows (the markup HTMX swaps into the page as you type). Exercises the
// service-layer match + the fragment builder, minus the full page chrome.
export const options = build();
export const handleSummary = summarize('search');

export default function () {
  const q = term();
  const res = http.get(`${BASE}/search?q=${encodeURIComponent(q)}`);
  check(res, {
    'search 200': (r) => r.status === 200,
    'search is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });
}
