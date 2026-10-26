// The parity gate's pass rule (PLAN §18.2) over lib/parity.sh's CSV: S0.1's analyze.mjs with the
// references M1 settled.
//
//   node lib/parity.mjs <results.csv> [--leg windows|linux] [--waivers tests/parity-waivers.txt]
//                       [--store mem|file] [--baselines] [candidate …]
//
// Per cell (scenario × store), per round, ratio = C.rps / reference.rps, both from the same round,
// which ran back to back. The reference is HEAD (709bc94) on the light routes, `static` and `seo`
// (v1.1.1 lacks 1.2.0's security headers there; Q35), and on a cell the waivers file names for this
// leg (Q6); max(HEAD, v1.1.1) everywhere else. A cell passes when
//   - the median of its per-round ratios is >= 0.97, or the bar of the cell's `perf-floor` line for
//     the leg (a documented exception Alex accepted at its measured level),
//   - no round's ratio is below 0.85,
//   - C's p99 is <= 1.10 × the reference's p99 (median over rounds).
// Candidates default to every variant but head and v111. A block re-run later (the same round,
// scenario and store, appended to the CSV) replaces the earlier rows: the last row per run wins.
// Exits 1 when a cell fails. --baselines prints S0.1's table instead: each baseline's median and
// noise band (max/min of its rps over the rounds) and HEAD / v1.1.1 per cell.

import { readFileSync } from 'node:fs';

const LIGHT = new Set(['static', 'seo']);

const args = process.argv.slice(2);
const file = args.shift();
let leg = '', waiverFile = '', onlyStore = '', baselines = false;
const want = [];
while (args.length) {
  const a = args.shift();
  if (a === '--leg') leg = args.shift();
  else if (a === '--waivers') waiverFile = args.shift();
  else if (a === '--store') onlyStore = args.shift();
  else if (a === '--baselines') baselines = true;
  else want.push(a);
}

// perf       | <scenario>@<store> | <legs> | <reason>           gated against HEAD alone
// perf-floor | <scenario>@<store> | <legs> | <bar> | <reason>   a median bar below 0.97, at the level Alex accepted
const waived = new Map(), floors = new Map();
if (waiverFile) {
  for (const line of readFileSync(waiverFile, 'utf8').split('\n')) {
    const f = line.split(' | ').map((x) => x.trim());
    if (f[0] === 'perf' && f.length >= 4) {
      if (!f[3]) throw new Error(`${waiverFile}: a perf waiver without a reason: ${line}`);
      if (!leg || f[2].split(/\s+/).includes(leg)) waived.set(f[1], f[3]);
    } else if (f[0] === 'perf-floor' && f.length >= 5) {
      const bar = Number(f[3]);
      if (!(bar > 0.85 && bar < 0.97) || !f[4]) throw new Error(`${waiverFile}: a perf floor needs a bar in (0.85, 0.97) and a reason: ${line}`);
      if (!leg || f[2].split(/\s+/).includes(leg)) floors.set(f[1], { bar, why: f[4] });
    }
  }
}

const rows = readFileSync(file, 'utf8').trim().split('\n').slice(1).map((l) => {
  const [round, scenario, store, variant, vus, rps, p50, p90, p95, p99, max, fail_rate, bytes, bg] = l.split(',');
  return { round: +round, scenario, store, variant, rps: +rps || 0, p99: +p99 || 0, fail: +fail_rate || 0, bg: +bg || 0 };
});
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); const n = s.length; return n ? (n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2) : NaN; };
const band = (xs) => (xs.length > 1 ? (Math.max(...xs) / Math.min(...xs)).toFixed(2) : '–');
const variants = [...new Set(rows.map((r) => r.variant))];
const cands = want.length ? want : variants.filter((v) => v !== 'head' && v !== 'v111');
const cells = [...new Set(rows.filter((r) => !onlyStore || r.store === onlyStore).map((r) => `${r.scenario}|${r.store}`))];
const get = (s, st, v, r) => rows.findLast((x) => x.scenario === s && x.store === st && x.variant === v && x.round === r);
const roundsOf = (s, st) => [...new Set(rows.filter((x) => x.scenario === s && x.store === st).map((x) => x.round))].sort((a, b) => a - b);

if (baselines) {
  console.log('| cell | HEAD rps (band) | v1.1.1 rps (band) | HEAD / v1.1.1 (median of rounds) | faster |');
  console.log('|---|---:|---:|---:|---|');
  for (const cell of cells) {
    const [s, st] = cell.split('|');
    const A = [], B = [], R = [];
    for (const r of roundsOf(s, st)) {
      const a = get(s, st, 'head', r), b = get(s, st, 'v111', r);
      if (!a || !b || !a.rps || !b.rps) continue;
      A.push(a.rps); B.push(b.rps); R.push(a.rps / b.rps);
    }
    if (!R.length) continue;
    const r = median(R);
    console.log(`| ${s}@${st} | ${Math.round(median(A))} (${band(A)}) | ${Math.round(median(B))} (${band(B)}) | ${r.toFixed(2)} | ${r >= 1 ? 'HEAD' : 'v1.1.1'} |`);
  }
  process.exit(0);
}

let failed = 0;
for (const cand of cands) {
  console.log(`\n## ${cand}${leg ? ` (${leg})` : ''}\n`);
  console.log(`| cell | reference | head rps (band) | v111 rps (band) | ${cand} rps | ratios per round | median | min | p99 ratio | bg | pass |`);
  console.log('|---|---|---:|---:|---:|---|---:|---:|---:|---|---|');
  let passed = 0, total = 0;
  for (const cell of cells) {
    const [s, st] = cell.split('|');
    const key = `${s}@${st}`;
    const bar = floors.get(key)?.bar ?? 0.97;
    const ref = (LIGHT.has(s) ? 'head' : waived.has(key) ? 'head (waiver)' : 'max') + (floors.has(key) ? `, bar ${bar}` : '');
    const ratios = [], p99r = [], A = [], B = [], C = [], bgs = [];
    for (const r of roundsOf(s, st)) {
      const a = get(s, st, 'head', r), b = get(s, st, 'v111', r), c = get(s, st, cand, r);
      if (!a || !b || !c || !c.rps) continue;
      const best = ref.startsWith('max') ? (a.rps >= b.rps ? a : b) : a;
      ratios.push(c.rps / best.rps);
      p99r.push(c.p99 / best.p99);
      A.push(a.rps); B.push(b.rps); C.push(c.rps); bgs.push(c.bg);
    }
    if (!ratios.length) continue;
    total++;
    const med = median(ratios), mn = Math.min(...ratios), p99 = median(p99r);
    const pass = med >= bar && mn >= 0.85 && p99 <= 1.10;
    if (pass) passed++;
    else failed++;
    console.log(`| ${key} | ${ref} | ${Math.round(median(A))} (${band(A)}) | ${Math.round(median(B))} (${band(B)}) | ${Math.round(median(C))} | ${ratios.map((x) => x.toFixed(2)).join(' ')} | ${med.toFixed(2)} | ${mn.toFixed(2)} | ${p99.toFixed(2)} | ${bgs.join('/')} | ${pass ? 'yes' : '**no**'} |`);
  }
  console.log(`\n${cand}: ${passed}/${total} cells pass`);
}
for (const [key, why] of waived) console.log(`waiver: ${key} against HEAD: ${why}`);
for (const [key, f] of floors) console.log(`waiver: ${key} passes at a median of ${f.bar}, not 0.97: ${f.why}`);
process.exit(failed ? 1 : 0);
