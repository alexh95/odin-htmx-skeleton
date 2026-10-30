package dbview_models

// ---- dbview: the types and the store contract ----------------------------------------------
//
// PLAN §15.4. An admin's own SQL against the database, read only. SQLite only (D18): a memory
// build has no SQL to run.

import "core:time"

import "../../../platform/store"

Error :: store.Error

Result :: struct {
	columns: []string,
	rows:    [][]string,
	cut:     bool, // there were more rows than MAX_ROWS
	ms:      f64,
}

// On a query-pool thread (store_sqlite.query): the result's strings in `allocator`'s keeping;
// `problem` is why it didn't run, or ran only so far, in words for the admin.
Store_Query :: proc(sql: string, max_rows, max_cell: int, budget: time.Duration, allocator := context.allocator) -> (Result, string)
