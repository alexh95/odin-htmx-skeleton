package jobs_storetest

// ---- the jobs store contract (SQLite and memory) ---------------------------------------------
//
// A save upserts by (boot, id); recent is newest first without the log, run has it; a queued or
// running row of another boot whose lease lapsed is failed as interrupted, and nothing else is;
// prune takes the rows that ended before the cut.

import "base:runtime"
import "core:nbio"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import mem "../../../stores/memory/jobs"
import sql "../../../stores/sqlite/jobs"

@(test)
runs_are_kept_failed_when_lapsed_and_pruned :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("jobs", sql.MIGRATIONS[:])

	OLD :: 1000 // an earlier boot
	NOW :: 2000 // this one
	rows := []m.Run_Row {
		{boot = OLD, id = 1, job = "store.backup", state = "running", queued_at = 10, started_at = 11, lease_until = 1500},
		{boot = OLD, id = 2, job = "store.backup", state = "queued", queued_at = 12, lease_until = 9000}, // lease still held
		{boot = OLD, id = 3, job = "store.backup", state = "done", queued_at = 13, started_at = 13, ended_at = 14, log = "ok\n"},
		{boot = NOW, id = 1, job = "store.backup", state = "running", queued_at = 2001, started_at = 2001, lease_until = 1}, // this boot's own
	}
	testing.expect_value(t, sql.save(rows), store.Error.None)
	rows[0].done, rows[0].total = 5, 10
	testing.expect_value(t, sql.save(rows[:1]), store.Error.None) // an upsert, not a second row

	n, err := sql.fail_lapsed(NOW, 3000)
	testing.expect(t, err == .None && n == 1)
	r, rerr := sql.run(OLD, 1)
	testing.expect(t, rerr == .None && r.state == "failed" && r.note == "interrupted by a restart" && r.ended_at == 3000 && r.done == 5)
	held, _ := sql.run(OLD, 2)
	testing.expect_value(t, held.state, "queued")
	mine, _ := sql.run(NOW, 1)
	testing.expect_value(t, mine.state, "running")

	recent := make([dynamic]m.Run_Row, context.temp_allocator)
	testing.expect_value(t, sql.recent(10, &recent), store.Error.None)
	testing.expect(t, len(recent) == 4 && recent[0].boot == NOW && recent[3].id == 1 && recent[1].log == "")
	done, _ := sql.run(OLD, 3)
	testing.expect_value(t, done.log, "ok\n")

	gone, _ := sql.prune(20)
	testing.expect_value(t, gone, 1) // the done one; the failed one ended at 3000
	_, nerr := sql.run(OLD, 3)
	testing.expect_value(t, nerr, store.Error.Not_Found)

	// The memory member: the same upsert and order, and no earlier boot to fail.
	testing.expect_value(t, mem.save(rows), store.Error.None)
	testing.expect_value(t, mem.save(rows[:1]), store.Error.None)
	got := make([dynamic]m.Run_Row, context.temp_allocator)
	testing.expect_value(t, mem.recent(10, &got), store.Error.None)
	testing.expect(t, len(got) == 4 && got[0].boot == NOW && got[3].done == 5)
	lapsed, _ := mem.fail_lapsed(NOW, 3000)
	testing.expect_value(t, lapsed, 0)
	pruned, _ := mem.prune(20)
	testing.expect_value(t, pruned, 1)
	free_all(context.temp_allocator)
}
