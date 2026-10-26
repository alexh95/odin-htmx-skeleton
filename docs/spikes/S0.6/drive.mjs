// S0.6 driver: the guard in the fork, and the watchdog (docs/spikes/S0.6.md).
//
//   node drive.mjs <win|linux> <guardlab binary> [phase ...]
//
// phases: pure dirty burst wal malformed watchdog (default: all). For linux, the binary is a path inside
// WSL and the server is started through `wsl -e`; it binds 0.0.0.0, which WSL forwards to Windows'
// loopback. Every server is fresh and runs in its own working directory (the DB and last-crash.txt).

import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';

const [OS, BIN, ...PHASES] = process.argv.slice(2);
const phases = PHASES.length ? PHASES : ['pure', 'dirty', 'burst', 'wal', 'malformed', 'watchdog'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let nextPort = 9300 + (OS === 'linux' ? 100 : 0);
const results = [];
const record = (name, pass, extra = '') => {
  results.push({ name, pass, extra });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${extra ? '  ' + extra : ''}`);
};

function start(env = {}) {
  const port = nextPort++;
  const all = { PORT: String(port), THREADS: '4', DB_PATH: `guardlab-${port}.db`, CRASH_FILE: `last-crash-${port}.txt`, ...env };
  let child;
  if (OS === 'linux') {
    const vars = Object.entries({ ...all, BIND_ALL: '1' }).map(([k, v]) => `${k}=${v}`);
    child = spawn('wsl', ['-d', 'Ubuntu-24.04', '--cd', '/root/m0/run', '-e', 'env', ...vars, BIN], { stdio: ['ignore', 'pipe', 'pipe'] });
  } else {
    child = spawn(BIN, [], { env: { ...process.env, ...all }, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  const s = { port, child, out: '', exited: null, exitAt: 0 };
  child.stdout.on('data', (d) => (s.out += d));
  child.stderr.on('data', (d) => (s.out += d));
  child.on('exit', (code) => { s.exited = code; s.exitAt = performance.now(); });
  return s;
}

function get(port, path, { method = 'GET', timeout = 3000, agent = false } = {}) {
  return new Promise((res) => {
    const req = http.request({ host: '127.0.0.1', port, path, method, agent, timeout }, (r) => {
      let body = '';
      r.setEncoding('utf8');
      r.on('data', (c) => (body += c));
      r.on('end', () => res({ status: r.statusCode, body }));
      r.on('error', () => res({ status: 0, body: '' }));
    });
    req.on('timeout', () => { req.destroy(); res({ status: -1, body: 'timeout' }); });
    req.on('error', (e) => res({ status: 0, body: String(e.code) }));
    req.end();
  });
}

async function ready(s) {
  for (let i = 0; i < 100; i++) {
    if ((await get(s.port, '/healthz', { timeout: 500 })).status === 200) return true;
    await sleep(50);
  }
  console.log(s.out);
  return false;
}

async function stop(s) {
  if (s.exited !== null) return;
  await get(s.port, '/admin/shutdown');
  for (let i = 0; i < 100 && s.exited === null; i++) await sleep(100);
  if (s.exited === null) s.child.kill('SIGKILL');
}

const PURE = ['assert', 'panic', 'ensure', 'bounds', 'slice', 'enum_index', 'type_assert', 'int_div_zero',
  'int_mod_zero', 'nil_deref', 'nil_write', 'stack_overflow', 'stack_overflow_again'];
const DIRTY = ['lock', 'rwlock', 'async', 'sqlite'];

async function phasePure() {
  const s = start();
  if (!(await ready(s))) return record('pure: server starts', false);
  for (const kind of PURE) {
    // The crash and 20 bystanders on their own connections, all at once.
    const [crash, ...by] = await Promise.all([
      get(s.port, `/crash/${kind}`),
      ...Array.from({ length: 20 }, (_, i) => get(s.port, i % 2 ? '/ui/ping' : '/r')),
    ]);
    const ok = by.filter((r) => r.status === 200).length;
    const alive = (await get(s.port, '/healthz')).status === 200;
    record(`pure ${kind}: 500 + ${ok}/20 bystanders, still serving`, crash.status === 500 && ok === 20 && alive && s.exited === null,
      `crash=${crash.status}`);
  }
  const lines = s.out.split('\n').filter((l) => l.includes('ev=crash')).length;
  record('pure: one crash line per crash', lines === PURE.length, `${lines} lines`);
  await stop(s);
}

async function phaseDirty() {
  for (const kind of DIRTY) {
    const s = start();
    if (!(await ready(s))) { record(`dirty ${kind}: server starts`, false); continue; }
    const t0 = performance.now();
    const [crash] = await Promise.all([
      get(s.port, `/crash/${kind}`),
      ...Array.from({ length: 5 }, () => get(s.port, '/r', { timeout: 8000 })),
    ]);
    for (let i = 0; i < 100 && s.exited === null; i++) await sleep(100);
    const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
    record(`dirty ${kind}: exit 70 within 6 s`, s.exited === 70 && secs <= 6,
      `crash=${crash.status} exit=${s.exited} after ${secs.toFixed(2)} s; ${/zone=dirty why="([^"]+)"/.exec(s.out)?.[1] ?? ''}`);
    if (s.exited === null) s.child.kill('SIGKILL');
  }
}

// The WAL check. Readers that are always busy starve every checkpoint whatever the reset does
// (12 §3.3), so the run has three steps: 1000 crashes mid-iteration while writes go on; one read
// on every loop's reader (the reset is pulled: it happens on the reader's next use); then writes
// only. With the reset the WAL file stops growing (checkpoints complete and the file is reused);
// without it, the abandoned statements keep their snapshots and it grows with every write.
async function walRun(env, label) {
  const s = start(env);
  if (!(await ready(s))) return record(`wal ${label}: server starts`, false);
  const walMB = async () => Number((await get(s.port, '/wal')).body.split(' ')[0]) / 1048576;
  let writes = 0, stopWriting = false;
  const writer = (async () => {
    const agent = new http.Agent({ keepAlive: true, maxSockets: 4 });
    while (!stopWriting) {
      await Promise.all(Array.from({ length: 4 }, () => get(s.port, '/w', { method: 'POST', agent })));
      writes += 4;
    }
  })();
  let crashes = 0;
  for (let i = 0; i < 1000; i += 10) {
    const r = await Promise.all(Array.from({ length: 10 }, () => get(s.port, '/crash/iter')));
    crashes += r.filter((x) => x.status === 500).length;
  }
  const afterCrashes = await walMB();
  // One read per loop: new connections land on every loop (Linux spreads them; Windows has one).
  await Promise.all(Array.from({ length: 64 }, () => get(s.port, '/r')));
  console.log('  /wal after the reads:', (await get(s.port, '/wal')).body);
  const steady = [];
  for (let i = 0; i < 6; i++) { await sleep(1000); steady.push(await walMB()); }
  console.log('  /wal at the end:', (await get(s.port, '/wal')).body);
  stopWriting = true;
  await writer;
  const alive = s.exited === null;
  console.log(`  wal ${label}: ${crashes} crashes, ${writes} writes; WAL ${afterCrashes.toFixed(1)} MB after the crashes, then ${steady.map((x) => x.toFixed(1)).join(' ')} MB at 1 s steps`);
  await stop(s);
  return { growth: steady.at(-1) - steady[0], last: steady.at(-1), crashes, alive };
}

async function phaseWal() {
  const reset = await walRun({ GUARD_BURST: '5000' }, 'with the pulled reset');
  const none = await walRun({ GUARD_BURST: '5000', NO_RESET: '1' }, 'without it (NO_RESET=1)');
  if (!reset || !none) return;
  record('wal: flat after 1000 pure traps mid-iteration (the reader-statement reset)',
    reset.crashes === 1000 && reset.alive && reset.growth <= 1 && none.growth > 4 * reset.growth + 1,
    `growth over 5 s of writes: ${reset.growth.toFixed(1)} MB with the reset, ${none.growth.toFixed(1)} MB without`);
}

// 10k malformed requests, raw, each on its own socket: none may kill the server.
const MALFORMED = [
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 9223372036854775808\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 18446744073709551617\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\nhello',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1_0\r\n\r\n0123456789',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0x5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\nhello',
  'OPTIONS * HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'POST /body HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: -5\r\n\r\n',
  'POST /body HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n-5\r\nhello\r\n0\r\n\r\n',
  'POST /body HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffffff\r\n',
  'POST /body HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n',
  'GET / HTTP/1.1\r\n\r\n',
  'GET / HTTP/2.0\r\nHost: x\r\n\r\n',
  'GET /' + 'a'.repeat(9000) + ' HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nX: ' + 'b'.repeat(9000) + '\r\n\r\n',
  'BREW / HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nbad header line\r\n\r\n',
  '\r\n\r\n\r\n',
  '\x00\x01\x02\xff\xfe GET / HTTP/1.1\r\n\r\n',
  'GET /crash/../../etc HTTP/1.1\r\nHost: x\r\n\r\n',
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
  const s = start();
  if (!(await ready(s))) return record('malformed: server starts', false);
  const N = 10000, PAR = 50;
  const codes = {};
  for (let i = 0; i < N; i += PAR) {
    const batch = await Promise.all(Array.from({ length: PAR }, (_, j) => raw(s.port, MALFORMED[(i + j) % MALFORMED.length])));
    for (const b of batch) codes[b.slice(9, 12) || 'none'] = (codes[b.slice(9, 12) || 'none'] || 0) + 1;
    if (s.exited !== null) break;
  }
  const alive = (await get(s.port, '/healthz')).status === 200 && s.exited === null;
  record(`malformed: ${N} requests, 0 deaths`, alive, JSON.stringify(codes));
  await stop(s);
}

async function phaseWatchdog() {
  const s = start();
  if (!(await ready(s))) return record('watchdog: server starts', false);
  const t0 = performance.now();
  get(s.port, '/crash/block?s=15', { timeout: 20000 });
  for (let i = 0; i < 200 && s.exited === null; i++) await sleep(100);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  record('watchdog: a 15 s block exits 70 within 11 s', s.exited === 70 && secs <= 11, `exit=${s.exited} after ${secs.toFixed(2)} s`);
  if (s.exited === null) s.child.kill('SIGKILL');
}

// More than 100 pure recoveries in 60 s count as dirty: each leaks what its callback allocated.
async function phaseBurst() {
  const s = start();
  if (!(await ready(s))) return record('burst: server starts', false);
  let n = 0;
  for (; n < 150 && s.exited === null; n++) await get(s.port, '/crash/bounds');
  for (let i = 0; i < 80 && s.exited === null; i++) await sleep(100);
  record('burst: the 101st pure recovery within a minute exits 70', s.exited === 70 && /why="too many recoveries"/.test(s.out),
    `exit=${s.exited} after ${n} crash requests`);
  if (s.exited === null) s.child.kill('SIGKILL');
}

const PH = { burst: phaseBurst, pure: phasePure, dirty: phaseDirty, wal: phaseWal, malformed: phaseMalformed, watchdog: phaseWatchdog };
for (const p of phases) await PH[p]();
const failed = results.filter((r) => !r.pass);
console.log(`\n${OS}: ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
