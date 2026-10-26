# M1 parity gate

**Gate:** PLAN §18.2 at the M1 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** **PASS** on both legs: 20 of 20 cells on each, counting the n = 5 re-runs §18.2 prescribes ·
**Date:** 2026-10-26 · **Candidate:** Windows `8c4f1a9` (v1.2.1-61), Linux `72590f6` (v1.2.1-63), the M1 release
build; between the two only chunked-body framing, log escaping, a deferred-watch test that store writes skip
(`watch = false`) and the test flags change, none of which a scenario reaches · **Baselines:** v1.2.0 (709bc94) and
v1.1.1 (ad98023), built by `tools/baseline` · **Raw rows:** `perf/results/v1.2.1-61-g8c4f1a9-windows.csv` (and
`-rerun`), `perf/results/v1.2.1-63-g72590f6-linux.csv` (and `-rerun`)

## Result

- **Windows:** 17 of 20 cells pass on n = 3; the three that missed (`seo@mem` on one round in a block sampled at
  20 % background, `seo@file` at a median of 0.94, `detail@mem` on p99 at 1.42× the throughput) pass their n = 5
  re-run, so all 20 pass (§18.2: a cell fails only if its re-run fails too). `write@mem` passes against max(HEAD,
  v1.1.1) at 1.00.
- **Linux:** 19 of 20 cells pass on n = 3. `write@mem` cleared its 0.93 floor on the median (0.94) but not the no-round-below-0.85 rule (round 3 at 0.77); its n = 5 re-run passes at a median of 0.99 of HEAD, no round below 0.98, so all 20 pass. On
  the quiet box the cell clears even the usual 0.97 bar; the floor Alex accepted (round 6) stays as its guard. The
  earlier 0.93–0.96 were measured while 1–1.5 cores of other load ran on the host.
- **Exceptions in force** (`tests/parity-waivers.txt`): `pages@mem` and `list@mem` gate against HEAD on both legs and
  `write@mem` on Linux (Q6); Linux `write@mem` passes at a median of 0.93 of HEAD (ANSWERS round 6, below). No file-DB
  cell is waived.

## Method

- **Procedure:** `load-tests/run.sh --parity` (S0.1's loop, folded in at M1): per round, per scenario, per store, HEAD,
  v1.1.1 and the candidate back to back on a fresh server each, the order rotated each round; `THREADS=16`,
  `LOG_LEVEL=warn`, `SEED=1`; k6 v2.0.0 at 200 VUs (`scale`: 20 VUs over 20k rows), 3 s warmup and a 10 s window;
  n = 3 rounds. A failing cell is re-run with n = 5 into its own CSV (`ROUNDS=5 RESULTS=… run.sh --parity <scenario>`);
  a block sampled over 20 % background is re-run in place (`ROUND_FIRST`, `ROUNDS`), and its last rows win. The
  Windows re-runs measured the leg's own binary (`VARIANTS=…`), so every Windows row is `8c4f1a9`.
  `load-tests/lib/parity.mjs` applies the pass rule with each cell's reference: HEAD alone on `static` and `seo` (Q35);
  HEAD on the `:memory:` cells the waivers file names for the leg (Q6); max(HEAD, v1.1.1) elsewhere; and a cell's
  `perf-floor` bar where Alex accepted one (round 6).
- **Builds:** the candidate `-o:speed` through `build.sh skeleton`, the baselines through `tools/baseline`, all on Odin
  dev-2026-10 (84bc3fc) and, per leg, the same SQLite 3.53.4 library (Windows: prepare's `cl /O2 /MT`; Linux:
  `clang -O2`, Ubuntu clang 18.1.3).
- **Box:** the dev PC (Ryzen 7 5800X, 8 cores and 16 threads, 64 GB), Windows 11 native, and Ubuntu on WSL2 (kernel
  6.18) with the server, k6 and the file DBs in WSL's own filesystem. The host's CPU is sampled for a second before
  each block (`typeperf`; in WSL through `typeperf.exe`), the `bg` column.
- **Background:** for these legs a stray process of this session (a `find`, a full core since midday) was ended and
  other sessions' Docker stacks in WSL (game servers) were paused, at Alex's word. Idle host CPU then read 4–13 %. The
  sample lands as the previous block's last server and k6 exit, which is why some blocks read above the idle level;
  every Windows block over 20 % was re-run, and one (`list`, round 1) read 21 % again, in a cell that passes at 3.08×
  HEAD. Earlier legs, before the quieting, read 17–35 % and are superseded.

## Windows (`8c4f1a9`)

n = 3, with the blocks over 20 % re-run in place:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 25564 (1.03) | 26609 (1.16) | 25337 | 1.08 0.99 0.97 | 0.99 | 0.97 | 0.92 | 9/8/11 | yes |
| static@file | head | 23084 (1.15) | 24035 (1.17) | 23047 | 1.00 0.99 1.02 | 1.00 | 0.99 | 0.98 | 9/8/11 | yes |
| seo@mem | head | 59855 (1.09) | 64539 (1.05) | 59787 | 1.05 1.00 0.83 | 1.00 | 0.83 | 1.27 | 13/4/20 | **no** |
| seo@file | head | 54797 (1.14) | 58089 (1.15) | 53145 | 0.93 0.94 1.02 | 0.94 | 0.93 | 1.08 | 13/4/20 | **no** |
| pages@mem | head (waiver) | 13420 (1.13) | 31760 (1.09) | 28071 | 2.11 2.09 2.03 | 2.09 | 2.03 | 1.03 | 4/4/5 | yes |
| pages@file | max | 10926 (1.01) | 25034 (1.06) | 29388 | 1.13 1.11 1.18 | 1.13 | 1.11 | 0.92 | 4/4/5 | yes |
| list@mem | head (waiver) | 10048 (1.03) | 39517 (1.13) | 31933 | 3.44 3.08 3.18 | 3.18 | 3.08 | 0.56 | 21/14/11 | yes |
| list@file | max | 8311 (1.02) | 28173 (1.02) | 33527 | 1.19 1.08 1.29 | 1.19 | 1.08 | 1.00 | 21/14/11 | yes |
| search@mem | max | 14168 (1.02) | 39051 (1.07) | 41339 | 1.00 1.06 1.11 | 1.06 | 1.00 | 0.58 | 13/18/11 | yes |
| search@file | max | 12005 (1.05) | 28849 (1.04) | 42600 | 1.48 1.35 1.48 | 1.48 | 1.35 | 0.52 | 13/18/11 | yes |
| api@mem | max | 13463 (1.02) | 34966 (1.17) | 34055 | 0.97 1.04 0.97 | 0.97 | 0.97 | 0.75 | 7/17/10 | yes |
| api@file | max | 11579 (1.01) | 27762 (1.04) | 33618 | 1.14 1.24 1.22 | 1.22 | 1.14 | 0.54 | 7/17/10 | yes |
| detail@mem | max | 11915 (1.02) | 19421 (1.04) | 27842 | 1.33 1.46 1.42 | 1.42 | 1.33 | 1.16 | 13/8/15 | **no** |
| detail@file | max | 9324 (1.05) | 12833 (1.04) | 30247 | 2.21 2.36 2.46 | 2.36 | 2.21 | 0.60 | 13/8/15 | yes |
| write@mem | max | 34630 (1.05) | 37844 (1.03) | 38437 | 1.04 1.00 1.00 | 1.00 | 1.00 | 0.69 | 19/15/17 | yes |
| write@file | max | 9734 (1.05) | 9887 (1.07) | 34811 | 3.54 3.52 3.72 | 3.54 | 3.52 | 0.34 | 19/15/17 | yes |
| mixed@mem | max | 14052 (1.06) | 28146 (1.07) | 32376 | 1.06 1.18 1.18 | 1.18 | 1.06 | 1.03 | 12/15/14 | yes |
| mixed@file | max | 10593 (1.25) | 17352 (1.03) | 29852 | 1.61 1.90 1.68 | 1.68 | 1.61 | 0.77 | 12/15/14 | yes |
| scale@mem | max | 148 (1.06) | 139 (1.05) | 1578 | 11.18 11.47 10.64 | 11.18 | 10.64 | 0.09 | 20/15/16 | yes |
| scale@file | max | 135 (1.01) | 132 (1.07) | 1530 | 11.97 11.38 11.32 | 11.38 | 11.32 | 0.08 | 20/15/16 | yes |

The n = 5 re-run of the cells that missed:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| seo@mem | head | 59882 (1.07) | 62496 (1.10) | 59704 | 1.04 0.96 0.98 1.04 0.99 | 0.99 | 0.96 | 0.97 | 13/19/11/11/13 | yes |
| seo@file | head | 59723 (1.04) | 61790 (1.04) | 60169 | 1.05 1.01 1.01 0.97 0.93 | 1.01 | 0.93 | 1.00 | 13/19/11/11/13 | yes |
| detail@mem | max | 12262 (1.22) | 19749 (1.10) | 31436 | 1.53 1.63 1.59 1.55 1.54 | 1.55 | 1.53 | 0.78 | 13/7/18/9/6 | yes |
| detail@file | max | 11550 (1.29) | 13164 (1.21) | 32324 | 2.54 2.44 2.47 1.93 2.22 | 2.44 | 1.93 | 0.57 | 13/7/18/9/6 | yes |

## Linux (`72590f6`)

n = 3, the box quiet (no block over 14 %):

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 31503 (1.03) | 32834 (1.07) | 32013 | 1.00 1.02 0.99 | 1.00 | 0.99 | 1.03 | 7/3/9 | yes |
| static@file | head | 32163 (1.05) | 31560 (1.06) | 31858 | 0.97 0.99 0.98 | 0.98 | 0.97 | 1.04 | 7/3/9 | yes |
| seo@mem | head | 64469 (1.02) | 69224 (1.02) | 65296 | 1.01 1.00 1.01 | 1.01 | 1.00 | 0.97 | 5/5/3 | yes |
| seo@file | head | 65021 (1.05) | 69427 (1.03) | 64933 | 1.00 1.00 1.00 | 1.00 | 1.00 | 1.03 | 5/5/3 | yes |
| pages@mem | head (waiver) | 14040 (1.03) | 35768 (1.06) | 35702 | 2.54 2.48 2.62 | 2.54 | 2.48 | 0.69 | 2/2/8 | yes |
| pages@file | max | 12419 (1.01) | 32919 (1.05) | 36216 | 1.09 1.12 1.11 | 1.11 | 1.09 | 0.91 | 2/2/8 | yes |
| list@mem | head (waiver) | 10140 (1.00) | 43511 (1.02) | 41389 | 4.08 4.10 4.08 | 4.08 | 4.08 | 0.36 | 1/1/3 | yes |
| list@file | max | 8957 (1.05) | 37498 (1.02) | 39534 | 1.03 1.07 1.09 | 1.07 | 1.03 | 0.75 | 1/1/3 | yes |
| search@mem | max | 17213 (1.03) | 49314 (1.11) | 53108 | 1.08 1.16 1.07 | 1.08 | 1.07 | 0.73 | 3/5/2 | yes |
| search@file | max | 15682 (1.09) | 36373 (1.07) | 52934 | 1.39 1.39 1.46 | 1.39 | 1.39 | 0.49 | 3/5/2 | yes |
| api@mem | max | 14920 (1.05) | 36481 (1.08) | 40114 | 1.10 1.03 1.01 | 1.03 | 1.01 | 0.86 | 5/3/14 | yes |
| api@file | max | 13739 (1.04) | 33183 (1.12) | 40124 | 1.27 1.14 1.03 | 1.14 | 1.03 | 0.59 | 5/3/14 | yes |
| detail@mem | max | 12088 (1.01) | 25749 (1.01) | 36250 | 1.40 1.44 1.41 | 1.41 | 1.40 | 0.61 | 7/1/4 | yes |
| detail@file | max | 9410 (1.04) | 15322 (1.05) | 36882 | 2.41 2.39 2.48 | 2.41 | 2.39 | 0.51 | 7/1/4 | yes |
| write@mem | head (waiver), bar 0.93 | 44748 (1.15) | 47251 (1.18) | 42103 | 0.94 0.99 0.77 | 0.94 | 0.77 | 0.86 | 1/8/2 | **no** |
| write@file | max | 11053 (1.02) | 10948 (1.01) | 29419 | 2.66 2.74 2.64 | 2.66 | 2.64 | 0.38 | 1/8/2 | yes |
| mixed@mem | max | 16084 (1.03) | 29930 (1.07) | 39352 | 1.33 1.31 1.38 | 1.33 | 1.31 | 0.71 | 1/4/5 | yes |
| mixed@file | max | 12673 (1.07) | 17880 (1.02) | 37664 | 2.11 2.01 2.11 | 2.11 | 2.01 | 0.64 | 1/4/5 | yes |
| scale@mem | max | 168 (1.02) | 139 (1.01) | 1735 | 9.54 10.68 10.46 | 10.46 | 9.54 | 0.09 | 2/6/1 | yes |
| scale@file | max | 156 (1.06) | 133 (1.06) | 1609 | 10.59 10.27 10.91 | 10.59 | 10.27 | 0.08 | 2/6/1 | yes |
The n = 5 re-run of `write` (`write@mem` missed only on round 3's 0.77, a round in which HEAD and v1.1.1 also ran 10–13 % below rounds 1 and 2):

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| write@mem | head (waiver), bar 0.93 | 44133 (1.12) | 46925 (1.25) | 43483 | 1.07 0.99 0.98 0.98 1.03 | 0.99 | 0.98 | 0.82 | 7/3/4/4/0 | yes |
| write@file | max | 11019 (1.06) | 10796 (1.10) | 29801 | 2.72 2.76 2.68 2.52 2.59 | 2.68 | 2.52 | 0.37 | 7/3/4/4/0 | yes |

## What changed since the first full legs

The first full Windows leg (`bf831da`, 13 of 20) and Linux leg (`1f164b6`, 18 of 20) led to these changes in the
request path, each measured A/B against the build before it:
- **F-14** (`fd3a34c`): M1-01's fix; no throughput effect.
- **F-15** (`1f164b6`): header values written whole, lower-case key lookups without a copy, no socket watch on a store
  write's deferred response. Windows `write@mem` went from about 32.7k to 37.2k rps, level with v1.1.1.
- **`7eee43d`**: the router tries the request's method's rows first and compares literal rows as strings; the request
  id and the access log's client id without `fmt` (the client id only when the line is written); `BEGIN IMMEDIATE`
  and `COMMIT` from the writer's statement cache. About +1 % on Linux `write@mem`.
- **F-16** (`8c4f1a9`, `72590f6`): the audit re-reads' fixes (a scan trampoline, chunk framing bounds); measured by
  these legs.

Tried and dropped, for no measurable gain: running each write's read-back on its loop instead of the writer (slower on
both legs), and a per-loop reply inbox that wakes a loop only when its inbox was empty (it removed the writer's wake
syscalls, 12 % of its time, but throughput did not move: B/A median 0.99 over 8 rounds).

## Linux `write@mem`

Gated against HEAD since Q6 (S0.4: on tmpfs v1.1.1's in-RAM insert is cheaper than a WAL append, so the chosen
`:memory:` mode, candidate C, can't reach max(HEAD, v1.1.1)); S0.4 measured candidate C at 0.98 of HEAD on the
skeleton's own request path. The starter measured 0.93–0.96 of HEAD through M1, with 1–1.5 cores of other load on the
host, and 0.99 (n = 5) on the quiet box of these legs; with that load it was the one cell under the 0.97 bar, which
is what the analysis below and Alex's decision answer.

What the profile shows (`docs/audit/M1.md`, Profile):
- **It is latency, not CPU.** Under the same load the server burns the same CPU per request as HEAD (45 s of CPU for
  40.4k rps against HEAD's 48 s for 42.2k, 13 s runs), and the loops spend about half their on-CPU samples waiting in
  io_uring. k6 runs 200 VUs in a closed loop, so throughput is 200 over the round-trip time, and each write's round
  trip carries the writer task's hop: the queue, the batch it joins (10.6 writes on average, about 200 µs of writer
  time), the commit and the reply's next tick. HEAD writes inline under its global mutex.
- **The writer's own cost** is mostly SQLite: each write maintains six indexes (D36's five sort indexes, which buy
  `pages` and `list` 2–3.8× HEAD, plus `idx_contacts_status`); a quarter of its time is the WAL's `pwrite`s to tmpfs,
  7 % the WAL locks. It is about 90 % busy at any load because it commits as soon as it is free.
- **The 2–3 points since S0.4** are most likely the M1 platform's per-request work on the round trip (the guard, the
  request id and route counter, deferred responses through `front`), which the profile shows as latency here, not
  CPU; the request-path savings above moved it about one point.

**Alex's decision** (ANSWERS round 6, 2026-10-26): the documented exception, at the measured level. The cell passes at
a median of 0.93 of HEAD (a `perf-floor` line; no round below 0.85 and p99 within 1.10× still apply), and the sort
indexes stay. A drop below 0.93 means the write path got slower and fails the gate.

## The 01 (A) checklist on `skeleton`

The skeleton's 40-item feature checklist (research 01 (A)), the superset the starter must keep. Each item is held by a
test, a drill or a check that ran green at M1, or is changed on purpose by the plan (the last column says how). e2e
specs are under `e2e/tests/`.

| # | Item | Held by | Status |
|---|---|---|---|
| 1 | Dashboard: live stat cards, count-up, sparklines, drill-through, tiles, ping, prose | `dashboard/dashboard.spec`, `platform/navigation.spec`, `platform/seo.spec` (prose) | green |
| 2 | `/components`: showroom, buttons, badges, avatars, meters, inputs, tabs, accordion, modal (backdrop keeps it open), drawer, toasts | `gallery/components.spec`, `platform/navigation.spec` (showroom), `contacts/escaping.spec` (rune-safe initials) | green |
| 3 | `/forms`: inline validation, range fill, submit creates a record, OOB toast, reset only on own 2xx, 422 keeps fields | `gallery/forms.spec`, `contacts/validation.spec`, `contacts/writes.spec` | green |
| 4 | `/data`: live filter, chips, sortable columns, windowed pager, inline add (422 to the slot), cycle, delete | `contacts/crud.spec`, `contacts/paging.spec`, `contacts/validation.spec` | green |
| 5 | Detail drawer: record, timeline (JOIN), related, inline edit (422 as typed), cycle, delete, row refresh | `contacts/crud.spec`, `contacts/validation.spec`, `contacts/events.spec` | green |
| 6 | Topbar active search: highlighted matches, result to `/data?q=`, collapse, Escape and outside click | `contacts/search.spec` | green |
| 7 | `/api/search` JSON, capped at 100 | `platform/assets.spec`, `contacts/paging.spec` | green |
| 8 | `/about` with the repo link; boosted navigation (body swap, title, crossfade on nav only, toasts survive) | `about/about.spec`, `platform/navigation.spec` | green |
| 9 | Themes: 6 styles × 23 schemes, SSR default, pre-paint restore, picker, persistence, a light scheme per style | `platform/navigation.spec`, `platform/security.spec` (pre-paint under CSP); `platform/theme/full` | green |
| 10 | 404 page in the layout, bare 404 for htmx, 405 with `Allow` | `platform/routing.spec` | green |
| 11 | Responsive: no horizontal overflow at 390 px on every nav page | `platform/responsive.spec` | green |
| 12 | Minimal variant: one-page notes (newest first, add over htmx, 422 into the slot) and about | the `minimal` profile: `home/home.spec`, `notes/notes.spec`, `about/about.spec` | changed: a profile on the memory store, replacing `init --minimal` (PLAN §7, D27) |
| 13 | Strict CSP, nosniff, X-Frame-Options, frame-ancestors, referrer policy on every response | `platform/security.spec` | green |
| 14 | Cross-site write guard before the body | `platform/security.spec`, `platform/limits.spec` | green |
| 15 | Body cap 64 KiB (413 unread), field caps with matching `maxlength` | `platform/limits.spec` | green |
| 16 | Escaping boundary; helpers take text; rune-safe truncation | `contacts/escaping.spec`; `platform/escape` unit tests | green |
| 17 | 64-bit ids end to end; `parse_id` rejects garbage and overflow | `contacts/ids.spec` | green |
| 18 | Store errors as values → 404/409/500 | `contacts/crud.spec` (missing id), `web.respond_store_error` | green; Busy now answers 503 with `retry-after` (store v3) |
| 19 | No path traversal; assets embedded | `platform/assets.spec`, the drills' malformed set | green |
| 20 | Atomic single-statement updates where races matter | `contacts/writes.spec` (concurrent cycles lose no step) | green |
| 21 | SEO: one canonical origin, tags, JSON-LD, robots and sitemap derived, favicon, ownership proofs, `*.fly.dev` 301 | `platform/seo.spec`, `platform/canonical.spec` | green; robots.txt now derived from `.Fragment` rows, same lines |
| 22 | SQLite pinned and verified, statically linked, `DB_PATH`, WAL, FKs, `contains_ci` | `prepare.*`, `check-pins.sh`, `contacts/search.spec` (Unicode highlighting) | green; built with D16's flags |
| 23 | Migrations by name and hash, legacy adoption, foreign schemas refused | `platform/store/sqlite` unit test (709bc94 and v1.1.1 fixture databases) | green; per feature now |
| 24 | Seed only unowned stores | `contacts/persistence.spec` | green |
| 25 | `--backup` online copy, refuses overwrite; restore runbook | `platform/backup.spec`; `docs/DATA.md` | green |
| 26 | Filter, sort, page and count in SQL | the `scale` scenario (20k rows) | green |
| 27 | One binary; fingerprinted immutable URLs; ETag/304 | `platform/assets.spec` | green; br and gzip precompressed |
| 28 | `x-version` on every response; the boot log line | `platform/ops.spec` | green |
| 29 | `LOG_LEVEL`; one access-log line, no query string | `platform/ops.spec` | green; logfmt with a request id |
| 30 | `/healthz` = `ok` while the store answers | `platform/assets.spec`, `platform/ops.spec` | green; plus `/livez`, `/readyz` |
| 31 | Env config | `bin --limits` | green; a typed table |
| 32 | N threads; clean shutdown on SIGINT | the drills' shutdown phase (exit 0 in 5.6 s with slow, half-sent and idle peers) | green; SIGTERM too |
| 33 | `prepare.*` (idempotent, pinned) and `run.*` | used throughout; `run.bat` on `minimal` checked by hand | green; per profile through `build.*` |
| 34 | `tools/init`: all-or-nothing rename, guard, leftover report, Next list; `tools/og` | tried on a scratch copy: both renamed profiles build | changed: no `--minimal` (the profile replaces it) |
| 35 | Docker: two stages, pinned Odin, UID 10001, `/data`, STOPSIGNAL, HEALTHCHECK, io_uring seccomp, compose | the image built and run in WSL (health, `/licenses`, clean stop); CI's `docker` job | green; one profile per build, `/app/server` |
| 36 | Fly config; the docker-host deploy | unchanged | green; `FLY_DEPLOY` stays off |
| 37 | CI: OS matrix, pins, Docker, e2e shards, gated deploy, timeouts | `.github/workflows/ci.yml`; the first run on the new layout (`930b1a9`, run 40351922975) | green: run 40383619999 on `7fe60a5`, every job, on the restated budgets (ANSWERS rounds 7 and 8; the idle budget is gated on the dev PC, a CI runner reports it) |
| 38 | e2e harness: one build, a server per worker, `api` project, shared specs | `e2e/` | green; specs per feature, chosen by tags |
| 39 | Load harness: fresh server per run, warmup, thresholds, flags, scale | `load-tests/run.sh` | green; scenarios per feature, `--parity`, route counters replace `parity.sh` |
| 40 | Docs set | CLAUDE.md, README, app/README, DATA.md, the e2e and load design notes | green; STRIP.md and DATA_IMPL.md removed (D45) |

40 of 40 green.
