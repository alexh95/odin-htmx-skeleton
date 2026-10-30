package accounts_store_sqlite

// ---- accounts in SQLite -------------------------------------------------------------------
//
// Reads on the loop's reader, their strings cloned into the request arena; every write is an
// op through the writer task. A sign-in's session row and the clearing of the user's failures
// commit together, in one op.

import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/accounts/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_accounts.sql", #load("migrations/0001_accounts.sql", string)},
}

@(private) USER_COLS :: "id, username, display, role, pw_hash, disabled_at, failed_logins, backoff_until"
@(private) SQL_BY_NAME :: "SELECT " + USER_COLS + " FROM users WHERE username = ?"
@(private) SQL_BY_ID :: "SELECT " + USER_COLS + " FROM users WHERE id = ?"
@(private) SQL_SESSION :: "SELECT user_id, created_at, last_seen, expires_at, step_up_at FROM sessions WHERE token_hash = ?"
@(private) SQL_ADMINS :: "SELECT count(*) FROM users WHERE role = 3 AND disabled_at = 0"
@(private) SQL_CREATE :: "INSERT INTO users(username, display, pw_hash, role, created_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_FAILED :: "UPDATE users SET failed_logins = failed_logins + 1, backoff_until = ? WHERE id = ?"
@(private) SQL_CLEAR :: "UPDATE users SET failed_logins = 0, backoff_until = 0 WHERE id = ?"
@(private) SQL_OPEN :: "INSERT INTO sessions(token_hash, user_id, created_at, last_seen, expires_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_TOUCH :: "UPDATE sessions SET last_seen = ? WHERE token_hash = ?"
@(private) SQL_CLOSE :: "DELETE FROM sessions WHERE token_hash = ?"

user_by_name :: proc(username: string) -> (m.User, m.Error) {
	q := db.read(SQL_BY_NAME)
	defer db.reset(q)
	db.bind_text(q, 1, username)
	return one_user(q)
}

user_by_id :: proc(id: i64) -> (m.User, m.Error) {
	q := db.read(SQL_BY_ID)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	return one_user(q)
}

@(private)
one_user :: proc(q: db.Stmt) -> (u: m.User, err: m.Error) {
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	role, ok := store.enum_from_int(m.Role, db.column_int(q, 3))
	if !ok { return {}, .Failed }
	return m.User {
		id = db.column_id(q, 0),
		username = db.clone_col(q, 1),
		display = db.clone_col(q, 2),
		role = role,
		pw_hash = db.clone_col(q, 4),
		disabled_at = db.column_id(q, 5),
		failed_logins = db.column_int(q, 6),
		backoff_until = db.column_id(q, 7),
	}, .None
}

session :: proc(token_hash: string) -> (s: m.Session, err: m.Error) {
	q := db.read(SQL_SESSION)
	defer db.reset(q)
	db.bind_text(q, 1, token_hash)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return m.Session {
		user_id = db.column_id(q, 0),
		created_at = db.column_id(q, 1),
		last_seen = db.column_id(q, 2),
		expires_at = db.column_id(q, 3),
		step_up_at = db.column_id(q, 4),
	}, .None
}

count_admins :: proc() -> (n: int, err: m.Error) {
	q := db.read(SQL_ADMINS)
	defer db.reset(q)
	if db.next_row(q, &err) { n = db.column_int(q, 0) }
	return
}

create_user :: proc(op: ^m.Create_User) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Create_User)(o)
		st := db.writer_stmt(SQL_CREATE)
		defer db.reset(st)
		db.bind_text(st, 1, op.username)
		db.bind_text(st, 2, op.display)
		db.bind_text(st, 3, op.pw_hash)
		db.bind_int(st, 4, int(op.role))
		db.bind_id(st, 5, now_ms())
		if o.err = db.step_done(st); o.err == .None { op.result = db.last_insert_id() }
	}
	return db.write(op)
}

login_failed :: proc(op: ^m.Login_Failed) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Login_Failed)(o)
		st := db.writer_stmt(SQL_FAILED)
		defer db.reset(st)
		db.bind_id(st, 1, op.backoff_until)
		db.bind_id(st, 2, op.user_id)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

open_session :: proc(op: ^m.Open_Session) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Open_Session)(o)
		st := db.writer_stmt(SQL_OPEN)
		db.bind_text(st, 1, op.token_hash)
		db.bind_id(st, 2, op.user_id)
		db.bind_id(st, 3, op.now)
		db.bind_id(st, 4, op.now)
		db.bind_id(st, 5, op.expires_at)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		cl := db.writer_stmt(SQL_CLEAR)
		defer db.reset(cl)
		db.bind_id(cl, 1, op.user_id)
		o.err = db.step_done(cl)
	}
	return db.write(op)
}

touch_session :: proc(op: ^m.Touch_Session) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Touch_Session)(o)
		st := db.writer_stmt(SQL_TOUCH)
		defer db.reset(st)
		db.bind_id(st, 1, op.now)
		db.bind_text(st, 2, op.token_hash)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

close_session :: proc(op: ^m.Close_Session) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Close_Session)(o)
		st := db.writer_stmt(SQL_CLOSE)
		defer db.reset(st)
		db.bind_text(st, 1, op.token_hash)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

@(private)
now_ms :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1e6 }
