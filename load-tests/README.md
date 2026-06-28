# Load tests

Throughput/latency tests for the `odin-http` server, driven by **[k6](https://k6.io)**
(single static binary, no npm — in keeping with the project). The design rationale and the
single-thread-ceiling investigation live in [`PLAN.md`](PLAN.md); this is the operating manual.

## Prerequisites

- **k6** — `winget install GrafanaLabs.k6` (Windows) · `brew install k6` (macOS) ·
  [other installers](https://grafana.com/docs/k6/latest/set-up/install-k6/). The run script
  also finds it at `C:\Program Files\k6\k6.exe`, or set `K6=/path/to/k6`.
- **Odin** on `PATH` (to build the app under test) — not needed with `--base`.
- **Git Bash** on Windows (`run.bat` shells out to `run.sh` — one driver, both platforms).
- *Optional:* **bombardier** for raw-throughput baselines; used only if it's on `PATH`.

## Run

```sh
./run.sh --quick                 # ~30s sanity: 20 VUs, short window, all scenarios
./run.sh                         # default sweep: 10,50,100 VUs over all scenarios
./run.sh --sweep                 # full curve: 1,10,50,100,200,500 VUs (the knee hunt)
./run.sh --vus 1,100,500 api     # explicit levels, one scenario
./run.sh --base https://odin-htmx-skeleton.fly.dev   # hit prod; skips build + local server
```

`run.bat` takes the same arguments on Windows. Env overrides: `DURATION` (30s), `WARMUP` (5s),
`P95`/`P99` (latency gate, ms), `PORT_BASE` (8090), `K6`, `BOMBARDIER`.

The driver builds the app `-o:speed`, then for **each scenario × VU level** launches a *fresh*
server on its own port (clean in-memory store), waits on `/healthz`, runs a warmup + measured
window, and tears it down. Everything lands in `results/` (git-ignored):

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
| `static.js` | `GET /static/{app.css,htmx.min.js}` | Embedded bytes from memory — the ceiling. |
| `pages.js`  | `GET /` and `/data` | Full-page HTML built by Odin (the view layer). |
| `list.js`   | `GET /contacts?status=&sort=` | The table region fragment — quick-filter + sort + paginate. |
| `search.js` | `GET /search?q=` | HTMX live-search fragment (filter + row render). |
| `api.js`    | `GET /api/search?q=` | Same filter via `json.marshal` (no HTML). |
| `detail.js` | `GET /contacts/:id` | Detail drilldown — get + derived activity trail + related scan. |
| `write.js`  | `POST /contacts` + `DELETE` | The mutating path; create→delete keeps the store steady. |
| `mixed.js`  | ~90% read / ~10% write | A realistic blend; bounded by the pure scenarios. |

Each shares `lib/config.js` (knobs) and `lib/options.js` (the warmup→measured-window shape,
thresholds, and the dependency-free JSON/CSV summary).

## Caveats

Loopback hides NIC cost and the load generator shares CPU with the server, so these are solid
for **relative** comparison (regressions, the thread-count before/after) but not absolute
headline figures — for those, generator and target belong on separate hosts (see `PLAN.md` and
[`../infra/PLAN.md`](../infra/PLAN.md)).

## Keep in sync with e2e

Per `CLAUDE.md`: every endpoint measured here also has a behaviour test in [`../e2e/`](../e2e).
Add an endpoint → add both its e2e scenario and its load scenario in the same change.
