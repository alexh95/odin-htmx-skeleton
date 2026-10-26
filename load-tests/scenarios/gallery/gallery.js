import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @gallery @contacts
//
// The gallery as a visitor uses it: both pages, the tab, overlay and toast
// fragments, the email check as you type, and a /forms submit, which creates a
// contact through contacts' store; it's deleted again so the table stays near
// its seed for the run. Per-request names keep the pages, the fragments and the
// writes apart in the summary.
export const options = build();
export const handleSummary = summarize('gallery');

const FORM = { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } };
const TABS = ['overview', 'activity', 'security'];

export default function () {
  for (const p of ['/components', '/forms']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'page 200': (x) => x.status === 200 });
  }
  const tab = TABS[__ITER % TABS.length];
  for (const p of [`/ui/tab/${tab}`, '/ui/modal', '/ui/drawer', '/ui/clear', '/ui/toast?kind=success']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: 'GET /ui/*' } });
    check(r, { 'fragment 200': (x) => x.status === 200 });
  }
  const v = http.post(`${BASE}/validate/email`, { email: `vu${__VU}@example.dev` }, { ...FORM, tags: { name: 'POST /validate/email' } });
  check(v, { 'validate 200': (r) => r.status === 200 });

  const made = http.post(
    `${BASE}/forms/submit`,
    { name: `Gallery ${__VU}-${__ITER}`, email: `g${__VU}-${__ITER}@example.dev`, role: 'Engineer', status: 'Active', score: '50' },
    { ...FORM, tags: { name: 'POST /forms/submit' } },
  );
  check(made, { 'submit 200': (r) => r.status === 200 });
  const id = (made.body || '').match(/saved as #(\d+)/);
  if (id) http.del(`${BASE}/contacts/${id[1]}`, null, { tags: { name: 'DELETE /contacts/:id' } });
}
