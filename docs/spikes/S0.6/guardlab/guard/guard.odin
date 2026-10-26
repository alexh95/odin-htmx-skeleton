package guard

// M0 spike S0.6: the crash guard (PLAN §10.2, D15), the prototype of `platform/guard`.
//
// `invoke` is the fork's F-5 hook: every callback the server owns runs inside it. A trap (an
// assertion, a panic, a bounds check, a divide by zero, a bad pointer, a stack overflow) jumps back
// here. The thread's counters then say whether anything shared could be left broken:
//   - locks_held:   a `Mutex` from this package is held (the only locks the app may take);
//   - async_posted: the callback posted an operation that will run later against its state;
//   - in_sqlite:    the trap came from inside SQLite's C code.
// Any of them above zero is dirty: the app's `on_dirty` runs (it answers 500 if it can, drains and
// exits 70). Otherwise the trap is pure: the fork answers 500 or ends the stream, and serving goes on.
//
// Formally this is undefined behaviour: Odin doesn't mark setjmp returns_twice. The guarded frame is
// kept trivial and everything read after the jump is a volatile load (R4).

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:time"

Counters :: struct {
	locks_held:   int,
	async_posted: int,
	in_sqlite:    int,
}

Crash :: struct {
	kind:  string, // "assert", "panic", "trap", "signal 11", "0xC0000005" …
	msg:   string,
	loc:   runtime.Source_Code_Location,
	code:  u32,
	dirty: bool,
	why:   string, // what made it dirty
}

@(private)
Frame :: struct {
	env:   Jmp_Buf,
	crash: Crash,
}

@(private, thread_local)
tl_frame: ^Frame
@(private, thread_local)
tl_counters: Counters
@(private, thread_local)
tl_recoveries: u64

// Pure recoveries leak what the callback had allocated from context.allocator, so many of them in a
// short window count as dirty (PLAN §10.2 rule 3).
RECOVERY_BURST  :: 100
RECOVERY_WINDOW :: 60 * time.Second

@(private)
burst: struct {
	mu:     sync.Mutex,
	start:  time.Tick,
	count:  int,
	limit:  int,
}

// What the app does with a crash: log it, and for a dirty one, drain and exit 70.
// Runs on the crashed thread, after the jump, outside any guard.
On_Crash :: #type proc(c: ^Crash)

@(private)
on_crash: On_Crash

// Installs the process-wide trap handlers. Call once at boot, before the server starts.
install :: proc(handler: On_Crash, burst_limit := RECOVERY_BURST) {
	on_crash = handler
	burst.limit = burst_limit
	_install_trap_handlers()
	thread_init()
}

// Per-thread setup (the alternate signal stack on Linux). The fork's on_thread_init (F-4) calls it.
thread_init :: proc() {
	_thread_init()
}

// How many pure crashes this thread recovered from. A store compares it before using the thread's
// reader connection and resets every statement on that connection when it moved (the pulled reset:
// the jump skipped the deferred resets, and an unreset reader pins the WAL).
recoveries :: proc() -> u64 {
	return tl_recoveries
}

counters :: proc() -> Counters {
	return tl_counters
}

// The fork's Server_Opts.invoke (F-5).
invoke :: proc(fn: proc(a, b: rawptr), a, b: rawptr) -> (returned: bool) {
	f: Frame
	prev := tl_frame
	tl_frame = &f
	saved := tl_counters
	tl_counters.async_posted = 0
	context.assertion_failure_proc = _assertion_failure

	if _setjmp(&f.env) != 0 {
		// Back from a trap. Everything below reads through volatile loads.
		tl_frame = intrinsics.volatile_load(&prev)
		c := intrinsics.volatile_load(&f.crash)
		n := intrinsics.volatile_load(&tl_counters)
		_after_trap(c.code)
		_classify(&c, n)
		if !c.dirty {
			tl_counters = saved
			tl_recoveries += 1
		}
		if on_crash != nil { on_crash(&c) }
		return false
	}

	fn(a, b)

	tl_frame = prev
	tl_counters.async_posted = saved.async_posted
	return true
}

@(private)
_classify :: proc(c: ^Crash, n: Counters) {
	switch {
	case n.in_sqlite > 0:
		c.dirty, c.why = true, "inside sqlite"
	case n.locks_held > 0:
		c.dirty, c.why = true, "lock held"
	case n.async_posted > 0:
		c.dirty, c.why = true, "async op posted"
	case:
		sync.mutex_lock(&burst.mu)
		if burst.count == 0 || time.tick_since(burst.start) > RECOVERY_WINDOW {
			burst.start, burst.count = time.tick_now(), 0
		}
		burst.count += 1
		too_many := burst.count > burst.limit
		sync.mutex_unlock(&burst.mu)
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
	_jump(&f.env)
}

// Called by the trap handlers (any thread). Jumps when this thread is inside invoke; returns false
// otherwise, and the handler lets the process die as it would have.
@(private)
_jump_from_trap :: proc "contextless" (kind: string, code: u32) -> bool {
	f := tl_frame
	if f == nil { return false }
	f.crash.kind = kind
	f.crash.code = code
	_jump(&f.env)
}

// ---- the counters' helpers -------------------------------------------------------------------

// The only lock the app takes (`tools/check locks` enforces it at M1). A trap while one is held is
// dirty: the 500 would go out, then every bystander would hang on the lock.
Mutex :: struct {
	m:     sync.Mutex,
	since: i64, // when the current holder took it (ns since boot), 0 = free; the watchdog reads it
}

lock :: proc(m: ^Mutex) {
	sync.mutex_lock(&m.m)
	tl_counters.locks_held += 1
	sync.atomic_store(&m.since, i64(time.tick_now()._nsec) | 1)
}

unlock :: proc(m: ^Mutex) {
	sync.atomic_store(&m.since, 0)
	tl_counters.locks_held -= 1
	sync.mutex_unlock(&m.m)
}

// Nanoseconds the lock has been held, 0 if free.
held_for :: proc(m: ^Mutex) -> time.Duration {
	since := sync.atomic_load(&m.since)
	if since == 0 { return 0 }
	return time.Duration(i64(time.tick_now()._nsec) - since)
}

// Marks an operation this callback posted (a timer, a dial, a cross-thread task): a trap after it is
// dirty, because the op would run later against state the jump abandoned.
posted :: proc() { tl_counters.async_posted += 1 }

// Around every call into SQLite (the store's binding calls these).
sqlite_enter :: #force_inline proc() { tl_counters.in_sqlite += 1 }
sqlite_leave :: #force_inline proc() { tl_counters.in_sqlite -= 1 }

// One line for a crash, in the access log's logfmt.
crash_line :: proc(c: ^Crash, route: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf(
		"lvl=error mod=guard ev=crash kind=%q code=0x%X zone=%s why=%q route=%q at=%s:%d msg=%q pid=%d",
		c.kind, c.code, "dirty" if c.dirty else "pure", c.why, route, c.loc.file_path, c.loc.line, c.msg,
		os.get_pid(), allocator = allocator,
	)
}
