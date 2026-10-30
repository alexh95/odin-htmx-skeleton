# M4 parity gate

**Gate:** PLAN §18.2 at the M4 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** Linux **PASS**, 20 of 20;
Windows 18 of 20 at n = 3, with `seo@file` passing at n = 5 and the two `static` cells reading either side of the 0.97
bar from run to run (below) · **Date:** 2026-10-30 · **Candidates:** `d136601` (the full Windows run), `30988ae` and
`eb228d8` (the Windows re-runs), `eb228d8` (Linux): the commits between them change the accounts identity, the
generator, CI and docs, and `platform/escape` gains a proc the skeleton never calls, so the skeleton's request path is
the same in all three · **Baselines:** v1.2.0 (709bc94) and v1.1.1 (ad98023), built by `tools/baseline` · **Raw rows:**
`perf/results/v2.2.0-rc.2-25-gd136601-windows.csv`, `-26-g30988ae-windows.csv` (static and seo, n = 5),
`-30-geb228d8-windows.csv` (static, n = 5) and `-30-geb228d8-linux.csv` · M3's gate: [PARITY.md](PARITY.md)

## Result

- **Linux:** 20 of 20 on n = 3, every block at 1–9 % background; nothing re-run. `static@file` 0.99, `static@mem` 1.00;
  `write@mem` passes its 0.93 floor at 0.96.
- **Windows:** 18 of 20 on n = 3 (`d136601`): `static@file` 0.95 and `seo@file` 0.96 missed. At n = 5 (`30988ae`)
  `seo@file` passes at 1.00 and `seo@mem` at 1.00, `static@mem` at 1.00, and `static@file` reads 0.97 (rounds
  0.89–1.06), just under. At n = 5 again (`eb228d8`) `static@file` passes at 0.98 and `static@mem` reads 0.95 (its first
  round at 25 % background). Over the three runs the static cells read 0.95–1.00, the same code path on both stores
  (static assets are embedded; the store isn't touched).
- **What M4 changed under the skeleton:** the layout (`data-kept`, a brand's own theme: no attribute for the skeleton,
  the same bytes out), the pre-paint script (one condition more, and so a new CSP hash), the full theme's stylesheet
  (one scheme block more: `static` serves it) and `front`'s rule check, which the skeleton's anonymous identity passes
  as before. Nothing in the request path of the other scenarios changed.
- **Exceptions in force** (`tests/parity-waivers.txt`), unchanged from M1: `pages@mem` and `list@mem` gate against
  HEAD on both legs and `write@mem` on Linux (Q6); Linux `write@mem` passes at a median of 0.93 of HEAD (ANSWERS round
  6). No file-DB cell is waived.

**Open, for Alex:** whether the Windows `static` cells, which alternate around 0.97 on the dev PC while Linux passes
both, stand as a pass (as M3's `static@file` did at n = 5), or want a quieter re-run of both legs.

## Method

As M3's ([PARITY.md](PARITY.md), Method): `load-tests/run.sh --parity`, per round, per scenario, per store, HEAD, v1.1.1
and the candidate back to back on a fresh server each, the order rotated each round; `THREADS=16`, `LOG_LEVEL=warn`,
`SEED=1`; k6 v2.0.0 at 200 VUs (`scale`: 20 VUs over 20k rows), 3 s warmup and a 10 s window; n = 3 rounds; a failing
cell re-run with n = 5 into its own CSV. The Linux leg ran in WSL2's own filesystem, a clone at the candidate commit
(`~/m3`), with k6 at `/opt/k6/k6`; its first attempt measured M3's commit, because an untracked results file stopped
the clone's checkout, and was discarded.
