package dbview_store_sqlite

// ---- dbview in SQLite --------------------------------------------------------------------------
//
// platform/store/sqlite's `adhoc`: the query-pool thread's own read-only reader, one statement
// SQLite calls read-only, ATTACH refused, a time budget. Nothing here writes or takes the
// writer's lock.

import "base:runtime"
import "core:time"

import db "../../../platform/store/sqlite"
import m "../../../features/dbview/models"

IMPL :: "sqlite"

query :: proc(sql: string, max_rows, max_cell: int, budget: time.Duration, allocator: runtime.Allocator = context.allocator) -> (m.Result, string) {
	r, problem := db.adhoc(sql, max_rows, max_cell, budget, allocator)
	return m.Result{r.columns, r.rows, r.cut, r.ms}, problem
}
