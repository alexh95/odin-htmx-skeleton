# M0 spikes

Each spike closes one unverified item before M1 builds on it (PLAN §22.2; D44). Each writes `S0.<n>.md` here with its
criterion, result and decision; a failure changes the design (PLAN or DECISIONS) before M1 starts. Spike code that M1
or M2 keeps (the fork's changes, the stream prototype, `tools/bundle`, `tools/baseline`) is costed once, here (PLAN
§22.1).

| Spike | Closes | Record |
|---|---|---|
| S0.1 Baseline capture | the reference and its noise band | [S0.1.md](S0.1.md) |
| S0.2 The fork under the skeleton's k6 | the fork keeps the request-path throughput | [S0.2.md](S0.2.md) |
| S0.3 htmx extensions in real browsers against Odin streams | hx-sse, hx-ws and hx-multipart never ran in a browser against Odin | [S0.3.md](S0.3.md) |
| S0.4 `:memory:` parity | D17's candidates | [S0.4.md](S0.4.md) |
| S0.5 Workers and argon2id | the login flow off the loops | [S0.5.md](S0.5.md) |
| S0.6 The guard in the fork + watchdog | the guard's integration | [S0.6.md](S0.6.md) |
| S0.7 Drain and restart | the unbounded waits at shutdown | [S0.7.md](S0.7.md) |
| S0.8 Caddy and streams | whether Caddy's `encode` delays events | [S0.8.md](S0.8.md) |
| S0.9 Linux leg on the dev PC | Odin in WSL2, a TSan build | [S0.9.md](S0.9.md) |
| S0.10 Bundles | `tools/bundle` and the bundle race | [S0.10.md](S0.10.md) |
| S0.11 Tuned SQLite | S10's flags across OSes | [S0.11.md](S0.11.md) |
| S0.12 apollo facts | the host's numbers | [S0.12.md](S0.12.md) |

## How a record reads

```
# S0.<n> <title>

**Closes:** <from PLAN §22.2> · **Pass criterion:** <verbatim from PLAN §22.2>
**Result:** PASS | FAIL | PASS with a change — one sentence · **Date:** YYYY-MM-DD · **Commit:** <the repo commit measured>

## Decision
What the plan does now, and whether PLAN.md or DECISIONS.md changed (which sections).

## Method
Box, toolchain, builds, commands; enough to re-run it.

## Results
Tables of the numbers, each with its unit and n.

## Caveats
What this does not show, and what is still UNVERIFIED (and which gate settles it).
```

Numbers come from runs made for the record, on the box named in Method. A claim with no run behind it is marked
**UNVERIFIED (…)** with the gate that settles it, as in the plan.

## Public-repo hygiene

The repo is public. Records name no LAN address, host path, user name, apollo hardware or service: they use the
placeholders of PLAN §2 (`<APOLLO_LAN_IP>`, `<APOLLO_CPU>`, `<APOLLO_DATA_DIR>` …), whose values live in the git-ignored
`docs/private/SITE.md`. Before a record is committed, SITE.md's hygiene grep must print nothing for it.
