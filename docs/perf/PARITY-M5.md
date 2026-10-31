# M5 parity gate

**Gate:** PLAN §18.2 at the M5 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** Linux **PASS**, 20 of 20;
Windows 19 of 20 measured, `pages@mem` missing on its p99 alone (below), accepted as a pass by Alex on 2026-10-31 ·
**Date:** 2026-10-31 · **Candidates:** `cf7f42b` (the
full Windows run), `f42f032` (Windows, six scenarios at n = 5), `23244f2` (Windows `pages` at n = 5; the full Linux run
and its two re-run cells): the commits between them fix M5's audit findings (the writer's memory report moved under
its lock, dbview, jobs, backups) and the drills, so the skeleton's request path is the same in all three ·
**Baselines:** v1.2.0 (709bc94) and v1.1.1 (ad98023), built by `tools/baseline` · **Raw rows:**
`perf/results/v2.2.0-rc.2-54-gcf7f42b-windows.csv`, `-55-gf42f032-windows-n5.csv`, `-56-g23244f2-windows-pages.csv`,
`-56-g23244f2-linux.csv`, `-56-g23244f2-linux-n5.csv` · M4's gate: [PARITY-M4.md](PARITY-M4.md)

## Result

- **Linux:** 18 of 20 at n = 3 (`23244f2`). `static@mem` (one round at 0.68 under 84 % background) and `mixed@mem`
  (one at 0.72) missed on a single round each; re-run at n = 5 both pass: `static@mem` 0.98 (0.96–1.00), `mixed@mem`
  1.14 (1.08–1.22). `pages@mem` passes at 2.59 of HEAD with a p99 ratio of 0.70; `write@mem` passes its 0.93 floor at
  0.97.
- **Windows:** 15 of 20 at n = 3 (`cf7f42b`) under 14–93 % background. At n = 5 (`f42f032`) `seo`, `list`, `search`,
  `api` and `write` pass on both stores (medians 0.97–1.27 against their references), and `pages@file` at 1.13.
  `pages@mem` is the one left: its throughput is 2.1–2.2 times HEAD's (its waiver's reference), but its p99 is 1.11–1.12
  times HEAD's against the 1.10 bar, in two n = 5 runs (`f42f032`, `23244f2`).
- **Why that cell reads as the machine, not M5:** against v1.1.1, which serves the same throughput, the candidate's
  p99 is the lower (27–28 ms against 29–30 ms; at M4 they were 23.8 and 23.4); every variant's numbers moved together
  from M4's run (v1.1.1's p99 23.4 → 29 ms, unchanged code); Linux passes the same cell at a p99 of 0.70; and nothing
  M5 changed is on the pages read path (a once-a-second memory report per loop's reader is the only new call there).
- **Exceptions in force** (`tests/parity-waivers.txt`), unchanged from M1: `pages@mem` and `list@mem` gate against
  HEAD on both legs and `write@mem` on Linux (Q6); Linux `write@mem` passes at a median of 0.93 of HEAD (ANSWERS round
  6). No file-DB cell is waived.

**Verdict on Windows `pages@mem` (Alex's call, 2026-10-31): accepted as a pass.** The cell stays at 19 of 20 measured:
its p99 is 1.11–1.12 times HEAD's against the 1.10 bar, at 2.1–2.2 times HEAD's throughput, and below v1.1.1's p99.
Linux passes the same cell at 0.70. No re-run.

## Method

As M4's ([PARITY-M4.md](PARITY-M4.md), Method): `load-tests/run.sh --parity`, per round, per scenario, per store, HEAD,
v1.1.1 and the candidate back to back on a fresh server each, the order rotated each round; `THREADS=16`,
`LOG_LEVEL=warn`, `SEED=1`; k6 v2.0.0 at 200 VUs (`scale`: 20 VUs over 20k rows), 3 s warmup and a 10 s window; n = 3
rounds; a failing cell re-run with n = 5 into its own CSV. The Linux leg ran in WSL2's own filesystem, a clone at the
candidate commit (`~/m3`), with k6 at `/opt/k6/k6`. The two legs never ran at once.
