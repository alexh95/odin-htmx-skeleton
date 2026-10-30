package accounts_models

// ---- accounts: the types and the store contract ------------------------------------------
//
// Below the domain, the identity and the store (PLAN §5.1, §17.1). Accounts need SQLite (D18):
// the store is the SQLite family's alone. Times are unix ms. A session is stored by the SHA-256
// of its token, as 64 hex characters, never the token.

import "../../../platform/authz"
import "../../../platform/store"

User :: struct {
	id:            i64,
	username:      string, // unique, case-insensitive
	display:       string,
	role:          Role,
	pw_hash:       string, // a PHC string (platform/password)
	disabled_at:   i64,    // 0: enabled
	failed_logins: int,
	backoff_until: i64,    // no verify before this (exponential backoff, never a lockout)
}

Session :: struct {
	token_hash: string,
	user_id:    i64,
	created_at: i64,
	last_seen:  i64,
	expires_at: i64, // the absolute end (30 days); the idle end (14) is last_seen's
	step_up_at: i64, // the last password or TOTP check; 0: none since sign-in
}

Error :: store.Error

// The store reads a role through this: it imports no authz.
Role :: authz.Role

// Writes go through the writer task (store.Op): the caller's `done` runs once stored.
Create_User :: struct {
	using op: store.Op,
	username: string,
	display:  string,
	pw_hash:  string,
	role:     Role,
	result:   i64, // the new id
}

// A wrong password: one more failure, and no verify before `backoff_until`.
Login_Failed :: struct {
	using op:      store.Op,
	user_id:       i64,
	backoff_until: i64,
}

// A sign-in: the session row, the user's failures cleared, the session it replaces (the
// cookie the request carried, rotated) closed, and the user's dead sessions swept. A sign-in
// is a password check, so it counts as a step-up.
Open_Session :: struct {
	using op:    store.Op,
	token_hash:  string,
	old_hash:    string, // "" when the request carried none
	user_id:     i64,
	now:         i64,
	expires_at:  i64,
	idle_before: i64, // a session last seen before this is dead
}

Touch_Session :: struct {
	using op:   store.Op,
	token_hash: string,
	now:        i64,
}

// Sign-out, and a member's revoke of one of their own sessions: only the user's.
Close_Session :: struct {
	using op:   store.Op,
	token_hash: string,
	user_id:    i64,
}

Store_User_By_Name :: proc(username: string) -> (User, Error)
Store_User_By_Id :: proc(id: i64) -> (User, Error)
Store_Session :: proc(token_hash: string) -> (Session, Error)
Store_Sessions_Of :: proc(user_id: i64, into: ^[dynamic]Session) -> Error // newest first
Store_Count_Admins :: proc() -> (int, Error)
// At boot, before the loops: the first admin, when no enabled one exists.
Store_Bootstrap_Admin :: proc(username, pw_hash: string) -> (created: bool, err: Error)
Store_Create_User :: proc(op: ^Create_User) -> bool // false: the store is busy; `done` won't run
Store_Login_Failed :: proc(op: ^Login_Failed) -> bool
Store_Open_Session :: proc(op: ^Open_Session) -> bool
Store_Touch_Session :: proc(op: ^Touch_Session) -> bool
Store_Close_Session :: proc(op: ^Close_Session) -> bool
