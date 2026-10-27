# platform/guard

Crash containment (D15, PLAN §10.2). Every entry point runs inside `invoke` (the fork's F-5 hook) or `call` (timers,
worker tasks, the writer task); a trap jumps back there, and the thread's counters say whether it is pure (answer 500,
serve on) or dirty (drain, exit 70). Also the only locks the app takes (`guard.Mutex`, `lock`/`unlock`), the
watchdog over loop ticks and held locks, and the crash drills a `-define:TEST_ROUTES=true` build registers. Layer L2 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
