# stores/sqlite/contacts

Contacts in SQLite: every list filtered, sorted, paged and counted by SQLite with only the rows asked for copied
out; reads on the loop's reader, writes as ops through the writer task. Migrations 0001-0003 keep the skeleton's
hashes (a 1.2.x database is adopted in place); 0004 adds an index per sort key. A feature store.

Audited: bf831da 2026-10-26 docs/audit/M1.md
