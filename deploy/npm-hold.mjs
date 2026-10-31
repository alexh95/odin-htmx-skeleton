// The stage 1b hold (PLAN §20.3, §22.3 M3: "1000 SSE through NPM held 1 h with no idle cuts"):
// from a LAN machine, N SSE streams on the lab witness through NPM over HTTPS, opened 50 a
// second, held for the duration with no reconnect, each counting the frames (heartbeats
// included) it gets. Pass: every stream opened, none ended before the end, and every one got a
// frame in each minute (no stream went quiet: idle cuts show as an end, a stall as a quiet minute).
// The witness's per-client stream caps must be lifted for the window (soak.override.yaml).
//
//   node deploy/npm-hold.mjs [--streams 1000] [--minutes 60] [--host odin-htmx-starter]
//
// Prints a line a minute; exits 1 on a FAIL.

import https from 'node:https';

const argv = process.argv.slice(2);
const flag = (name, def) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : def; };
const N = Number(flag('--streams', '1000'));
const MINUTES = Number(flag('--minutes', '60'));
const HOST = `${flag('--host', 'odin-htmx-starter')}.alexh95.com`;
const KEY = `hold${Date.now()}`;

const streams = [];
const opened = () => streams.filter((s) => s.status === 200).length;

function open(i) {
  const s = { i, status: 0, frames: 0, minuteFrames: 0, quietMinutes: 0, ended: 0, why: '' };
  streams.push(s);
  const req = https.get({ host: HOST, path: `/events?t=lab.feed:${KEY}-${i % 50}`, agent: false, headers: { accept: 'text/event-stream' } }, (r) => {
    s.status = r.statusCode;
    if (r.statusCode !== 200) { s.why = `status ${r.statusCode}`; r.resume(); return; }
    r.setEncoding('utf8');
    r.on('data', (c) => { const n = (c.match(/\n\n/g) || []).length; s.frames += n; s.minuteFrames += n; });
    r.on('end', () => { s.ended ||= Date.now(); s.why ||= 'the server ended it'; });
    r.on('error', (e) => { s.ended ||= Date.now(); s.why ||= String(e.code || e); });
  });
  req.on('error', (e) => { s.ended ||= Date.now(); s.why ||= String(e.code || e); });
  s.req = req;
}

const t0 = Date.now();
for (let i = 0; i < N; i++) {
  open(i);
  if (i % 50 === 49) await new Promise((r) => setTimeout(r, 1000));
}
await new Promise((r) => setTimeout(r, 5000));
console.log(`opened ${opened()} of ${N} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);

const end = Date.now() + MINUTES * 60_000;
let minute = 0;
while (Date.now() < end) {
  await new Promise((r) => setTimeout(r, 60_000));
  minute += 1;
  let quiet = 0;
  for (const s of streams) {
    if (s.status === 200 && !s.ended && s.minuteFrames === 0) { s.quietMinutes += 1; quiet += 1; }
    s.minuteFrames = 0;
  }
  const ended = streams.filter((s) => s.ended).length;
  console.log(`minute ${minute}: ${opened() - ended} held, ${ended} ended, ${quiet} quiet this minute, ${streams.reduce((a, s) => a + s.frames, 0)} frames so far`);
}

const ended = streams.filter((s) => s.ended);
const quiet = streams.filter((s) => s.quietMinutes > 0);
const pass = opened() === N && ended.length === 0 && quiet.length === 0;
console.log(`${pass ? 'PASS' : 'FAIL'} hold: ${N} SSE through NPM for ${MINUTES} min: ${opened()} opened, ${ended.length} ended early, ${quiet.length} went quiet for a minute or more`);
for (const s of ended.slice(0, 10)) console.log(`  stream ${s.i}: ${s.why} after ${((s.ended - t0) / 60000).toFixed(1)} min`);
for (const s of streams.filter((s) => s.status !== 200).slice(0, 10)) console.log(`  stream ${s.i}: ${s.why || 'never answered'}`);
for (const s of streams) s.req?.destroy();
process.exit(pass ? 0 : 1);
