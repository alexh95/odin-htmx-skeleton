# Load tests

Throughput/latency tests for the `odin-http` server, driven by **[k6](https://k6.io)**
(single static binary, no npm — in keeping with the project). The design rationale lives in
[`PLAN.md`](PLAN.md), the skeleton's recorded numbers in [`RESULTS.md`](RESULTS.md); this is the
operating manual.

## Prerequisites

- **k6** — `winget install GrafanaLabs.k6` (Windows) · `brew install k6` (macOS) ·
  [other installers](https://grafana.com/docs/k6/latest/set-up/install-k6/). The run script
  also finds it at `C:\Program Files\k6\k6.exe`, or set `K6=/path/to/k6`.
- **Odin** + a **C toolchain** on `PATH` (to build the app under test, which links SQLite) — not
  needed with `--base`. Run `app/prepare.*` once first so `vendor/sqlite/` is built.
- **Git Bash** on Windows (`run.bat` shells out to `run.sh` — one driver, both platforms).
- *Optional:* **bombardier** for raw-throughput baselines; used only if it's on `PATH`.

## Run

```sh
./run.sh --quick                 # ~30s sanity: 20 VUs, short window, all scenarios
./run.sh                         # default sweep: 10,50,100 VUs over all scenarios
./run.sh --sweep                 # full curve: 1,10,50,100,200,500 VUs (the knee hunt)
./run.sh --vus 1,100,500 api     # explicit levels, one scenario
./run.sh --base https://odin-htmx-skeleton.fly.dev   # hit prod; skips build + local server
./run.sh --quick --strict        # as a gate: exit 1 if any run breaches its thresholds
PROFILE=minimal ./run.sh --quick # another profile (skeleton by default)
./run.sh --parity                # the parity gate (PLAN §18.2): see below
```

`run.bat` takes the same arguments on Windows. Env overrides: `DURATION` (30s), `WARMUP` (5s),
`P95`/`P99` (latency gate, ms), `PORT_BASE` (8090), `K6`, `BOMBARDIER`.

With no scenario names it runs every scenario of the profile's features, so a new scenario is
just a new file. Scenarios live per feature, `scenarios/<f>/<name>.js`, and each has a
`// tags: @<f> …` line naming every feature it touches, as the e2e specs are tagged; the driver asks
the built binary what it mounts (`--features --json`) and takes the scenarios whose tags it has.
A scenario's name is its file's, and names are unique across features.

**What fails a run.** Each scenario's thresholds: under 1% failed requests and p95/p99 under
`P95`/`P99` in the measured window (plus any scenario-specific check rate). A breach is reported and
the sweep carries on. By default the driver still exits 0, because finding the knee is the point of
a sweep; `--strict` makes any breached run exit 1. CI runs only the quick run, for route coverage:
shared runners measure the neighbours as much as the server (see `PLAN.md`).

The driver builds the profile `-o:speed` through `../build.sh`, then for **each scenario × VU
level** launches a *fresh* server on its own port (clean `:memory:` store; a port something else
already listens on is skipped, since Windows lets a second server bind it), waits on `/healthz`,
runs a warmup + measured window, keeps the server's per-route request counters, and tears it down.
Everything lands in `results/` (git-ignored), and the counters in
`../app/build/coverage/load/<profile>/` for `tools/check parity`:

```
results/
  summary.md            generated table, also printed at the end
  raw/<scenario>_<vus>.json   per-run k6 summary (RPS, latency percentiles, bytes/s)
  raw/<scenario>_<vus>.csv    one row per run (what summary.md is stitched from)
  raw/server_<port>.log       the app's stdout/stderr for that run
  raw/bombardier.txt          optional baselines, if bombardier was present
```

Curated headline numbers get hand-copied into [`RESULTS.md`](RESULTS.md) (committed); `results/`
itself is scratch.

## Scenarios

| File | Endpoint(s) | Measures |
|---|---|---|
| `platform/static.js` | `GET /static/{app.css,htmx.min.js}` | Embedded bytes from memory — the ceiling. |
| `platform/seo.js`    | `GET /robots.txt`, `/sitemap.xml` | The crawler contract — a fixed string plus a walk over the nav. |
| `platform/ops.js`    | the probes, `/metrics`, `/licenses`, `/favicon.ico`, the ownership proofs | What operators and crawlers' owners poll. |
| `dashboard/pages.js` | `GET /` and `/data` | Full-page HTML built by Odin (the view layer). |
| `dashboard/ping.js`  | `GET /ui/ping` | The cheapest fragment. |
| `gallery/gallery.js` | `/components`, `/forms`, the `/ui/*` fragments, `/validate/email`, `/forms/submit` | The gallery as a visitor uses it; a submit's contact is deleted again. |
| `contacts/list.js`   | `GET /contacts?status=&sort=` | The table region fragment — quick-filter + sort + paginate. |
| `contacts/search.js` | `GET /search?q=` | HTMX live-search fragment (filter + row render). |
| `contacts/api.js`    | `GET /api/search?q=` | Same filter via `json.marshal` (no HTML). |
| `contacts/detail.js` | `GET /contacts/:id` | Detail drilldown — get + the **events-timeline JOIN** + related scan. |
| `contacts/write.js`  | `POST` + `POST` + `DELETE` | The mutating path; create→edit→delete keeps the store steady. |
| `contacts/mixed.js`  | ~90% read / ~10% write | A realistic blend; bounded by the pure scenarios. |
| `contacts/scale.js`  | the list paths at 20k rows | Sizes the store's SQL paging, at 20 VUs. |
| `home/home.js`       | `GET /` (minimal) | The notes card's read. |
| `notes/notes.js`     | `POST /notes` | The notes card's one write. |
| `about/about.js`     | `GET /about` | The page shell around the profile's copy. |
| `lab/lab.js`         | the lab's pages, the resync refetch, a publish, `/lab/stats` | The contract pages, each rendering its live element and the hub's cursor. |
| `lab/streams.js`     | `/lab/sse/tick`, `/lab/multipart`, `/lab/mp/count`, `/events` + `/lab/close` | Streams that end, measured whole; `/events` subscribed and ended by a kick (k6 returns from an SSE request only at its end: fan-out is `tools/streamload`'s, PLAN §19.1.7). |
| `lab/sockets.js`     | the room page, then `/lab/ws/echo` and `/lab/ws/chat` | WebSocket round trips through `k6/websockets`, the room's through the hub. |
| `scripting/scripting.js` | the nonce class's four pages, `/scripting/hello`, `/scripting/score`, its SSE (`end=1`), multipart and WebSocket streams | A fresh nonce per response; the streams' four buttons. The socket opens every tenth iteration: one per iteration left loopback pairs in TIME_WAIT faster than Windows frees them, and the client's dials failed. |
| `compat/compat.js`   | `/compat`, `/compat/htmx2` with its save and refusal, `/compat/alpine`, the two pings | The refusal is a 422 by design (`expectedStatuses`). |
| `accounts/nick.js`   | `/login` (page, pick), `/logout` | The nickname form; a pick is a 303 and a signed cookie. |
| `audit/audit.js`     | `/admin/audit`, its next page, its CSV export | The audit log's reads as the test admin, signed in once per VU. |
| `accounts/members.js` | `/register`, `/accounts/profile`, `/reset`, `/admin/accounts` and each of its writes | A member registered each iteration (an argon hash), then the admin's changes with a reason, in a jar of its own. |
| `accounts/totp.js`   | `/accounts/totp`, `/step-up`, `/login/code`, new codes, off | Two-step sign-in's routes without turning it on; a step-up is an argon verify. |
| `accounts/live.js`   | a member page and its `/events` on `accounts.user` | The stream a revoke ends, held a moment and cut (out of the gates, as `chat_streams.js`). |
| `accounts/login.js`  | `/login` (page, sign-in), `/accounts/sessions`, sign-out or revoke, `/csp-report` once | A sign-in storm on `full`: one argon2id verify per iteration (503 busy is expected past the pool's queue); the gate is on the other pages (`kind:page`), which argon must not slow. run.sh boots the suites' test admin with the limits lifted. |
| `chat/chat.js`       | `/chat`, a room per transport in turn, the setting, a post (or its 429), the menu, edit, delete, read, typing, a CSP report | A member's requests; most posts meet the 5-per-10-s limit, whose 429 is measured too (`expectedStatuses`). |
| `chat/chat_streams.js` | the socket (snapshot, a message back), `/since` and its 304, `/parts` and `/events` held a moment | The live transports; the held streams are cut by the client and left out of the gates (`held:no`). |
| `notify/notify.js`   | `/notify`, `/notify/list`, `POST /notify/read` | A member's Inbox. |
| `bot/bot.js`         | `/bot`, a conversation, an answer per delivery in turn, a quick one, Stop | Whole mock answers (`BOT_DELAY_MS=0`, the hourly limits lifted): thousands of generations a quick run. |
| `ops/panel.js`       | `/admin/ops` per mode, `/admin/ops/panel` and its 304, `/admin/ops/parts` held | An admin's view of the 1 Hz panel (loopback is admin here). |
| `status/status.js`   | `/status` per mode, `/status/parts`, `/status/board` and its 304 | The status board, both ways. |

A nick build's scenarios sign in once per VU (`lib/nick.js`) and keep the jar across iterations
(`noCookiesReset`): k6 empties it each iteration otherwise. `run.sh`'s server counts loopback as the LAN and as
its admins, answers the bot at once and lifts its hourly limits. A scenario that holds streams and cuts them gates
only the requests tagged `held:no`, and the summary reads those.

The ten skeleton scenarios (static, seo, pages, list, search, api, detail, write, mixed, scale) are
the parity gate's, unchanged from the skeleton so the same files measure HEAD and v1.1.1.

Each shares `lib/config.js` (knobs) and `lib/options.js` (the warmup→measured-window shape,
thresholds, and the dependency-free JSON/CSV summary).

## Caveats

Loopback hides NIC cost and the load generator shares CPU with the server, so these are solid
for **relative** comparison (regressions, the thread-count before/after) but not absolute
headline figures — for those, generator and target belong on separate hosts (see `PLAN.md` and
[`../infra/PLAN.md`](../infra/PLAN.md)).

On Windows, a sweep's socket scenarios (`lab/sockets.js`, `lab/streams.js`) leave thousands of loopback pairs in
TIME_WAIT, which Windows holds for about two minutes; a scenario right after them can fail a few dials (k6 error
1213, every route of a VU at once) and breach the 1 % gate. Run alone, it is clean: read such a failure that way
before suspecting the server (`--out json` on k6 shows the codes).

## Keep in sync with e2e

Per `CLAUDE.md`: every endpoint measured here also has a behaviour test in [`../e2e/`](../e2e).
Add an endpoint → add both its e2e scenario and its load scenario in the same change. The servers'
per-route request counters check it: `tools/check parity` wants a non-zero count for every route
the profile mounts from both suites, or a waiver with its reason in `../tests/parity-waivers.txt`
(PLAN §19.1.11). It replaces the skeleton's `parity.sh`, a grep for path literals.

## The parity gate

`./run.sh --parity [scenario …]` runs PLAN §18.2's procedure (`lib/parity.sh`, spike S0.1's loop):
it builds HEAD (709bc94) and v1.1.1 into `../perf/baseline/` with `tools/baseline` when they aren't
there, builds `skeleton` -o:speed, and runs every variant back to back per round, scenario and store
(`:memory:` and a file DB; 200 VUs, `scale` at 20; 3 s warmup + 10 s window; n = 3 rounds; a fresh
server each). Rows go to `../perf/results/<version>-<leg>.csv`; `lib/parity.mjs` then prints the
pass rule's table: the reference is HEAD on `static` and `seo` and on the cells
`../tests/parity-waivers.txt` waives for this leg, max(HEAD, v1.1.1) elsewhere; a cell passes at a
median paired ratio ≥ 0.97 (or the bar of the cell's `perf-floor` line, an exception Alex accepted at
its measured level), no round below 0.85 and p99 ≤ 1.10×. Run it on both legs (Windows and
Linux on WSL2); about 80 minutes of measurement each.
