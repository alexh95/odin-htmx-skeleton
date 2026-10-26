// S0.8 in a real browser: Chromium (Playwright from e2e/) opens /page on each Caddy site and
// measures write-to-arrival for SSE (EventSource, and fetch as htmx 4's hx-sse reads it),
// multipart/mixed over fetch (as hx-multipart reads it) and WebSocket frames. The page clock is
// aligned to the server's by the same-origin /now sample with the smallest round trip.
//
//   node browser.mjs [n=500] [short=50] [prio=high]   → one JSON line per site and kind
//
// prio=high raises this client and the Chromium it launched (that process tree only) to
// HIGH_PRIORITY_CLASS (Windows), for a round on a busy box; the server and Caddy are raised by hand.
import { createRequire } from 'node:module';
import { execSync, execFileSync } from 'node:child_process';
import os from 'node:os';

const require = createRequire(new URL('../../../e2e/package.json', import.meta.url));
const { chromium } = require('playwright');

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.split('=')));
const N = +(args.n ?? 500), SHORT = +(args.short ?? 50), HIGH = args.prio === 'high';
if (HIGH) os.setPriority(0, os.constants.priority.PRIORITY_HIGH);
// the browser process this script launched and all its children, nothing else
const raise = (pid) => execFileSync('powershell', ['-NoProfile', '-Command', `
$all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
$ids = @(${pid}); $i = 0
while ($i -lt $ids.Count) { $ids += @($all | Where-Object ParentProcessId -eq $ids[$i] | ForEach-Object ProcessId); $i++ }
foreach ($id in $ids) { try { (Get-Process -Id $id).PriorityClass = 'High' } catch {} }`]);
// [label, origin, Chromium flags]; tls-h1 is the TLS site with h2 turned off in the browser
const SITES = [
	['plain', 'http://127.0.0.1:18781', []],
	['spark', 'http://127.0.0.1:18782', []],
	['matcher', 'http://127.0.0.1:18785', []],
	['tls', 'https://localhost:18786', []],
	['spark-tls', 'https://localhost:18784', []],
	['spark-tls-h1', 'https://localhost:18784', ['--disable-http2']],
];
// the box's CPU just before each site (Windows typeperf), to spot a disturbed run
const cpu = () => {
	const line = execSync(String.raw`typeperf "\Processor(_Total)\% Processor Time" -sc 1`).toString().split(/\r?\n/)[2];
	return Math.round(+line.split('"')[3]);
};

for (const [label, base, flags] of SITES) {
	const server = await chromium.launchServer({ args: flags });
	const browser = await chromium.connect(server.wsEndpoint());
	const version = browser.version();
	const cpu_before = cpu();
	const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
	const page = await ctx.newPage();
	await page.goto(base + '/page');
	if (HIGH) raise(server.process().pid);
	const rows = await page.evaluate(async ({ N, SHORT }) => {
		const nowUs = () => (performance.timeOrigin + performance.now()) * 1000;
		let cal = null;
		for (let i = 0; i < 40; i++) {
			const t0 = nowUs();
			const s = +(await (await fetch('/now', { cache: 'no-store' })).text());
			const t1 = nowUs();
			if (!cal || t1 - t0 < cal.rtt) cal = { rtt: t1 - t0, off: s - (t0 + t1) / 2 };
		}
		const delay = (t, at) => (at - (t - cal.off)) / 1000;
		const stamp = (s) => { const m = /t=(\d+) i=(\d+)/.exec(s); return m && { t: +m[1], i: +m[2] }; };

		async function fetchStream(url, accept, mp, out) {
			const res = await fetch(url, { headers: { Accept: accept }, cache: 'no-store' });
			const enc = res.headers.get('content-encoding') ?? 'identity';
			const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
			let buf = '';
			for (;;) {
				const { value, done } = await reader.read();
				if (done) break;
				const at = nowUs();
				buf += value;
				for (;;) {
					let body;
					if (mp) {
						const h = buf.indexOf('\r\n\r\n');
						if (h < 0) break;
						const cl = /Content-Length: (\d+)/i.exec(buf.slice(0, h));
						if (!cl || buf.length < h + 4 + +cl[1]) break;
						body = buf.slice(h + 4, h + 4 + +cl[1]);
						buf = buf.slice(h + 6 + +cl[1]);
					} else {
						const i = buf.indexOf('\n\n');
						if (i < 0) break;
						body = buf.slice(0, i);
						buf = buf.slice(i + 2);
					}
					const s = stamp(body);
					if (s) out.push({ i: s.i, d: delay(s.t, at) });
				}
			}
			return enc;
		}

		const eventSource = (url, out) => new Promise((resolve, reject) => {
			const es = new EventSource(url);
			es.onmessage = (e) => {
				const s = stamp(e.data);
				out.push({ i: s.i, d: delay(s.t, nowUs()) });
				if (s.i === N) { es.close(); resolve('?'); }
			};
			es.onerror = () => { es.close(); reject(new Error('EventSource error')); };
		});

		const ws = (url, out) => new Promise((resolve, reject) => {
			const w = new WebSocket(url);
			w.onmessage = (e) => { const s = stamp(e.data); out.push({ i: s.i, d: delay(s.t, nowUs()) }); };
			w.onclose = (e) => resolve('ws ' + e.code);
			w.onerror = () => reject(new Error('ws error'));
		});

		const pct = (a, q) => a[Math.min(a.length - 1, Math.max(0, Math.ceil(q * a.length) - 1))];
		const sum = (xs) => {
			const s = xs.map((x) => x.d).sort((a, b) => a - b);
			const r = (v) => Math.round(v * 100) / 100;
			return { n: s.length, p50: r(pct(s, 0.5)), p99: r(pct(s, 0.99)), max: r(s[s.length - 1]) };
		};
		const entry = (path) => {
			const e = performance.getEntriesByType('resource').filter((r) => r.name.includes(path)).pop();
			return e ? { proto: e.nextHopProtocol, encoded: e.encodedBodySize, decoded: e.decodedBodySize } : {};
		};

		const wsBase = location.origin.replace(/^http/, 'ws');
		const q = `n=${N}&ms=10`;
		const out = [];
		const cases = [
			['es-sse', '/sse/tick?' + q + '&pad=1024', (u, o) => eventSource(u, o)],
			['fetch-sse', '/sse/tick?' + q + '&pad=1024&f', (u, o) => fetchStream(u, 'text/event-stream', false, o)],
			['fetch-mp-small', '/multipart?' + q + '&pad=0', (u, o) => fetchStream(u, 'multipart/mixed', true, o)],
			['fetch-mp', '/multipart?' + q + '&pad=1024', (u, o) => fetchStream(u, 'multipart/mixed', true, o)],
			['ws', '/ws/tick?' + q + '&pad=1024', (u, o) => ws(wsBase + u, o)],
		];
		for (const [kind, path, fn] of cases) {
			const xs = [];
			const enc = await fn(path, xs);
			out.push({ kind, enc, all: sum(xs), ...entry(path) });
		}
		// first event of fresh streams, one at a time
		for (const [kind, path, mp] of [['fetch-sse-first', '/sse/tick?n=3&ms=50&pad=1024', false], ['fetch-mp-first', '/multipart?n=3&ms=50&pad=1024', true]]) {
			const firsts = [];
			let enc;
			for (let k = 0; k < SHORT; k++) {
				const xs = [];
				enc = await fetchStream(path + '&k=' + k, mp ? 'multipart/mixed' : 'text/event-stream', mp, xs);
				firsts.push(xs.find((x) => x.i === 1));
			}
			out.push({ kind, enc, all: sum(firsts), ...entry(path + '&k=0') });
		}
		return { clock_rtt_ms: Math.round(cal.rtt) / 1000, out };
	}, { N, SHORT });
	for (const r of rows.out) console.log(JSON.stringify({ browser: 'chromium ' + version, site: label, cpu_before, ...(HIGH && { prio: 'high' }), clock_rtt_ms: rows.clock_rtt_ms, ...r }));
	await browser.close();
	await server.close();
}
