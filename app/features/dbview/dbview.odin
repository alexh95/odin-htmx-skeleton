package dbview

// ---- dbview: the domain (PLAN §15.4, D36) ---------------------------------------------------
//
// An admin's own read-only SQL, for looking, never for changing: the text is checked here (a
// length cap), run by the store on the query pool, and capped there (MAX_ROWS, MAX_CELL, BUDGET).

import "base:runtime"
import "core:strings"
import "core:time"

import m "models"
import dbview_store "store:dbview"

MAX_SQL :: 4000 // bytes
MAX_ROWS :: 200
MAX_CELL :: 200 // characters
BUDGET :: 2 * time.Second

// The text to run, or why not.
check :: proc(raw: string) -> (sql, problem: string) {
	sql = strings.trim_space(raw)
	if sql == "" { return "", "Write a query." }
	if len(sql) > MAX_SQL { return "", "A query is at most 4000 bytes." }
	return sql, ""
}

// On a query-pool thread.
query :: proc(sql: string, allocator: runtime.Allocator) -> (m.Result, string) {
	return dbview_store.query(sql, MAX_ROWS, MAX_CELL, BUDGET, allocator)
}
