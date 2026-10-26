package store

// ---- platform/store: what every store shares (L2) --------------------------
//
// Both families import it: the SQLite stores (app/stores/sqlite/<f>/) and the
// memory stores (app/stores/memory/<f>/). Each feature's store contract, its
// proc types, lives in the feature's models package (PLAN §6.4); this package
// holds only the vocabulary they all use.

import "base:intrinsics"

// What a store call fails with, a value the layers above branch on. The
// store's own message goes to the log, never to the client.
Error :: enum u8 {
	None,
	Not_Found,  // no row with that id
	Constraint, // the row broke a NOT NULL, UNIQUE, CHECK or FOREIGN KEY rule
	Busy,       // a queue is full (the writer task, the query pool): answer 503
	Failed,     // anything else: I/O, a lock held past busy_timeout, a full disk
}

// One migration of one feature's SQLite store: `MIGRATIONS := [?]store.Migration{
// {1, "0001_init.sql", #load("migrations/0001_init.sql", string)}, …}`, a package
// variable (a slice literal inside a proc would point into its frame, 09 §4.4).
// Applied migrations are keyed (feature, seq, name, sha256) and never change.
Migration :: struct {
	seq:  int,
	name: string,
	sql:  string,
}

// An enum read from a column or a form: an out-of-range value is an error, never
// an index (02 F3: an unchecked enum read from SQLite indexed a label table out
// of bounds). `ok` is false for anything not a member.
enum_from_int :: proc($E: typeid, v: int) -> (e: E, ok: bool) where intrinsics.type_is_enum(E) {
	for m in E {
		if int(m) == v { return m, true }
	}
	return {}, false
}

// One hit of a global search (the find feature at M8): each source domain fills
// these, and one list never mixes FTS5 and contains_ci hits (PLAN §11.8).
Search_Hit :: struct {
	source:  string, // "chat", "wiki" …: the Find_Source's name
	title:   string,
	snippet: string, // escaped, with <mark> around the hits
	href:    string,
	at:      i64,    // unix seconds, for the order across sources
}

// A domain's search, mounted in the profile's FIND_SOURCES table.
Find_Source :: struct {
	name:   string,
	search: proc(q: string, limit: int, out: ^[dynamic]Search_Hit) -> Error,
}
