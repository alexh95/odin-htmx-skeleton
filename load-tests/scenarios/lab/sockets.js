import http from 'k6/http';
import { check } from 'k6';
import { WebSocket } from 'k6/websockets';
import { BASE } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @lab
//
// A visit to the room page, then WebSocket round trips, opened and closed every
// iteration: ten messages to the echo, then one room message, which comes back
// through the hub as the room's escaped fragment. k6 counts the page load as the
// iteration's HTTP request (a socket is a ws_session), so the run's RPS is pages.
export const options = build({ 'ws_sessions{phase:load}': ['count>0'] });
export const handleSummary = summarize('sockets');

const WS = BASE.replace(/^http/, 'ws');

function session(path, sends, want) {
  return new Promise((resolve) => {
    const ws = new WebSocket(`${WS}${path}`, null, { tags: { name: `GET ${path.split('?')[0]}` } });
    let got = 0;
    ws.onopen = () => sends(ws);
    ws.onmessage = () => { if (++got === want) ws.close(); };
    ws.onclose = () => resolve(got);
    ws.onerror = () => resolve(got);
  });
}

export default async function () {
  const page = http.get(`${BASE}/lab/streams/chat`, { tags: { name: 'GET /lab/streams/chat' } });
  check(page, { 'room page 200': (r) => r.status === 200 });
  const echoed = await session('/lab/ws/echo', (ws) => { for (let i = 0; i < 10; i++) ws.send(`ping ${i}`); }, 10);
  check(echoed, { 'echo: 10 back': (n) => n === 10 });
  const room = `load-${__VU}`;
  const said = await session(`/lab/ws/chat?room=${room}`, (ws) => ws.send(JSON.stringify({ message: `hi ${__ITER}` })), 1);
  check(said, { 'room: the message back': (n) => n === 1 });
}
