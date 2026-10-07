# Data — past the in-memory POC

> **Update:** the SQLite step described here now ships (see
> [`DATA_IMPL.md`](DATA_IMPL.md) and the `src/repository/` package (`db.odin` + `repo.odin` + `contacts.odin` + `events.odin`)). `DB_PATH=:memory:` keeps
> the old POC behaviour (in-RAM, seeded on boot, gone on exit — now a real in-RAM SQLite rather than
> a hand-rolled slice); a file path persists. The *when-is-each-right* reasoning below still stands.

Originally forward-looking. The starting point was an **in-memory POC**: a `[dynamic]Contact` behind
an `RW_Mutex`, seeded on boot, gone on exit. This documents how to make it real *when it makes
sense* — and when it honestly doesn't need to.

## The seam already exists

The whole point of the layered design is that the datasource is swappable without touching anything
above it. **the `src/repository/` package (`db.odin` + `repo.odin` + `contacts.odin` + `events.odin`) is the only code that touches storage.** Everything
else speaks in `models.Contact` and calls `repo_list / repo_get / repo_create / repo_update /
repo_delete`. Swapping backends = reimplementing those procedures. Services, views, controllers,
and the entire HTTP surface stay byte-for-byte identical.

So this is not a rewrite — it lives behind a contract that already holds.

## When in-memory is genuinely fine

Don't add a database to look serious. The POC store is the *correct* choice when:

- the data is a fixed seed / demo fixture, or is rebuilt from an authoritative source on boot;
- it fits comfortably in RAM and the working set is small;
- a single process owns it, and losing it on restart is acceptable (or it's reseeded);
- you want zero operational surface.

That describes this showcase exactly. The honesty rule (PHILOSOPHY → "the 90%") is to *call it a
POC*, not to pretend it's durable.

> The concrete, step-by-step **implementation plan** — bindings, schema, the seven `repo_*` as SQL,
> concurrency, migrations, build/ops — lives in [`DATA_IMPL.md`](DATA_IMPL.md). This file is the
> *why/when*; that one is the *how*.

## The recommended next step: SQLite

When you need persistence, the answer that keeps the philosophy intact is **SQLite**:

- **One file on disk**, in-process, no network hop, no server to run — the data analogue of "one
  self-contained binary." Add a volume, keep everything else.
- Fast enough by a wide margin for the sweet-spot apps in [`USE_CASES.md`](USE_CASES.md) — an admin
  console's read/write rates are nowhere near SQLite's ceiling.
- One C dependency, which is in keeping with the line we hold (it's the most-deployed database on
  earth, not a framework). In Odin: bind the SQLite **amalgamation** (a single `.c` file) directly.
  (There is no `vendor:sqlite3` collection — the request to add one,
  [odin-lang/Odin #3736](https://github.com/odin-lang/Odin/issues/3736), was closed *won't
  implement*.)

Concretely, `repo_*` becomes thin SQL:

```odin
// repo_create -> INSERT ... RETURNING id;  repo_list -> SELECT ... ;  etc.
// Build models.Contact rows from the result set, cloned into the right allocator
// exactly as the snapshot pattern does today.
```

**Concurrency maps cleanly onto what we already built.** Run SQLite in **WAL mode** with a
`busy_timeout`: many concurrent readers + one writer at a time — which is *precisely* the
`RW_Mutex` contract the repository already enforces (shared reads, exclusive writes). The
multithreaded server stays correct; SQLite handles durability and the read/write discipline carries
over. Add the read scenarios to `load-tests/` and re-measure — disk + WAL will move the numbers, and
that before/after is worth recording.

## When you outgrow one box: Postgres

Reach past SQLite only when the topology demands it:

- **multiple app instances** sharing one dataset (horizontal scale), or
- **high concurrent write** load beyond one writer, or
- you want a managed/networked DB, replication, rich types, or analytics alongside.

In Odin: `libpq` via `foreign import`, or a driver if one exists for your version. The cost is real
and worth naming: a **network hop per query** and an **operational surface** (a server to run,
secure, back up). For the sweet-spot apps this is usually premature — SQLite first, Postgres when a
concrete constraint forces it, not by default.

## Migrations & operations (keep it boring)

- **Schema as plain SQL files**, applied in order at startup (a `schema_version` table + a tiny
  apply-on-boot loop) or by a one-shot tool. No ORM, no migration framework — same discipline as the
  rest of the stack.
- **Backups** are `<bin> --backup <file>` (SQLite: a consistent copy via `VACUUM INTO`, safe while
  the server runs; see the runbook below) or your provider's snapshots (Postgres). **Never copy
  `data.db` itself while the server runs**: in WAL mode, recent commits live in `data.db-wal` until a
  checkpoint, so a copy of the main file alone can silently miss them.
- **Seeding** stays exactly as `repo_seed` does now, just writing through the real backend.

## Backup and restore (SQLite)

The binary backs itself up: `DB_PATH=<live db> <bin> --backup <new file>` writes a consistent,
compacted snapshot with `VACUUM INTO` and exits. It opens its own connection, so it runs beside the
live server, and it refuses to overwrite an existing file. `/healthz` stays green throughout.

**Back up** (from wherever the database lives; use a dated name, so each run makes a new file):

```sh
# Fly (the Dockerfile puts the binary at /app/demo — /app/<name> after init; the volume at /data):
fly ssh console -C "/app/demo --backup /data/backup-$(date +%F).db"   # DB_PATH is already set
fly ssh sftp get /data/backup-$(date +%F).db                                     # take it off the volume
# Docker host:
docker exec <container> /app/demo --backup /data/backup-$(date +%F).db
docker cp <container>:/data/backup-$(date +%F).db .
```

Run it on a schedule (a cron job or systemd timer on the host; on Fly, a scheduled GitHub Action or
machine running the same `fly ssh console` line), keep several, and copy them **off the machine**: a
backup on the same volume dies with it. A Fly volume lives on one host, so its snapshots are a
second line, not the first.

**Restore**:

1. Stop the app (`fly scale count 0`, or `docker compose stop`).
2. Replace `data.db` with the backup, and **delete `data.db-wal` and `data.db-shm`**: a stale WAL
   would be replayed onto the restored file.
3. Start the app. The boot log names the migrations it applied (none, if the backup is current), and
   a backup from an older release is migrated forward like any database; one written by a different
   app is refused with a message rather than opened.
4. Check `/healthz` and a page you know the data for.

Rehearse it once before you need it: `e2e/tests/backup.spec.ts` does exactly this.

**One machine, one database.** With `DB_PATH` on a volume, `fly scale count 2` gives two machines
two separate databases that drift apart. Persistent SQLite here means one machine; past that is the
Postgres row of the table below.

## Summary

| | in-memory (now) | SQLite (next) | Postgres (scale) |
|---|---|---|---|
| persistence | none | one file | networked server |
| ops surface | none | a volume | a database to run |
| concurrency | RW_Mutex | WAL (readers + 1 writer) | full MVCC |
| in-process | yes | yes | no (network hop) |
| fits the philosophy | as a POC | **yes** | when justified |

The repository seam means you can sit at any row of that table and move right exactly when a real
constraint — not a vibe — makes you.
