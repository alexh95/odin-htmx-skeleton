package accounts_storetest

// ---- the accounts store contract (SQLite: accounts have no memory member, D18) ------------
//
// A user is found by name whatever its case, a second one of the same name is refused, a
// failed login counts and backs off, a sign-in opens the session and clears the failures,
// and a session is touched and closed by its token's hash.

import "base:runtime"
import "core:nbio"
import "core:strings"
import "core:testing"
import "core:time"

import "../../../platform/authz"
import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/accounts"

@(private = "file")
answered: int

@(private = "file")
last_err: store.Error

@(private = "file")
settle :: proc(t: ^testing.T, want: int) {
	deadline := time.tick_now()
	for answered < want && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, answered == want, "%d of %d writes answered", answered, want)
}

@(private = "file")
DONE :: proc(o: ^store.Op) {
	answered += 1
	last_err = o.err
	store.free_op(o)
}

@(private = "file")
create :: proc(t: ^testing.T, name: string, role: authz.Role) -> store.Error {
	op := store.new_op(m.Create_User, 3 * len(name) + 64)
	a := store.op_allocator(op)
	op.username = strings.clone(name, a)
	op.display = strings.clone(name, a)
	op.pw_hash = strings.clone("$argon2id$v=19$m=19456,t=2,p=1$x$y", a)
	op.role = role
	op.done = DONE
	before := answered
	testing.expect(t, sql.create_user(op))
	settle(t, before + 1)
	return last_err
}

@(test)
the_store_keeps_users_and_sessions :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("accounts", sql.MIGRATIONS[:])

	testing.expect_value(t, create(t, "Alex", .Admin), store.Error.None)
	testing.expect_value(t, create(t, "alex", .User), store.Error.Constraint) // unique whatever the case
	testing.expect_value(t, create(t, "sam", .User), store.Error.None)

	u, err := sql.user_by_name("ALEX")
	testing.expect_value(t, err, store.Error.None)
	testing.expect(t, u.username == "Alex" && u.role == .Admin && u.failed_logins == 0)
	_, err = sql.user_by_name("nobody")
	testing.expect_value(t, err, store.Error.Not_Found)
	n, _ := sql.count_admins()
	testing.expect_value(t, n, 1)

	failed := store.new_op(m.Login_Failed, 0)
	failed.user_id, failed.backoff_until, failed.done = u.id, 5000, DONE
	testing.expect(t, sql.login_failed(failed))
	settle(t, answered + 1)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 1 && u.backoff_until == 5000)

	HASH :: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	open := store.new_op(m.Open_Session, len(HASH))
	open.token_hash = strings.clone(HASH, store.op_allocator(open))
	open.user_id, open.now, open.expires_at, open.done = u.id, 1000, 9000, DONE
	testing.expect(t, sql.open_session(open))
	settle(t, answered + 1)
	s, serr := sql.session(HASH)
	testing.expect_value(t, serr, store.Error.None)
	testing.expect(t, s.user_id == u.id && s.created_at == 1000 && s.last_seen == 1000 && s.expires_at == 9000 && s.step_up_at == 0)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 0 && u.backoff_until == 0) // a sign-in clears them

	touch := store.new_op(m.Touch_Session, len(HASH))
	touch.token_hash = strings.clone(HASH, store.op_allocator(touch))
	touch.now, touch.done = 2000, DONE
	testing.expect(t, sql.touch_session(touch))
	settle(t, answered + 1)
	s, _ = sql.session(HASH)
	testing.expect_value(t, s.last_seen, 2000)

	close := store.new_op(m.Close_Session, len(HASH))
	close.token_hash = strings.clone(HASH, store.op_allocator(close))
	close.done = DONE
	testing.expect(t, sql.close_session(close))
	settle(t, answered + 1)
	_, serr = sql.session(HASH)
	testing.expect_value(t, serr, store.Error.Not_Found)
}
