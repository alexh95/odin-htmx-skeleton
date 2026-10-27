# platform/sys

The OS pieces under the guard, and the clocks: glibc's `_setjmp`, the trap handlers (`sigaction` with a per-thread
alternate stack on POSIX, a vectored exception handler and `_resetstkoflw` on Windows), the per-thread counters the
guard classifies a trap by (`locks_held`, `async_posted`, `in_sqlite`), the open-file limit, `process_alive` (the
ephemeral sweep) and a fast wall clock. Bindings and thread-local primitives only, no policy: `platform/guard` decides
what a trap means (PLAN §5.2, §10.2). Layer L1 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
