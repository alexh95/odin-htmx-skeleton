// S0.8: the record's Node tables from run.sh rounds.  node tables.mjs results/node-high-*.jsonl
// A cell is "p50 / p99 / max" in ms: p50 is the median of the rounds' p50, p99 and max the worst round.
// Within a round, the try with the quietest box (lowest cpu_run) counts. First-event cells use each
// fresh stream's first event only.
import fs from 'node:fs';

const rounds = process.argv.slice(2).map((f) => {
	const m = new Map();
	for (const l of fs.readFileSync(f, 'utf8').trim().split('\n')) {
		const r = JSON.parse(l);
		const key = [r.label, r.kind, r.pad ?? '', r.streams ?? 1].join('|');
		if (!m.has(key) || (m.get(key).cpu_run ?? 0) > (r.cpu_run ?? 0)) m.set(key, r);
	}
	return m;
});
const med = (a) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor((s.length - 1) / 2)]; };
const f1 = (v) => v.toFixed(1);
const cell = (label, kind, pad, streams, pick = (r) => r.all) => {
	const s = rounds.map((m) => m.get([label, kind, pad, streams].join('|'))).filter(Boolean).map(pick);
	return s.length ? `${f1(med(s.map((x) => x.p50)))} / ${f1(Math.max(...s.map((x) => x.p99)))} / ${f1(Math.max(...s.map((x) => x.max)))}` : '';
};
const first = (r) => r.first;

console.log('| Case | SSE, small | SSE, 1 KiB | multipart, small | multipart, 1 KiB | SSE first event | multipart first part | SSE, 100 streams | multipart, 100 streams |');
console.log('|---|---|---|---|---|---|---|---|---|');
for (const s of ['direct', 'plain', 'stack', 'spark-zstd', 'spark-gzip', 'matcher']) {
	console.log(`| ${s} | ${cell(s, 'sse', 0, 1)} | ${cell(s, 'sse', 1024, 1)} | ${cell(s, 'mp', 0, 1)} | ${cell(s, 'mp', 1024, 1)} | ${cell(s, 'sse', 1024, 200, first)} | ${cell(s, 'mp', 1024, 200, first)} | ${cell(s, 'sse', 1024, 100)} | ${cell(s, 'mp', 1024, 100)} |`);
}
console.log(`\n| spark-nt | SSE 1 KiB ${cell('spark-nt', 'sse', 1024, 1)} | multipart 1 KiB ${cell('spark-nt', 'mp', 1024, 1)} |`);
for (const s of ['direct-ws', 'spark-ws']) {
	console.log(`| ${s} | push small ${cell(s, 'ws', 0, 1)} | push 1 KiB ${cell(s, 'ws', 1024, 1)} | echo RTT ${cell(s, 'echo', '', 1, (r) => r.rtt)} |`);
}
const all = process.argv.slice(2).flatMap((f) => fs.readFileSync(f, 'utf8').trim().split('\n').map((l) => JSON.parse(l)));
const kept = rounds.flatMap((m) => [...m.values()]);
console.log(`\nruns ${all.length}, kept ${kept.length}; box CPU over kept runs ${Math.min(...kept.map((r) => r.cpu_run))}–${Math.max(...kept.map((r) => r.cpu_run))} %`);
