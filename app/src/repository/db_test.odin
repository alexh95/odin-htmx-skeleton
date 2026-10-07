package repository

import "../sqlite"

import "core:fmt"
import "core:log"
import "core:strings"
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

@(test)
a_broken_migration_rolls_back_and_names_its_file :: proc(t: ^testing.T) {
	sync.guard(&serial)
	db_open(":memory:")
	defer db_close()
	migrations := []Migration {
		{"0001_a.sql", "CREATE TABLE a (x);"},
		{"0002_b.sql", "CREATE TABLE b (x); CREATE TABLE b (x);"}, // fails on its second statement
	}
	problem := apply_migrations(migrations)
	testing.expect(t, strings.contains(problem, "0002_b.sql"), problem)
	testing.expect_value(t, table_count("a"), 1)
	testing.expect_value(t, table_count("b"), 0) // its first statement was rolled back too
	testing.expect_value(t, scalar_int("SELECT count(*) FROM schema_version"), 1)
}

@(test)
an_edited_or_unknown_migration_stops_the_boot :: proc(t: ^testing.T) {
	sync.guard(&serial)
	db_open(":memory:")
	defer db_close()
	testing.expect_value(t, apply_migrations({{"0001_a.sql", "CREATE TABLE a (x);"}, {"0002_b.sql", "CREATE TABLE b (x);"}}), "")
	testing.expect_value(t, apply_migrations({{"0001_a.sql", "CREATE TABLE a (x);"}, {"0002_b.sql", "CREATE TABLE b (x);"}}), "")

	edited := apply_migrations({{"0001_a.sql", "CREATE TABLE a (x, y);"}, {"0002_b.sql", "CREATE TABLE b (x);"}})
	testing.expect(t, strings.contains(edited, "never change"), edited)

	// The --minimal starter meeting the demo's data.db: a different #1, and a #2
	// it has never heard of.
	other := apply_migrations({{"0001_init.sql", "CREATE TABLE notes (x);"}})
	testing.expect(t, strings.contains(other, "0001_a.sql"), other)
	testing.expect_value(t, table_count("notes"), 0)
}

@(test)
a_database_from_before_named_migrations_is_adopted :: proc(t: ^testing.T) {
	sync.guard(&serial)
	db_open(":memory:")
	defer db_close()
	// What 1.1 left behind: version numbers only.
	exec("CREATE TABLE schema_version (version INTEGER NOT NULL); INSERT INTO schema_version VALUES (1); CREATE TABLE a (x);")

	testing.expect_value(t, apply_migrations({{"0001_a.sql", "CREATE TABLE a (x);"}, {"0002_b.sql", "CREATE TABLE b (x);"}}), "")
	testing.expect_value(t, table_count("b"), 1)
	testing.expect_value(t, scalar_int("SELECT count(*) FROM schema_version WHERE name IS NOT NULL AND hash IS NOT NULL"), 2)
	// …and from then on it is checked like any other.
	testing.expect(t, apply_migrations({{"0001_x.sql", "CREATE TABLE a (x);"}}) != "")
}

@(private = "file")
table_count :: proc(name: string) -> int {
	return scalar_int(csql(fmt.tprintf("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='%s'", name)))
}
