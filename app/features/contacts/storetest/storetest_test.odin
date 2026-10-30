package contacts_storetest

// ---- the contacts store's demo reset (SQLite: contacts has no memory member) --------------
//
// A seed fills empty tables only; a reset empties both tables and seeds them again, in one
// transaction, whatever was added meanwhile: full's lab host starts over each night (X38).

import "base:runtime"
import "core:nbio"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/contacts"

@(test)
a_reset_puts_the_demo_rows_back :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("contacts", sql.MIGRATIONS[:])

	count :: proc() -> int {
		n, _ := sql.filter_count({status = -1}) // any status
		return n
	}
	sql.seed()
	seeded := count()
	testing.expect(t, seeded > 0)

	// Grown past the seed, as visitors would.
	testing.expect(t, db.write_now(proc() -> bool {
		st := db.writer_stmt("INSERT INTO contacts(name,email,role,status,score,notes,notify) VALUES('Visitor','v@example.dev',0,0,50,'',0)")
		defer db.reset(st)
		return db.step_done(st) == store.Error.None
	}))
	testing.expect_value(t, count(), seeded + 1)
	sql.seed()
	testing.expect_value(t, count(), seeded + 1) // a seed fills empty tables only

	testing.expect(t, sql.reset())
	testing.expect_value(t, count(), seeded)
	found := make([dynamic]m.Contact, context.temp_allocator)
	testing.expect_value(t, sql.match({q = "Visitor", status = -1}, 10, &found), store.Error.None)
	testing.expect_value(t, len(found), 0)
}
