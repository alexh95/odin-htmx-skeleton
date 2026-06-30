# Implementing the data layer in Odin (SQLite)

> **Status: implemented.** This was the plan; it now ships. The store is SQLite, bound as the
> amalgamation in `src/sqlite/` and implemented across `src/repository/` (`repo.odin` + `contacts.odin` + `events.odin`), selected by
> `DB_PATH` (`:memory:` default for tests/dev, a file in prod). The notes below describe the
> shipped design; a few specifics differ from the original draft and are flagged inline.

This is the concrete "how" that [`DATA.md`](DATA.md) (the "why/when") points to: replacing the
in-memory POC store with a persistent **SQLite** layer in Odin, without changing a single line above
the repository.

## 0. The contract to preserve

The `src/repository/` package is the only code that touches storage. The rest of the app speaks
in `models.Contact` and calls exactly these procedures:

```odin
repo_list   :: proc() -> []models.Contact
repo_get    :: proc(id: int) -> (models.Contact, bool)
repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> models.Contact
repo_update :: proc(id: int, name, email: string, role: models.Role, status: models.Status, score: int) -> (models.Contact, bool)
repo_set_status :: proc(id: int, status: models.Status) -> (models.Contact, bool)
repo_delete :: proc(id: int) -> bool
repo_seed   :: proc()
```

**The whole job is to reimplement these seven over SQLite.** Services, views, controllers, e2e, and
load-tests do not change. Two invariants must hold exactly as today:

1. **Returned strings live in `context.temp_allocator`.** Today `snapshot()` clones name/email into
   the request arena so nothing aliases the store across the lock. With SQLite, `sqlite3_column_text`
   returns a pointer owned by the statement (invalidated on the next `step`/`reset`), so you **must**
   clone column text into the temp arena before returning — same discipline, same allocator.
2. **`repo_create`/`repo_update` accept arbitrary input; `repo_delete` frees.** With SQLite the DB
   owns the bytes, so there's nothing to free on delete — the `delete()` calls simply go away.

## 1. The dependency

SQLite is a single C library — in keeping with the "two-dependency" line (it's the most-deployed
database on earth, not a framework). **Bind the amalgamation directly.**

> **There is no `vendor:sqlite3` collection in Odin.** The request to add one
> ([odin-lang/Odin #3736](https://github.com/odin-lang/Odin/issues/3736)) was closed *won't
> implement*. An earlier draft of this doc listed `import "vendor:sqlite3"` as an option — that was
> wrong; disregard it.

The amalgamation is SQLite's official single-file distribution (`sqlite3.c` + `sqlite3.h`). We
follow the **htmx precedent, not the odin-http submodule one**: `prepare.sh`/`prepare.bat` fetch a
**pinned** `sqlite-amalgamation-XXXXXXX.zip` from sqlite.org, **verify its SHA-256**, unzip into a
gitignored `app/vendor/sqlite/`, and **compile it once** into a static lib so `odin build` just
links it:

- Windows: `cl /c /O2 /MT sqlite3.c && lib /OUT:sqlite3.lib sqlite3.obj`
- Linux/macOS: `clang -O2 -c sqlite3.c -o sqlite3.o && ar rcs sqlite3.a sqlite3.o`

> The Windows compile uses **`/MT`** (static CRT), not `/MD`: Odin links the CRT statically on
> Windows, and `/MD`'s dynamic-import (`__imp_*`) symbols don't resolve against Odin's `libucrt.lib`.

No git submodule (the amalgamation has no canonical git repo; its canonical form is the versioned
zip), and neither the source nor the built lib is committed. The version and its SHA-256 are pinned
together at the top of `prepare.*` — the same reproducibility discipline as `ODIN_VERSION` and
`htmx`. ~15 `foreign` decls (`app/src/sqlite/sqlite.odin`) cover everything below, with a per-OS
link block pointing at `app/vendor/sqlite/`: `sqlite3.lib` on Windows; `sqlite3.a` +
`system:pthread` + `system:dl` on Linux/macOS. A C toolchain is now a hard build requirement.

## 2. Schema + migrations (keep it boring)

Schema is plain SQL applied in order at boot — no ORM, no migration framework.

```sql
-- migrations/0001_init.sql
CREATE TABLE IF NOT EXISTS contacts (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  name   TEXT    NOT NULL,
  email  TEXT    NOT NULL,
  role   INTEGER NOT NULL,   -- mirrors models.Role  (store the enum's int value)
  status INTEGER NOT NULL,   -- mirrors models.Status
  score  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);
```

Enums map to their integer value (`int(role)`), so the DB stays in lockstep with `models` with no
lookup table; the label tables (`ROLE_NAMES`) remain the single source of truth for display. A
`schema_version` table + a tiny apply-on-boot loop runs any migration whose number exceeds the
stored version. `#load` the `.sql` files at compile time so they ride inside the binary.

## 3. Connection lifecycle + pragmas

Open once at startup (from `main`, next to `repo_seed`). The pragmas are what make SQLite behave
well under the multithreaded server:

```odin
sqlite3_open_v2("data.db", &db, OPEN_READWRITE | OPEN_CREATE, nil)
exec(db, "PRAGMA journal_mode=WAL;")     // many readers + one writer concurrently
exec(db, "PRAGMA busy_timeout=5000;")    // wait, don't fail, on a brief write lock
exec(db, "PRAGMA foreign_keys=ON;")
exec(db, "PRAGMA synchronous=NORMAL;")   // safe with WAL, much faster than FULL
```

**Prepare statements once, reuse forever.** Each `repo_*` proc has one or two prepared statements
created at init and reused (bind → step → reset). This is the single biggest perf lever and avoids
re-parsing SQL on every request.

## 4. Concurrency — maps cleanly onto what's already there

The server runs N nbio threads and today guards the slice with an `sync.RW_Mutex` (shared reads,
exclusive writes). SQLite gives you the same model at the storage layer; pick one:

- **Recommended: WAL + one connection per thread** (or a small pool keyed by thread). WAL lets all
  reader connections run concurrently while one writer proceeds; `busy_timeout` absorbs the brief
  writer lock. Drop the `RW_Mutex` — SQLite is the concurrency authority now. Compile SQLite in
  **serialized** or **multi-thread** mode and don't share one connection's statements across threads.
- **Shipped (v1): a single shared connection behind the existing `RW_Mutex`.** Keep the lock, but
  every `repo_*` takes it **exclusively** — including reads. A single connection's prepared
  statements are shared mutable state (bound params + cursor), so two threads stepping them under a
  *shared* read lock would corrupt each other; correctness requires serializing. (So this v1 doesn't
  actually get parallel reads — that's the point of the *Recommended* option above, deferred until
  the load tests demand it. The `RW_Mutex` type is kept precisely so reads can drop back to the
  shared lock once per-thread WAL connections land.) Correct and trivial; serializes all DB access.

> The original draft of this section said the simple option takes the lock "shared for reads,
> exclusive for writes." That's subtly wrong for *one* connection with shared statements — corrected
> above. The shared-reads model is right for the per-thread-connection design, not this one.

Either way the load-test before/after (`load-tests/RESULTS.md`) is the arbiter: implement the simple
one, measure, then move to per-thread connections if reads don't scale.

## 5. The procedures (sketches)

The shape is identical for all; here are the representative two. `q_*` are prepared statements;
`scan_contact` reads columns into a `models.Contact` **cloning text into the temp arena**.

```odin
@(private = "file")
scan_contact :: proc(st: ^sqlite3.Stmt) -> models.Contact {
    return models.Contact {
        id     = int(sqlite3.column_int(st, 0)),
        name   = clone_col(st, 1),   // strings.clone(string(column_text), context.temp_allocator)
        email  = clone_col(st, 2),
        role   = models.Role(sqlite3.column_int(st, 3)),
        status = models.Status(sqlite3.column_int(st, 4)),
        score  = int(sqlite3.column_int(st, 5)),
    }
}

repo_list :: proc() -> []models.Contact {
    out := make([dynamic]models.Contact, context.temp_allocator)
    defer sqlite3.reset(q_list)
    for sqlite3.step(q_list) == .ROW {
        append(&out, scan_contact(q_list))
    }
    return out[:]
}

repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> models.Contact {
    sqlite3.reset(q_create)
    bind_text(q_create, 1, name); bind_text(q_create, 2, email)
    sqlite3.bind_int(q_create, 3, i32(role)); sqlite3.bind_int(q_create, 4, i32(status))
    sqlite3.bind_int(q_create, 5, i32(score))
    sqlite3.step(q_create)                              // INSERT ... ; (no RETURNING needed)
    id := int(sqlite3.last_insert_rowid(db))
    c, _ := repo_get(id)                                // read back as the temp-cloned snapshot
    return c
}
```

`repo_get` = `SELECT … WHERE id=? LIMIT 1`; `repo_update` = `UPDATE … WHERE id=?` then `repo_get`;
`repo_set_status` = `UPDATE contacts SET status=? WHERE id=?`; `repo_delete` = `DELETE … WHERE id=?`
returning `sqlite3_changes(db) > 0`; `repo_seed` = the same loop as today, writing through
`repo_create` (wrapped in one transaction — `BEGIN`/`COMMIT` — so 20 inserts are one fsync).

**Note the allocator discipline:** every string handed out is cloned into `context.temp_allocator`
inside `scan_contact`. Nothing returned points into a statement's buffer, so a later `step`/`reset`
on another thread can't pull the rug out — exactly the guarantee `snapshot()` gives today.

## 6. Filtering/sorting: push it down (optional, later)

Today `service_page` filters/sorts in Odin over the full list. With SQLite you *can* push `q`/status
filtering and sort into SQL (`WHERE … LIKE ? AND status=? ORDER BY …`) and only fetch one page. Not
required for correctness — the in-Odin path keeps working over `repo_list` — but it's the natural
next optimization once the dataset outgrows "fits in a slice." Keep it behind the same
`service_page` signature so nothing above notices.

## 7. Build, deploy, ops

- **Build**: `prepare.*` fetches + compiles the amalgamation into `app/vendor/sqlite/`; `odin build
  src` then links it via the `foreign import` block. Because we vendor the amalgamation, the build
  needs a **C toolchain** (not `libsqlite3-dev`): the Dockerfile and CI gain `clang binutils unzip`
  (Windows uses MSVC `cl`/`lib` + PowerShell `Expand-Archive`). The runtime image carries nothing —
  sqlite is statically linked into the binary.
- **Deploy**: the binary needs a writable path for `data.db` *only when `DB_PATH` points at a file*.
  apollo-11 mounts a named docker volume at `/data` and sets `DB_PATH=/data/data.db` (durable across
  redeploys). On Fly, leaving `DB_PATH` unset keeps `:memory:` (the live demo reseeds each deploy);
  to persist, `fly volumes create`, add `[mounts]` + `DB_PATH` to `fly.toml` (operator step — a
  `[mounts]` referencing a missing volume fails the deploy). Back up = copy the file (or `VACUUM
  INTO`).
- **The store no longer resets per process** — so e2e/load, which rely on a clean fixture, should
  point at an ephemeral DB (`:memory:` or a temp file deleted per run). Wire this via the existing
  `PORT`/env pattern: `DB_PATH=:memory:` for tests, a real path in prod. `repo_seed` still runs at
  boot, so a fresh `:memory:` DB looks exactly like today.

## 8. Testing & parity (unchanged contract, one new test)

Because the contract is identical, **the entire e2e and load suite passes as-is** — that's the proof
the swap is clean. Add exactly one new behaviour: a test that data **survives a restart** (create →
restart the process pointed at a file DB → the contact is still there), the one thing the in-memory
store could never do. Keep e2e/load at par as always.

## 9. Rollout (as shipped)

1. Landed the binding (`src/sqlite/`) + schema + the repository (`repo.odin` + per-table files),
   **`DB_PATH`-selected** — `:memory:` for tests/dev (the old in-memory Odin store was *removed*,
   not kept as a parallel backend), a file path to persist.
2. Ran the full e2e + load suites — they passed untouched, plus one new test (survives a restart).
3. Measured with `load-tests/` (single shared connection); recorded next to the threading
   before/after in `RESULTS.md`.
4. Reads scale ~3–4× under the exclusive lock (the `detail` JOIN worst at 1.9×) → the open next
   step is **per-thread WAL connections**, now load-justified.

## When this is the wrong tool

Per `DATA.md`: reach past SQLite for multiple app instances sharing one dataset, high concurrent
*write* load, or a managed/networked DB — that's Postgres (`libpq` via `foreign import`), at the cost
of a network hop per query and an operational surface. For a single-box internal admin console,
SQLite is the endpoint, not a stepping stone.
