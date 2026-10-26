import http from 'k6/http';
import { check } from 'k6';
import { BASE, term } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The plain-JSON surface: same filter as /search, but the response goes through
// json.marshal instead of the HTML builder. Isolates marshalling cost and proves
// the service layer stands on its own without HTMX.
export const options = build();
export const handleSummary = summarize('api');

export default function () {
  const q = term();
  const res = http.get(`${BASE}/api/search?q=${encodeURIComponent(q)}`);
  check(res, {
    'api 200': (r) => r.status === 200,
    'api is json': (r) => (r.headers['Content-Type'] || '').includes('json'),
    'api parses': (r) => {
      try {
        return Array.isArray(r.json());
      } catch (_) {
        return false;
      }
    },
  });
}
