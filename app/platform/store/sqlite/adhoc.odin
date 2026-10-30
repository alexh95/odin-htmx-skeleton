package store_sqlite

// ---- an admin's own SQL, read only (PLAN §15.4: dbview) --------------------------------------
//
// On a query-pool thread, on that thread's reader: a connection opened read-only, so nothing it
// runs takes the writer's lock or writes, whatever the text says. One statement, which SQLite
// itself must call read-only (`stmt_readonly`), with ATTACH refused (`LIMIT_ATTACHED` 0: an
// attach is read-only to SQLite, and would open any file the process can read); a progress
// handler interrupts it past `budget`, since a long read's snapshot pins the WAL (12 §3.3).
// Rows and cells are capped; values are text as SQLite gives them, a blob as its size.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "../../sqlite"
import "../../sys"

Adhoc :: struct {
	columns: []string,
	rows:    [][]string,
	cut:     bool, // more rows than max_rows
	ms:      f64,
}

@(private, thread_local)
adhoc_deadline: i64 // mono ns: the progress handler interrupts past it

// From a query-pool task's `run`. The result's strings are in `allocator`; `problem` is the
// refusal or SQLite's error, for the admin.
adhoc :: proc(text: string, max_rows, max_cell: int, budget: time.Duration, allocator: runtime.Allocator) -> (out: Adhoc, problem: string) {
	if db.mode == .Single { return {}, "this build serves :memory: on one connection: dbview needs a reader of its own" }
	r := reader()
	if r == nil { return {}, "the store has no reader on this thread" }
	conn := r.db
	sqlite.limit(conn, sqlite.LIMIT_ATTACHED, 0)
	st, rc, rest := sqlite.prepare_first(conn, text)
	if rc != sqlite.OK { return {}, strings.clone(sqlite.errmsg(conn), allocator) }
	if st == nil { return {}, "there is no statement there" }
	defer sqlite.finalize(st)
	if strings.trim_space(strings.trim_left(strings.trim_space(rest), ";")) != "" { return {}, "one statement at a time" }
	if !sqlite.stmt_readonly(st) { return {}, "only reads: that statement would change something" }

	t0 := sys.mono_ns()
	adhoc_deadline = t0 + i64(budget)
	sqlite.progress_handler(conn, 1000, proc "c" (_: rawptr) -> c.int {
		return 1 if sys.mono_ns() > adhoc_deadline else 0
	}, nil)
	defer sqlite.progress_handler(conn, 0, nil, nil)

	n := sqlite.column_count(st)
	cols := make([]string, n, allocator)
	for i in 0 ..< n { cols[i] = strings.clone(sqlite.column_name(st, i), allocator) }
	rows := make([dynamic][]string, allocator)
	for {
		rc = sqlite.step(st)
		if rc != sqlite.ROW { break }
		if len(rows) == max_rows {
			out.cut = true
			break
		}
		row := make([]string, n, allocator)
		for i in 0 ..< n { row[i] = cell(st, i, max_cell, allocator) }
		append(&rows, row)
	}
	out.columns, out.rows, out.ms = cols, rows[:], f64(sys.mono_ns() - t0) / 1e6
	switch {
	case rc == sqlite.ROW || rc == sqlite.DONE:
	case rc == sqlite.INTERRUPT: problem = fmt.aprintf("stopped past the %d s budget, with %d rows so far", i64(budget / time.Second), len(rows), allocator = allocator)
	case:                        problem = strings.clone(sqlite.errmsg(conn), allocator)
	}
	return
}

@(private)
cell :: proc(st: Stmt, col, max_cell: int, allocator: runtime.Allocator) -> string {
	switch sqlite.column_type(st, col) {
	case sqlite.NULL: return "NULL"
	case sqlite.BLOB: return fmt.aprintf("<%d bytes>", sqlite.column_bytes(st, col), allocator = allocator)
	}
	s := sqlite.column_text(st, col)
	if utf8.rune_count_in_string(s) <= max_cell { return strings.clone(s, allocator) }
	n, i := 0, 0
	for _, at in s {
		if n == max_cell { i = at; break }
		n += 1
	}
	return strings.concatenate({s[:i], "…"}, allocator)
}
