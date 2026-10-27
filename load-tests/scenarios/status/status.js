import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @status
//
// A visitor's status page in both modes: the page, its multipart/parallel board (a part per
// probe, then the end), and the poll with its tag (304 while no state changed).
export const options = build();
export const handleSummary = summarize('status');

export default function () {
  const poll = __ITER % 2 === 1;
  const page = http.get(`${BASE}/status${poll ? '?mode=poll' : ''}`, { tags: { name: 'GET /status' } });
  check(page, { 'status page 200': (r) => r.status === 200 });
  const parts = http.get(`${BASE}/status/parts`, { tags: { name: 'GET /status/parts' } });
  check(parts, { 'parts: the probes': (r) => r.status === 200 && r.body.includes('HX-Target: #st-process') });
  const board = http.get(`${BASE}/status/board`, { tags: { name: 'GET /status/board' } });
  check(board, { 'board and a tag': (r) => r.status === 200 && r.headers['Hx-Ptag'] !== undefined });
  const again = http.get(`${BASE}/status/board`, { headers: { 'HX-PTag': board.headers['Hx-Ptag'] || '0' }, tags: { name: 'GET /status/board' }, responseCallback: http.expectedStatuses(200, 304) });
  check(again, { 'board again: 304': (r) => r.status === 304 || r.status === 200 });
}
