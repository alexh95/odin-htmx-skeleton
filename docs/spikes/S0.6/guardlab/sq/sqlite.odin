package sq

// The few SQLite calls guardlab needs, each wrapped so the guard's in_sqlite counter is up while
// SQLite's C code runs (PLAN §10.2 rule 2). The prototype of `platform/sqlite`'s discipline.

import "core:c"

import "../guard"

when ODIN_OS == .Windows {
	foreign import lib "../../../../../app/vendor/sqlite/sqlite3.lib"
} else {
	foreign import lib {
		"../../../../../app/vendor/sqlite/sqlite3.a",
		"system:pthread",
		"system:dl",
	}
}

DB :: distinct rawptr
Stmt :: distinct rawptr
Context :: distinct rawptr
Value :: distinct rawptr

OK :: 0
ROW :: 100
DONE :: 101

OPEN_READONLY :: 0x00000001
OPEN_READWRITE :: 0x00000002
OPEN_CREATE :: 0x00000004
OPEN_NOMUTEX :: 0x00008000
UTF8 :: 1

Scalar_Func :: #type proc "c" (ctx: Context, argc: c.int, argv: [^]Value)

@(default_calling_convention = "c", link_prefix = "sqlite3_")
foreign lib {
	@(link_name = "sqlite3_open_v2") _open_v2 :: proc(filename: cstring, ppDb: ^DB, flags: c.int, zVfs: cstring) -> c.int ---
	@(link_name = "sqlite3_exec") _exec :: proc(db: DB, sql: cstring, cb: rawptr, arg: rawptr, errmsg: ^cstring) -> c.int ---
	@(link_name = "sqlite3_prepare_v2") _prepare_v2 :: proc(db: DB, sql: cstring, nByte: c.int, ppStmt: ^Stmt, pzTail: ^cstring) -> c.int ---
	@(link_name = "sqlite3_step") _step :: proc(stmt: Stmt) -> c.int ---
	@(link_name = "sqlite3_reset") _reset :: proc(stmt: Stmt) -> c.int ---
	@(link_name = "sqlite3_bind_text") _bind_text :: proc(stmt: Stmt, idx: c.int, text: [^]u8, nByte: c.int, destructor: rawptr) -> c.int ---
	@(link_name = "sqlite3_column_int64") _column_int64 :: proc(stmt: Stmt, col: c.int) -> i64 ---
	@(link_name = "sqlite3_next_stmt") _next_stmt :: proc(db: DB, stmt: Stmt) -> Stmt ---
	@(link_name = "sqlite3_errmsg") _errmsg :: proc(db: DB) -> cstring ---
	@(link_name = "sqlite3_create_function_v2") _create_function_v2 :: proc(db: DB, name: cstring, nargs: c.int, flags: c.int, app: rawptr, xfunc: Scalar_Func, xstep: rawptr, xfinal: rawptr, destroy: rawptr) -> c.int ---
	@(link_name = "sqlite3_result_int") result_int :: proc(ctx: Context, v: c.int) ---
}

TRANSIENT := rawptr(~uintptr(0))

open :: proc(path: cstring, flags: c.int) -> (db: DB, rc: c.int) {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	rc = _open_v2(path, &db, flags | OPEN_NOMUTEX, nil)
	return
}

exec :: proc(db: DB, sql: cstring) -> c.int {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _exec(db, sql, nil, nil, nil)
}

prepare :: proc(db: DB, sql: cstring) -> (s: Stmt, rc: c.int) {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	rc = _prepare_v2(db, sql, -1, &s, nil)
	return
}

step :: proc(s: Stmt) -> c.int {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _step(s)
}

reset :: proc(s: Stmt) -> c.int {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _reset(s)
}

bind_text :: proc(s: Stmt, idx: c.int, text: string) -> c.int {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _bind_text(s, idx, raw_data(text), c.int(len(text)), TRANSIENT)
}

column_int64 :: proc(s: Stmt, col: c.int) -> i64 {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _column_int64(s, col)
}

// Resets every statement of the connection (the pulled reset after a pure recovery).
reset_all :: proc(db: DB) -> (n: int) {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	for s := _next_stmt(db, nil); s != nil; s = _next_stmt(db, s) {
		_reset(s)
		n += 1
	}
	return
}

errmsg :: proc(db: DB) -> cstring {
	return _errmsg(db)
}

create_function :: proc(db: DB, name: cstring, f: Scalar_Func) -> c.int {
	guard.sqlite_enter(); defer guard.sqlite_leave()
	return _create_function_v2(db, name, 0, UTF8, nil, f, nil, nil, nil)
}
