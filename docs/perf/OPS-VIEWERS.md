# One ops render, whatever the viewers (M5)

**Gate:** PLAN §22.3, M5's row: "one ops render per second whatever the number of viewers (CPU flat from 1 to 100
viewers)" · **Held by:** the `opsviewers` drill (`tools/drills/drills.mjs`), in CI's Linux drills job for `streams`
and on the dev PC's Windows leg · **Date:** 2026-10-30

## Why it holds

`ops.sample` (1 s) renders the panel once into the kept HTML and publishes that one string on `ops.panel` (a
`.Sample` topic). A viewer costs a write of those bytes: SSE through the hub, a poll answered from the kept render
(304 while the ptag matches), multipart through the same topic. Nothing renders per viewer.

## How it's measured

The release build with the nick identity's loopback admin; 1, then 10, then 100 SSE viewers of
`/events?t=ops.panel`, each held 3 s to settle and then 10 s measured. The server's CPU time is read from outside
(Windows' `TotalProcessorTime`, Linux's `utime + stime`), and each viewer's refreshes are counted. Pass: 99 more
viewers cost at most 30 ms of CPU a second (3 % of a core), and the slowest viewer got at least 8 refreshes in 10 s.

## Results

| Leg | 1 viewer | 10 viewers | 100 viewers | Slowest viewer, 10 s |
|---|---:|---:|---:|---:|
| Windows (dev PC, `streams`, THREADS=4) | 0.0 ms/s | 1.6 ms/s | 3.1 ms/s | 11 refreshes at every count |
| Linux | CI's drills job for `streams` prints its row | | | |

Windows reads CPU time in 15.6 ms ticks, so a single viewer's cost rounds to zero over 10 s.
