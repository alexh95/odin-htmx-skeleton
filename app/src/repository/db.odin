package repository

import "../sqlite"

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"

// ---- SQLite plumbing (entity-agnostic) ----------------------------------
//
// The connection, its lock, the boot-time migration runner and the small
// bind/scan/exec helpers every table file uses. Nothing here knows a table:
// it is shared, unchanged, by the demo and the `init --minimal` starter. The
// app's own wiring — which migrations, which statements, the seed — lives in
// repo.odin, and each table in its own file.
//
// Backend is chosen by DB_PATH (see main): ":memory:" (the test/dev default — a
// real in-RAM SQLite, gone on exit) or a file that persists.
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

// What a store call can fail with, returned as a value for the layers above to
// branch on. The SQLite message itself goes to the log, not to the client.
Error :: enum {
	None,
	Not_Found, // no row with that id
	Constraint, // the row broke a NOT NULL / UNIQUE / CHECK / FOREIGN KEY rule
	Failed, // anything else: I/O, a lock held past busy_timeout, a full disk
}

@(private)
db_open :: proc(path: string) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if sqlite.open_v2(cpath, &db, sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE, nil) != sqlite.OK {
		fatal("open")
	}
	exec("PRAGMA journal_mode=WAL;") // many readers + one writer (a no-op on :memory:)
	exec("PRAGMA busy_timeout=5000;") // wait, don't fail, on a brief write lock
	exec("PRAGMA foreign_keys=ON;") // ON DELETE CASCADE and friends are off without it
	exec("PRAGMA synchronous=NORMAL;") // safe under WAL, much faster than FULL
}

// Checkpoints the WAL on a file DB. Runs after the server loop returns, so no
// request is in flight.
@(private)
db_close :: proc() {
	sqlite.close(db)
}

// Migrations applied in order at boot; index i == migration #(i+1).
@(private)
migrate :: proc(migrations: []string) {
	exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")
	cur := scalar_int("SELECT coalesce(max(version),0) FROM schema_version")
	for i in cur ..< len(migrations) {
		exec(csql(migrations[i]))
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

// An empty Odin string has a nil data pointer, and SQLite binds a nil pointer
// as NULL, which a NOT NULL column then rejects. Point at a real byte instead,
// with length 0, so "" is stored as the empty text it is.
@(private = "file") EMPTY := [1]u8{}

@(private)
bind_text :: proc(st: sqlite.Stmt, idx: c.int, s: string) {
	p := raw_data(s)
	if p == nil {
		p = &EMPTY[0]
	}
	sqlite.bind_text(st, idx, p, c.int(len(s)), sqlite.TRANSIENT)
}

// Run a write to completion. Anything but DONE is an error: last_insert_rowid
// and changes() still describe the previous statement, so reading them after a
// failed step hands back someone else's row.
@(private)
step_done :: proc(st: sqlite.Stmt) -> Error {
	rc := sqlite.step(st)
	if rc == sqlite.DONE {
		return .None
	}
	return step_error(rc)
}

// Advance a read; false at the end of the rows or on an error, which lands in
// err^. For `for next_row(st, &err) { ... }` loops that report how they ended.
@(private)
next_row :: proc(st: sqlite.Stmt, err: ^Error) -> bool {
	switch rc := sqlite.step(st); rc {
	case sqlite.ROW:
		return true
	case sqlite.DONE:
		return false
	case:
		err^ = step_error(rc)
		return false
	}
}

@(private = "file")
step_error :: proc(rc: c.int) -> Error {
	log.errorf("sqlite step failed (%d): %s", rc, sqlite.errmsg(db))
	// The low byte is the primary result code; the rest says which constraint.
	return (rc & 0xff) == sqlite.CONSTRAINT ? .Constraint : .Failed
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
// loudly. A failing step during a request is the caller's to handle: it comes
// back as an Error (step_done / next_row) and the request fails, not the server.
@(private)
fatal :: proc(what: string) {
	fmt.eprintfln("sqlite %s failed: %s", what, sqlite.errmsg(db))
	os.exit(1)
}
