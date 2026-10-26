// The request-path drills and budgets (PLAN §19.1.9 tier 1, §19.1.10, §18.4), for one profile.
//
//   node tools/drills/drills.mjs <profile> [phase …] [--wsl DIR]
//
// Phases (default: all): release pure dirty burst hang malformed shutdown restart fdceiling budgets.
// It builds the profile twice through build.{sh,bat}: a TEST_ROUTES build, which mounts
// /__test/crash/<kind> and /__test/shutdown (platform/web/drills.odin), and the release build at
// -o:speed, which must answer 404 there and is the one the budgets measure. Every server is fresh,
// on a port nothing else listens on.
//
// --wsl DIR runs the servers inside WSL instead, from a checkout at DIR (built there first), with
// BIND_ALL=1 so Windows' loopback reaches them: the Linux leg from a Windows host that has no node
// in WSL. Signals go through `wsl kill`; native Windows has no SIGTERM to send a child, so the
// shutdown drill uses /__test/shutdown there, which starts the same drain.
//
// Prints PASS/FAIL per check; exits 1 on any FAIL.

import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, statSync } from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const wslAt = argv.indexOf('--wsl');
const WSL = wslAt >= 0 ? argv.splice(wslAt, 2)[1] : '';
const [PROFILE, ...PHASES] = argv;
if (!PROFILE) {
  console.error('usage: node tools/drills/drills.mjs <profile> [phase …] [--wsl DIR]');
  process.exit(2);
}
const WIN = process.platform === 'win32' && !WSL;
const LINUX = !WIN;
const EXE = WIN ? '.exe' : '';
const ALL = ['release', 'pure', 'dirty', 'burst', 'hang', 'malformed', 'shutdown', 'restart', 'fdceiling', 'budgets'];
const phases = PHASES.length ? PHASES : ALL;

// PLAN §18.4 (ANSWERS round 7): binaries in MiB, Windows -o:speed, as CI reads them; idle memory
// is 6 MB plus 0.4 MB per event loop (each has its log buffer, counters and io ring).
const MiB = 1024 * 1024;
const BUDGET = {
  size: { minimal: 1.5 * MiB, skeleton: 2.75 * MiB },
  idle: (loops) => 6e6 + 0.4e6 * loops,
  readyMs: 50,
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const record = (name, pass, extra = '') => {
  results.push({ name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${extra ? '  ' + extra : ''}`);
};

// ---- builds -------------------------------------------------------------------------

function build(out, ...flags) {
  let r;
  if (WSL) {
    r = spawnSync('wsl', ['--cd', WSL, '-e', 'env', `OUT=${out}`, 'sh', 'build.sh', PROFILE, ...flags], { stdio: 'inherit' });
  } else if (WIN) {
    r = spawnSync('cmd', ['/c', path.join(ROOT, 'build.bat'), PROFILE, ...flags], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, OUT: out } });
  } else {
    r = spawnSync('sh', ['build.sh', PROFILE, ...flags], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, OUT: out } });
  }
  if (r.status !== 0) throw new Error(`build ${out} failed`);
}

const DRILL_BIN = `app/bin/${PROFILE}-drills${EXE}`;
const RELEASE_BIN = `app/bin/${PROFILE}-release${EXE}`;

// ---- servers ------------------------------------------------------------------------

let nextPort = 9700 + (LINUX ? 100 : 0);

// netstat lists every socket (the state last); ss -ltn only listening ones.
function listening(port) {
  if (WIN) {
    const out = spawnSync('netstat', ['-an', '-p', 'tcp'], { encoding: 'utf8' }).stdout || '';
    return new RegExp(`[:.]${port}\\s.*LISTENING`).test(out);
  }
  const out = spawnSync(WSL ? 'wsl' : 'ss', WSL ? ['-e', 'ss', '-ltn'] : ['-ltn'], { encoding: 'utf8' }).stdout || '';
  return new RegExp(`[:.]${port}\\s`).test(out);
}

function freePort() {
  while (listening(nextPort)) nextPort++;
  return nextPort++;
}

// A server, fresh: its output, exit code and exit time are kept. An empty env value means unset.
function start(bin, env = {}, port = freePort(), { ulimit = 0 } = {}) {
  const all = Object.fromEntries(Object.entries({
    PORT: String(port), THREADS: '4', LOG_LEVEL: 'info', CRASH_FILE: `app/build/last-crash-${port}.txt`, ...env,
  }).filter(([, v]) => v !== ''));
  let child;
  if (WSL || LINUX) {
    const vars = Object.entries({ ...all, ...(WSL ? { BIND_ALL: '1' } : {}) }).map(([k, v]) => `${k}=${v}`);
    // `echo $$` then exec: the first line is the server's own pid, for kill.
    const script = `${ulimit ? `ulimit -n ${ulimit}; ` : ''}echo pid $$; exec env ${vars.join(' ')} ${bin}`;
    child = WSL
      ? spawn('wsl', ['--cd', WSL, '-e', 'sh', '-c', script], { stdio: ['ignore', 'pipe', 'pipe'] })
      : spawn('sh', ['-c', script], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
  } else {
    const base = { ...process.env };
    for (const k of Object.keys(env)) if (env[k] === '') delete base[k];
    child = spawn(path.join(ROOT, bin), [], { cwd: ROOT, env: { ...base, ...all }, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  const s = { port, child, out: '', exited: null, exitAt: 0, pid: WIN ? child.pid : 0, startAt: performance.now() };
  const onOut = (d) => {
    s.out += d;
    if (!s.pid) { const m = /^pid (\d+)/m.exec(s.out); if (m) s.pid = Number(m[1]); }
  };
  child.stdout.on('data', onOut);
  child.stderr.on('data', onOut);
  child.on('exit', (code) => { s.exited = code; s.exitAt = performance.now(); });
  return s;
}

function signal(s, sig) {
  if (WSL) spawnSync('wsl', ['-e', 'kill', `-${sig}`, String(s.pid)]);
  else if (LINUX) process.kill(s.pid, `SIG${sig}`);
  else if (sig === 'KILL') spawnSync('taskkill', ['/F', '/PID', String(s.pid)]);
  else throw new Error(`no SIG${sig} on Windows`);
}

async function waitExit(s, ms) {
  for (let t = 0; t < ms && s.exited === null; t += 50) await sleep(50);
  return s.exited;
}

async function stop(s) {
  if (s.exited !== null) return;
  signal(s, 'KILL');
  await waitExit(s, 3000);
}

function get(port, p, { timeout = 3000, headers = {} } = {}) {
  return new Promise((res) => {
    const req = http.get({ host: '127.0.0.1', port, path: p, agent: false, timeout, headers }, (r) => {
      let body = '';
      r.setEncoding('utf8');
      r.on('data', (c) => (body += c));
      r.on('end', () => res({ status: r.statusCode, body }));
      r.on('error', () => res({ status: 0, body: '' }));
    });
    req.on('timeout', () => { req.destroy(); res({ status: -1, body: 'timeout' }); });
    req.on('error', (e) => res({ status: 0, body: String(e.code) }));
  });
}

async function ready(s, path_ = '/readyz') {
  for (let i = 0; i < 400; i++) {
    if ((await get(s.port, path_, { timeout: 500 })).status === 200) return true;
    if (s.exited !== null) break;
    await sleep(10);
  }
  console.log(s.out.slice(-2000));
  return false;
}

// The build's features: the sqlite drill exists only where the store is SQLite.
function features() {
  const r = WSL
    ? spawnSync('wsl', ['--cd', WSL, '-e', RELEASE_BIN, '--features', '--json'], { encoding: 'utf8' })
    : spawnSync(path.join(ROOT, RELEASE_BIN), ['--features', '--json'], { encoding: 'utf8' });
  return JSON.parse(r.stdout);
}

// ---- phases -------------------------------------------------------------------------

const PURE = ['panic', 'bounds', 'div', 'nil', 'stack'];

async function phaseRelease() {
  const s = start(RELEASE_BIN);
  if (!(await ready(s))) return record('release: server starts', false);
  const crash = await get(s.port, '/__test/crash/panic');
  const shut = await get(s.port, '/__test/shutdown');
  record('release: /__test/* answers 404 without TEST_ROUTES', crash.status === 404 && shut.status === 404 && s.exited === null,
    `crash=${crash.status} shutdown=${shut.status}`);
  await stop(s);
}

async function phasePure() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('pure: server starts', false);
  for (const kind of PURE) {
    // The crash and 20 bystanders on their own connections, at once.
    const [crash, ...by] = await Promise.all([
      get(s.port, `/__test/crash/${kind}`),
      ...Array.from({ length: 20 }, (_, i) => get(s.port, i % 2 ? '/about' : '/healthz')),
    ]);
    const ok = by.filter((r) => r.status === 200).length;
    const alive = (await get(s.port, '/livez')).status === 200;
    record(`pure ${kind}: 500, ${ok}/20 bystanders, still serving`, crash.status === 500 && ok === 20 && alive && s.exited === null,
      `crash=${crash.status}`);
  }
  const lines = s.out.split('\n').filter((l) => l.includes('ev=crash') && l.includes('route="GET /__test/crash/(%a+)"')).length;
  record('pure: one crash line per crash, naming the route', lines === PURE.length, `${lines} lines`);
  await stop(s);
}

async function phaseDirty(f) {
  const kinds = ['lock', 'async', ...(f.store === 'sqlite' ? ['sqlite'] : [])];
  for (const kind of kinds) {
    const s = start(DRILL_BIN);
    if (!(await ready(s))) { record(`dirty ${kind}: server starts`, false); continue; }
    const t0 = performance.now();
    const [crash] = await Promise.all([
      get(s.port, `/__test/crash/${kind}`, { timeout: 8000 }),
      ...Array.from({ length: 5 }, () => get(s.port, '/about', { timeout: 8000 })),
    ]);
    await waitExit(s, 8000);
    const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
    const why = /zone=dirty[^\n]*why="([^"]+)"/.exec(s.out)?.[1] ?? '';
    record(`dirty ${kind}: drains and exits 70 within 6 s`, s.exited === 70 && secs <= 6,
      `crash=${crash.status} exit=${s.exited} after ${secs.toFixed(2)} s ${why}`);
    await stop(s);
  }
  if (f.store !== 'sqlite') {
    const s = start(DRILL_BIN);
    if (await ready(s)) {
      const r = await get(s.port, '/__test/crash/sqlite');
      record(`dirty sqlite: no such drill in a ${f.store} build (404)`, r.status === 404, `status=${r.status}`);
    }
    await stop(s);
  }
}

// More than the burst limit of pure recoveries in a minute counts as dirty: each one leaks what
// its callback allocated.
async function phaseBurst() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('burst: server starts', false);
  let n = 0;
  for (; n < 150 && s.exited === null; n++) await get(s.port, '/__test/crash/bounds');
  await waitExit(s, 8000);
  record('burst: the recovery past the limit within a minute exits 70', s.exited === 70 && /why="too many recoveries"/.test(s.out),
    `exit=${s.exited} after ${n} crash requests`);
  await stop(s);
}

async function phaseHang() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('hang: server starts', false);
  const t0 = performance.now();
  get(s.port, '/__test/crash/hang?s=15', { timeout: 20000 });
  await waitExit(s, 14000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  const named = /ev=watchdog[^\n]*id=\S+[^\n]*route="GET \/__test\/crash\/\(%a\+\)"/.test(s.out);
  record('hang: the watchdog exits 70 within 11 s and names the route and request', s.exited === 70 && secs <= 11 && named,
    `exit=${s.exited} after ${secs.toFixed(2)} s, named=${named}`);
  await stop(s);
}

// Tier 1 of the fuzz plan (PLAN §19.1.9): 10k malformed requests, raw, each on its own socket.
const MALFORMED = [
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 9223372036854775808\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 18446744073709551617\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\nhello',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1_0\r\n\r\n0123456789',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0x5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\nhello',
  'OPTIONS * HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: -5\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n-5\r\nhello\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffffff\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n',
  // F-14: chunk data not followed by CRLF, a trailer field (on a write and on a GET, whose unread
  // body the response drains), and chunk sizes with a sign, a separator or past 64 bits.
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\nX-Trailer: 1\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nX-Trailer: 1\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n+5\r\nhello\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n1_0\r\n0123456789abcdef\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n8000000000000005\r\nhello\r\n0\r\n\r\n',
  // F-16: one-byte chunks by the thousand, under both caps on a write (12k overflowed a Windows loop's
  // stack before the scan trampoline, M1-17) and past them on a GET's drain; a size line past 4 KiB
  // (M1-18); a trailer line past it (M1-19); a bare LF and trailing whitespace in framing (M1-20).
  'POST /contacts HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n' + '1\r\na\r\n'.repeat(12000) + '0\r\n\r\n',
  'GET /healthz HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n' + '1\r\na\r\n'.repeat(50000) + '0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n1;' + 'x'.repeat(5000) + '\r\na\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n0\r\nX-T: ' + 'y'.repeat(5000) + '\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\nhello\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5  \r\nhello\r\n0\r\n\r\n',
  'GET / HTTP/1.1\r\n\r\n',
  'GET / HTTP/2.0\r\nHost: x\r\n\r\n',
  'GET /' + 'a'.repeat(9000) + ' HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nX: ' + 'b'.repeat(9000) + '\r\n\r\n',
  'BREW / HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nbad header line\r\n\r\n',
  '\r\n\r\n\r\n',
  '\x00\x01\x02\xff\xfe GET / HTTP/1.1\r\n\r\n',
  'GET /static/../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET /about?%zz=%ff%00 HTTP/1.1\r\nHost: x\r\n\r\n',
  'POST /about HTTP/1.1\r\nHost: x\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 9\r\n\r\n%%%&&==%%',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhel', // half a body, then gone
];

function raw(port, payload) {
  return new Promise((res) => {
    const sock = net.connect(port, '127.0.0.1');
    let got = '';
    sock.setTimeout(2000, () => sock.destroy());
    sock.on('connect', () => { sock.write(Buffer.from(payload, 'latin1')); sock.end(); });
    sock.on('data', (d) => (got += d));
    sock.on('close', () => res(got.slice(0, 12)));
    sock.on('error', () => res('ERR'));
  });
}

async function phaseMalformed() {
  const s = start(RELEASE_BIN);
  if (!(await ready(s))) return record('malformed: server starts', false);
  const N = 10000, PAR = 50, codes = {};
  for (let i = 0; i < N && s.exited === null; i += PAR) {
    const batch = await Promise.all(Array.from({ length: PAR }, (_, j) => raw(s.port, MALFORMED[(i + j) % MALFORMED.length])));
    for (const b of batch) { const k = b.slice(9, 12) || 'none'; codes[k] = (codes[k] || 0) + 1; }
  }
  const alive = (await get(s.port, '/livez')).status === 200 && s.exited === null;
  record(`malformed: ${N} requests, /livez 200 after, 0 deaths`, alive, JSON.stringify(codes));
  await stop(s);
}

// The shutdown bound (PLAN §8.7): a slowloris, a half-sent body, an idle peer that never answers
// the FIN and 50 idle keep-alive connections are open; a signal must still end it in 6 s, exit 0.
async function phaseShutdown() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('shutdown: server starts', false);
  const socks = [];
  const open = (fn) => { const c = net.connect(s.port, '127.0.0.1', () => fn(c)); c.on('error', () => {}); socks.push(c); return c; };
  const slow = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n'));
  const slowTimer = setInterval(() => slow.write(`X-Slow-${Date.now()}: 1\r\n`), 1000);
  open((c) => c.write('POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n' + 'x'.repeat(500)));
  const idle = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n\r\n'));
  idle.on('data', () => idle.pause());
  for (let i = 0; i < 50; i++) open((c) => c.write('GET /livez HTTP/1.1\r\nHost: x\r\n\r\n'));
  await sleep(1000);
  const t0 = performance.now();
  if (WIN) get(s.port, '/__test/shutdown');
  else signal(s, 'TERM');
  await waitExit(s, 9000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  clearInterval(slowTimer);
  for (const c of socks) c.destroy();
  record('shutdown: a signal with slow, half-sent and idle peers open exits 0 within 6 s', s.exited === 0 && secs <= 6,
    `exit=${s.exited} after ${secs.toFixed(2)} s${WIN ? ' (/__test/shutdown)' : ' (SIGTERM)'}`);
  await stop(s);
}

// kill -9, then the next server on the same port after 0, 50 and 100 ms: F-12's bind retry.
async function phaseRestart() {
  for (const delay of [0, 50, 100]) {
    const port = freePort();
    const a = start(RELEASE_BIN, {}, port);
    if (!(await ready(a))) { record(`restart +${delay} ms: first server starts`, false); continue; }
    await get(port, '/about');
    signal(a, 'KILL');
    await waitExit(a, 3000);
    await sleep(delay);
    const b = start(RELEASE_BIN, {}, port);
    const ok = await ready(b);
    record(`restart: kill -9, then a new server on the port after ${delay} ms`, ok, ok ? '' : b.out.slice(-300));
    await stop(b);
  }
}

// Past the open-file limit, keep-alive connections get the cap's 503, not a stalled accept: a
// fresh request still has an answer within 100 ms, and /livez is 200 once they go (Linux only:
// the limit is a ulimit).
async function phaseFdCeiling() {
  if (WIN) return record('fdceiling: Linux only (a ulimit)', true, 'skipped on Windows');
  const s = start(RELEASE_BIN, {}, freePort(), { ulimit: 256 });
  if (!(await ready(s))) return record('fdceiling: server starts under ulimit -n 256', false);
  const socks = [];
  const statuses = {};
  await Promise.all(Array.from({ length: 400 }, () => new Promise((res) => {
    const c = net.connect(s.port, '127.0.0.1', () => c.write('GET /livez HTTP/1.1\r\nHost: x\r\n\r\n'));
    let got = '';
    c.on('data', (d) => { got += d; const k = got.slice(9, 12); if (k) { statuses[k] = (statuses[k] || 0) + 1; res(); } });
    c.on('error', () => { statuses.err = (statuses.err || 0) + 1; res(); });
    c.on('close', () => res());
    socks.push(c);
  })));
  const t0 = performance.now();
  const r = await get(s.port, '/livez', { timeout: 1000 });
  const ms = performance.now() - t0;
  for (const c of socks) c.destroy();
  await sleep(500);
  const after = (await get(s.port, '/livez')).status;
  record('fdceiling: 400 keep-alive connections under ulimit -n 256: an answer within 100 ms, 200 after',
    r.status > 0 && ms < 100 && after === 200 && s.exited === null,
    `while full: ${r.status} in ${ms.toFixed(1)} ms; per connection ${JSON.stringify(statuses)}; after: ${after}`);
  await stop(s);
}

function rss(s) {
  if (WIN) {
    const r = spawnSync('powershell', ['-NoProfile', '-Command', `(Get-Process -Id ${s.pid}).WorkingSet64`], { encoding: 'utf8' });
    return Number(r.stdout.trim());
  }
  const r = WSL
    ? spawnSync('wsl', ['-e', 'cat', `/proc/${s.pid}/status`], { encoding: 'utf8' })
    : { stdout: readFileSync(`/proc/${s.pid}/status`, 'utf8') };
  return Number(/VmRSS:\s+(\d+) kB/.exec(r.stdout)?.[1] ?? 0) * 1024;
}

async function phaseBudgets() {
  // Boot → /readyz, from the spawn, with the default loop count: the median of 5. Through WSL
  // the spawn costs wsl.exe's own start (about 0.7 s), so there the server's boot_ms counts.
  const times = [];
  for (let i = 0; i < 5; i++) {
    const s = start(RELEASE_BIN, { THREADS: '', LOG_LEVEL: 'info' });
    let ms = Infinity;
    for (let t = 0; t < 2000; t++) {
      if ((await get(s.port, '/readyz', { timeout: 200 })).status === 200) { ms = performance.now() - s.startAt; break; }
      if (s.exited !== null) break;
      await sleep(2);
    }
    if (WSL) ms = Number(/boot_ms=(\d+)/.exec(s.out)?.[1] ?? Infinity);
    times.push(ms);
    await stop(s);
  }
  times.sort((a, b) => a - b);
  const boot = times[2];
  record(`budgets: boot → /readyz ≤ ${BUDGET.readyMs} ms (median of 5, ${WSL ? "the server's boot_ms" : 'from the spawn'})`,
    boot <= BUDGET.readyMs, `${times.map((t) => t.toFixed(0)).join(' ')} ms`);

  // Idle memory, the default loop count, after a page, an asset and 3 s.
  const s = start(RELEASE_BIN, { THREADS: '', LOG_LEVEL: 'warn' });
  if (await ready(s)) {
    for (const p of ['/', '/about', '/static/app.css']) await get(s.port, p);
    await sleep(3000);
    const bytes = rss(s);
    const loops = Number(/\((\d+) threads?\)/.exec(s.out)?.[1] ?? os.availableParallelism());
    const cap = BUDGET.idle(loops);
    record(`budgets: idle ${WIN ? 'working set' : 'RSS'} ≤ ${(cap / 1e6).toFixed(1)} MB (6 + 0.4 × ${loops} loops)`,
      bytes > 0 && bytes <= cap, `${(bytes / 1e6).toFixed(2)} MB`);
  }
  await stop(s);

  // Size: the budget is Windows -o:speed's; elsewhere it's reported only.
  const bin = WSL ? null : path.join(ROOT, RELEASE_BIN);
  const size = bin && existsSync(bin) ? statSync(bin).size : 0;
  const cap = BUDGET.size[PROFILE];
  if (WIN && cap) record(`budgets: binary ≤ ${cap / MiB} MiB (Windows -o:speed)`, size <= cap, `${size} B`);
  else if (size) console.log(`info  budgets: binary ${size} B (the size budget is Windows')`);
}

// ---- run ----------------------------------------------------------------------------

build(DRILL_BIN, '-define:TEST_ROUTES=true');
build(RELEASE_BIN, '-o:speed');
const f = features();
console.log(`${PROFILE} on ${WSL ? 'Linux (WSL)' : process.platform}: store ${f.store}; phases: ${phases.join(' ')}`);
const PH = {
  release: phaseRelease, pure: phasePure, dirty: () => phaseDirty(f), burst: phaseBurst, hang: phaseHang,
  malformed: phaseMalformed, shutdown: phaseShutdown, restart: phaseRestart, fdceiling: phaseFdCeiling, budgets: phaseBudgets,
};
for (const p of phases) {
  if (!PH[p]) { console.error(`unknown phase ${p}`); process.exit(2); }
  await PH[p]();
}
const failed = results.filter((r) => !r.pass);
console.log(`\n${PROFILE} (${WSL ? 'linux' : process.platform}): ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
