# dbview

`/admin/dbview` (PLAN §15.4, M5; D36): an admin's own SQL against the site's database, read only. Packages: `dbview`
(the domain: the text's cap, the limits), `models`, `views` and `web`; one store, `stores/sqlite/dbview` (SQLite only,
D18: a memory build has no SQL to run).

The query runs on the store's query pool, on that thread's own reader, which is opened read-only: whatever the text
says, it can't write, and it never takes the writer's lock (the `dbview` drill holds that: writes beside a query that
runs to its budget keep their latency). It must be one statement that SQLite itself calls read-only (`stmt_readonly`),
`ATTACH` is refused (`LIMIT_ATTACHED` 0: SQLite counts an attach as a read, and it would open any file the process can
read), and a progress handler stops it at 2 s, since a long read's snapshot pins the WAL (12 §3.3). At most 200 rows
and 200 characters a cell come back; values are text as SQLite gives them, a blob as its size. Every query is audited
(`dbview.query`, the whole SQL in the entry's detail, so padding can't hide what was read). It reads every table,
the accounts' TOTP secrets and session-token hashes among them: that is `Admin_Db`'s grant, which only Admin holds.

| Route | Perm | What |
|---|---|---|
| `GET /admin/dbview` | `Admin_Db`, LAN only, step-up | the form |
| `POST /admin/dbview` | `Admin_Db`, LAN only, step-up | sql (at most 4000 bytes): the result's table, or why it didn't run (422 for an empty or long text) |

It owns `/admin/dbview`, its own prefix.

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read)
