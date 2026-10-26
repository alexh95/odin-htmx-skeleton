// S0.7 driver: drain and restart (docs/spikes/S0.7.md), against S0.6's guardlab server.
//
//   node drain.mjs <win|linux> <guardlab binary> [drain|rebind|timeouts] [rounds]
//
// drain: 500 SSE + 500 WebSocket streams, a slowloris, a half-sent body and an idle peer that never
// answers the FIN are open; then SIGTERM (Linux) or /admin/shutdown (Windows has no SIGTERM; the
// route calls the same server_shutdown). Measures signal → exit and what each client got.
// rebind: kill -9 the server and start it again on the same port after 0, 50 and 100 ms, with F-12's
// bind retry on and off.

import { spawn, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import http from 'node:http';
import net from 'node:net';

const [OS, BIN, WHAT = 'drain', ROUNDS = '3'] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let nextPort = 9500 + (OS === 'linux' ? 100 : 0);
const results = [];
const record = (name, pass, extra = '') => {
  results.push({ name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${extra ? '  ' + extra : ''}`);
};

function start(env = {}, port = nextPort++) {
  const all = { PORT: String(port), THREADS: '4', DB_PATH: `drain-${port}.db`, CRASH_FILE: `last-crash-${port}.txt`, ...env };
  let child;
  if (OS === 'linux') {
    const vars = Object.entries({ ...all, BIND_ALL: '1' }).map(([k, v]) => `${k}=${v}`);
    child = spawn('wsl', ['-d', 'Ubuntu-24.04', '--cd', '/root/m0/run', '-e', 'env', ...vars, BIN], { stdio: ['ignore', 'pipe', 'pipe'] });
  } else {
    child = spawn(BIN, [], { env: { ...process.env, ...all }, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  const s = { port, child, out: '', exited: null, exitAt: 0, pid: 0 };
  const onOut = (d) => {
    s.out += d;
    const m = /pid (\d+)/.exec(s.out);
    if (m) s.pid = Number(m[1]);
  };
  child.stdout.on('data', onOut);
  child.stderr.on('data', onOut);
  child.on('exit', (code) => { s.exited = code; s.exitAt = performance.now(); });
  return s;
}

function get(port, path, timeout = 2000) {
  return new Promise((res) => {
    const req = http.get({ host: '127.0.0.1', port, path, agent: false, timeout }, (r) => { r.resume(); r.on('end', () => res(r.statusCode)); });
    req.on('timeout', () => { req.destroy(); res(-1); });
    req.on('error', () => res(0));
  });
}

async function ready(s, tries = 100) {
  for (let i = 0; i < tries; i++) {
    if ((await get(s.port, '/healthz', 500)) === 200) return true;
    if (s.exited !== null) return false;
    await sleep(50);
  }
  return false;
}

function sigterm(s) {
  if (OS === 'linux') spawnSync('wsl', ['-d', 'Ubuntu-24.04', '-e', 'kill', '-TERM', String(s.pid)]);
  else get(s.port, '/admin/shutdown');
}

function sigkill(s) {
  if (OS === 'linux') spawnSync('wsl', ['-d', 'Ubuntu-24.04', '-e', 'kill', '-KILL', String(s.pid)]);
  else spawnSync('taskkill', ['/F', '/PID', String(s.child.pid)]);
}

// An SSE client on a raw socket: records whether a retry: event came, and how the stream ended.
function sse(port) {
  return new Promise((res) => {
    const c = { retry: false, ended: false, opened: false, sock: null };
    const sock = net.connect(port, '127.0.0.1', () => sock.write(`GET /sse HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept: text/event-stream\r\n\r\n`));
    c.sock = sock;
    let buf = '';
    sock.on('data', (d) => {
      buf += d;
      if (!c.opened && buf.includes(': open')) { c.opened = true; res(c); }
      if (/retry: \d+\ndata: restarting/.test(buf)) c.retry = true;
      if (buf.endsWith('0\r\n\r\n')) c.ended = true;
    });
    sock.on('close', () => { c.ended = true; if (!c.opened) res(c); });
    sock.on('error', () => {});
  });
}

// A WebSocket client on a raw socket: records the server's close code.
function ws(port) {
  return new Promise((res) => {
    const c = { code: 0, opened: false, sock: null };
    const key = crypto.randomBytes(16).toString('base64');
    const sock = net.connect(port, '127.0.0.1', () => sock.write(
      `GET /ws HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`));
    c.sock = sock;
    let buf = Buffer.alloc(0), upgraded = false;
    sock.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      if (!upgraded) {
        const i = buf.indexOf('\r\n\r\n');
        if (i < 0) return;
        upgraded = buf.subarray(0, 12).toString() === 'HTTP/1.1 101';
        buf = buf.subarray(i + 4);
        c.opened = upgraded;
        res(c);
      }
      // Server frames are unmasked: find a close frame (opcode 8) and read its code.
      while (buf.length >= 2) {
        const op = buf[0] & 0x0f, len = buf[1] & 0x7f;
        if (buf.length < 2 + len) break;
        if (op === 8 && len >= 2) c.code = buf.readUInt16BE(2);
        buf = buf.subarray(2 + len);
      }
    });
    sock.on('close', () => { if (!c.opened) res(c); });
    sock.on('error', () => {});
  });
}

async function phaseDrain(round) {
  const s = start();
  if (!(await ready(s))) return record(`drain ${round}: server starts`, false, s.out);
  const sses = [], wss = [];
  for (let i = 0; i < 500; i += 50) {
    sses.push(...await Promise.all(Array.from({ length: 50 }, () => sse(s.port))));
    wss.push(...await Promise.all(Array.from({ length: 50 }, () => ws(s.port))));
  }
  // A slowloris: a header line every 2 s, never the end of the headers.
  const slow = net.connect(s.port, '127.0.0.1', () => slow.write('GET /healthz HTTP/1.1\r\nHost: x\r\n'));
  const slowTimer = setInterval(() => slow.write(`X-Slow-${Date.now()}: 1\r\n`), 2000);
  slow.on('error', () => {});
  // A half-sent body: 1000 promised, 500 sent.
  const half = net.connect(s.port, '127.0.0.1', () => half.write('POST /body HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n' + 'x'.repeat(500)));
  half.on('error', () => {});
  // An idle peer that never answers the FIN: one request, then it stops reading and never closes.
  const idle = net.connect(s.port, '127.0.0.1', () => idle.write('GET /healthz HTTP/1.1\r\nHost: x\r\n\r\n'));
  idle.on('data', () => idle.pause());
  idle.on('error', () => {});
  await sleep(1500);
  const stats = await new Promise((r) => http.get({ host: '127.0.0.1', port: s.port, path: '/stats', agent: false }, (x) => { let b = ''; x.on('data', (c) => (b += c)); x.on('end', () => r(b)); }).on('error', () => r('?')));
  const opened = `${sses.filter((c) => c.opened).length} SSE, ${wss.filter((c) => c.opened).length} WS open (server: ${stats})`;

  const t0 = performance.now();
  sigterm(s);
  for (let i = 0; i < 150 && s.exited === null; i++) await sleep(100);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  clearInterval(slowTimer);
  await sleep(300);
  const ws1012 = wss.filter((c) => c.code === 1012).length;
  const sseRetry = sses.filter((c) => c.retry).length;
  record(`drain ${round}: exit within 6 s`, s.exited === 0 && secs <= 6, `exit=${s.exited} after ${secs.toFixed(2)} s; ${opened}`);
  record(`drain ${round}: every WebSocket got 1012`, ws1012 === 500, `${ws1012}/500`);
  record(`drain ${round}: every SSE got a retry: event`, sseRetry === 500, `${sseRetry}/500`);
  for (const c of [...sses, ...wss]) c.sock.destroy();
  slow.destroy(); half.destroy(); idle.destroy();
  if (s.exited === null) sigkill(s);
}

async function phaseRebind() {
  for (const retry of ['3000', '0']) {
    for (const gap of [0, 50, 100]) {
      const port = nextPort++;
      const a = start({ BIND_RETRY_MS: retry }, port);
      if (!(await ready(a))) { record(`rebind: first server starts`, false); continue; }
      // Some traffic, and connections still open at the kill.
      const held = await Promise.all(Array.from({ length: 20 }, () => sse(port)));
      sigkill(a);
      for (let i = 0; i < 50 && a.exited === null; i++) await sleep(20);
      await sleep(gap);
      const b = start({ BIND_RETRY_MS: retry }, port);
      const up = await ready(b, 120);
      const name = `rebind after kill -9, ${gap} ms gap, bind retry ${retry === '0' ? 'off' : '3 s'}`;
      record(name, retry === '0' ? true : up, `${up ? 'serving' : 'not serving'}${b.exited !== null ? ` (exit ${b.exited}: ${/could not listen[^\n]*/.exec(b.out)?.[0] ?? ''})` : ''}`);
      for (const c of held) c.sock.destroy();
      sigkill(b);
      await sleep(200);
    }
  }
}

// F-7's timeouts, enforced by each thread's 1 s sweep: with 2 s header, 3 s idle and 2 s body
// timeouts, a slowloris, an idle keep-alive connection and a stalled body each end within their
// deadline plus one sweep and the 500 ms close delay (the body with a 400, then closed), and the
// server keeps serving.
async function phaseTimeouts() {
  const s = start({ HEADER_TIMEOUT_MS: '2000', IDLE_TIMEOUT_MS: '3000', BODY_TIMEOUT_MS: '2000' });
  if (!(await ready(s))) return record('timeouts: server starts', false, s.out);
  const ended = (sock) => new Promise((res) => { const t0 = performance.now(); let got = '';
    sock.on('data', (d) => (got += d)); sock.on('close', () => res({ ms: performance.now() - t0, got })); sock.on('error', () => {}); });
  const slow = net.connect(s.port, '127.0.0.1', () => slow.write('GET /healthz HTTP/1.1\r\nHost: x\r\n'));
  const slowEnd = ended(slow);
  const idle = net.connect(s.port, '127.0.0.1');
  const idleEnd = ended(idle);
  const body = net.connect(s.port, '127.0.0.1', () => body.write('POST /body HTTP/1.1\r\nHost: x\r\nContent-Length: 100\r\n\r\n' + 'x'.repeat(10)));
  const bodyEnd = ended(body);
  const [a, b, c] = await Promise.all([slowEnd, idleEnd, bodyEnd].map((p) => Promise.race([p, sleep(8000).then(() => ({ ms: Infinity, got: '' }))])));
  record('timeouts: headers never finished, cut by the 2 s header timeout', a.ms >= 1900 && a.ms <= 3600, `${(a.ms / 1000).toFixed(2)} s`);
  record('timeouts: idle connection, cut by the 3 s idle timeout', b.ms >= 2900 && b.ms <= 4600, `${(b.ms / 1000).toFixed(2)} s`);
  record('timeouts: body stalled, 400 after the 2 s body timeout', c.ms >= 1900 && c.ms <= 3600 && c.got.startsWith('HTTP/1.1 400'), `${(c.ms / 1000).toFixed(2)} s, ${c.got.slice(0, 12)}`);
  record('timeouts: still serving', (await get(s.port, '/healthz')) === 200);
  await stopServer(s);
}

async function stopServer(s) {
  sigterm(s);
  for (let i = 0; i < 100 && s.exited === null; i++) await sleep(100);
  if (s.exited === null) sigkill(s);
}

if (WHAT === 'drain') for (let r = 1; r <= Number(ROUNDS); r++) await phaseDrain(r);
if (WHAT === 'timeouts') await phaseTimeouts();
if (WHAT === 'rebind') await phaseRebind();
const failed = results.filter((r) => !r.pass);
console.log(`\n${OS} ${WHAT}: ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
