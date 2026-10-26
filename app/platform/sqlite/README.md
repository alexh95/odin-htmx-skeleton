# platform/sqlite

The SQLite amalgamation's binding, the only place the C ABI is crossed. `prepare.*` fetches the pinned amalgamation
and compiles it with D16's flags into `app/vendor/sqlite/`. Every call runs with the thread's `in_sqlite` counter
raised, so the guard knows a trap inside SQLite is dirty (D15). Layer L1 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
