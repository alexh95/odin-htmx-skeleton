# platform/store/memory

What the memory family's stores share (D16, D18): rows kept in the process behind a `guard.Mutex`, ops run at once
under it. It links no SQLite, so a memory profile builds where no SQLite library exists; rows go when the process
does. Layer L2 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
