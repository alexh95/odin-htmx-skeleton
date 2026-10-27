import http from 'k6/http';
import { check } from 'k6';
import { WebSocket } from 'k6/websockets';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @scripting
//
// The nonce class: its four pages, each with a fresh nonce in its policy and on
// every htmx element; the fragment its demos fetch; the hs-include score; and its
// three streams, each sending the four buttons once (the SSE stream asked to end
// after its event, the socket closed once it has them). The SSE and multipart
// answers end with their connection kept alive, so k6 reuses it; a socket can't
// be, so one opens every tenth iteration: one per iteration left thousands of
// loopback pairs in TIME_WAIT a second, and the client's dials failed for want
// of a port. k6 counts the socket as a ws_session, not an HTTP request.
export const options = build({ 'ws_sessions{phase:load}': ['count>0'] });
export const handleSummary = summarize('scripting');

const WS = BASE.replace(/^http/, 'ws');
const PN = 'AAAAAAAAAAAAAAAAAAAAAA=='; // a page nonce's shape: base64url of 16 bytes

function socket() {
  return new Promise((resolve) => {
    const ws = new WebSocket(`${WS}/scripting/streams/ws?pn=${PN}`, null, { tags: { name: 'GET /scripting/streams/ws' } });
    let got = '';
    ws.onmessage = (e) => { got = e.data; ws.close(); };
    ws.onclose = () => resolve(got);
    ws.onerror = () => resolve(got);
  });
}

export default async function () {
  for (const p of ['/scripting', '/scripting/live', '/scripting/streams', '/scripting/tt']) {
    const r = http.get(`${BASE}${p}`, { tags: { name: `GET ${p}` } });
    check(r, { 'page: nonce policy': (x) => x.status === 200 && (x.headers['Content-Security-Policy'] || '').includes("script-src 'nonce-") });
  }
  const h = http.get(`${BASE}/scripting/hello?v=load`, { tags: { name: 'GET /scripting/hello' } });
  check(h, { 'hello': (r) => r.status === 200 && (r.body || '').includes('hello-load') });
  const s = http.post(`${BASE}/scripting/score`, { score: '3' }, { tags: { name: 'POST /scripting/score' } });
  check(s, { 'score heard': (r) => r.status === 200 && (r.body || '').includes('heard 3 of 4') });
  const e = http.get(`${BASE}/scripting/streams/sse?pn=${PN}&end=1`, { tags: { name: 'GET /scripting/streams/sse' } });
  check(e, { 'sse: the buttons': (r) => r.status === 200 && (r.body || '').includes('id="sse-page"') });
  const m = http.get(`${BASE}/scripting/streams/mp?pn=${PN}`, { tags: { name: 'GET /scripting/streams/mp' } });
  check(m, { 'multipart: the buttons': (r) => r.status === 200 && (r.body || '').includes('id="mp-page"') });
  if (__ITER % 10 === 0) {
    const w = await socket();
    check(w, { 'ws: the buttons': (x) => x.includes('id="ws-page"') });
  }
}
