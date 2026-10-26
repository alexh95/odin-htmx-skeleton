# Load tests

Throughput/latency tests for the `odin-http` server, driven by **[k6](https://k6.io)**
(single static binary, no npm — in keeping with the project). The design rationale and the
single-thread-ceiling investigation live in [`PLAN.md`](PLAN.md); this is the operating manual.

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
a sweep; `--strict` makes any breached run exit 1. CI doesn't run this suite: shared runners measure
the neighbours as much as the server (see `PLAN.md`).

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

The ten skeleton scenarios (static, seo, pages, list, search, api, detail, write, mixed, scale) are
the parity gate's, unchanged from the skeleton so the same files measure HEAD and v1.1.1.

Each shares `lib/config.js` (knobs) and `lib/options.js` (the warmup→measured-window shape,
thresholds, and the dependency-free JSON/CSV summary).

## Caveats

Loopback hides NIC cost and the load generator shares CPU with the server, so these are solid
for **relative** comparison (regressions, the thread-count before/after) but not absolute
headline figures — for those, generator and target belong on separate hosts (see `PLAN.md` and
[`../infra/PLAN.md`](../infra/PLAN.md)).

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
median paired ratio ≥ 0.97, no round below 0.85 and p99 ≤ 1.10×. Run it on both legs (Windows and
Linux on WSL2); about 80 minutes of measurement each.
