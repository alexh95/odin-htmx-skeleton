package repository

import "../sqlite"

import "core:c"
import "core:crypto/sha2"
import "core:encoding/hex"
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

// ---- migrations ---------------------------------------------------------
//
// Plain SQL files applied in order at boot; migrations[i] is migration #(i+1).
// Each runs in its own transaction together with the schema_version row that
// records it, so one that fails halfway leaves the schema exactly as it was
// (SQLite DDL is transactional; a migration file must not BEGIN/COMMIT itself).
//
// Every applied migration is recorded by file name and content hash and checked
// against the binary's list on each boot. An edited, renamed or unknown one
// stops the boot with a message naming it. Counting versions alone can't tell
// a different schema from the same one: that is how the --minimal starter met a
// demo data.db and died on "no such table: notes".

Migration :: struct {
	name, sql: string,
}

@(private)
migrate :: proc(migrations: []Migration) {
	if problem := apply_migrations(migrations); problem != "" {
		fmt.eprintfln("migrations: %s", problem)
		os.exit(1)
	}
}

// Returns "" or what stopped it; the caller decides whether that's fatal.
@(private)
apply_migrations :: proc(migrations: []Migration) -> (problem: string) {
	Applied :: struct {
		version:    int,
		name, hash: string,
		legacy:     bool,
	}

	exec("BEGIN;")
	exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")
	// 1.1 and earlier recorded only the number. Add the identity columns; the
	// rows they find are adopted below, trusting the binary that finds them.
	if scalar_int("SELECT count(*) FROM pragma_table_info('schema_version') WHERE name='hash'") == 0 {
		exec("ALTER TABLE schema_version ADD COLUMN name TEXT;")
		exec("ALTER TABLE schema_version ADD COLUMN hash TEXT;")
	}

	rows := make([dynamic]Applied, context.temp_allocator)
	{
		st: sqlite.Stmt
		prep("SELECT version, name, hash FROM schema_version ORDER BY version", &st)
		defer sqlite.finalize(st)
		err: Error
		for next_row(st, &err) {
			legacy := sqlite.column_type(st, 2) == sqlite.NULL
			append(&rows, Applied{column_id(st, 0), clone_col(st, 1), clone_col(st, 2), legacy})
		}
	}

	for r, i in rows {
		switch {
		case r.version != i + 1:
			problem = fmt.tprintf("schema_version should count 1, 2, 3…; found #%d where #%d belongs", r.version, i + 1)
		case r.version > len(migrations):
			problem = fmt.tprintf(
				"the database has migration #%d (%s), which this binary doesn't. It was written by a newer or a different app; point DB_PATH at its own file.",
				r.version, r.legacy ? "unnamed" : r.name,
			)
		case r.legacy:
			m := migrations[i]
			st: sqlite.Stmt
			prep("UPDATE schema_version SET name=?, hash=? WHERE version=?", &st)
			bind_text(st, 1, m.name);bind_text(st, 2, migration_hash(m.sql));bind_id(st, 3, r.version)
			err := step_done(st)
			sqlite.finalize(st)
			if err != .None {
				problem = "recording the names of earlier migrations failed"
			}
		case r.name != migrations[i].name || r.hash != migration_hash(migrations[i].sql):
			m := migrations[i]
			problem = fmt.tprintf(
				"migration #%d was applied as %s (sha256 %s) but this binary has %s (sha256 %s). An applied migration must never change: add a new one instead. For a dev database built by another schema, move it aside (delete app/data.db*).",
				r.version, r.name, r.hash[:min(12, len(r.hash))], m.name, migration_hash(m.sql)[:12],
			)
		}
		if problem != "" {
			exec("ROLLBACK;")
			return
		}
	}
	exec("COMMIT;")

	for m, i in migrations[len(rows):] {
		exec("BEGIN;")
		if sqlite.exec(db, csql(m.sql), nil, nil, nil) != sqlite.OK {
			problem = fmt.tprintf("%s failed: %s. Rolled back; the schema is unchanged.", m.name, sqlite.errmsg(db))
			exec("ROLLBACK;")
			return
		}
		st: sqlite.Stmt
		prep("INSERT INTO schema_version(version, name, hash) VALUES(?,?,?)", &st)
		bind_id(st, 1, len(rows) + i + 1);bind_text(st, 2, m.name);bind_text(st, 3, migration_hash(m.sql))
		err := step_done(st)
		sqlite.finalize(st)
		if err != .None {
			exec("ROLLBACK;")
			return fmt.tprintf("recording %s failed", m.name)
		}
		exec("COMMIT;")
		log.infof("migrations: applied %s", m.name)
	}
	return ""
}

// sha256 of the SQL, hex. Carriage returns are dropped first, so a checkout
// with CRLF line endings hashes the same as the LF one that wrote the record.
@(private)
migration_hash :: proc(sql: string) -> string {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	rest := sql
	for len(rest) > 0 {
		cr := strings.index_byte(rest, '\r')
		chunk := cr < 0 ? rest : rest[:cr]
		sha2.update(&ctx, transmute([]byte)chunk)
		rest = cr < 0 ? "" : rest[cr + 1:]
	}
	sum: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
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

// Row ids are 64-bit. c.int is 32, and binding an id through it silently
// reduced it mod 2^32: /contacts/4294967297 read (and deleted) contact #1.
@(private)
bind_id :: proc(st: sqlite.Stmt, idx: c.int, id: int) {
	sqlite.bind_int64(st, idx, i64(id))
}

@(private)
column_id :: proc(st: sqlite.Stmt, col: c.int) -> int {
	return int(sqlite.column_int64(st, col))
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
