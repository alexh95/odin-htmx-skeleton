import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @home
//
// The home page: the profile's copy over one card per feature that offers one
// (the notes card reads its newest notes from the store). The gap between this
// and `static` is the cost of the view and the store's read.
export const options = build();
export const handleSummary = summarize('home');

export default function () {
  const res = http.get(`${MAIN}/`);
  check(res, {
    'home 200': (r) => r.status === 200,
    'home is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });
}
