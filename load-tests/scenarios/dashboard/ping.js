import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @dashboard
//
// The dashboard's ping button: a small fragment rendered from the clock, no
// store. The cheapest fragment, so the floor under the others.
export const options = build();
export const handleSummary = summarize('ping');

export default function () {
  const res = http.get(`${BASE}/ui/ping`);
  check(res, { 'ping 200': (r) => r.status === 200 });
}
