package repository

import "../sqlite"

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

// ---- repository: SQLite plumbing (entity-agnostic) ----------------------
//
// The store is SQLite (amalgamation, bound in src/sqlite/). This file owns the
// shared connection + lock, the boot-time migration runner, and the small
// bind/scan/exec helpers. Each entity lives in its own file — contacts.odin
// (the seven repo_*) and events.odin (event_*) — which call these helpers and
// own their own prepared statements. Nothing above the repository changes.
//
// Backend is chosen by DB_PATH (see main): ":memory:" (the test/dev default — a
// real in-RAM SQLite, seeded fresh per boot, gone on exit) or a file that persists.
//
// Concurrency v1: ONE shared connection, the RW_Mutex taken EXCLUSIVELY for every
// op — reads included. A single connection's prepared statements are shared
// mutable state (bound params + cursor), so two threads stepping them under a
// *shared* read lock would corrupt each other. Parallel reads come back when we
// move to per-thread WAL connections, deferred until the load tests demand it
// (docs/DATA_IMPL.md §4). The RW_Mutex type is kept for exactly that future.
//
// Allocator discipline: every string handed back is cloned into
// context.temp_allocator (clone_col), so nothing returned points into a statement
// buffer a later step/reset could invalidate.

@(private) db: sqlite.DB
@(private) lock: sync.RW_Mutex

// Migrations applied in order at boot; index i == migration #(i+1). #load'd so
// they ride inside the binary. Add 0003_*.sql here to grow the schema.
@(private = "file") MIGRATIONS := [?]string {
	#load("migrations/0001_init.sql", string),
	#load("migrations/0002_events.sql", string),
}

// ---- lifecycle (called from main, around repo_seed) ---------------------

repo_open :: proc(path: string) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if sqlite.open_v2(cpath, &db, sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE, nil) != sqlite.OK {
		fatal("open")
	}
	exec("PRAGMA journal_mode=WAL;") // many readers + one writer (a no-op on :memory:)
	exec("PRAGMA busy_timeout=5000;") // wait, don't fail, on a brief write lock
	exec("PRAGMA foreign_keys=ON;") // events.actor_id/target_id ON DELETE CASCADE
	exec("PRAGMA synchronous=NORMAL;") // safe under WAL, much faster than FULL
	migrate()
	prepare_contacts()
	prepare_events()
}

// Finalize statements and close the connection (checkpoints the WAL on a file
// DB). Symmetry with repo_open; wire via `defer` in main. Runs after the server
// loop returns, so no request is in flight.
repo_close :: proc() {
	finalize_contacts()
	finalize_events()
	sqlite.close(db)
}

// Seed both tables, but each only when empty — so a persistent DB isn't
// duplicated, and a DB migrated from contacts-only (e.g. an existing deploy)
// still gets its events backfilled. One transaction = one fsync; events seed
// after contacts so the FK targets exist.
repo_seed :: proc() {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	exec("BEGIN;")
	if count_contacts() == 0 {
		seed_contacts()
	}
	if count_events() == 0 {
		seed_events()
	}
	exec("COMMIT;")
}

@(private = "file")
migrate :: proc() {
	exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")
	cur := scalar_int("SELECT coalesce(max(version),0) FROM schema_version")
	for i in cur ..< len(MIGRATIONS) {
		exec(csql(MIGRATIONS[i]))
		exec(csql(fmt.tprintf("INSERT INTO schema_version(version) VALUES(%d);", i + 1)))
	}
}

// ---- shared helpers (caller holds the lock) -----------------------------

@(private)
exec :: proc(sql: cstring) {
	if sqlite.exec(db, sql, nil, nil, nil) != sqlite.OK {
		fatal("exec")
	}
}

@(private)
prep :: proc(sql: cstring, out: ^sqlite.Stmt) {
	if sqlite.prepare_v2(db, sql, -1, out, nil) != sqlite.OK {
		fatal("prepare")
	}
}

@(private)
bind_text :: proc(st: sqlite.Stmt, idx: c.int, s: string) {
	sqlite.bind_text(st, idx, raw_data(s), c.int(len(s)), sqlite.TRANSIENT)
}

// Clone a text column into the request temp arena — never alias a stmt buffer.
@(private)
clone_col :: proc(st: sqlite.Stmt, col: c.int) -> string {
	return strings.clone_from_cstring(sqlite.column_text(st, col), context.temp_allocator)
}

// One-shot scalar query (its own prepared+finalized stmt); used by migrate.
@(private)
scalar_int :: proc(sql: cstring) -> int {
	st: sqlite.Stmt
	prep(sql, &st)
	defer sqlite.finalize(st)
	if sqlite.step(st) == sqlite.ROW {
		return int(sqlite.column_int(st, 0))
	}
	return 0
}

@(private)
csql :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

// Startup/migration errors are unrecoverable (a broken DB at boot), so bail
// loudly. Per-request statement steps are best-effort — a bad input shouldn't
// take the server down — and surface as a not-found / empty result.
@(private)
fatal :: proc(what: string) {
	fmt.eprintfln("sqlite %s failed: %s", what, sqlite.errmsg(db))
	os.exit(1)
}
