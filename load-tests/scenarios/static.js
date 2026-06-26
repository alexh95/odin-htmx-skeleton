import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// Best case: serving embedded bytes from memory. No HTML build, no store touch —
// this is the server's ceiling, the number every other scenario is measured
// against. Hits the two assets a real page actually pulls.
export const options = build();
export const handleSummary = summarize('static');

export default function () {
  const css = http.get(`${BASE}/static/app.css`);
  check(css, { 'css 200': (r) => r.status === 200 });

  const js = http.get(`${BASE}/static/htmx.min.js`);
  check(js, { 'htmx 200': (r) => r.status === 200 });
}
