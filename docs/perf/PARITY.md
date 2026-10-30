# M3 parity gate

**Gate:** PLAN §18.2 at the M3 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** **PASS** on both legs: 20 of
20 cells on each · **Date:** 2026-10-30 · **Candidates:** `c490e2a` (v2.2.0-rc.1-1) on Windows, `48666d6`
(v2.2.0-rc.1-12) on Linux: the commits between them change no code the skeleton builds (the audit's fixes are in
status, chat's socket, landing, the generator and the deploy files; `platform/stream`'s one change is a comment) ·
**Baselines:** v1.2.0 (709bc94) and v1.1.1 (ad98023), built by `tools/baseline` · **Raw rows:**
`perf/results/v2.2.0-rc.1-1-gc490e2a-windows.csv` with its `-rerun`, and `v2.2.0-rc.1-12-g48666d6-linux.csv` ·
M2's gate: [PARITY-M2.md](PARITY-M2.md), M1's: [PARITY-M1.md](PARITY-M1.md)

## Result

- **Windows:** 19 of 20 cells passed on the first pass, with eight blocks sampled over 20 % background (22–32 %).
  Those blocks were re-run in place (`ROUND_FIRST`, `ROUNDS`) and read 6–18 %; with their rows, 20 of 20 pass.
  `static@file` (gated against HEAD alone, Q35) read a median of 0.97 at first, with its first round at 22 %; in place
  it reads 0.98, and its n = 5 re-run passes at 0.98 (rounds 0.94–1.00), with `static@mem` at 1.00.
- **Linux:** 20 of 20 cells pass on n = 3, every block at 3–18 % background; nothing was re-run. `write@mem` passes
  its 0.93 floor (round 6) at 0.96.
- **What M3 changed under the skeleton:** the release image and the fork's F-24 (a HEAD's body), which no scenario
  sends; the request path is M2's.
- **Exceptions in force** (`tests/parity-waivers.txt`), unchanged from M1: `pages@mem` and `list@mem` gate against
  HEAD on both legs and `write@mem` on Linux (Q6); Linux `write@mem` passes at a median of 0.93 of HEAD (ANSWERS round
  6). No file-DB cell is waived.

## Method

As M2's ([PARITY-M2.md](PARITY-M2.md), Method): `load-tests/run.sh --parity`, per round, per scenario, per store,
HEAD, v1.1.1 and the candidate back to back on a fresh server each, the order rotated each round; `THREADS=16`,
`LOG_LEVEL=warn`, `SEED=1`; k6 v2.0.0 at 200 VUs (`scale`: 20 VUs over 20k rows), 3 s warmup and a 10 s window; n = 3
rounds. A block sampled over 20 % background is re-run in place and its last rows win; a failing cell is re-run with
n = 5 into its own CSV. `load-tests/lib/parity.mjs` applies the pass rule.

- **Builds:** the candidate `-o:speed` through `build.sh skeleton`; the baselines through `tools/baseline`; Odin
  dev-2026-10 on both legs, each with its own SQLite 3.53.4 library.
- **Box:** the dev PC (Ryzen 7 5800X, 8 cores and 16 threads, 64 GB), Windows 11 native, and Ubuntu on WSL2 with the
  server, k6 and the file DBs in WSL's own filesystem (a clone at the candidate commit). Other sessions' Docker stacks
  in WSL kept running, untouched, as at M2.

## Windows (`c490e2a`)

n = 3, with the blocks over 20 % re-run in place:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 24966 (1.16) | 26922 (1.11) | 25928 | 0.94 1.02 1.04 | 1.02 | 0.94 | 0.99 | 13/4/5 | yes |
| static@file | head | 25366 (1.13) | 24852 (1.16) | 24977 | 1.00 0.97 0.98 | 0.98 | 0.97 | 1.03 | 13/4/5 | yes |
| seo@mem | head | 60702 (1.11) | 64018 (1.06) | 62565 | 1.06 1.04 1.00 | 1.04 | 1.00 | 0.99 | 16/4/15 | yes |
| seo@file | head | 61434 (1.05) | 66066 (1.11) | 62277 | 1.01 0.92 1.06 | 1.01 | 0.92 | 1.02 | 16/4/15 | yes |
| pages@mem | head (waiver) | 13842 (1.01) | 32723 (1.10) | 31887 | 2.34 2.12 2.29 | 2.29 | 2.12 | 0.90 | 12/7/4 | yes |
| pages@file | max | 11266 (1.02) | 27347 (1.04) | 31483 | 1.18 1.19 1.12 | 1.18 | 1.12 | 1.08 | 12/7/4 | yes |
| list@mem | head (waiver) | 10178 (1.05) | 40395 (1.15) | 34670 | 3.09 3.48 3.33 | 3.33 | 3.09 | 0.53 | 11/3/17 | yes |
| list@file | max | 8437 (1.03) | 27619 (1.05) | 32684 | 1.21 1.14 1.28 | 1.21 | 1.14 | 0.90 | 11/3/17 | yes |
| search@mem | max | 14246 (1.02) | 43087 (1.18) | 46031 | 1.04 1.07 1.02 | 1.04 | 1.02 | 0.62 | 18/15/13 | yes |
| search@file | max | 12094 (1.03) | 28861 (1.05) | 45115 | 1.43 1.56 1.62 | 1.56 | 1.43 | 0.48 | 18/15/13 | yes |
| api@mem | max | 13636 (1.03) | 36867 (1.03) | 36949 | 0.94 1.01 1.02 | 1.01 | 0.94 | 0.80 | 6/10/4 | yes |
| api@file | max | 11653 (1.03) | 28019 (1.02) | 36751 | 1.31 1.32 1.30 | 1.31 | 1.30 | 0.47 | 6/10/4 | yes |
| detail@mem | max | 12382 (1.02) | 19878 (1.00) | 34683 | 1.75 1.74 1.66 | 1.74 | 1.66 | 0.92 | 6/10/10 | yes |
| detail@file | max | 9463 (1.01) | 13013 (1.00) | 34044 | 2.64 2.60 2.62 | 2.62 | 2.60 | 0.52 | 6/10/10 | yes |
| write@mem | max | 36669 (1.10) | 39383 (1.07) | 43503 | 1.04 1.10 1.09 | 1.09 | 1.04 | 0.66 | 15/10/6 | yes |
| write@file | max | 9924 (1.11) | 9765 (1.03) | 39970 | 3.65 4.02 4.07 | 4.02 | 3.65 | 0.29 | 15/10/6 | yes |
| mixed@mem | max | 14301 (1.02) | 28648 (1.13) | 34051 | 1.07 1.10 1.26 | 1.10 | 1.07 | 0.81 | 19/4/5 | yes |
| mixed@file | max | 10880 (1.05) | 16452 (1.07) | 33520 | 1.92 1.99 2.04 | 1.99 | 1.92 | 0.56 | 19/4/5 | yes |
| scale@mem | max | 149 (1.03) | 143 (1.01) | 1677 | 11.54 12.23 11.27 | 11.54 | 11.27 | 0.08 | 18/18/10 | yes |
| scale@file | max | 139 (1.02) | 134 (1.00) | 1722 | 11.73 12.91 12.40 | 12.40 | 11.73 | 0.07 | 18/18/10 | yes |

`static` at n = 5 (`-rerun.csv`): `static@mem` median 1.00 (0.95–1.00), `static@file` 0.98 (0.94–1.00), p99 ratios
0.99 and 1.01, background 7–16 %: both pass.

## Linux (`48666d6`)

n = 3:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 31801 (1.11) | 31926 (1.01) | 32234 | 1.02 0.99 0.98 | 0.99 | 0.98 | 1.08 | 6/4/7 | yes |
| static@file | head | 30222 (1.02) | 31969 (1.06) | 30701 | 1.02 1.02 1.03 | 1.02 | 1.02 | 1.05 | 6/4/7 | yes |
| seo@mem | head | 62326 (1.10) | 65685 (1.05) | 61295 | 0.92 0.98 1.00 | 0.98 | 0.92 | 1.02 | 4/6/9 | yes |
| seo@file | head | 58845 (1.12) | 67354 (1.03) | 58150 | 0.97 1.04 0.99 | 0.99 | 0.97 | 0.98 | 4/6/9 | yes |
| pages@mem | head (waiver) | 13977 (1.00) | 35636 (1.00) | 35092 | 2.52 2.50 2.54 | 2.52 | 2.50 | 0.73 | 8/7/7 | yes |
| pages@file | max | 12164 (1.03) | 32654 (1.01) | 34995 | 1.10 1.07 1.06 | 1.07 | 1.06 | 0.95 | 8/7/7 | yes |
| list@mem | head (waiver) | 9933 (1.01) | 41237 (1.04) | 39256 | 3.95 3.99 3.95 | 3.95 | 3.95 | 0.37 | 18/4/5 | yes |
| list@file | max | 8825 (1.00) | 36231 (1.00) | 39191 | 1.10 1.08 1.08 | 1.08 | 1.08 | 0.77 | 18/4/5 | yes |
| search@mem | max | 16654 (1.02) | 46484 (1.01) | 49316 | 1.07 1.04 1.07 | 1.07 | 1.04 | 0.79 | 4/4/7 | yes |
| search@file | max | 15381 (1.01) | 37815 (1.02) | 50037 | 1.30 1.34 1.33 | 1.33 | 1.30 | 0.51 | 4/4/7 | yes |
| api@mem | max | 15061 (1.01) | 36634 (1.05) | 38560 | 1.05 1.04 1.07 | 1.05 | 1.04 | 0.86 | 5/10/10 | yes |
| api@file | max | 13738 (1.00) | 33136 (1.01) | 38380 | 1.14 1.16 1.16 | 1.16 | 1.14 | 0.64 | 5/10/10 | yes |
| detail@mem | max | 11871 (1.06) | 25434 (1.01) | 35038 | 1.38 1.43 1.39 | 1.39 | 1.38 | 0.61 | 8/8/4 | yes |
| detail@file | max | 9349 (1.01) | 15274 (1.01) | 35121 | 2.24 2.33 2.30 | 2.30 | 2.24 | 0.53 | 8/8/4 | yes |
| write@mem | head (waiver), bar 0.93 | 42889 (1.02) | 45705 (1.01) | 41284 | 0.96 0.96 0.96 | 0.96 | 0.96 | 0.84 | 16/13/6 | yes |
| write@file | max | 11078 (1.07) | 11113 (1.04) | 29762 | 2.63 2.77 2.67 | 2.67 | 2.63 | 0.36 | 16/13/6 | yes |
| mixed@mem | max | 15656 (1.06) | 31465 (1.17) | 37162 | 1.04 1.29 1.18 | 1.18 | 1.04 | 0.74 | 6/4/7 | yes |
| mixed@file | max | 12560 (1.14) | 18373 (1.02) | 35405 | 1.96 1.84 1.94 | 1.94 | 1.84 | 0.67 | 6/4/7 | yes |
| scale@mem | max | 167 (1.16) | 133 (1.04) | 1707 | 10.55 10.07 10.85 | 10.55 | 10.07 | 0.08 | 5/6/3 | yes |
| scale@file | max | 159 (1.07) | 129 (1.02) | 1582 | 10.33 9.95 10.29 | 10.29 | 9.95 | 0.09 | 5/6/3 | yes |
