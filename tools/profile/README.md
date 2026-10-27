# tools/profile

The two profiling artifacts behind M1's profile (`docs/audit/M1.md`, Profile), made repeatable for each milestone
exit. Linux only, as perf is; on the dev PC it runs in WSL from a copy of the tree (the parity gate's Linux leg, with
k6 at `/opt/k6/k6`).

```sh
sh tools/profile/profile.sh <profile> <scenario> [--spall]
```

- **perf**: builds the profile at `-o:speed -debug`, drives `load-tests/scenarios/*/<scenario>.js` at 200 VUs for
  8 s and records 4 s of the server (`perf record -F 199 --call-graph dwarf`). It writes, to `app/build/profile/`:
  `<p>-<scenario>.perf.txt` (perf script's samples, which speedscope.app and the Firefox profiler open),
  `.folded` (a stack a line with its count), `.top.txt` (the 30 heaviest functions, inclusive and self) and, when
  FlameGraph's scripts are on PATH or in `$FLAMEGRAPH`, `.svg`. Ubuntu's `perf` is a wrapper that wants linux-tools
  for the running kernel, which WSL's kernels have none of; the script falls back to any installed linux-tools perf
  (`PERF` overrides).
- **`--spall`**: builds a scratch copy of the profile with `spall_hook.odin` in its `cmd/`, so every procedure's
  calls go to `<p>-<scenario>.spall` (spall's viewer, gravitymoth.com/spall), with 1 VU for 1 s (`SPALL_SECONDS`)
  on 2 loops. The instrumentation inflates every call, so read its call counts, not its times. It is large: about
  0.8 GB a second of `pages`.

`spall_hook.odin` is never part of a profile in the repo and doesn't build on its own (package `main` with no
`main`): the script copies it into the scratch build only.

Audited: not read by `docs/audit/M2.md` (dev-time, off the request path)
