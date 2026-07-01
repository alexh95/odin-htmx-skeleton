# Load-test results

Curated headline numbers from the k6 suite. Regenerate raw data with `./run.sh --vus 1,10,50,100,200`
(see [`README.md`](README.md)); `results/` is scratch, this file is the committed record.

The centerpiece is the **single- vs multi-thread** comparison over the SQLite store — same binary,
`THREADS=1` vs `THREADS=16`, swept across the VU curve. It's the experiment the whole load plan was
built to run (`PLAN.md`): quantify the single-thread ceiling, then show what one nbio loop per core
buys once the store is guarded by an `RW_Mutex`.

## Run

| | |
|---|---|
| **Date** | 2026-07-01 (v1.0.0) |
| **Machine** | AMD Ryzen 7 5800X (8C/16T), Windows 11 |
| **Build** | `odin build src -o:speed` (dev-2026-06) |
| **Store** | **SQLite** amalgamation, `:memory:` (a real in-RAM SQLite; a `file` backend is compared separately) |
| **Configs** | `THREADS=1` vs `THREADS=16` (one nbio loop per hw thread), same binary |
| **Generator** | k6 v2.0.0, **co-located** (loopback `127.0.0.1`) — shares the 16 hw threads |
| **Window** | 10s measured, 3s warmup, fresh server per scenario × VU level, 0% errors throughout |

> **Caveat — relative, not absolute.** The generator shares the box, so at high VUs k6 and the
> server fight for the same cores; loopback also hides NIC cost (see the two-host section for a real
> wire). Solid for *comparison* — the point here — **not** a real-world ceiling. `RPS` =
> `http_reqs/s`; `static`/`pages`/`write` issue 2 requests per iteration, the rest 1.

## Headline: 1 → 16 threads (SQLite)

Guarding the store and running one nbio loop per core scales reads **~4×** with **0% errors** the
whole way up. **Throughput at 200 VUs** (single thread saturated, 16 threads loaded):

| scenario | RPS @1T | RPS @16T | speedup | p99 @1T → @16T |
|---|---:|---:|---:|---:|
| search | 8 105  | 37 237 | **4.6×** | 41.1 → 14.0 ms |
| pages  | 6 484  | 27 149 | **4.2×** | 65.3 → 32.0 ms |
| mixed  | 5 654  | 23 256 | **4.1×** | 63.4 → 19.6 ms |
| list   | 7 911  | 31 531 | **4.0×** | 44.0 → 22.4 ms |
| api    | 7 803  | 29 999 | **3.8×** | 50.2 → 19.4 ms |
| static | 9 457  | 21 361 | **2.3×** | 29.0 → 33.5 ms |
| write  | 13 268 | 27 922 | **2.1×** | 27.9 → 16.8 ms |
| detail | 8 676  | 16 716 | **1.9×** | 35.9 → 35.1 ms |

Reads land **~4×** on 8 cores (16 hw threads shared with the co-located generator). `write` and the
`detail` JOIN scale least — the single-connection exclusive lock, quantified below.

## Per-scenario before/after sweep

RPS and p99 at each VU level, 1 thread vs 16. The single thread saturates by ~10 VUs; sixteen
threads push the knee out to ~50 VUs at 4×+ the throughput, then hold low-latency where the single
thread is already shedding.

### search — `GET /search?q=` (HTMX fragment)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 685 | 3 649  | 1.0 | 1.0  | 1.0  |
| 10  | 8 687 | 26 536 | 3.1 | 2.5  | 1.7  |
| 50  | 8 619 | 35 742 | 4.1 | 9.7  | 4.7  |
| 100 | 8 335 | 35 487 | 4.3 | 20.2 | 10.9 |
| 200 | 8 105 | 37 237 | 4.6 | 41.1 | 14.0 |

### api — `GET /api/search?q=` (`json.marshal`)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 086 | 3 119  | 1.0 | 0.8  | 1.0  |
| 10  | 7 326 | 24 168 | 3.3 | 3.1  | 1.7  |
| 50  | 7 209 | 31 636 | 4.4 | 12.4 | 4.8  |
| 100 | 7 039 | 32 230 | 4.6 | 26.0 | 8.6  |
| 200 | 7 803 | 29 999 | 3.8 | 50.2 | 19.4 |

### pages — `GET /` and `/data` (full HTML)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 424 | 3 478  | 1.0 | 0.8  | 0.8  |
| 10  | 7 752 | 27 001 | 3.5 | 3.1  | 1.7  |
| 50  | 7 061 | 33 059 | 4.7 | 15.4 | 5.6  |
| 100 | 6 691 | 30 329 | 4.5 | 32.0 | 12.4 |
| 200 | 6 484 | 27 149 | 4.2 | 65.3 | 32.0 |

### list — `GET /contacts` (filter/sort/paginate)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 502 | 3 508  | 1.0 | 1.0  | 1.0  |
| 10  | 9 107 | 26 008 | 2.9 | 2.3  | 1.7  |
| 50  | 8 720 | 35 074 | 4.0 | 9.9  | 5.6  |
| 100 | 8 212 | 33 889 | 4.1 | 21.1 | 9.3  |
| 200 | 7 911 | 31 531 | 4.0 | 44.0 | 22.4 |

### mixed — ~90% read / ~10% write

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 476 | 3 437  | 1.0 | 0.9  | 1.0  |
| 10  | 8 440 | 25 050 | 3.0 | 2.6  | 1.7  |
| 50  | 7 643 | 27 939 | 3.7 | 11.9 | 7.7  |
| 100 | 6 624 | 26 700 | 4.0 | 26.8 | 13.5 |
| 200 | 5 654 | 23 256 | 4.1 | 63.4 | 19.6 |

### static — `GET /static/{app.css, htmx.min.js}` (embedded bytes)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T | MB/s 16T |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 017  | 4 063  | 1.0 | 0.8  | 0.8  | 278 |
| 10  | 14 678 | 31 277 | 2.1 | 1.7  | 1.6  | 2 030 |
| 50  | 11 622 | 34 977 | 3.0 | 6.3  | 6.1  | **2 282** |
| 100 | 9 960  | 26 266 | 2.6 | 14.0 | 15.7 | 1 734 |
| 200 | 9 457  | 21 361 | 2.3 | 29.0 | 33.5 | 1 425 |

### detail — `GET /contacts/:id` (the events JOIN + related scan)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 503  | 3 242  | 0.9 | 0.9  | 1.0  |
| 10  | 10 023 | 16 653 | 1.7 | 2.1  | 1.7  |
| 50  | 9 612  | 16 778 | 1.7 | 8.2  | 8.3  |
| 100 | 9 110  | 16 865 | 1.9 | 17.1 | 12.6 |
| 200 | 8 676  | 16 716 | 1.9 | 35.9 | 35.1 |

### write — `POST /contacts` + `DELETE` (create→delete)

| VUs | RPS 1T | RPS 16T | × | p99 1T | p99 16T |
|---:|---:|---:|---:|---:|---:|
| 1   | 3 581  | 3 600  | 1.0 | 1.0  | 1.0  |
| 10  | 14 655 | 25 493 | 1.7 | 1.8  | 1.7  |
| 50  | 14 989 | 29 061 | 1.9 | 6.2  | 4.9  |
| 100 | 13 758 | 28 475 | 2.1 | 12.2 | 10.8 |
| 200 | 13 268 | 27 922 | 2.1 | 27.9 | 16.8 |

## Reading

**Reads scale ~4× on the 8-core box.** `search`, `api`, `pages`, `list` and `mixed` all land between
3.8× and 4.6× at their plateau. It isn't a clean 8× (or 16×) for two reasons: the k6 generator eats
cores on the *same* machine, and — the structural one — SQLite's **v1 single shared connection takes
an *exclusive* lock on every op, reads included**. Only the DB section serialises; body parse, HTML
render and the response all parallelise, so throughput climbs until that critical section dominates.

**The `detail` JOIN is the clearest signal of that lock.** It scales worst (**1.9×**) and, at 16
threads, is **flat at ~16.7k RPS from 50 VUs up** — the events-timeline JOIN does the most work
*under* the lock, so it saturates its critical section early and adding threads buys nothing beyond
it. That is the concrete, measured trigger for the deferred optimisation: **per-thread WAL
connections**, which let readers run concurrently again (`docs/DATA_IMPL.md` §4). Re-run this after.

**Writes scale ~2×, and that's the lock talking.** `repo_create`/`repo_delete` take the exclusive
lock, so the mutation itself serialises no matter how many threads are up. Writes still nearly double
because most of a write request (body parse, validation, rendering the row + toast) happens outside
the lock and *does* parallelise. For a read-heavy app that's the right trade: cheap parallel reads,
correctness on writes.

**`static` scales least (~2–3×)** because past a point it's bandwidth/memcpy-bound, not CPU-bound —
but it still peaks at a remarkable **~2.3 GB/s** over loopback at 50 VUs (16T). Above that the shared
box runs out of cores (server + generator both want them) and the high-VU numbers dip. htmx 4 shrank
the embedded copy to ~36 KB, so the per-iteration payload is lighter than earlier (pre-4) runs.

**The knee moved out and up.** Single-thread throughput peaks at ~10 VUs and then only latency grows;
sixteen threads keep climbing to ~50 VUs and hold a 4× plateau with p99 in low single-digit ms where
the single thread is already at 10–25 ms. **0% errors at every level, 1 and 16 threads alike**
(through 200 VUs — the single-thread overload cliff at 500 VUs was characterised on the earlier
in-memory store; see below).

## Persistence — `:memory:` vs file

Same 16-thread server, `write` scenario at 200 VUs, `:memory:` vs a real file DB (WAL,
`synchronous=NORMAL`):

| backend | RPS | p99 ms | fail% |
|---|---:|---:|---:|
| `:memory:` | 27 922 | 16.8 | 0.0 |
| file (WAL, `synchronous=NORMAL`) | 9 358 | 39.7 | 0.0 |

A file DB costs **~3×** on writes — the WAL append + periodic fsync — exactly what `DATA.md`
predicted. Reads are unaffected (the working set is page-cached), so a persistent deploy keeps the
read profile above and pays only on the write path. **0% errors** throughout, `:memory:` and file
alike.

## Before SQLite — the in-memory store (historical)

The pre-SQLite store was a `[dynamic]Contact` slice under the same `RW_Mutex`. On the 06-27 in-memory
run, reads scaled **~5× (1→8 threads)** — *more* than SQLite's ~4× — because a slice can take a
**shared** read lock, so readers ran truly in parallel; and the single thread's overload cliff at
**500 VUs** (13–34% dropped requests on the read scenarios) went to **0%** at 8 threads. SQLite's v1
single connection trades that shared-read concurrency for persistence and durability (one connection
⇒ exclusive lock on reads too). Recovering concurrent reads is exactly what **per-thread WAL
connections** would buy — the load-justified next step. That store no longer exists; these numbers
are kept only to frame the trade.

## Prod — live Fly deployment

> Measured 2026-06-29 against `https://odin-htmx-skeleton.fly.dev`; RTT-bound and build-insensitive,
> so not re-run for 1.0. It's a sizing check for the free tier, not a threading comparison.

Modest sweep (1 / 10 / 50 VUs, 10s) from the workstation. **0% errors at every level**, every
scenario — the deployed multithreaded build is healthy.

| scenario | RPS @1 | RPS @10 | RPS @50 | p50 | p99 @50 |
|---|---:|---:|---:|---:|---:|
| write  | 6.7 | 67 | **300** | ~122–129 ms | 193 ms |
| search | 6.7 | 67 | 275 | ~124–156 ms | 244 ms |
| api    | 6.8 | 66 | 274 | ~121–158 ms | 193 ms |
| pages  | 6.1 | 61 | 254 | ~133–157 ms | 259 ms |
| static | 5.1 | 54 | 240 | ~150–161 ms | 308 ms |
| mixed  | 6.6 | 52 | 197 | ~125–160 ms | 614 ms |

The shape is pure **Little's Law over the wire**: latency is pinned near the **~130 ms RTT** to the
Fly region (server time is sub-ms to single-digit-ms, per the local runs — invisible under the
network floor), so throughput ≈ concurrency ÷ RTT and climbs almost linearly with VUs. One always-on
`shared-cpu-1x` sustained **~250–300 RPS from a single remote client at 50 connections with zero
errors**. `static` moved ~11 MB/s at 50 VUs — RTT/proxy-bound, nowhere near the 2.3 GB/s loopback
ceiling, as expected over the internet. The 1→N thread scaling does **not** show here — the box has
one shared vCPU — so this is a health-and-sizing check, not a threading comparison.

## Two-host: apollo-11 home server (real network)

> Measured 2026-06-28 — generator and target on **separate machines**, so unlike loopback these
> aren't fiction. Network-bound, so kept as-is for 1.0. **0% errors everywhere.**

k6 on the workstation (5800X) → 1 GbE LAN → **apollo-11** (Intel i3-7100, 2C/4T, 4 nbio threads,
Docker), deployed via [`../deploy/apollo-11`](../deploy/apollo-11).

### Direct (`http://<server-lan-ip>:8090`, no proxy)

| scenario | RPS @1 | @10 | @50 | @100 | @200 | p99 @100 | bound by |
|---|---:|---:|---:|---:|---:|---:|---|
| write  | 1 845 | 19 783 | 38 553 | 45 307 | 45 496 | 11.6 ms | CPU (i3, 4 threads) |
| search | 1 867 | 17 442 | 27 468 | 27 646 | 27 959 | 9.8 ms | CPU |
| api    | 1 796 | 16 315 | 21 987 | 22 445 | 22 548 | 9.3 ms | CPU |
| pages  | 1 577 |  7 166 |  7 091 |  7 075 |  7 072 | 34.6 ms | **1 GbE wire** |
| static | 1 170 |  2 296 |  2 295 |  2 261 |  2 266 | 106 ms | **1 GbE wire** |
| mixed  | 1 362 |  5 949 |  6 801 |  6 424 |  5 662 | 32.4 ms | mix |

Two regimes, and they're the whole point of going two-host:

- **Byte-heavy endpoints hit the wire, not the server.** `static` and `pages` flatline at
  **~114 MB/s ≈ 912 Mbit/s** — a saturated gigabit link — from 10 VUs up. On loopback `static` did
  **~2.3 GB/s**; over real Ethernet it's **114 MB/s**. That ~20× gap is the clearest lesson here:
  **loopback byte-throughput is fiction.** The bottleneck moved off the CPU and onto the NIC.
- **Small-response endpoints are CPU-bound on the i3** and scale fine: `search` ~27k, `api` ~22k,
  `write` ~45k RPS, p99 in single-digit ms, 0 errors — a modest 4-thread box comfortably handles
  tens of thousands of req/s when the payload is small.
- **At 1 VU everything is ~1.2–1.9k RPS**: one connection is RTT-bound by the ~0.5 ms LAN round trip
  (≈1/0.0005 = 2000/s ceiling). Concurrency amortizes it; that's why 10 VUs jumps ~10×.

### Through the reverse proxy (NPM + TLS subdomain)

Same suite through nginx-proxy-manager with a Let's Encrypt cert (Cloudflare DNS-only, so this is
NPM, not Cloudflare's edge). Everything collapses to a **~1–1.4k RPS** ceiling regardless of
endpoint — the convergence that means *the path*, not the app, is the limit. Attribution (api @ 50
VUs, RPS / p95):

| path | RPS | p95 | vs direct |
|---|---:|---:|---:|
| direct app `:8090` | 21 987 | 3.3 ms | 1× |
| NPM + TLS, **no** hairpin (k6 `hosts` → LAN IP) | 1 888 | 42 ms | **~12× slower** |
| subdomain (NAT hairpin + NPM + TLS) | 707 | 87 ms | ~31× slower |

The dominant cost is **NPM's TLS termination + proxying on the shared 2-core i3** — simultaneously
running the app container, Vaultwarden, a game server, etc., so TLS workers and the app's threads
fight for four hardware threads. The **NAT-loopback hairpin** (an artifact of load-testing the
*public* hostname from *inside* the LAN) adds a further ~2.7×. Neither reflects a real external
client, and neither is the Odin server's limit: the app itself does 22k RPS on this box. Takeaways:
terminate TLS on hardware that isn't also the workload, give nginx upstream keepalive, and don't
benchmark your own public hostname from behind your own NAT.

## Open / follow-ups

- **Per-thread WAL connections (SQLite).** The sweep above quantifies the v1 cost: one shared
  connection forces an exclusive lock on reads too, so they scale ~4× instead of ~5× (worst for the
  `detail` JOIN at 1.9×, flat past 50 VUs). Moving to one WAL connection per nbio thread should
  restore concurrent reads — the load-test-justified next optimisation (`docs/DATA_IMPL.md` §4).
  Re-run the headline after.
- **Write-path scaling** is lock-bound by design. If writes ever became hot, the next step would be a
  sharded or finer-grained store — but for a read-heavy app the single exclusive writer is the right
  simplicity/perf trade, now quantified (~2×).
- **A generator outside the LAN** would measure the true external path (real RTT + uplink + optionally
  Cloudflare's edge), rather than the NAT-hairpin artifact seen from inside.
- **File-DB read profile.** These runs measured the file backend only on the write path; a full
  file-DB read sweep (cold vs warm page cache) would confirm reads match `:memory:` as expected.
