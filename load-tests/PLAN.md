# Load tests — design

The operating manual is [`README.md`](README.md); the numbers the skeleton recorded are in
[`RESULTS.md`](RESULTS.md); the performance plan for the whole starter (budgets, the parity gate)
is `docs/PLAN.md` §18. This is the why behind the harness.

## Goal

Measure how each profile holds up under concurrency: throughput (RPS) and latency (p50 to p99) per
endpoint, where the knee is as load climbs, and whether a change made it slower. Two uses:

- **Relative**: a sweep or a quick run on one box, before and after a change.
- **The parity gate**: `run.sh --parity` holds `skeleton` to the skeleton's last two releases on the
  same box, the same scenarios and the same SQLite library, paired round by round (PLAN §18.2).

## Tooling

Single static binaries, no npm: **k6** for the scenarios (its own JS runtime, with warmup and
measured phases and thresholds), and optionally **bombardier** for raw-throughput baselines.

## Method

- Build the profile `-o:speed` through `build.sh` (load-test the fast build).
- A **fresh server per scenario × VU level**, on a port nothing else listens on, so every run starts
  from the seed: the write path grows the store for the length of a run, and a clean baseline per
  run keeps runs comparable. (Each write scenario also deletes what it creates where it can.)
- Warm up, then a fixed measured window; the summary reports the measured phase only.
- Loopback hides NIC cost and shares the CPU with the generator: fine for relative numbers, a caveat
  for absolute ones. The parity gate samples the box's background CPU before each block and re-runs
  a round past 20 %.

## Scenarios per feature

Scenarios live with the feature they measure (`scenarios/<f>/`) and carry the e2e suite's tags, so a
profile runs exactly the scenarios its build mounts. The skeleton's ten (static, seo, pages, list,
search, api, detail, write, mixed, scale) stay as the skeleton wrote them: the gate runs the same
files against the old releases.

## Route coverage

Every server the driver starts is scraped for its per-route request counters before it stops;
`tools/check parity` holds them, and e2e's, to the profile's routes (PLAN §19.1.11).

## CI

Shared runners measure their neighbours as much as the server, so CI gates on nothing absolute: its
`coverage` job runs the quick run for route coverage only. The gate runs on the dev PC, on both legs
(Windows and Linux).
