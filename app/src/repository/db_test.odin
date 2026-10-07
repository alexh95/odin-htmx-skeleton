package repository

import "../sqlite"

import "core:log"
import "core:sync"
import "core:testing"

// ---- tests for the plumbing: `odin test src/repository` -----------------
//
// Generic on purpose: each test builds its own tables in a fresh :memory: DB,
// so they hold for the demo and the --minimal starter alike. They share
// db.odin's one connection, so each holds `serial` for its whole run (the test
// runner is multi-threaded).

@(private = "file") serial: sync.Mutex

@(test)
empty_text_is_stored_as_empty_text :: proc(t: ^testing.T) {
	sync.guard(&serial)
	db_open(":memory:")
	defer db_close()
	exec("CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT NOT NULL);")

	ins: sqlite.Stmt
	prep("INSERT INTO t(s) VALUES(?)", &ins)
	defer sqlite.finalize(ins)
	bind_text(ins, 1, "")
	testing.expect_value(t, step_done(ins), Error.None)

	sel: sqlite.Stmt
	prep("SELECT s FROM t", &sel)
	defer sqlite.finalize(sel)
	err: Error
	testing.expect(t, next_row(sel, &err))
	testing.expect_value(t, sqlite.column_type(sel, 0), sqlite.TEXT) // "", not NULL
	testing.expect_value(t, clone_col(sel, 0), "")
}

@(test)
a_failed_write_is_an_error_not_a_stale_row :: proc(t: ^testing.T) {
	sync.guard(&serial)
	db_open(":memory:")
	defer db_close()
	exec("CREATE TABLE t (id INTEGER PRIMARY KEY, n INTEGER NOT NULL CHECK (n > 0));")

	ins: sqlite.Stmt
	prep("INSERT INTO t(n) VALUES(?)", &ins)
	defer sqlite.finalize(ins)

	sqlite.bind_int(ins, 1, 1)
	testing.expect_value(t, step_done(ins), Error.None)
	sqlite.reset(ins)
	testing.expect_value(t, sqlite.last_insert_rowid(db), 1)

	// The CHECK fails; last_insert_rowid still says 1, which is why a caller
	// must see the error rather than read the id. (step_done logs the failure
	// as an error, which the test runner would count against the test.)
	context.logger = log.nil_logger()
	sqlite.bind_int(ins, 1, 0)
	testing.expect_value(t, step_done(ins), Error.Constraint)
	sqlite.reset(ins)
	testing.expect_value(t, sqlite.last_insert_rowid(db), 1)
}
