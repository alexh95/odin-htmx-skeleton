// The parity gate's pass rule (PLAN §18.2) over parity.sh's CSV.
//
//   node analyze.mjs <results.csv> [--against head|v111|both] [--store mem|file] [candidate ...]
//
// --against both (the default) is the parity gate's max(A, B); S0.2 compares the fork against head
// alone, because that build keeps head's store. --store keeps one store's cells. Candidates default
// to every variant but head and v111. A block re-run later (the same round, scenario and store,
// appended to the CSV) replaces the earlier rows: the last row per run wins.
//
// Per cell (scenario × store), per round: ratio = C.rps / max(A.rps, B.rps), A = head (709bc94),
// B = v111, all from the same round, which ran back to back. A cell passes when
//   - the median of its per-round ratios is >= 0.97,
//   - no round's ratio is below 0.85,
//   - C's p99 is <= 1.10 × the p99 of the faster baseline (median over rounds).
// Also printed: each baseline's noise band (max/min of its rps over the rounds), the faster
// baseline per cell, and the rounds' background CPU.

import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const file = args.shift();
let against = 'both', onlyStore = '';
const want = [];
while (args.length) {
  const a = args.shift();
  if (a === '--against') against = args.shift();
  else if (a === '--store') onlyStore = args.shift();
  else want.push(a);
}
const rows = readFileSync(file, 'utf8').trim().split('\n').slice(1).map((l) => {
  const [round, scenario, store, variant, vus, rps, p50, p90, p95, p99, max, fail_rate, bytes, bg] = l.split(',');
  return { round: +round, scenario, store, variant, rps: +rps || 0, p99: +p99 || 0, fail: +fail_rate || 0, bg: +bg || 0 };
});
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); const n = s.length; return n ? (n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2) : NaN; };
const variants = [...new Set(rows.map((r) => r.variant))];
const cands = want.length ? want : variants.filter((v) => v !== 'head' && v !== 'v111');
const cells = [...new Set(rows.filter((r) => !onlyStore || r.store === onlyStore).map((r) => `${r.scenario}|${r.store}`))];
const get = (s, st, v, r) => rows.findLast((x) => x.scenario === s && x.store === st && x.variant === v && x.round === r);

const out = [];
for (const cand of cands) {
  console.log(`\n## ${cand} against ${against === 'both' ? 'max(head, v111)' : against}\n`);
  console.log('| cell | head rps (band) | v111 rps (band) | ' + cand + ' rps | ratios per round | median | min | p99 ratio | bg | pass |');
  console.log('|---|---:|---:|---:|---|---:|---:|---:|---|---|');
  let passed = 0, total = 0;
  for (const cell of cells) {
    const [s, st] = cell.split('|');
    const rounds = [...new Set(rows.filter((x) => x.scenario === s && x.store === st).map((x) => x.round))].sort();
    const ratios = [], p99r = [], A = [], B = [], C = [], bgs = [];
    for (const r of rounds) {
      const a = get(s, st, 'head', r), b = get(s, st, 'v111', r), c = get(s, st, cand, r);
      if (!a || !b || !c || !c.rps) continue;
      const best = against === 'head' ? a : against === 'v111' ? b : (a.rps >= b.rps ? a : b);
      ratios.push(c.rps / best.rps);
      p99r.push(c.p99 / best.p99);
      A.push(a.rps); B.push(b.rps); C.push(c.rps); bgs.push(c.bg);
    }
    if (!ratios.length) continue;
    total++;
    const med = median(ratios), mn = Math.min(...ratios), p99 = median(p99r);
    const pass = med >= 0.97 && mn >= 0.85 && p99 <= 1.10;
    if (pass) passed++;
    const band = (xs) => (xs.length > 1 ? (Math.max(...xs) / Math.min(...xs)).toFixed(2) : '–');
    console.log(`| ${s}@${st} | ${Math.round(median(A))} (${band(A)}) | ${Math.round(median(B))} (${band(B)}) | ${Math.round(median(C))} | ${ratios.map((x) => x.toFixed(2)).join(' ')} | ${med.toFixed(2)} | ${mn.toFixed(2)} | ${p99.toFixed(2)} | ${bgs.join('/')} | ${pass ? 'yes' : '**no**'} |`);
    out.push({ cand, cell, med, mn, p99, pass });
  }
  console.log(`\n${cand}: ${passed}/${total} cells pass`);
}
