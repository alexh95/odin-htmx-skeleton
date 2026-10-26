package notes_storetest

// ---- the notes store contract, run against both families (D37) --------------------------
//
// One test binary imports both stores (their package names are unique, LC §3)
// and holds each to the same behaviour: the seed goes into an empty store only,
// recent lists newest first up to its limit, and an add answers its stored note
// through the caller's continuation on the loop that asked.

import "base:runtime"
import "core:nbio"
import "core:strings"
import "core:testing"
import "core:time"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import mem "../../../stores/memory/notes"
import sql "../../../stores/sqlite/notes"

@(private = "file")
Family :: struct {
	name:   string,
	recent: m.Store_Recent,
	add:    m.Store_Add,
	seed:   m.Store_Seed,
}

@(private = "file")
Probe :: struct {
	using add: m.Add,
	got:       ^[dynamic]m.Note,
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	f.seed()
	f.seed() // into an empty store only: twice is once
	list := make([dynamic]m.Note, context.temp_allocator)
	testing.expect_value(t, f.recent(10, &list), m.Error.None)
	testing.expectf(t, len(list) == 3, "%s: %d seeded notes", f.name, len(list))
	if len(list) == 3 {
		testing.expectf(t, strings.has_prefix(list[0].body, "Welcome"), "%s: newest first, got %q", f.name, list[0].body)
		testing.expect(t, list[0].id > list[1].id && list[1].id > list[2].id)
	}

	got := make([dynamic]m.Note)
	defer delete(got)
	for body in ([]string{"one", "two", "a third, with ünïcode"}) {
		op := store.new_op(Probe, 2 * len(body))
		op.body = strings.clone(body, store.op_allocator(op))
		op.got = &got
		op.done = proc(o: ^store.Op) {
			p := (^Probe)(o)
			assert(o.err == .None)
			n := p.result
			n.body = strings.clone(n.body)
			append(p.got, n)
			store.free_op(o)
		}
		testing.expectf(t, f.add(op), "%s: add accepted", f.name)
	}
	deadline := time.tick_now()
	for len(got) < 3 && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, len(got) == 3, "%s: %d adds answered", f.name, len(got))
	for n in got { delete(n.body) }

	clear(&list)
	f.recent(2, &list)
	testing.expectf(t, len(list) == 2 && list[0].body == "a third, with ünïcode" && list[1].body == "two", "%s: recent(2) = %v", f.name, list[:])
}

// One test, in order: the stores are process-wide.
@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	conforms(t, {"memory", mem.recent, mem.add, mem.seed})

	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("notes", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.recent, sql.add, sql.seed})
}
