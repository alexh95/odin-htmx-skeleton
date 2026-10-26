// S0.5: /ui/ping latency at a fixed arrival rate, with LOGINS logins/s alongside (0 = none).
//   k6 run -e BASE=http://127.0.0.1:8080 -e PING_RPS=4000 -e LOGINS=50 -e WARM=5s -e DUR=30s -e OUT=x.json p99.js
// Open model on purpose: the ping rate stays fixed whatever the logins cost, so a slower loop
// shows up as latency instead of hiding as fewer requests.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE || 'http://127.0.0.1:8080';
const PING_RPS = parseInt(__ENV.PING_RPS || '4000', 10);
const LOGINS = parseInt(__ENV.LOGINS || '0', 10);
const WARM = __ENV.WARM || '5s';
const DUR = __ENV.DUR || '30s';
const BODY = 'user=alice&pass=correct%20horse%20battery%20staple';

const scenarios = {
  warm: {
    executor: 'constant-arrival-rate', exec: 'ping', rate: PING_RPS, timeUnit: '1s',
    duration: WARM, preAllocatedVUs: 100, maxVUs: 1000, gracefulStop: '0s', tags: { phase: 'warm' },
  },
  ping: {
    executor: 'constant-arrival-rate', exec: 'ping', rate: PING_RPS, timeUnit: '1s', startTime: WARM,
    duration: DUR, preAllocatedVUs: 100, maxVUs: 1000, tags: { phase: 'load' },
  },
};
if (LOGINS > 0) {
  // Logins run through the warm-up too, so the pool is in its steady state when the window opens.
  scenarios.login = {
    executor: 'constant-arrival-rate', exec: 'login', rate: LOGINS, timeUnit: '1s',
    duration: `${parseInt(WARM, 10) + parseInt(DUR, 10)}s`, preAllocatedVUs: 20, maxVUs: 400,
    tags: { phase: 'login' },
  };
}

export const options = {
  discardResponseBodies: true,
  scenarios,
  thresholds: {
    'http_req_duration{scenario:ping}': ['p(99)>=0'],
    'http_reqs{scenario:ping}': ['count>=0'],
    'http_req_duration{scenario:login}': ['p(99)>=0'],
    'http_reqs{scenario:login,status:200}': ['count>=0'],
    'http_reqs{scenario:login,status:503}': ['count>=0'],
    'dropped_iterations{scenario:ping}': ['count>=0'],
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(90)', 'p(99)', 'p(99.9)', 'max'],
};

export function ping() {
  const r = http.get(`${BASE}/ui/ping`);
  check(r, { 'ping 200': (x) => x.status === 200 });
}

export function login() {
  http.post(`${BASE}/login`, BODY, { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
}

export function handleSummary(data) {
  const m = data.metrics;
  const v = (name, k) => (m[name] && m[name].values ? m[name].values[k] : 0);
  const d = 'http_req_duration{scenario:ping}';
  const out = {
    ping_rps: v('http_reqs{scenario:ping}', 'count') / parseInt(DUR, 10),
    ping_p50: v(d, 'p(50)'), ping_p90: v(d, 'p(90)'), ping_p99: v(d, 'p(99)'), ping_p999: v(d, 'p(99.9)'),
    ping_max: v(d, 'max'),
    ping_dropped: v('dropped_iterations{scenario:ping}', 'count'),
    login_200: v('http_reqs{scenario:login,status:200}', 'count'),
    login_503: v('http_reqs{scenario:login,status:503}', 'count'),
    login_p50: v('http_req_duration{scenario:login}', 'p(50)'),
    login_p99: v('http_req_duration{scenario:login}', 'p(99)'),
  };
  return { [__ENV.OUT || 'p99.json']: JSON.stringify(out) };
}
