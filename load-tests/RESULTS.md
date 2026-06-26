# Load-test results

Curated headline numbers from the k6 suite. Regenerate the raw data with `./run.sh --sweep`
(see [`README.md`](README.md)); `results/` is scratch, this file is the committed record.

## Run

| | |
|---|---|
| **Date** | 2026-06-27 |
| **Machine** | AMD Ryzen 7 5800X (8C/16T), Windows 11 |
| **Build** | `odin build src -o:speed` (dev-2026-06), `thread_count = 1` |
| **Generator** | k6 v2.0.0, **co-located** (loopback `127.0.0.1`) |
| **Window** | 20s measured, 4s warmup, fresh server per scenario × VU level |

> **Caveat — relative, not absolute.** The load generator shares the box (1 of 16 hardware
> threads serves; k6 takes the rest), and loopback hides NIC cost. These numbers are solid for
> *comparison* — endpoint vs endpoint, the saturation shape, future before/after — but they are
> **not** the server's real-world ceiling. For headline figures, put generator and target on
> separate hosts over a real link (`PLAN.md`, [`../infra/PLAN.md`](../infra/PLAN.md)).
>
> `RPS` is `http_reqs/s` (a fair server-throughput metric). Note the per-iteration request
> count differs: `static`, `pages` and `write` issue **2** requests per iteration; `search`,
> `api` and `mixed` issue **1**. So compare RPS as raw request throughput, not as "operations".

## Per-scenario sweep

Each table is one scenario across the VU curve. The pattern is identical everywhere: throughput
plateaus by ~10 VUs, then **latency grows roughly linearly with VUs while RPS stays flat** — one
busy thread, so added concurrency becomes queue depth, not work done (Little's Law in the flesh).

### static — `GET /static/{app.css, htmx.min.js}` (embedded bytes, the byte-throughput ceiling)

| VUs | RPS | p50 | p95 | p99 | max | fail | throughput |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 720  | 0.0  | 0.6  | 0.9  | 2.5    | 0%    | 237 MB/s |
| 10  | 18 546 | 0.0  | 1.6  | 1.7  | 12.7   | 0%    | **938 MB/s** |
| 50  | 15 921 | 2.6  | 4.6  | 5.1  | 35.5   | 0%    | 806 MB/s |
| 100 | 13 314 | 5.7  | 9.8  | 11.4 | 139.5  | 0%    | 674 MB/s |
| 200 | 12 389 | 11.8 | 21.5 | 23.8 | 584.4  | 0%    | 624 MB/s |
| 500 | 13 205 | 29.3 | 51.5 | 60.5 | 2307   | 9.7%  | 585 MB/s |

### write — `POST /contacts` + `DELETE` (create→delete, store held steady)

| VUs | RPS | p50 | p95 | p99 | max | fail |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 230  | 0.0  | 0.5  | 1.0  | 17.8  | 0%    |
| 10  | 23 585 | 0.0  | 1.5  | 1.6  | 5.3   | 0%    |
| 50  | **25 561** | 1.5 | 3.4 | 4.6 | 20.8 | 0%    |
| 100 | 24 393 | 3.1  | 7.2  | 9.2  | 62.0  | 0%    |
| 200 | 21 627 | 6.3  | 15.2 | 19.3 | 220.4 | 0%    |
| 500 | 19 759 | 18.1 | 37.0 | 61.9 | 890   | 2.2%  |

### pages — `GET /` and `/data` (full HTML built by Odin)

| VUs | RPS | p50 | p95 | p99 | max | fail | throughput |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 421  | 0.0  | 0.6  | 0.7   | 1.5   | 0%     | 73 MB/s |
| 10  | 12 351 | 0.5  | 1.6  | 2.1   | 4.7   | 0%     | 208 MB/s |
| 50  | 11 814 | 3.1  | 7.6  | 9.8   | 46.7  | 0%     | 198 MB/s |
| 100 | 11 094 | 6.1  | 15.4 | 21.0  | 160.6 | 0%     | 190 MB/s |
| 200 | 10 449 | 11.7 | 32.7 | 44.0  | 606.0 | 0%     | 177 MB/s |
| 500 | 11 780 | 27.6 | 81.0 | 110.6 | 2263  | 14.9%  | 165 MB/s |

### search — `GET /search?q=` (HTMX fragment: filter + row render)

| VUs | RPS | p50 | p95 | p99 | max | fail |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 384  | 0.0  | 0.6  | 0.8  | 1.8   | 0%    |
| 10  | 10 780 | 0.5  | 1.6  | 2.1  | 4.8   | 0%    |
| 50  | 10 793 | 3.2  | 6.7  | 8.4  | 47.5  | 0%    |
| 100 | 10 619 | 7.2  | 13.8 | 16.9 | 150.8 | 0%    |
| 200 | 10 194 | 14.0 | 28.2 | 35.1 | 527.4 | 0%    |
| 500 | 11 236 | 34.5 | 70.2 | 90.4 | 1946  | 13.3% |

### api — `GET /api/search?q=` (`json.marshal`, the costliest read)

| VUs | RPS | p50 | p95 | p99 | max | fail |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 3 679 | 0.0  | 0.6  | 0.8   | 1.5   | 0%    |
| 10  | 8 856 | 1.0  | 1.8  | 2.6   | 4.2   | 0%    |
| 50  | 8 888 | 4.6  | 8.3  | 10.8  | 56.4  | 0%    |
| 100 | 8 721 | 8.7  | 16.9 | 22.6  | 183.3 | 0%    |
| 200 | 8 461 | 17.0 | 34.4 | 47.1  | 668.6 | 0%    |
| 500 | 9 972 | 41.5 | 84.6 | 115.7 | 2397  | 18.2% |

### mixed — ~90% read / ~10% write (the realistic blend)

| VUs | RPS | p50 | p95 | p99 | max | fail |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 4 234  | 0.0  | 0.6   | 0.8   | 12.1  | 0%    |
| 10  | 12 011 | 0.5  | 1.6   | 2.1   | 14.5  | 0%    |
| 50  | 10 654 | 3.2  | 7.4   | 9.2   | 46.7  | 0%    |
| 100 | 9 199  | 8.0  | 16.9  | 21.0  | 166.9 | 0%    |
| 200 | 7 840  | 18.4 | 39.3  | 49.2  | 662.8 | 0%    |
| 500 | 8 285  | 41.3 | 121.4 | 168.3 | 3352  | 35.1% |

## Reading

**The single-thread ceiling is real and visible.** Throughput tops out by ~10 VUs and then holds
flat (or sags) as concurrency climbs, while latency rises almost linearly: e.g. `api` p99 goes
2.6 → 10.8 → 22.6 → 47.1 ms across 10 → 50 → 100 → 200 VUs with RPS pinned near ~8.7k the whole
way. That is exactly one saturated server — past the knee, every extra VU adds queue time, not
work. The knee sits around **10 VUs**: below it you're latency-bound (sub-millisecond), above it
throughput-bound.

**Endpoint cost, at the ~50-VU plateau (sustained RPS):**

```
write  ~25.5k   ← 2 tiny reqs/iter (~12.7k create+delete pairs/s); store stays steady, so cheap
static ~16k     ← byte-bound, not CPU-bound: ~800 MB/s over loopback is the socket ceiling here
pages  ~12k
search ~11k
api    ~8.9k    ← json.marshal is the most expensive read per request
```

`static` serves the most **bytes** (≈938 MB/s peak — that's loopback/socket bandwidth, the htmx
file is ~51 KB) but not the most requests; `write` serves the most **requests** because both its
responses are tiny and the create→delete keeps the store from growing. `api`'s marshalling is the
heaviest per-request read path.

**Failures only appear at 500 VUs** (2–35%, worst on `mixed`). With one accept/event thread
sharing a single hardware thread against a 500-VU generator *on the same box*, connections start
timing out and resetting — this is as much a co-located-generator artifact as a server limit, and
is the loudest reason the absolute numbers need a two-host rig. Up to 200 VUs the server is
**0% errors** everywhere.

## Open: the headline before/after

Throughput is pinned by **one core** while 15 hardware threads sit idle. The obvious next lever is
`thread_count = N` — but the in-memory store is lock-free *because* the loop is single-threaded
(`src/repository/repository.odin`), so it must be guarded with a lock first. The plan
(`PLAN.md` → "What we expect to learn") is to add that lock, raise `thread_count`, and re-run the
read-heavy scenarios for the scaling curve: how close to linear reads scale, and what the write
path's contention looks like. That before/after is the result that would justify (or reject)
moving off the single-thread design. Tracked in [`../TODO.md`](../TODO.md); not done here.
