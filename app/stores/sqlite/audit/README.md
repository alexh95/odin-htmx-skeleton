# stores/sqlite/audit

The audit log in SQLite (PLAN §17.7): `audit_log`, append-only by its triggers (no update; a delete only of an entry
older than 400 days). An append is an op through the writer task that nobody waits on; a page is a keyset read on the
loop's reader, newest first, filtered by the actor's name (any case) and an action prefix. A feature store.
