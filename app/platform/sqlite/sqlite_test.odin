package sqlite

import "core:c"
import "core:testing"

import "../sys"

@(private = "file") seen_inside: int

@(test)
in_sqlite_is_up_exactly_while_sqlite_runs :: proc(t: ^testing.T) {
	db, rc := open(":memory:", OPEN_READWRITE | OPEN_CREATE)
	testing.expect_value(t, rc, OK)
	defer close(db)
	testing.expect_value(t, enable_qpsg(db), OK)

	// A function called from SQL sees the counter raised by the step that runs it.
	probe :: proc "c" (ctx: Context, argc: c.int, argv: [^]Value) {
		seen_inside = sys.counters.in_sqlite
		result_int(ctx, 7)
	}
	testing.expect_value(t, create_function(db, "probe", 0, probe), OK)
	testing.expect_value(t, exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT NOT NULL)"), OK)

	s, prc := prepare(db, "INSERT INTO t(s) VALUES (?)")
	testing.expect_value(t, prc, OK)
	bind_text(s, 1, "")
	testing.expect_value(t, step(s), DONE)
	finalize(s)

	q, _ := prepare(db, "SELECT probe(), s, typeof(s) FROM t")
	testing.expect_value(t, step(q), ROW)
	testing.expect_value(t, column_int(q, 0), 7)
	testing.expect_value(t, column_text(q, 2), "text") // "" binds as empty text, not NULL
	testing.expect_value(t, reset_all(db), 1)
	finalize(q)

	testing.expect_value(t, seen_inside, 1)
	testing.expect_value(t, sys.counters.in_sqlite, 0)
}
