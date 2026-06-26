import { VUS, DURATION, WARMUP, P95, P99 } from './config.js';

// One definition of "how a scenario runs" for the whole suite. Two phases on the
// same VU level: a warmup whose samples we throw away, then the measured window.
// Tagging the window `phase:load` and hanging the thresholds off that tag means
// the warmup's cold-cache noise never lands in the reported numbers, and the
// pass/fail submetrics (…{phase:load}) show up in the summary for the run scripts
// to scrape. Pass extra per-scenario thresholds (e.g. a check rate) as `extra`.
export function options(extra = {}) {
  return {
    discardResponseBodies: false, // scenarios assert on bodies; cost is negligible here
    scenarios: {
      warmup: {
        executor: 'constant-vus',
        vus: VUS,
        duration: WARMUP,
        gracefulStop: '0s',
        tags: { phase: 'warmup' },
      },
      load: {
        executor: 'constant-vus',
        vus: VUS,
        duration: DURATION,
        startTime: WARMUP,
        tags: { phase: 'load' },
      },
    },
    thresholds: Object.assign(
      {
        // Hard gate: under 1% non-2xx in the measured window.
        'http_req_failed{phase:load}': ['rate<0.01'],
        // Latency guard (advisory across a sweep; tighten via --env P95/P99 for CI).
        'http_req_duration{phase:load}': [`p(95)<${P95}`, `p(99)<${P99}`],
        // Force the throughput submetric to exist so the summary carries per-phase RPS.
        'http_reqs{phase:load}': ['count>0'],
      },
      extra,
    ),
    summaryTrendStats: ['avg', 'p(50)', 'p(90)', 'p(95)', 'p(99)', 'max'],
  };
}

// Compact, dependency-free end-of-test summary. Avoids k6's remote jslib import
// (CI may be offline) and emits exactly what RESULTS.md wants: a one-line console
// digest plus a machine-readable JSON blob at __ENV.OUT for the run scripts to
// aggregate. Reads the {phase:load} submetrics so warmup is excluded.
export function summarize(name) {
  return function handleSummary(data) {
    const m = data.metrics;
    const dur = m['http_req_duration{phase:load}'] || m.http_req_duration;
    const reqs = m['http_reqs{phase:load}'] || m.http_reqs;
    const failed = m['http_req_failed{phase:load}'] || m.http_req_failed;
    const recv = m.data_received;

    const v = (x, k) => (x && x.values ? x.values[k] : 0);
    const out = {
      scenario: name,
      vus: parseInt(__ENV.VUS || '0', 10),
      duration: __ENV.DURATION || '',
      rps: round(v(reqs, 'rate')),
      count: v(reqs, 'count'),
      fail_rate: round(v(failed, 'rate'), 4),
      bytes_per_s: Math.round(v(recv, 'rate')),
      latency_ms: {
        avg: round(v(dur, 'avg')),
        p50: round(v(dur, 'p(50)')),
        p90: round(v(dur, 'p(90)')),
        p95: round(v(dur, 'p(95)')),
        p99: round(v(dur, 'p(99)')),
        max: round(v(dur, 'max')),
      },
    };

    const line =
      `\n  ${name} @ ${out.vus} VUs: ` +
      `${out.rps} rps  ` +
      `p50 ${out.latency_ms.p50}ms  p95 ${out.latency_ms.p95}ms  p99 ${out.latency_ms.p99}ms  ` +
      `fail ${(out.fail_rate * 100).toFixed(2)}%\n`;

    // One CSV row per run (no header) so the run scripts can `cat` every run into
    // one table with zero JSON tooling (no jq/python dependency on the box).
    const L = out.latency_ms;
    const csv =
      `${out.scenario},${out.vus},${out.rps},${L.p50},${L.p90},${L.p95},${L.p99},` +
      `${L.max},${out.fail_rate},${out.bytes_per_s}\n`;

    const result = { stdout: line };
    if (__ENV.OUT) result[__ENV.OUT] = JSON.stringify(out, null, 2);
    if (__ENV.OUT_CSV) result[__ENV.OUT_CSV] = csv;
    return result;
  };
}

function round(n, dp = 2) {
  if (n == null || isNaN(n)) return 0;
  const f = Math.pow(10, dp);
  return Math.round(n * f) / f;
}
