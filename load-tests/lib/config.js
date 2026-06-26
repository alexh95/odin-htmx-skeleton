// Shared knobs for every scenario. The run scripts override these per run via
// --env; the defaults make a bare `k6 run scenarios/x.js` do something sensible.
//
// k6 reads env through __ENV (its own JS runtime — not Node, no process.env).

export const BASE = __ENV.BASE_URL || 'http://127.0.0.1:8080';

// One steady load level per run. The run scripts sweep this across the curve
// (1, 10, 50, 100, 200, 500) and collect each point; a lone run uses 50.
export const VUS = parseInt(__ENV.VUS || '50', 10);
export const DURATION = __ENV.DURATION || '30s';
export const WARMUP = __ENV.WARMUP || '5s';

// Latency budget for the pass/fail gate, in milliseconds. Generous by default so
// a full VU sweep doesn't hard-fail at the high end (finding that knee is the
// point). A fixed-reference CI run can tighten these via --env.
export const P95 = __ENV.P95 || '50';
export const P99 = __ENV.P99 || '100';

// Search terms drawn from the seeded store (see repository.repo_seed): a mix of
// exact-ish names and short fragments so the filter does real work and returns
// non-empty result sets.
const TERMS = ['grace', 'liam', 'noah', 'ava', 'admin', 'active', 'a', 'e', 'in', 'son'];
export function term() {
  return TERMS[Math.floor(Math.random() * TERMS.length)];
}
