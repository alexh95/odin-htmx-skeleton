import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @about
//
// The about page: the layout around the profile's copy, no store. Close to the
// cost of the page shell alone.
export const options = build();
export const handleSummary = summarize('about');

export default function () {
  const res = http.get(`${BASE}/about`);
  check(res, {
    'about 200': (r) => r.status === 200,
    'about is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });
}
