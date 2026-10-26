import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The contacts table region: GET /contacts with status filter + sort + page —
// the filtered/sorted list render that backs the table swaps (and /data). The
// `pages` scenario covers the full page; this isolates the region fragment with
// the quick-filter and sort variations.
export const options = build();
export const handleSummary = summarize('list');

const STATUS = ['', 'Active', 'Invited', 'Disabled'];
const SORT = ['name', 'score_desc', 'role', 'status'];

export default function () {
  const status = STATUS[Math.floor(Math.random() * STATUS.length)];
  const sort = SORT[Math.floor(Math.random() * SORT.length)];
  const res = http.get(`${BASE}/contacts?status=${status}&sort=${sort}&page=1`);
  check(res, {
    'list 200': (r) => r.status === 200,
    'list is html': (r) => (r.headers['Content-Type'] || '').includes('html'),
  });
}
