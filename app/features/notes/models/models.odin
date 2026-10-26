package notes_models

// ---- notes: the types and the store contract ------------------------------------------
//
// Below the domain, the views and both stores (PLAN §5.1): each store, in either
// family, checks its procs against the proc types here in its contract.odin.

import "../../../platform/store"

Note :: struct {
	id:   i64,
	body: string,
	at:   i64, // unix seconds, set when it is added
}

Error :: store.Error

// Adding a note is a write: the caller's `done` runs once it is stored (at once
// in the memory family, after the writer task's batch in SQLite). The op owns its
// body and its result (store.new_op).
Add :: struct {
	using op: store.Op,
	body:     string,
	result:   Note,
}

Store_Recent :: proc(limit: int, out: ^[dynamic]Note) -> Error
Store_Add :: proc(op: ^Add) -> bool // false: the store is busy; `done` won't run
Store_Seed :: proc()
