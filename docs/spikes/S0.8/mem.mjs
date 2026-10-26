// S0.8 Caddy's memory per open stream: k SSE streams (or multipart, kind=mp) held open through one
// site, Go heap in use read from Caddy's admin /metrics after a forced GC, before and with them.
//
//   node mem.mjs base=http://127.0.0.1:18782 admin=http://127.0.0.1:18789 k=500 kind=sse ae="..." label=...
import http from 'node:http';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const i = a.indexOf('=');
	return [a.slice(0, i), a.slice(i + 1)];
}));
const { base, admin } = args;
const k = +(args.k ?? 500), kind = args.kind ?? 'sse';
const ae = args.ae ?? 'gzip, deflate, br, zstd';
const nt = args.nt === '1' ? '&nt=1' : '';

// node:http, not fetch: Caddy's admin API refuses fetch's `Sec-Fetch-Mode: cors` without an Origin
const get = (url) => new Promise((resolve, reject) => {
	http.get(url, (res) => {
		let body = '';
		res.setEncoding('latin1');
		res.on('data', (c) => { body += c; });
		res.on('end', () => resolve(body));
	}).on('error', reject);
});

async function heap() {
	// a forced GC, twice: sync.Pool keeps a victim cache across one GC, and Caddy pools its encoders
	for (let i = 0; i < 2; i++) await get(admin + '/debug/pprof/heap?gc=1');
	const m = await get(admin + '/metrics');
	const v = (name) => +(new RegExp('^' + name + ' (\\S+)', 'm').exec(m)?.[1] ?? NaN);
	return { inuse: v('go_memstats_heap_inuse_bytes'), sys: v('go_memstats_sys_bytes') };
}

const before = await heap();
const path = (kind === 'mp' ? '/multipart?n=100000&ms=1000&pad=1024' : '/sse/tick?n=0&ms=1000&pad=1024') + nt;
const reqs = [];
let enc = new Set();
// opened 50 at a time: in a burst of 500, some of Caddy's upstream dials were refused (Windows loopback)
const open = () => new Promise((resolve, reject) => {
	const req = http.get(base + path, { agent: false, headers: { 'Accept-Encoding': ae } }, (res) => {
		if (res.statusCode !== 200) return reject(new Error('status ' + res.statusCode));
		enc.add(res.headers['content-encoding'] ?? 'identity');
		let chunks = 0;
		res.on('data', () => { if (++chunks === 2) resolve(); });
	});
	req.on('error', reject);
	reqs.push(req);
});
for (let i = 0; i < k; i += 50) await Promise.all(Array.from({ length: Math.min(50, k - i) }, open));
const during = await heap();
for (const r of reqs) r.destroy();
const mib = (b) => Math.round(b / 1048576 * 10) / 10;
console.log(JSON.stringify({
	label: args.label ?? base, kind, k, nt: nt !== '', enc: [...enc].join(','),
	heap_inuse_mib: [mib(before.inuse), mib(during.inuse)], sys_mib: [mib(before.sys), mib(during.sys)],
	per_stream_kib: Math.round((during.inuse - before.inuse) / k / 1024),
}));
