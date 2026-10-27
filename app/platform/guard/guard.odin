package guard

// ---- platform/guard: crash containment (L2) --------------------------------
//
// D15, PLAN §10.2. Every entry point runs inside `invoke` (the fork's F-5 hook:
// accept, the scanner's reads, dispatch, sends, stream ops) or `call` (the app's
// timers, worker tasks, the writer task). A trap (an assertion, a panic, a bounds
// check, a divide by zero, a bad pointer, a stack overflow) jumps back here, and
// the thread's counters (sys.counters) say whether anything shared may be broken:
//
//   - locks_held:   a guard.Mutex is held (the only locks the app takes);
//   - async_posted: the callback posted an op that runs later against its state;
//   - in_sqlite:    the trap came from inside SQLite's C code.
//
// Any above zero is dirty: the app's handler answers 500 if it can, drains and
// exits 70. Otherwise it is pure: the caller answers 500 or ends its stream, and
// serving goes on. More than RECOVERY_BURST pure recoveries in a minute count as
// dirty, since each leaks what it had allocated from context.allocator.
//
// Formally this is undefined behaviour: Odin doesn't mark setjmp returns_twice.
// The guarded frame stays trivial and everything read after the jump is a
// volatile load (R4).

import "base:intrinsics"
import "base:runtime"
import "core:sync"
import "core:time"

import "../obs"
import "../sys"

Crash :: struct {
	kind:  string, // "assert", "panic", "bounds", "segv", "stack_overflow", "hang" …
	msg:   string,
	loc:   runtime.Source_Code_Location,
	code:  u32,
	dirty: bool,
	why:   string, // what made it dirty
}

// The app's response to a crash: on the crashed thread, after the jump, outside
// any guard. A dirty one must not return to serving: it drains and exits 70.
On_Crash :: #type proc(c: ^Crash)

RECOVERY_BURST :: 100
RECOVERY_WINDOW :: 60 * time.Second

@(private)
Frame :: struct {
	env:   sys.Jmp_Buf,
	crash: Crash,
}

@(private, thread_local) tl_frame: ^Frame
@(private, thread_local) tl_recoveries: u64
@(private, thread_local) tl_unwind: Unwind

@(private)
Unwind :: struct {
	fn:   proc(data: rawptr),
	data: rawptr,
}

@(private)
g: struct {
	on_crash:   On_Crash,
	recoveries: obs.Counter,
	dirty:      obs.Counter,
	burst_mu:   sync.Mutex,
	burst_at:   time.Tick,
	burst_n:    int,
	burst_max:  int,
}

// Once at boot, before any thread starts: the process-wide trap handlers.
install :: proc(handler: On_Crash, burst_limit := RECOVERY_BURST) {
	g.on_crash = handler
	g.burst_max = burst_limit
	g.recoveries = obs.register_counter("app_guard_recoveries_total", "", "Pure crashes recovered from (D15).")
	g.dirty = obs.register_counter("app_guard_dirty_total", "", "Dirty crashes: each one drains and exits 70.")
	sys.install_trap_handlers(_jump_from_trap)
	thread_init()
}

// Every thread that runs guarded code: the loops (F-4), the workers, the writer.
thread_init :: proc() {
	sys.thread_init()
}

// How many pure crashes this thread recovered from. The SQLite store compares it
// before using the loop's reader, and on a timer, and resets every statement when
// it moved: the pulled reset (D15 rule 3), so guard never calls into SQLite.
recoveries :: proc() -> u64 {
	return tl_recoveries
}

// What a crash in the current guarded call must still finish (M1-04): a
// continuation that took a deferred response over (web.resume) owes it an
// answer, which the fork gives (500, then close). Scoped to the innermost call;
// cleared by the code that set it once it no longer applies (web.finish).
set_unwind :: proc(fn: proc(data: rawptr), data: rawptr) {
	tl_unwind = {fn, data}
}

clear_unwind :: proc() {
	tl_unwind = {}
}

// The fork's Server_Opts.invoke (F-5).
invoke :: proc(fn: proc(a, b: rawptr), a, b: rawptr) -> (returned: bool) {
	f: Frame
	prev := tl_frame
	prev_unwind := tl_unwind
	tl_frame = &f
	tl_unwind = {}
	saved := sys.counters
	sys.counters.async_posted = 0
	context.assertion_failure_proc = _assertion_failure

	if sys.setjmp(&f.env) != 0 {
		tl_frame = intrinsics.volatile_load(&prev)
		c := intrinsics.volatile_load(&f.crash)
		n := intrinsics.volatile_load(&sys.counters)
		u := tl_unwind
		tl_unwind = intrinsics.volatile_load(&prev_unwind)
		sys.after_trap(c.code)
		_classify(&c, n)
		if c.dirty {
			obs.inc(g.dirty)
		} else {
			sys.counters = saved
			tl_recoveries += 1
			obs.inc(g.recoveries)
		}
		if g.on_crash != nil { g.on_crash(&c) }
		// After the crash line, which names the request the unwind is about to end.
		if u.fn != nil { u.fn(u.data) }
		return false
	}

	fn(a, b)

	tl_frame = prev
	tl_unwind = prev_unwind
	sys.counters.async_posted = saved.async_posted
	return true
}

// The app's own entry points: a timer, a worker task, the writer task's batch.
call :: proc(fn: proc(data: rawptr), data: rawptr) -> (returned: bool) {
	return invoke(proc(a, b: rawptr) { (proc(data: rawptr))(a)(b) }, rawptr(fn), data)
}

@(private)
_classify :: proc(c: ^Crash, n: sys.Counters) {
	switch {
	case n.in_sqlite > 0:
		c.dirty, c.why = true, "inside sqlite"
	case n.locks_held > 0:
		c.dirty, c.why = true, "lock held"
	case n.async_posted > 0:
		c.dirty, c.why = true, "async op posted"
	case:
		sync.mutex_lock(&g.burst_mu)
		if g.burst_n == 0 || time.tick_since(g.burst_at) > RECOVERY_WINDOW {
			g.burst_at, g.burst_n = time.tick_now(), 0
		}
		g.burst_n += 1
		too_many := g.burst_n > g.burst_max
		sync.mutex_unlock(&g.burst_mu)
		if too_many { c.dirty, c.why = true, "too many recoveries" }
	}
}

@(private)
_assertion_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	f := tl_frame
	if f == nil { runtime.default_assertion_failure_proc(prefix, message, loc) }
	f.crash.kind = "assert" if prefix == "Runtime assertion" || prefix == "assertion" else prefix
	f.crash.msg = message
	f.crash.loc = loc
	sys.longjmp(&f.env)
}

// From the trap handlers, on the trapping thread: jumps when it is inside a guard.
@(private)
_jump_from_trap :: proc "contextless" (kind: string, code: u32) -> bool {
	f := tl_frame
	if f == nil { return false }
	f.crash.kind = kind
	f.crash.code = code
	sys.longjmp(&f.env)
}

// ---- the counters' helpers --------------------------------------------------

// The only lock the app takes (`tools/check locks`). A trap while one is held is
// dirty: the 500 would go out, then every bystander would hang on the lock.
Mutex :: struct {
	m:     sync.Mutex,
	since: i64, // atomic: mono ns when the holder took it, 0 = free; the watchdog reads it
}

lock :: proc(m: ^Mutex) {
	sync.mutex_lock(&m.m)
	sys.counters.locks_held += 1
	sync.atomic_store(&m.since, sys.mono_ns() | 1)
}

try_lock :: proc(m: ^Mutex) -> bool {
	if !sync.mutex_try_lock(&m.m) { return false }
	sys.counters.locks_held += 1
	sync.atomic_store(&m.since, sys.mono_ns() | 1)
	return true
}

unlock :: proc(m: ^Mutex) {
	sync.atomic_store(&m.since, 0)
	sys.counters.locks_held -= 1
	sync.mutex_unlock(&m.m)
}

held_ns :: proc(m: ^Mutex) -> i64 {
	since := sync.atomic_load(&m.since)
	return sys.mono_ns() - since if since != 0 else 0
}

// Marks an op this callback posted (a timer, a cross-thread task, a dial): a trap
// after it is dirty, because the op would run later against abandoned state.
posted :: proc() { sys.counters.async_posted += 1 }

// One line for a crash: the access log's logfmt, with the request it was serving.
log_crash :: proc(c: ^Crash) {
	l, ok := obs.begin(.Fatal if c.dirty else .Error, "guard", "crash")
	if !ok { return }
	id, route := obs.current_request()
	obs.str(&l, "id", id)
	obs.str(&l, "route", route)
	obs.str(&l, "kind", c.kind)
	obs.num(&l, "code", i64(c.code))
	obs.str(&l, "zone", "dirty" if c.dirty else "pure")
	if c.dirty { obs.str(&l, "why", c.why) }
	obs.num(&l, "loop", i64(obs.current_loop()))
	if c.loc.file_path != "" {
		obs.str(&l, "at", c.loc.file_path)
		obs.num(&l, "line", i64(c.loc.line))
	}
	if c.msg != "" { obs.str(&l, "msg", c.msg) }
	obs.end(&l)
	obs.flush()
}
