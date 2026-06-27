# Load tests — plan

> Status: **implemented, headline result in.** The k6 scenarios, the `run.sh`/`run.bat` driver,
> and `RESULTS.md` are in the repo — see [`README.md`](README.md) to run them and
> [`RESULTS.md`](RESULTS.md) for the numbers. The headline **thread-count before/after** is done:
> the store is now guarded by an `sync.RW_Mutex` and `thread_count` defaults to the core count,
> and reads scale ~5× (1→8 threads) while the overload failures vanish. This document is kept as
> the design rationale; the remaining open item is **two-host absolute numbers** (everything so
> far is co-located or RTT-bound).

## Goal

Measure how the Odin / `odin-http` server holds up under concurrency: throughput (RPS) and
latency (p50/p90/p95/p99) per endpoint, where latency knees as load climbs, and — the
interesting one — the ceiling imposed by the **single-threaded event loop**.

The server runs `thread_count = 1` on purpose so the in-memory store can stay lock-free (see
`app/src/repository/repository.odin`). Load testing is exactly the trigger to revisit that
decision: first
quantify the single-thread ceiling, then re-run with `thread_count = N` — which only becomes
correct once the store is guarded. That before/after is a headline result, not a footnote.

## Tooling

Two layers, both single static binaries (no `npm`, in keeping with the project):

- **`bombardier`** (or `oha` / `wrk`) — quick raw-throughput baselines per endpoint. Point,
  shoot, read RPS and a latency histogram.
- **`k6`** — scenario-based mixed workloads with ramping VUs and pass/fail thresholds. Its
  scripts are k6's own JS runtime, not a Node project. This is the primary tool; bombardier
  is for fast sanity baselines.

## Layout

```
load-tests/
  scenarios/
    static.js        # GET /static/app.css + /static/htmx.min.js  (best case, file serving)
    pages.js         # GET / and /data                            (HTML build cost in Odin)
    search.js        # GET /search?q=…                            (filter + highlight)
    api.js           # GET /api/search?q=…                        (json.marshal cost)
    write.js         # POST /contacts (+ DELETE)                  (mutates the store)
    mixed.js         # ~90% read / 10% write, realistic blend
  run.sh / run.bat   # build app, launch server, run each tool, collect results/
  results/           # raw output + a generated summary table (gitignored)
  RESULTS.md         # template: machine, build flags, table per scenario, the thread note
```

## Method

- Build the app `-o:speed` (the showcase build is unoptimised; load-test the fast one).
- Launch a fresh `bin/demo.exe` per scenario on a dedicated port; parse the `listening` line.
- Warm up ~5s, then a fixed 30s window per run. Sweep concurrency: 1, 10, 50, 100, 200, 500
  VUs; record the curve and the knee.
- Loopback hides NIC cost and shares CPU with the load generator — fine for relative
  comparisons, noted as a caveat for absolute numbers. A second machine over a real link is
  the follow-up for headline figures.

## Metrics

RPS, latency p50/p90/p95/p99 and max, error/non-2xx rate, throughput in bytes/s. k6
thresholds turn these into pass/fail (e.g. `http_req_duration p(95) < 25ms` at 100 VUs,
`http_req_failed < 1%`).

## The write path needs care

`POST /contacts` grows the store for the whole run, so search/sort/render costs drift upward
and memory climbs — it won't hold steady like the read scenarios. Options, in order of
preference:
1. Restart the server between write-heavy runs for clean, comparable baselines.
2. Add a test-only reset/reseed endpoint, compiled behind a build flag so it never ships.
3. Accept the drift and report it as a degradation curve (store size vs latency) — itself an
   interesting result.

Also: because the loop is single-threaded, concurrent writes are already serialised, so
there's no data race to chase — only a throughput ceiling to measure.

## What we expect to learn

- Static and JSON endpoints should top out highest; HTML-page endpoints cost more (the
  builder work) but should still be cheap.
- A clear single-thread RPS ceiling where p99 climbs sharply.
- After adding a store lock and `thread_count = N`: how close to linear the read-heavy
  scenarios scale, and what the write path's contention looks like. This is the data that
  would justify (or not) moving off the lock-free single-thread design.

## Parity with e2e

Per the policy in `CLAUDE.md`: every endpoint measured here must also have a behaviour test in
`e2e/`. When you add a load scenario for a new endpoint, add its e2e scenario in the same
change (or file a TODO). The two suites cover the same surface from two angles.

## CI (optional)

A nightly job that runs the read scenarios and fails on threshold regressions, with results
committed to `RESULTS.md`. Keep write/stress runs manual — they're noisier and longer.

Where this runs (dedicated env vs. shared runners, k6 Cloud free tier): see
[`infra/PLAN.md`](../infra/PLAN.md).
