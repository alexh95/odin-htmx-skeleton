package web

// ---- TEST_ROUTES: the crash drills (PLAN §19.1.10, D10) ---------------------------------
//
// Mounted on the main host by platform/app only in a -define:TEST_ROUTES=true
// build, never in a release one, whose /__test/* answers 404. Each kind is one
// class of crash, run inside the request:
//
//   panic, bounds, div, nil, stack   pure: 500, serving goes on, recoveries +1
//   lock, async                      dirty: a lock still held, an op posted; exit 70
//   hang                             the loop stops ticking (?s=15): the watchdog's exit 70
//   <registered>                     guard.register_drill's (store/sqlite's `sqlite`)
//
// /__test/shutdown starts the drain a signal would: Windows can't send a child
// SIGTERM, and the shutdown drill needs the same path on both OSes.

import "base:intrinsics"
import "core:nbio"
import "core:time"

import "../guard"

TEST_ROUTES :: guard.TEST_ROUTES

TEST_ROUTE_ROWS := [?]Route {
	{.Get, "/__test/crash/(%a+)", test_crash, .Public, {}, 0},
	{.Get, "/__test/shutdown", test_shutdown_route, .Public, {}, 0},
}

// Set by platform/app: what a signal does.
test_shutdown: proc()

// Runtime values, so the optimiser can't fold a crash away.
@(private = "file") sink: int
@(private = "file") idx := 7
@(private = "file") zero := 0
@(private = "file") drill_mu: guard.Mutex

@(private = "file")
recurse :: proc(n: int) -> int {
	buf: [256]byte
	buf[n % 256] = byte(n)
	if n > 100_000_000 { return int(buf[3]) }
	return recurse(n + 1) + int(buf[n % 7])
}

test_crash :: proc(req: ^Request, res: ^Response) {
	switch kind := req.url_params[0]; kind {
	case "panic":
		panic("drill: panic")
	case "bounds":
		a := [4]int{}
		sink = a[idx]
	case "div":
		sink = 10 / zero
	case "nil":
		p := (^int)(uintptr(zero))
		sink = intrinsics.volatile_load(p)
	case "stack":
		sink = recurse(0)
	case "lock":
		guard.lock(&drill_mu)
		defer guard.unlock(&drill_mu)
		if idx != 0 { panic("drill: a crash while a lock is held") }
	case "async":
		// An op posted before the crash would run later against abandoned state.
		nbio.timeout_poly(10 * time.Second, rawptr(nil), proc(_: ^nbio.Operation, _: rawptr) {})
		guard.posted()
		panic("drill: a crash after posting an op")
	case "hang":
		time.sleep(time.Duration(query_int(req, "s", 15)) * time.Second)
	case:
		for d in guard.drills {
			if d.kind == kind {
				d.run()
				respond_plain(res, "no crash")
				return
			}
		}
		not_found(req, res)
		return
	}
	respond_plain(res, "no crash")
}

@(private = "file")
test_shutdown_route :: proc(req: ^Request, res: ^Response) {
	respond_plain(res, "draining")
	if test_shutdown != nil { test_shutdown() }
}
