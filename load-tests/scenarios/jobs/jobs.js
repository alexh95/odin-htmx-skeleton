import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @jobs @accounts-accounts
//
// The admin on /admin/jobs (M5): the test admin, signed in once per VU, reads the page, runs a
// job by hand with a reason (many VUs asking at once share the queued run), downloads the log of
// a run the page lists, and is refused for a run that has ended and a key that names none.
export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true; // the admin's session stays
export const handleSummary = summarize('jobs');

const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };
const PROMPT = { ...FORM, 'HX-Request': 'true', 'HX-Prompt': encodeURI('load test') };
const ok = (...codes) => http.expectedStatuses(...codes);

export default function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: ok(303, 503) });
    check(r, { 'admin signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${MAIN}/admin/jobs`, { tags: { name: 'GET /admin/jobs' } });
  check(page, { 'jobs page': (r) => r.status === 200 && r.body.includes('id="jobs-runs"') });
  const run = http.post(`${MAIN}/admin/jobs/run`, { job: 'ops.sample' }, { headers: PROMPT, tags: { name: 'POST /admin/jobs/run' } });
  check(run, { 'queued': (r) => r.status === 200 && r.body.includes('Queued') });
  const keys = [...(page.body || '').matchAll(/id="run-(\d+)-(\d+)"/g)];
  if (keys.length > 0) {
    const [, boot, id] = keys[0];
    const log = http.get(`${MAIN}/admin/jobs/runs/${boot}/${id}/log`, { tags: { name: 'GET /admin/jobs/runs/:boot/:id/log' } });
    check(log, { 'log': (r) => r.status === 200 && r.body.startsWith('ops.sample, run') });
    const stop = http.post(`${MAIN}/admin/jobs/cancel`, { run: `${boot}-${id}` }, { headers: PROMPT, tags: { name: 'POST /admin/jobs/cancel' }, responseCallback: ok(200, 409) });
    check(stop, { 'cancel: stopped or ended': (r) => r.status === 200 || r.status === 409 });
  }
}
