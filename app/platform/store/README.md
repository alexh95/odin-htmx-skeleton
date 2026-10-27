# platform/store

What every store shares, in both families: `Error` (failures as values), `Op` (a write: its `run`, its `done` and
an arena for its strings), `enum_from_int`, `contains_ci`. Each feature's store contract lives in the feature's
`models` package (PLAN §6.4). Layer L2 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
