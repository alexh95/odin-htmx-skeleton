# stores/sqlite/notes

Notes in SQLite: reads on the loop's reader; an add goes through the writer task and reads the row back inside its
batch, so the caller answers with exactly what was stored. A feature store.

Audited: bf831da 2026-10-26 docs/audit/M1.md
