package accounts_storetest

// ---- the accounts store contract (SQLite: accounts have no memory member, D18) ------------
//
// A user is found by name whatever its case, a second one of the same name is refused, a
// failed login counts and backs off, a sign-in opens the session (a step-up), clears the
// failures, closes the session it rotates and sweeps the dead ones, a session is touched and
// closed by its token's hash and only by its user, and the boot's admin is made only once.

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

	made, berr := sql.bootstrap_admin("root", "$argon2id$v=19$m=19456,t=2,p=1$x$y")
	testing.expect(t, berr == .None && made)
	made, berr = sql.bootstrap_admin("root2", "$argon2id$v=19$m=19456,t=2,p=1$x$y")
	testing.expect(t, berr == .None && !made) // an enabled admin exists
	root, rerr := sql.user_by_name("root")
	testing.expect(t, rerr == .None && root.role == .Admin)

	testing.expect_value(t, create(t, "Alex", .Admin), store.Error.None)
	testing.expect_value(t, create(t, "alex", .User), store.Error.Constraint) // unique whatever the case
	testing.expect_value(t, create(t, "sam", .User), store.Error.None)

	u, err := sql.user_by_name("ALEX")
	testing.expect_value(t, err, store.Error.None)
	testing.expect(t, u.username == "Alex" && u.role == .Admin && u.failed_logins == 0)
	_, err = sql.user_by_name("nobody")
	testing.expect_value(t, err, store.Error.Not_Found)
	n, _ := sql.count_admins()
	testing.expect_value(t, n, 2) // root and Alex

	failed := store.new_op(m.Login_Failed, 0)
	failed.user_id, failed.backoff_until, failed.done = u.id, 5000, DONE
	testing.expect(t, sql.login_failed(failed))
	settle(t, answered + 1)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 1 && u.backoff_until == 5000)

	OLD :: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
	DEAD :: "1111111111111111111111111111111111111111111111111111111111111111"
	HASH :: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	open_at(t, OLD, "", u.id, 500, 9000, 0)
	open_at(t, DEAD, "", u.id, 100, 9000, 0)
	open_at(t, HASH, OLD, u.id, 1000, 9000, 200) // rotates OLD; DEAD, last seen at 100, is swept
	s, serr := sql.session(HASH)
	testing.expect_value(t, serr, store.Error.None)
	testing.expect(t, s.user_id == u.id && s.created_at == 1000 && s.last_seen == 1000 && s.expires_at == 9000 && s.step_up_at == 1000)
	_, serr = sql.session(OLD)
	testing.expect_value(t, serr, store.Error.Not_Found)
	_, serr = sql.session(DEAD)
	testing.expect_value(t, serr, store.Error.Not_Found)
	all := make([dynamic]m.Session, context.temp_allocator)
	testing.expect_value(t, sql.sessions_of(u.id, &all), store.Error.None)
	testing.expect(t, len(all) == 1 && all[0].token_hash == HASH)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 0 && u.backoff_until == 0) // a sign-in clears them

	touch := store.new_op(m.Touch_Session, len(HASH))
	touch.token_hash = strings.clone(HASH, store.op_allocator(touch))
	touch.now, touch.done = 2000, DONE
	testing.expect(t, sql.touch_session(touch))
	settle(t, answered + 1)
	s, _ = sql.session(HASH)
	testing.expect_value(t, s.last_seen, 2000)

	sam, _ := sql.user_by_name("sam")
	close_as(t, HASH, sam.id) // another user's revoke closes nothing
	_, serr = sql.session(HASH)
	testing.expect_value(t, serr, store.Error.None)
	close_as(t, HASH, u.id)
	_, serr = sql.session(HASH)
	testing.expect_value(t, serr, store.Error.Not_Found)

}

@(private = "file")
open_at :: proc(t: ^testing.T, hash, old: string, user: i64, now, expires, idle_before: i64) {
	op := store.new_op(m.Open_Session, len(hash) + len(old))
	a := store.op_allocator(op)
	op.token_hash, op.old_hash = strings.clone(hash, a), strings.clone(old, a)
	op.user_id, op.now, op.expires_at, op.idle_before, op.done = user, now, expires, idle_before, DONE
	before := answered
	testing.expect(t, sql.open_session(op))
	settle(t, before + 1)
	testing.expect_value(t, last_err, store.Error.None)
}

@(private = "file")
close_as :: proc(t: ^testing.T, hash: string, user: i64) {
	op := store.new_op(m.Close_Session, len(hash))
	op.token_hash = strings.clone(hash, store.op_allocator(op))
	op.user_id, op.done = user, DONE
	before := answered
	testing.expect(t, sql.close_session(op))
	settle(t, before + 1)
}
