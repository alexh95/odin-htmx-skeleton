// S0.8 h2 check: one SSE or multipart stream through Caddy's TLS site over HTTP/2 with node:http2,
// to tell Chromium's own h2 delay from Caddy's. Same stamps and clock alignment as measure.mjs.
//
//   node h2.mjs [base=https://localhost:18784] [path=/sse/tick?n=300&ms=10&pad=1024] [ae=...] [prio=high]
import http2 from 'node:http2';
import os from 'node:os';
import zlib from 'node:zlib';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(0, i), a.slice(i + 1)]; }));
const base = args.base ?? 'https://localhost:18784';
const ae = args.ae ?? 'gzip, deflate, br, zstd';
const path = args.path ?? '/sse/tick?n=300&ms=10&pad=1024';
if (args.prio === 'high') os.setPriority(0, os.constants.priority.PRIORITY_HIGH);
const nowUs = () => (performance.timeOrigin + performance.now()) * 1000;

let cal = null;
for (let i = 0; i < 40; i++) {
	const t0 = nowUs();
	const s = +(await (await fetch('http://127.0.0.1:18780/now')).text());
	const t1 = nowUs();
	if (!cal || t1 - t0 < cal.rtt) cal = { rtt: t1 - t0, off: s - (t0 + t1) / 2 };
}

const client = http2.connect(base, { rejectUnauthorized: false });
const req = client.request({ ':path': path, 'accept-encoding': ae });
const ds = [];
req.on('response', (h) => {
	const enc = h['content-encoding'] ?? 'identity';
	let dec = req;
	if (enc === 'zstd') dec = req.pipe(zlib.createZstdDecompress());
	if (enc === 'gzip') dec = req.pipe(zlib.createGunzip({ flush: zlib.constants.Z_SYNC_FLUSH }));
	let buf = '';
	dec.on('data', (c) => {
		const at = nowUs();
		buf += c.toString('latin1');
		for (const m of buf.matchAll(/t=(\d+) i=(\d+)/g)) ds.push((at - (+m[1] - cal.off)) / 1000);
		buf = buf.slice(buf.lastIndexOf('i=') + 2);
	});
	dec.on('end', () => {
		ds.sort((a, b) => a - b);
		const p = (q) => Math.round(ds[Math.min(ds.length - 1, Math.ceil(q * ds.length) - 1)] * 100) / 100;
		console.log(JSON.stringify({ path, proto: 'h2', enc, n: ds.length, p50: p(0.5), p99: p(0.99), max: p(1) }));
		client.close();
	});
});
req.end();
