# M2 parity gate

**Gate:** PLAN §18.2 at the M2 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** **PASS** on both legs: 20 of
20 cells on each, counting the n = 5 re-runs §18.2 prescribes · **Date:** 2026-10-27 · **Candidate:** `40f8716`
(v2.0.0-63) on both legs, the M2 release candidate after its audit's fixes · **Baselines:** v1.2.0 (709bc94) and
v1.1.1 (ad98023), built by `tools/baseline` · **Raw rows:** `perf/results/v2.0.0-63-g40f8716-windows.csv` and
`-linux.csv`, each with its `-rerun` · M1's gate: [PARITY-M1.md](PARITY-M1.md)

## Result

- **Windows:** 19 of 20 cells pass on n = 3. `pages@mem` (gated against HEAD, Q6) runs at 1.99× HEAD but its p99 read
  1.20× HEAD's; its n = 5 re-run passes at 1.99× with the p99 at 1.10, the bar. The candidate's own p99 didn't move the
  wrong way: 24.6–27.4 ms in this leg's rounds against 27.7–32.4 ms at M1 (`8c4f1a9`), at about 31k rps against 28k.
  The ratio rose because this leg's HEAD measured 21.3–21.7 ms, where M1's measured 24.4–39.8.
- **Linux:** 19 of 20 cells pass on n = 3. `static@file` (gated against HEAD alone, Q35) read a median of 0.97 that
  rounds up to the bar it missed; its n = 5 re-run passes at 1.01. `write@mem` passes its 0.93 floor (round 6) at
  0.95.
- **Against M1's legs:** on Windows every cell's candidate reads 0.99–1.17× M1's (`8c4f1a9`). On Linux the
  candidate reads a median of 0.97× M1's (`72590f6`) and the baselines 0.98× theirs, the box being busier (below);
  `api` (0.96 on both stores, baselines level) and `mixed@file` (0.88, a cell whose rounds spread 1.67–1.97 against
  max) dipped further. An A/B of the two candidates, M1's binary against M2's on n = 5 at 3–9 % background, put
  `api@mem` at 1.00, `api@file` 1.00, `mixed@mem` 1.01 and `mixed@file` 0.95 (rounds 0.93–1.05): the `api` dip was
  the box, and `mixed@file` may carry a few per cent of M2's one change on its path (a handler's reads in one read
  transaction), which `TODO.md` keeps to A/B before M3's gate.
- **Exceptions in force** (`tests/parity-waivers.txt`), unchanged from M1: `pages@mem` and `list@mem` gate against
  HEAD on both legs and `write@mem` on Linux (Q6); Linux `write@mem` passes at a median of 0.93 of HEAD (ANSWERS round
  6). No file-DB cell is waived.

## Method

As M1's ([PARITY-M1.md](PARITY-M1.md), Method): `load-tests/run.sh --parity`, per round, per scenario, per store,
HEAD, v1.1.1 and the candidate back to back on a fresh server each, the order rotated each round; `THREADS=16`,
`LOG_LEVEL=warn`, `SEED=1`; k6 v2.0.0 at 200 VUs (`scale`: 20 VUs over 20k rows), 3 s warmup and a 10 s window; n = 3
rounds. A failing cell is re-run with n = 5 into its own CSV; a block sampled over 20 % background is re-run in place
(`ROUND_FIRST`, `ROUNDS`), and its last rows win. `load-tests/lib/parity.mjs` applies the pass rule (median ≥ the
cell's bar, no round below 0.85, p99 ≤ 1.10× the reference's) with each cell's reference: HEAD alone on `static` and
`seo` (Q35), HEAD on the waived `:memory:` cells (Q6), max(HEAD, v1.1.1) elsewhere.

- **Builds:** the candidate `-o:speed` through `build.sh skeleton`; the baselines through `tools/baseline`; Odin
  dev-2026-10 (84bc3fc) on both legs, each leg with its own SQLite 3.53.4 library as at M1.
- **Box:** the dev PC (Ryzen 7 5800X, 8 cores and 16 threads, 64 GB), Windows 11 native, and Ubuntu on WSL2 (kernel
  6.18) with the server, k6 and the file DBs in WSL's own filesystem; the Linux leg ran in a git clone of this
  checkout at the same commit. The host's CPU is sampled for a second before each block (`typeperf`), the `bg` column.
- **Background:** unlike M1's legs, other sessions' Docker stacks in WSL (ten game-server containers) kept running,
  untouched. Blocks read 3–40 %; the six Windows blocks and the one Linux block over 20 % were re-run in place and
  read 4–16 % then, and the re-run of `pages@mem` re-ran its one block over 20 % (round 2, 40 %) at 7 %. Every row
  below is at 19 % or less.

## Windows (`40f8716`)

n = 3, with the blocks over 20 % re-run in place:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 26042 (1.07) | 27598 (1.04) | 25995 | 1.00 0.96 1.00 | 1.00 | 0.96 | 0.97 | 15/7/11 | yes |
| static@file | head | 26356 (1.03) | 27104 (1.09) | 26413 | 1.03 1.00 0.99 | 1.00 | 0.99 | 1.02 | 15/7/11 | yes |
| seo@mem | head | 57954 (1.04) | 62198 (1.04) | 60411 | 1.03 1.04 1.04 | 1.04 | 1.03 | 0.94 | 8/3/10 | yes |
| seo@file | head | 58807 (1.01) | 63439 (1.04) | 58599 | 1.01 0.99 0.99 | 0.99 | 0.99 | 0.96 | 8/3/10 | yes |
| pages@mem | head (waiver) | 15545 (1.01) | 32841 (1.03) | 30898 | 2.00 1.99 1.94 | 1.99 | 1.94 | 1.20 | 19/13/7 | **no** |
| pages@file | max | 13439 (1.02) | 27883 (1.00) | 32057 | 1.17 1.10 1.15 | 1.15 | 1.10 | 1.01 | 19/13/7 | yes |
| list@mem | head (waiver) | 12567 (1.01) | 38921 (1.03) | 35219 | 2.83 2.76 2.81 | 2.81 | 2.76 | 0.60 | 10/9/7 | yes |
| list@file | max | 10749 (1.02) | 29064 (1.00) | 34560 | 1.18 1.20 1.19 | 1.19 | 1.18 | 0.89 | 10/9/7 | yes |
| search@mem | max | 17301 (1.06) | 42560 (1.10) | 42946 | 0.99 1.05 0.95 | 0.99 | 0.95 | 0.78 | 6/11/5 | yes |
| search@file | max | 15064 (1.01) | 29822 (1.04) | 44998 | 1.51 1.49 1.54 | 1.51 | 1.49 | 0.41 | 6/11/5 | yes |
| api@mem | max | 16184 (1.00) | 35314 (1.07) | 35751 | 0.98 1.03 1.03 | 1.03 | 0.98 | 0.84 | 8/16/13 | yes |
| api@file | max | 13962 (1.01) | 28659 (1.02) | 35036 | 1.21 1.23 1.24 | 1.23 | 1.21 | 0.61 | 8/16/13 | yes |
| detail@mem | max | 14260 (1.01) | 21031 (1.01) | 32681 | 1.56 1.58 1.55 | 1.56 | 1.55 | 0.93 | 6/13/11 | yes |
| detail@file | max | 11742 (1.02) | 15415 (1.01) | 31984 | 2.10 2.09 2.06 | 2.09 | 2.06 | 0.59 | 6/13/11 | yes |
| write@mem | max | 36199 (1.02) | 39531 (1.03) | 39932 | 0.98 0.99 1.07 | 0.99 | 0.98 | 0.74 | 5/4/10 | yes |
| write@file | max | 12240 (1.01) | 12563 (1.01) | 36105 | 2.89 2.82 2.91 | 2.89 | 2.82 | 0.40 | 5/4/10 | yes |
| mixed@mem | max | 17281 (1.02) | 29424 (1.08) | 32083 | 1.09 1.11 0.99 | 1.09 | 0.99 | 0.93 | 7/15/11 | yes |
| mixed@file | max | 13173 (1.03) | 18499 (1.05) | 32466 | 1.73 1.71 1.80 | 1.73 | 1.71 | 0.55 | 7/15/11 | yes |
| scale@mem | max | 157 (1.01) | 174 (1.02) | 1843 | 10.81 10.66 9.94 | 10.66 | 9.94 | 0.09 | 7/17/17 | yes |
| scale@file | max | 147 (1.01) | 163 (1.01) | 1733 | 10.71 10.69 10.60 | 10.69 | 10.60 | 0.10 | 7/17/17 | yes |

`pages@mem`'s n = 5 re-run (`-rerun.csv`), its round 2 re-run in place:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| pages@mem | head (waiver) | 15703 (1.02) | 33183 (1.06) | 31297 | 1.99 2.03 2.01 1.99 1.92 | 1.99 | 1.92 | 1.10 | 19/7/5/11/13 | yes |

## Linux (`40f8716`)

n = 3, with the block over 20 % re-run in place:

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@mem | head | 32079 (1.06) | 33432 (1.04) | 32023 | 0.96 0.99 1.02 | 0.99 | 0.96 | 1.03 | 6/6/8 | yes |
| static@file | head | 32378 (1.05) | 32870 (1.01) | 31418 | 0.95 1.03 0.97 | 0.97 | 0.95 | 1.01 | 6/6/8 | **no** |
| seo@mem | head | 62859 (1.02) | 66364 (1.01) | 62323 | 0.98 0.99 1.01 | 0.99 | 0.98 | 1.01 | 7/10/14 | yes |
| seo@file | head | 63071 (1.03) | 66147 (1.01) | 62506 | 0.99 1.01 1.00 | 1.00 | 0.99 | 1.02 | 7/10/14 | yes |
| pages@mem | head (waiver) | 14001 (1.01) | 37178 (1.07) | 35801 | 2.52 2.59 2.56 | 2.56 | 2.52 | 0.70 | 4/12/8 | yes |
| pages@file | max | 12225 (1.01) | 32077 (1.01) | 36287 | 1.10 1.14 1.13 | 1.13 | 1.10 | 0.91 | 4/12/8 | yes |
| list@mem | head (waiver) | 9933 (1.01) | 41197 (1.02) | 39093 | 3.95 3.93 4.00 | 3.95 | 3.93 | 0.35 | 11/6/6 | yes |
| list@file | max | 8797 (1.01) | 36067 (1.02) | 39520 | 1.10 1.11 1.10 | 1.10 | 1.10 | 0.77 | 11/6/6 | yes |
| search@mem | max | 16806 (1.02) | 46981 (1.02) | 50227 | 1.05 1.07 1.07 | 1.07 | 1.05 | 0.78 | 10/8/3 | yes |
| search@file | max | 15375 (1.01) | 37323 (1.01) | 50172 | 1.32 1.34 1.38 | 1.34 | 1.32 | 0.51 | 10/8/3 | yes |
| api@mem | max | 14980 (1.01) | 36449 (1.01) | 38564 | 1.06 1.05 1.04 | 1.05 | 1.04 | 0.86 | 9/7/10 | yes |
| api@file | max | 13688 (1.00) | 33275 (1.02) | 38477 | 1.17 1.18 1.15 | 1.17 | 1.15 | 0.62 | 9/7/10 | yes |
| detail@mem | max | 11779 (1.00) | 25102 (1.03) | 35235 | 1.40 1.43 1.39 | 1.40 | 1.39 | 0.63 | 6/7/12 | yes |
| detail@file | max | 9215 (1.01) | 15153 (1.01) | 35346 | 2.33 2.32 2.35 | 2.33 | 2.32 | 0.52 | 6/7/12 | yes |
| write@mem | head (waiver), bar 0.93 | 43125 (1.01) | 45505 (1.01) | 41021 | 0.95 0.97 0.95 | 0.95 | 0.95 | 0.83 | 7/7/6 | yes |
| write@file | max | 10629 (1.30) | 10971 (1.01) | 29005 | 2.71 2.64 2.57 | 2.64 | 2.57 | 0.34 | 7/7/6 | yes |
| mixed@mem | max | 15913 (1.05) | 30833 (1.19) | 38285 | 1.15 1.33 1.24 | 1.24 | 1.15 | 0.75 | 12/11/5 | yes |
| mixed@file | max | 12729 (1.13) | 17797 (1.05) | 33013 | 1.86 1.67 1.97 | 1.86 | 1.67 | 0.74 | 12/11/5 | yes |
| scale@mem | max | 166 (1.00) | 135 (1.03) | 1705 | 10.29 10.57 10.28 | 10.29 | 10.28 | 0.08 | 5/4/5 | yes |
| scale@file | max | 156 (1.03) | 127 (1.02) | 1587 | 10.15 9.93 9.94 | 9.94 | 9.93 | 0.08 | 5/4/5 | yes |

`static@file`'s n = 5 re-run (`-rerun.csv`):

| cell | reference | head rps (band) | v111 rps (band) | skeleton rps | ratios per round | median | min | p99 ratio | bg | pass |
|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| static@file | head | 31696 (1.07) | 33796 (1.02) | 32069 | 0.98 1.04 1.00 1.04 1.01 | 1.01 | 0.98 | 1.01 | 6/8/4/6/8 | yes |
