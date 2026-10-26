package guard

import "base:runtime"
import "core:testing"

import "../obs"
import "../sys"

@(private = "file")
seen: struct {
	n:     int,
	last:  Crash,
}

@(private = "file")
record :: proc(c: ^Crash) {
	seen.n += 1
	seen.last = c^
}

@(private = "file")
boom :: proc(a, b: rawptr) {
	panic("boom")
}

@(private = "file")
out_of_bounds :: proc(a, b: rawptr) {
	xs := []int{1, 2, 3}
	i := (^int)(a)^
	_ = xs[i]
}

// One test, in order: the trap handlers and the burst window are process-wide.
@(test)
classify_crashes :: proc(t: ^testing.T) {
	// Boot-time registrations live as long as the process, as they do in main.
	context.allocator = runtime.heap_allocator()
	obs.init(.Error)
	install(record, burst_limit = 3)

	testing.expect(t, call(proc(_: rawptr) {}, nil), "a callback that returns")

	// Pure: nothing shared was touched.
	testing.expect(t, !invoke(boom, nil, nil))
	testing.expect_value(t, seen.last.dirty, false)
	testing.expect_value(t, seen.last.msg, "boom")
	testing.expect_value(t, recoveries(), 1)

	ten := 10
	testing.expect(t, !invoke(out_of_bounds, &ten, nil), "a bounds trap is caught")
	testing.expect_value(t, seen.last.dirty, false)

	// Dirty: a lock held, an op posted, inside SQLite.
	m: Mutex
	testing.expect(t, !invoke(proc(a, _: rawptr) { lock((^Mutex)(a)); panic("with the lock") }, &m, nil))
	testing.expect_value(t, seen.last.dirty, true)
	testing.expect_value(t, seen.last.why, "lock held")
	sys.counters = {}
	unlock(&m)
	sys.counters = {}

	testing.expect(t, !invoke(proc(_, _: rawptr) { posted(); panic("after posting") }, nil, nil))
	testing.expect_value(t, seen.last.why, "async op posted")
	sys.counters = {}

	testing.expect(t, !invoke(proc(_, _: rawptr) { sys.counters.in_sqlite += 1; panic("in sqlite") }, nil, nil))
	testing.expect_value(t, seen.last.why, "inside sqlite")
	sys.counters = {}

	// Pure recoveries past the burst limit count as dirty: two so far, the limit is 3.
	testing.expect(t, !invoke(boom, nil, nil))
	testing.expect_value(t, seen.last.dirty, false)
	testing.expect(t, !invoke(boom, nil, nil))
	testing.expect_value(t, seen.last.dirty, true)
	testing.expect_value(t, seen.last.why, "too many recoveries")
	testing.expect_value(t, recoveries(), 3)

	// Counters are restored after a pure crash, so the thread goes on clean.
	testing.expect_value(t, sys.counters, sys.Counters{})
	testing.expect_value(t, seen.n, 7)
}
