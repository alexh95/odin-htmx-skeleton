import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The pages: full-page HTML built by Odin procedures on every request (no
// template cache). `/` also reads the notes list from SQLite; `/about` is the
// shell alone. The gap between these and `static` is the cost of the view + data
// layers. Add a scenario per endpoint as your app grows.
export const options = build();
export const handleSummary = summarize('pages');

export default function () {
  const home = http.get(`${BASE}/`);
  check(home, {
    'home 200': (r) => r.status === 200,
    'home is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });

  const about = http.get(`${BASE}/about`);
  check(about, { 'about 200': (r) => r.status === 200 });
}
