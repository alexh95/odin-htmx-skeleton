# stores/sqlite/dbview

dbview's one store (PLAN §15.4; SQLite only, D18): `query` runs an admin's SQL through `platform/store/sqlite`'s
`adhoc` on a query-pool thread's own read-only reader: one statement, read-only by SQLite's own account, `ATTACH`
refused, interrupted past its time budget, rows and cells capped. It never writes and never takes the writer's lock.
A feature store.

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read)
