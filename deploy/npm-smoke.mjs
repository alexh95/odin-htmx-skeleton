// The stage 1b smoke through NPM (PLAN §20.3, M3 slice 10): from a LAN machine, over HTTPS, read
// only. Every witness answers its page with HTTP/2 and its version, renders in a real browser
// with no console error or CSP violation, and the lab streams through NPM: an SSE stream opens and
// gets the server's first frame, and a WebSocket upgrades and echoes. Redirects: http to https,
// and the alias host to the starter's. Houston answers once starter-full runs.
//
//   node deploy/npm-smoke.mjs [--version v2.2.0-rc.2] [--houston]
//
// It needs e2e's node_modules (Playwright's chromium): run it from the repo root after
// `cd e2e && npm ci`. Prints PASS/FAIL per check; exits 1 on any FAIL.

import http2 from 'node:http2';
import https from 'node:https';
import http from 'node:http';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../e2e/package.json', import.meta.url));
const { chromium } = require('@playwright/test');

const argv = process.argv.slice(2);
const flag = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : ''; };
const VERSION = flag('--version');
const HOUSTON = argv.includes('--houston');
const SITE = 'alexh95.com';
const WITNESSES = ['odin-htmx-starter', 'starter-minimal', 'starter-streams', 'starter-skeleton'];
const HOSTS = [...WITNESSES, ...(HOUSTON ? ['houston', 'houston-lab'] : [])];

const results = [];
const record = (name, pass, detail = '') => {
  results.push({ name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${detail ? `  ${detail}` : ''}`);
};

// One request over HTTP/2: its status, headers and the protocol NPM agreed.
function h2get(host, path) {
  return new Promise((res) => {
    const s = http2.connect(`https://${host}.${SITE}`);
    s.on('error', (e) => res({ status: 0, error: String(e.code || e) }));
    const r = s.request({ ':path': path });
    let body = '';
    let headers = {};
    r.on('response', (h) => { headers = h; });
    r.setEncoding('utf8');
    r.on('data', (c) => { body += c; });
    r.on('end', () => { res({ status: headers[':status'], headers, body, alpn: s.alpnProtocol }); s.close(); });
    r.on('error', (e) => { res({ status: 0, error: String(e.code || e) }); s.close(); });
    r.end();
  });
}

// A plain request, any scheme, no redirect followed.
function plain(url) {
  return new Promise((res) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout: 5000 }, (r) => { r.resume(); res({ status: r.statusCode, location: r.headers.location ?? '' }); });
    req.on('timeout', () => { req.destroy(); res({ status: -1 }); });
    req.on('error', (e) => res({ status: 0, location: String(e.code) }));
  });
}

// An SSE stream's head and its first frame, or what stopped it.
function sse(host, path) {
  return new Promise((res) => {
    const t0 = performance.now();
    const req = https.get({ host: `${host}.${SITE}`, path, timeout: 5000 }, (r) => {
      let got = '';
      r.setEncoding('utf8');
      r.on('data', (c) => {
        got += c;
        if (/\n\n/.test(got)) { req.destroy(); res({ status: r.statusCode, type: r.headers['content-type'], ms: Math.round(performance.now() - t0), first: got.split('\n')[0] }); }
      });
    });
    req.on('timeout', () => { req.destroy(); res({ status: -1 }); });
    req.on('error', () => {});
  });
}

for (const host of HOSTS) {
  const r = await h2get(host, '/');
  const version = r.headers?.['x-version'] ?? '';
  record(`${host}: / answers 200 over HTTP/2${VERSION ? ` at ${VERSION}` : ''}`,
    r.status === 200 && r.alpn === 'h2' && (!VERSION || version === VERSION),
    `status ${r.status} alpn ${r.alpn} x-version ${version}${r.error ? ` ${r.error}` : ''}`);
}

for (const host of HOSTS) {
  const p = await plain(`http://${host}.${SITE}/`);
  record(`${host}: http 301s to https`, p.status === 301 && p.location.startsWith(`https://${host}.${SITE}`), `${p.status} ${p.location}`);
}
const alias = await plain(`https://htmx-odin-starter.${SITE}/x?y=1`);
record('htmx-odin-starter 301s to odin-htmx-starter, path and query kept', alias.status === 301 && alias.location === `https://odin-htmx-starter.${SITE}/x?y=1`, `${alias.status} ${alias.location}`);

const browser = await chromium.launch();
try {
  for (const host of HOSTS) {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.addInitScript(() => document.addEventListener('securitypolicyviolation', (e) => console.error(`csp: ${e.violatedDirective} ${e.blockedURI}`)));
    const res = await page.goto(`https://${host}.${SITE}/`, { waitUntil: 'networkidle' }).catch((e) => ({ status: () => 0, e }));
    const title = await page.title().catch(() => '');
    record(`${host}: renders in a browser with no error or CSP violation`, res.status() === 200 && errors.length === 0 && title !== '',
      `status ${res.status()} title "${title}"${errors.length ? ` errors: ${errors.slice(0, 3).join(' | ')}` : ''}`);
    await page.close();
  }

  // The lab streams through NPM: SSE's first frame unbuffered, and a socket that upgrades and echoes.
  const key = `smoke${Date.now()}`;
  const s = await sse('odin-htmx-starter', `/events?t=lab.feed:${key}`);
  // nginx acts on X-Accel-Buffering and drops it, so the proof it streams is the first frame's time.
  record('lab: an SSE stream through NPM opens and gets its first frame at once, unbuffered',
    s.status === 200 && /text\/event-stream/.test(s.type ?? '') && s.ms < 1000 && s.first === ': open', JSON.stringify(s));
  const page = await browser.newPage();
  await page.goto(`https://odin-htmx-starter.${SITE}/lab`);
  const ws = await page.evaluate((room) => new Promise((done) => {
    const sock = new WebSocket(`wss://${location.host}/lab/ws/chat?room=${room}`);
    const t = setTimeout(() => done({ open: false, why: 'no open in 5 s' }), 5000);
    sock.onopen = () => { clearTimeout(t); sock.close(); done({ open: true }); };
    sock.onerror = () => { clearTimeout(t); done({ open: false, why: 'error' }); };
  }), key);
  record('lab: a WebSocket through NPM upgrades', ws.open, JSON.stringify(ws));
  await page.close();
} finally {
  await browser.close();
}

const failed = results.filter((r) => !r.pass);
console.log(`\nnpm smoke: ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
