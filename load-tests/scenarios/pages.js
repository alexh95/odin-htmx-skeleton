import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// Full-page HTML built by Odin procedures on every request (no template cache).
// `/` is the dashboard; `/data` additionally runs filter+sort+paginate over the
// store and renders a table — the heaviest read page. The gap between this and
// `static` is the cost of the view layer.
export const options = build();
export const handleSummary = summarize('pages');

export default function () {
  const home = http.get(`${BASE}/`);
  check(home, {
    'home 200': (r) => r.status === 200,
    'home is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });

  const data = http.get(`${BASE}/data`);
  check(data, { 'data 200': (r) => r.status === 200 });
}
