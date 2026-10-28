import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @landing
//
// The starter's own page (rendered once at boot) and the init-command builder's fragment,
// one selection that plans and one the generator would refuse.
export const options = build();
export const handleSummary = summarize('landing');

export default function () {
  const page = http.get(`${BASE}/`, { tags: { name: 'GET /' } });
  check(page, { 'page 200': (r) => r.status === 200 && (r.body || '').includes('init-command') });
  const ok = http.get(`${BASE}/landing/command?name=acme&f-contacts=1&f-dashboard=1`, { tags: { name: 'GET /landing/command' } });
  check(ok, { 'planned': (r) => r.status === 200 && (r.body || '').includes('--features contacts,dashboard') });
  const no = http.get(`${BASE}/landing/command?name=acme&f-chat=1&store=sqlite`, { tags: { name: 'GET /landing/command' } });
  check(no, { 'refused': (r) => r.status === 200 && (r.body || '').includes('landing-problems') });
}
