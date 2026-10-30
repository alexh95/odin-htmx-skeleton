package accounts_store_sqlite

// ---- accounts in SQLite -------------------------------------------------------------------
//
// Reads on the loop's reader, their strings cloned into the request arena; every write is an
// op through the writer task but the boot's first admin. A sign-in's session row, the session
// it replaces, the user's dead sessions and the clearing of their failures commit together.

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
@(private) SESSION_COLS :: "token_hash, user_id, created_at, last_seen, expires_at, step_up_at"
@(private) SQL_SESSION :: "SELECT " + SESSION_COLS + " FROM sessions WHERE token_hash = ?"
@(private) SQL_SESSIONS_OF :: "SELECT " + SESSION_COLS + " FROM sessions WHERE user_id = ? ORDER BY last_seen DESC LIMIT 100"
@(private) SQL_ADMINS :: "SELECT count(*) FROM users WHERE role = 3 AND disabled_at = 0"
@(private) SQL_CREATE :: "INSERT INTO users(username, display, pw_hash, role, created_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_FAILED :: "UPDATE users SET failed_logins = failed_logins + 1, backoff_until = ? WHERE id = ?"
@(private) SQL_CLEAR :: "UPDATE users SET failed_logins = 0, backoff_until = 0 WHERE id = ?"
@(private) SQL_OPEN :: "INSERT INTO sessions(token_hash, user_id, created_at, last_seen, expires_at, step_up_at) VALUES(?, ?, ?, ?, ?, ?)"
@(private) SQL_SWEEP :: "DELETE FROM sessions WHERE user_id = ? AND (expires_at <= ? OR last_seen < ?)"
@(private) SQL_TOUCH :: "UPDATE sessions SET last_seen = ? WHERE token_hash = ?"
@(private) SQL_CLOSE :: "DELETE FROM sessions WHERE token_hash = ? AND user_id = ?"
@(private) SQL_CLOSE_ANY :: "DELETE FROM sessions WHERE token_hash = ?" // the cookie a sign-in replaces, whoever's

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
	return one_session(q), .None
}

sessions_of :: proc(user_id: i64, into: ^[dynamic]m.Session) -> (err: m.Error) {
	q := db.read(SQL_SESSIONS_OF)
	defer db.reset(q)
	db.bind_id(q, 1, user_id)
	for db.next_row(q, &err) { append(into, one_session(q)) }
	return
}

@(private)
one_session :: proc(q: db.Stmt) -> m.Session {
	return m.Session {
		token_hash = db.clone_col(q, 0),
		user_id = db.column_id(q, 1),
		created_at = db.column_id(q, 2),
		last_seen = db.column_id(q, 3),
		expires_at = db.column_id(q, 4),
		step_up_at = db.column_id(q, 5),
	}
}

count_admins :: proc() -> (n: int, err: m.Error) {
	q := db.read(SQL_ADMINS)
	defer db.reset(q)
	if db.next_row(q, &err) { n = db.column_int(q, 0) }
	return
}

// write_now takes no data, so the boot's one write reads it from here.
@(private = "file")
boot: struct {
	username, pw_hash: string,
	created:           bool,
}

bootstrap_admin :: proc(username, pw_hash: string) -> (created: bool, err: m.Error) {
	boot.username, boot.pw_hash, boot.created = username, pw_hash, false
	ok := db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_ADMINS)
		e: m.Error
		n := db.column_int(q, 0) if db.next_row(q, &e) else -1
		db.reset(q)
		if n != 0 { return n > 0 }
		st := db.writer_stmt(SQL_CREATE)
		defer db.reset(st)
		db.bind_text(st, 1, boot.username)
		db.bind_text(st, 2, boot.username)
		db.bind_text(st, 3, boot.pw_hash)
		db.bind_int(st, 4, int(m.Role.Admin))
		db.bind_id(st, 5, now_ms())
		boot.created = db.step_done(st) == .None
		return boot.created
	})
	return boot.created, .None if ok else .Failed
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
		sw := db.writer_stmt(SQL_SWEEP)
		db.bind_id(sw, 1, op.user_id)
		db.bind_id(sw, 2, op.now)
		db.bind_id(sw, 3, op.idle_before)
		o.err = db.step_done(sw)
		db.reset(sw)
		if o.err != .None { return }
		if op.old_hash != "" {
			old := db.writer_stmt(SQL_CLOSE_ANY)
			db.bind_text(old, 1, op.old_hash)
			o.err = db.step_done(old)
			db.reset(old)
			if o.err != .None { return }
		}
		st := db.writer_stmt(SQL_OPEN)
		db.bind_text(st, 1, op.token_hash)
		db.bind_id(st, 2, op.user_id)
		db.bind_id(st, 3, op.now)
		db.bind_id(st, 4, op.now)
		db.bind_id(st, 5, op.expires_at)
		db.bind_id(st, 6, op.now)
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
		db.bind_id(st, 2, op.user_id)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

@(private)
now_ms :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1e6 }
