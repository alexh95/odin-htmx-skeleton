package sqlite

// ---- SQLite amalgamation binding ----------------------------------------
//
// ~20 foreign decls for the symbols the repository uses. The amalgamation is
// fetched + compiled by prepare.* into app/vendor/sqlite/ (sqlite3.lib on
// Windows, sqlite3.a on unix); the link block below points there. This is the
// only place the C ABI is crossed.
//
// There is no `vendor:sqlite3` collection in Odin (the request to add one,
// odin-lang/Odin #3736, was closed "won't implement"), so we bind the
// amalgamation directly — also the most self-contained option, in keeping with
// the single-binary ethos.

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "../../vendor/sqlite/sqlite3.lib"
} else {
	foreign import lib {
		"../../vendor/sqlite/sqlite3.a",
		"system:pthread",
		"system:dl",
	}
}

// Opaque handles.
DB :: distinct rawptr
Stmt :: distinct rawptr

// Result codes. Extended codes keep the primary one in their low byte.
OK :: 0
CONSTRAINT :: 19
ROW :: 100
DONE :: 101

// column_type results.
INTEGER :: 1
FLOAT :: 2
TEXT :: 3
BLOB :: 4
NULL :: 5

// open_v2 flags.
OPEN_READWRITE :: 0x00000002
OPEN_CREATE :: 0x00000004

// SQLITE_TRANSIENT (-1): tell SQLite to copy the bound bytes, so a temp-arena
// string need not outlive the bind. (bind_text's destructor arg is pointer-sized;
// we only ever pass this sentinel, so it's typed rawptr to skip proc-type noise.)
TRANSIENT := rawptr(~uintptr(0))

@(default_calling_convention = "c", link_prefix = "sqlite3_")
foreign lib {
	open_v2 :: proc(filename: cstring, ppDb: ^DB, flags: c.int, zVfs: cstring) -> c.int ---
	exec :: proc(db: DB, sql: cstring, cb: rawptr, arg: rawptr, errmsg: ^cstring) -> c.int ---
	prepare_v2 :: proc(db: DB, sql: cstring, nByte: c.int, ppStmt: ^Stmt, pzTail: ^cstring) -> c.int ---
	bind_text :: proc(stmt: Stmt, idx: c.int, text: [^]u8, nByte: c.int, destructor: rawptr) -> c.int ---
	bind_int :: proc(stmt: Stmt, idx: c.int, val: c.int) -> c.int ---
	bind_int64 :: proc(stmt: Stmt, idx: c.int, val: i64) -> c.int ---
	bind_double :: proc(stmt: Stmt, idx: c.int, val: f64) -> c.int ---
	bind_null :: proc(stmt: Stmt, idx: c.int) -> c.int ---
	step :: proc(stmt: Stmt) -> c.int ---
	reset :: proc(stmt: Stmt) -> c.int ---
	column_int :: proc(stmt: Stmt, col: c.int) -> c.int ---
	column_int64 :: proc(stmt: Stmt, col: c.int) -> i64 ---
	column_double :: proc(stmt: Stmt, col: c.int) -> f64 ---
	column_type :: proc(stmt: Stmt, col: c.int) -> c.int --- // INTEGER … NULL; tells NULL from 0 / ""
	column_text :: proc(stmt: Stmt, col: c.int) -> cstring --- // NUL-terminated
	finalize :: proc(stmt: Stmt) -> c.int ---
	last_insert_rowid :: proc(db: DB) -> i64 ---
	changes :: proc(db: DB) -> c.int ---
	close :: proc(db: DB) -> c.int ---
	errmsg :: proc(db: DB) -> cstring ---
}
