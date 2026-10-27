# platform/store/sqlite

Store v3 (D16, PLAN §11): one read-only connection per reading thread, opened on its first read; one writer
connection, written by the writer task, which commits whatever is queued, up to 100 writes, as one transaction and
answers each on the loop that queued it; `:memory:` served by `MEMMODE` (an unsynced ephemeral WAL file by default);
the migration runner per feature, adopting 709bc94 and v1.1.1 databases; `--backup` and `--adopt-profile`; the
query pool. Layer L2 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
