// S0.8 measuring client (Node 22.15+, for zlib zstd): the delay from the server's write to the
// arrival of each SSE event, multipart part or WebSocket frame, decoded as a browser would.
//
//   node measure.mjs base=http://127.0.0.1:18782 kind=sse|mp|ws|echo n=1000 ms=10 pad=0
//        streams=1 conc=1 nt=0 ae="gzip, deflate, br, zstd" label=spark
//
// The server stamps `t=<unix µs>` into each event just before its write. The client clock is
// aligned to the server's by the /now sample with the smallest round trip (`clock=`, default the
// server itself, not through Caddy). Prints one JSON line: delays in ms (p50, p99, max over every
// event; the same over each stream's first event), the Content-Encoding seen, wire and decoded bytes.
import http from 'node:http';
import os from 'node:os';
import https from 'node:https';
import zlib from 'node:zlib';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const i = a.indexOf('=');
	return [a.slice(0, i), a.slice(i + 1)];
}));
const base = args.base;
const clock = args.clock ?? 'http://127.0.0.1:18780';
const kind = args.kind ?? 'sse';
const n = +(args.n ?? 1000), ms = +(args.ms ?? 10), pad = +(args.pad ?? 0);
const streams = +(args.streams ?? 1), conc = +(args.conc ?? 1);
const ae = args.ae ?? 'gzip, deflate, br, zstd';
const nt = args.nt === '1' ? '&nt=1' : '';
const label = args.label ?? base;
// prio=high: the client at HIGH_PRIORITY_CLASS (Windows), like the server and Caddy in the high rounds
if (args.prio === 'high') os.setPriority(0, os.constants.priority.PRIORITY_HIGH);

const nowUs = () => (performance.timeOrigin + performance.now()) * 1000;

// The whole box's CPU busy share over the run (all cores, from os.cpus()), to spot a disturbed run.
const cpuSnap = () => os.cpus().reduce((a, c) => { const t = c.times; a.idle += t.idle; a.total += t.user + t.nice + t.sys + t.idle + t.irq; return a; }, { idle: 0, total: 0 });

async function calibrate() {
	let best = null;
	for (let i = 0; i < 40; i++) {
		const t0 = nowUs();
		const s = +(await (await fetch(clock + '/now')).text());
		const t1 = nowUs();
		if (!best || t1 - t0 < best.rtt) best = { rtt: t1 - t0, off: s - (t0 + t1) / 2 };
	}
	return best;
}

const pct = (a, q) => a.length ? a[Math.min(a.length - 1, Math.max(0, Math.ceil(q * a.length) - 1))] : null;
const summary = (a) => {
	const s = [...a].sort((x, y) => x - y);
	const r = (v) => v === null ? null : Math.round(v * 100) / 100;
	return { n: s.length, p50: r(pct(s, 0.5)), p99: r(pct(s, 0.99)), max: r(s[s.length - 1] ?? null) };
};

// One HTTP stream; `parse` gets decoded text and its arrival time and returns stamps it completed.
function httpStream(path, accept, parse) {
	return new Promise((resolve, reject) => {
		const u = new URL(base + path);
		const mod = u.protocol === 'https:' ? https : http;
		const req = mod.get(u, {
			agent: false,
			rejectUnauthorized: false,
			headers: { 'Accept-Encoding': ae, Accept: accept, 'Cache-Control': 'no-cache' },
		}, (res) => {
			const enc = res.headers['content-encoding'] ?? 'identity';
			let wire = 0, decoded = 0;
			res.on('data', (c) => { wire += c.length; });
			let dec = res;
			if (enc === 'gzip') dec = res.pipe(zlib.createGunzip({ flush: zlib.constants.Z_SYNC_FLUSH }));
			else if (enc === 'zstd') dec = res.pipe(zlib.createZstdDecompress());
			else if (enc === 'br') dec = res.pipe(zlib.createBrotliDecompress({ flush: zlib.constants.BROTLI_OPERATION_FLUSH }));
			dec.on('data', (c) => { decoded += c.length; parse(c.toString('latin1'), nowUs()); });
			dec.on('end', () => resolve({ enc, wire, decoded, status: res.statusCode }));
			dec.on('error', reject);
		});
		req.on('error', reject);
	});
}

function sseParser(record) {
	let buf = '';
	return (txt, at) => {
		buf += txt;
		for (let i; (i = buf.indexOf('\n\n')) >= 0;) {
			const ev = buf.slice(0, i);
			buf = buf.slice(i + 2);
			const m = /t=(\d+) i=(\d+)/.exec(ev);
			if (m) record(+m[2], +m[1], at);
		}
	};
}

// multipart/mixed as hx-multipart reads it: a part is complete when its Content-Length bytes are in.
function mpParser(record) {
	let buf = '';
	return (txt, at) => {
		buf += txt;
		for (;;) {
			const h = buf.indexOf('\r\n\r\n');
			if (h < 0) return;
			const cl = /Content-Length: (\d+)/i.exec(buf.slice(0, h));
			if (!cl) return;
			const end = h + 4 + +cl[1];
			if (buf.length < end) return;
			const m = /t=(\d+) i=(\d+)/.exec(buf.slice(h + 4, end));
			buf = buf.slice(end + 2);
			if (m) record(+m[2], +m[1], at);
		}
	};
}

function wsTick(record) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(base.replace(/^http/, 'ws') + `/ws/tick?n=${n}&ms=${ms}&pad=${pad}`);
		let bytes = 0;
		ws.onmessage = (e) => {
			const at = nowUs();
			bytes += e.data.length;
			const m = /t=(\d+) i=(\d+)/.exec(e.data);
			if (m) record(+m[2], +m[1], at);
		};
		ws.onclose = (e) => resolve({ enc: 'ws', wire: bytes, decoded: bytes, status: e.code });
		ws.onerror = (e) => reject(new Error('ws error ' + (e.message ?? '')));
	});
}

// Round trips through /ws/echo: n messages, one at a time, `ms` apart; one clock, no offset.
function wsEcho(rtts) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(base.replace(/^http/, 'ws') + '/ws/echo');
		let sent = 0;
		const send = () => { sent++; ws.send(`c=${nowUs()} ${'x'.repeat(pad)}`); };
		ws.onopen = send;
		ws.onmessage = (e) => {
			rtts.push((nowUs() - +/c=([\d.]+)/.exec(e.data)[1]) / 1000);
			if (sent < n) setTimeout(send, ms); else ws.close(1000);
		};
		ws.onclose = (e) => resolve({ enc: 'ws', status: e.code });
		ws.onerror = (e) => reject(new Error('ws error ' + (e.message ?? '')));
	});
}

const cal = await calibrate();
const all = [], first = [];
const encs = new Set();
let wire = 0, decoded = 0, missing = 0;

async function one() {
	const got = new Set();
	const record = (i, t, at) => {
		const d = (at - (t - cal.off)) / 1000;
		all.push(d);
		if (i === 1) first.push(d);
		got.add(i);
	};
	let r;
	if (kind === 'sse') r = await httpStream(`/sse/tick?n=${n}&ms=${ms}&pad=${pad}${nt}`, 'text/event-stream', sseParser(record));
	else if (kind === 'mp') r = await httpStream(`/multipart?n=${n}&ms=${ms}&pad=${pad}${nt}`, 'multipart/mixed', mpParser(record));
	else if (kind === 'ws') r = await wsTick(record);
	encs.add(r.enc);
	wire += r.wire;
	decoded += r.decoded;
	missing += n - got.size;
}

const t0 = Date.now();
const c0 = cpuSnap();
let out;
if (kind === 'echo') {
	const rtts = [];
	await wsEcho(rtts);
	out = { label, kind, ae, enc: 'ws', rtt: summary(rtts) };
} else {
	let next = 0;
	await Promise.all(Array.from({ length: conc }, async () => {
		while (next < streams) { next++; await one(); }
	}));
	out = {
		label, kind, ae, pad, ms, streams, enc: [...encs].join(','),
		all: summary(all), first: summary(first), missing,
		wire, decoded,
	};
}
const c1 = cpuSnap();
out.cpu_run = Math.round(100 * (1 - (c1.idle - c0.idle) / (c1.total - c0.total)));
out.clock_rtt_ms = Math.round(cal.rtt) / 1000;
if (args.prio) out.prio = args.prio;
out.secs = (Date.now() - t0) / 1000;
console.log(JSON.stringify(out));
