package guardlab

// The crash routes (what M1 puts behind -define:TEST_ROUTES; release images assert they answer
// 404). 13 pure kinds answer 500 and the server keeps serving; `lock`, `rwlock`, `async` and
// `sqlite` are dirty and exit 70; `iter` is a pure crash mid-iteration on the loop's reader, for
// the WAL check; `block` stalls the loop for the watchdog.

import "base:intrinsics"
import "core:nbio"
import "core:sync"
import "core:time"

import http "vendor_fork:odin-http"

import "guard"
import "sq"

@(private = "file") sink: int
@(private = "file") idx := 7
@(private = "file") zero := 0
@(private = "file") nilp: ^int
@(private = "file") E :: enum { A, B, C }
@(private = "file") NAMES := [E]string{ .A = "a", .B = "b", .C = "c" }
@(private = "file") bad_e := E(99)
@(private = "file") U :: union { int, string }
@(private = "file") u_val: U = 5
@(private = "file") rw: sync.RW_Mutex
@(private = "file") lock_mu: guard.Mutex

Crash_Kind :: struct {
	name:  string,
	f:     proc(),
	dirty: bool,
}

CRASH_KINDS := [?]Crash_Kind{
	{"assert", proc() { assert(idx == 0, "idx must be 0") }, false},
	{"panic", proc() { panic("explicit panic") }, false},
	{"ensure", proc() { ensure(idx == 0) }, false},
	{"bounds", proc() { a := [4]int{}; sink = a[idx] }, false},
	{"slice", proc() { a := []int{1, 2, 3}; s := a[1:idx]; sink = len(s) }, false},
	{"enum_index", proc() { sink = len(NAMES[bad_e]) }, false},
	{"type_assert", proc() { s := u_val.(string); sink = len(s) }, false},
	{"int_div_zero", proc() { sink = 10 / zero }, false},
	{"int_mod_zero", proc() { sink = 10 % zero }, false},
	{"nil_deref", proc() { sink = intrinsics.volatile_load(nilp) }, false},
	{"nil_write", proc() { p := nilp; p^ = 5; sink = p^ }, false},
	{"stack_overflow", proc() { sink = recurse(0) }, false},
	{"stack_overflow_again", proc() { sink = recurse(0) }, false},
	// Dirty: a lock still held after the jump would hang every bystander.
	{"lock", proc() {
		guard.lock(&lock_mu)
		defer guard.unlock(&lock_mu)
		if idx != 0 { panic("panic while holding a lock") }
	}, true},
	{"rwlock", proc() {
		// A plain RW_Mutex isn't counted (it isn't allowed at M1, `tools/check locks`); this one is
		// counted by hand, as guard.Mutex would.
		sync.rw_mutex_lock(&rw)
		tl_counted_lock()
		defer sync.rw_mutex_unlock(&rw)
		a := [4]int{}
		sink = a[idx]
	}, true},
}

@(private = "file")
tl_counted_lock :: proc() {
	m: guard.Mutex
	guard.lock(&m) // raises locks_held; never released: the jump skips the unlock
}

@(private = "file")
recurse :: proc(n: int) -> int {
	buf: [256]byte
	buf[n % 256] = byte(n)
	if n > 100_000_000 { return int(buf[3]) }
	return recurse(n + 1) + int(buf[n % 7])
}

crash_init :: proc() {
	// A runtime nil, so -o:speed can't fold the load away.
	nilp = (^int)(uintptr(len(NAMES) / 1000))
}

// GET /crash/<kind>
crash_route :: proc(req: ^http.Request, res: ^http.Response) {
	kind := req.url_params[0]
	for k in CRASH_KINDS {
		if k.name == kind {
			k.f()
			http.respond_plain(res, "no crash")
			return
		}
	}
	switch kind {
	case "async":
		// An op posted before the crash would run later against abandoned state: dirty.
		nbio.timeout_poly(10 * time.Second, res, proc(_: ^nbio.Operation, res: ^http.Response) {})
		guard.posted()
		panic("panic after posting an op")
	case "sqlite":
		r := reader()
		_ = intrinsics.volatile_load(&r.boom)
		step_boom(r)
		http.respond_plain(res, "no crash")
	case "iter":
		// Step a reader statement part way, then crash between steps: in_sqlite is 0, so it's pure,
		// and the statement is left holding its snapshot until the pulled reset.
		r := reader()
		import_step_three(r)
		a := [4]int{}
		sink = a[idx]
		http.respond_plain(res, "no crash")
	case "block":
		// The loop stops ticking: the watchdog's case.
		time.sleep(time.Duration(query_int(req, "s", 15)) * time.Second)
		http.respond_plain(res, "unblocked")
	case:
		http.respond(res, http.Status.Not_Found)
	}
}

@(private = "file")
step_boom :: proc(r: ^Reader) {
	sq.step(r.boom)
}

@(private = "file")
import_step_three :: proc(r: ^Reader) {
	for _ in 0 ..< 3 { sq.step(r.iter) }
}
