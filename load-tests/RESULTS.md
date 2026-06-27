# Load-test results

Curated headline numbers from the k6 suite. Regenerate raw data with `./run.sh --sweep` (see
[`README.md`](README.md)); `results/` is scratch, this file is the committed record.

The centerpiece is the **single- vs multi-thread before/after** — the experiment the whole load
plan was built to run (`PLAN.md`). Same binary, `THREADS=1` vs `THREADS=8`, swept across the VU
curve. A third pass hits the live Fly deployment for an absolute-over-the-internet reference.

## Run

| | |
|---|---|
| **Date** | 2026-06-27 |
| **Machine** | AMD Ryzen 7 5800X (8C/16T), Windows 11 |
| **Build** | `odin build src -o:speed` (dev-2026-06) |
| **Configs** | `THREADS=1` (was the only mode) vs `THREADS=8` (one nbio loop per core), same binary |
| **Generator** | k6 v2.0.0, **co-located** (loopback `127.0.0.1`) — shares the 16 hw threads |
| **Window** | 20s measured, 4s warmup, fresh server per scenario × VU level |

> **Caveat — relative, not absolute.** The generator shares the box, so at high VUs k6 and the
> server fight for the same cores; loopback also hides NIC cost. Solid for *comparison* (the whole
> point here), **not** a real-world ceiling. `RPS` = `http_reqs/s`; `static`/`pages`/`write` issue
> 2 requests per iteration, `search`/`api`/`mixed` issue 1.

## Headline: 1 → 8 threads

Two things happen at once when the store stops being single-threaded: **read throughput scales
~5×**, and the **overload failures disappear**.

**Throughput at 100 VUs** (a loaded-but-not-pathological point):

| scenario | RPS @ 1 thread | RPS @ 8 threads | speedup | p99 @1T → @8T |
|---|---:|---:|---:|---:|
| search | 9 853  | 53 978 | **5.5×** | 18.2 → 6.1 ms |
| mixed  | 8 894  | 46 185 | **5.2×** | 21.7 → 7.2 ms |
| pages  | 9 627  | 49 495 | **5.1×** | 24.2 → 8.5 ms |
| api    | 8 428  | 42 728 | **5.1×** | 23.3 → 7.7 ms |
| static | 11 700 | 40 321 | **3.4×** | 12.9 → 11.1 ms |
| write  | 23 307 | 43 996 | **1.9×** | 9.3 → 5.4 ms |

**Overload behaviour at 500 VUs** — the single thread starved (its one accept loop couldn't keep
up, connections timed out); eight threads absorb it cleanly:

| scenario | fail% @ 1 thread | fail% @ 8 threads |
|---|---:|---:|
| mixed  | 34.0% | **0.0%** |
| api    | 18.7% | **0.0%** |
| pages  | 14.7% | **0.0%** |
| search | 13.6% | **0.0%** |
| static | 12.6% | **0.0%** |
| write  | 1.6%  | **0.0%** |

## Per-scenario before/after sweep

RPS and p99 at each VU level, 1 thread vs 8. The pattern: single-thread saturates by ~10 VUs;
eight threads push the knee out to ~50 VUs at 4–5× the throughput, then hold flat with low
latency where the single thread was already shedding load.

### search — `GET /search?q=` (HTMX fragment)

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T |
|---:|---:|---:|---:|---:|---:|
| 1   | 4 036  | 4 315  | 1.1 | 0.9  | 0.7  |
| 10  | 10 553 | 37 259 | 3.5 | 2.2  | 1.6  |
| 50  | 10 228 | 54 710 | 5.3 | 9.0  | 3.1  |
| 100 | 9 853  | 53 978 | 5.5 | 18.2 | 6.1  |
| 200 | 9 510  | 50 450 | 5.3 | 37.6 | 10.4 |
| 500 | 10 666 | 45 826 | 4.3 | 94.1 | 20.2 |

### api — `GET /api/search?q=` (`json.marshal`)

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 431 | 3 635  | 1.1 | 0.8   | 0.7  |
| 10  | 8 720 | 30 524 | 3.5 | 2.6   | 1.6  |
| 50  | 8 511 | 43 313 | 5.1 | 11.6  | 3.5  |
| 100 | 8 428 | 42 728 | 5.1 | 23.3  | 7.7  |
| 200 | 8 198 | 41 085 | 5.0 | 48.9  | 14.2 |
| 500 | 9 770 | 42 483 | 4.3 | 119.1 | 33.0 |

### pages — `GET /` and `/data` (full HTML)

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T |
|---:|---:|---:|---:|---:|---:|
| 1   | 4 127  | 4 249  | 1.0 | 0.8   | 0.7  |
| 10  | 11 869 | 38 253 | 3.2 | 2.3   | 1.6  |
| 50  | 10 624 | 53 388 | 5.0 | 10.9  | 3.7  |
| 100 | 9 627  | 49 495 | 5.1 | 24.2  | 8.5  |
| 200 | 9 272  | 43 754 | 4.7 | 49.3  | 19.4 |
| 500 | 10 803 | 35 611 | 3.3 | 119.7 | 53.1 |

### mixed — ~90% read / ~10% write

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T |
|---:|---:|---:|---:|---:|---:|
| 1   | 4 226  | 4 338  | 1.0 | 0.7   | 0.7  |
| 10  | 11 398 | 34 862 | 3.1 | 2.1   | 1.6  |
| 50  | 9 932  | 47 205 | 4.8 | 9.8   | 3.4  |
| 100 | 8 894  | 46 185 | 5.2 | 21.7  | 7.2  |
| 200 | 7 698  | 43 616 | 5.7 | 50.2  | 13.3 |
| 500 | 7 687  | 34 258 | 4.5 | 179.5 | 31.5 |

### static — `GET /static/{app.css, htmx.min.js}` (embedded bytes)

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T | MB/s 8T |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 306  | 4 618  | 1.1 | 1.0  | 0.7  | 234 |
| 10  | 16 229 | 40 295 | 2.5 | 1.8  | 1.6  | 1 948 |
| 50  | 13 241 | 49 813 | 3.8 | 6.3  | 4.3  | **2 390** |
| 100 | 11 700 | 40 321 | 3.4 | 12.9 | 11.1 | 1 942 |
| 200 | 10 373 | 30 324 | 2.9 | 29.0 | 27.8 | 1 483 |
| 500 | 12 320 | 24 605 | 2.0 | 66.2 | 67.3 | 1 206 |

### write — `POST /contacts` + `DELETE` (create→delete)

| VUs | RPS 1T | RPS 8T | × | p99 1T | p99 8T |
|---:|---:|---:|---:|---:|---:|
| 1   | 4 119  | 4 286  | 1.0 | 1.0  | 0.7  |
| 10  | 23 081 | 34 478 | 1.5 | 1.6  | 1.6  |
| 50  | 25 302 | 44 191 | 1.7 | 4.6  | 3.5  |
| 100 | 23 307 | 43 996 | 1.9 | 9.3  | 5.4  |
| 200 | 20 691 | 41 638 | 2.0 | 20.6 | 8.8  |
| 500 | 19 146 | 39 696 | 2.1 | 64.2 | 19.1 |

## Reading

**Reads scale ~5×, almost linearly with the 8 cores.** `search`, `api`, `pages` and `mixed` all
land between 5.0× and 5.5× at their plateau. It isn't a clean 8× because the k6 generator is
eating cores on the *same* box (16 hw threads shared between server and load tool) and because the
shared lock + per-read snapshot aren't free — but ~5× on 8 cores against a co-located generator is
the read scaling the RW_Mutex was supposed to buy. The shared read lock does its job: readers run
in parallel.

**Writes scale ~1.8–2×, and that's the lock talking.** `repo_create`/`repo_delete` take the
*exclusive* lock, so the actual store mutation is serialised no matter how many threads are up —
exactly the contention the plan flagged. Writes still nearly double because most of a write
request (body parse, validation, rendering the row + toast) happens outside the lock and *does*
parallelise; only the brief mutation serialises. For this workload that's the right trade: cheap
reads in parallel, correctness on writes.

**The overload cliff is gone.** At 500 VUs the single thread was dropping 13–34% of requests on
the read scenarios — one accept loop can't service 500 concurrent connections while also doing the
work. Eight threads serve **0.0% errors at every level**, 500 VUs included. This robustness win is
arguably bigger than the throughput one: the server stops falling over under a thundering herd.

**`static` scales least (~3×)** because past a point it's bandwidth/memcpy-bound, not CPU-bound —
but it still peaks at a remarkable **~2.4 GB/s** over loopback at 50 VUs (8T) before the shared box
runs out of cores at 200–500 VUs. `static` is the one scenario where 8 threads *and* the generator
together saturate the machine, so its high-VU numbers dip.

**The knee moved out and up.** Single-thread throughput peaked at ~10 VUs and then only latency
grew; eight threads keep climbing to ~50 VUs and hold a 4–5× plateau with p99 in low single-digit
ms where the single thread was already at 10–25 ms.

## Prod — live Fly deployment

Modest sweep (1 / 10 / 50 VUs, 10s) from the workstation against
`https://odin-htmx-skeleton.fly.dev`. **0% errors at every level**, every scenario — the
deployed multithreaded build is healthy.

| scenario | RPS @1 | RPS @10 | RPS @50 | p50 | p99 @50 |
|---|---:|---:|---:|---:|---:|
| write  | 6.7 | 67 | **300** | ~122–129 ms | 193 ms |
| search | 6.7 | 67 | 275 | ~124–156 ms | 244 ms |
| api    | 6.8 | 66 | 274 | ~121–158 ms | 193 ms |
| pages  | 6.1 | 61 | 254 | ~133–157 ms | 259 ms |
| static | 5.1 | 54 | 240 | ~150–161 ms | 308 ms |
| mixed  | 6.6 | 52 | 197 | ~125–160 ms | 614 ms |

The shape is pure **Little's Law over the wire**: latency is pinned near the **~130 ms RTT** to
the Fly region (server time is sub-ms to single-digit-ms, per the local runs — invisible under the
network floor), so throughput ≈ concurrency ÷ RTT and climbs almost linearly with VUs (1 → ~6 RPS,
50 → ~250–300 RPS). One always-on `shared-cpu-1x` sustained **~250–300 RPS from a single remote
client at 50 connections with zero errors**. `static` moved ~11 MB/s at 50 VUs — RTT/proxy-bound,
nowhere near the 2.4 GB/s loopback ceiling, as expected over the internet. `mixed`'s fatter tail
(p99 ~600 ms) is the write branch queueing on the single vCPU. As flagged, the 1→8 thread scaling
does **not** show here — the box has one core — so this pass is a health-and-sizing check, not a
threading comparison.

> **Caveats specific to prod.** This is one always-on **`shared-cpu-1x` / 1 vCPU** Fly machine,
> hit **over the public internet** through Fly's proxy. So (a) latency is dominated by RTT, not
> server time — the sub-ms loopback floor becomes tens of ms; (b) throughput is capped by one
> shared vCPU, so the multi-thread scaling above does **not** reproduce here (the box has one
> core to give); (c) absolute numbers reflect a $0–5/mo demo host, not the server's capability.
> The point of this pass is a sanity check that the deployed build behaves and to size what the
> free tier sustains, not to compare against the 16-thread workstation.

## Open / follow-ups

- **Two-host absolute numbers.** Everything here is co-located (local) or RTT-bound (prod). The
  real ceiling needs generator and target on separate hosts over a real link — a dedicated Fly
  machine or the Oracle Always-Free VM, generator elsewhere (`PLAN.md`, [`../infra/PLAN.md`](../infra/PLAN.md)).
- **Write-path scaling** is lock-bound by design. If writes ever became hot, the next step would be
  a sharded or finer-grained store — but for a read-heavy app the single exclusive writer is the
  right simplicity/perf trade, now quantified.
