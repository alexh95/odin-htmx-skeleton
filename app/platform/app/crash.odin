package app

// ---- crashes, hangs, signals, and each loop's tick ---------------------------------------
//
// D15, PLAN §10.2. A pure crash is logged and serving goes on (the fork answered
// 500 or ended the stream). A dirty one is logged, written to CRASH_FILE, and
// drains: wait() returns as if signalled, the profile's drain calls run, and the
// process exits 70, or is cut at 5.5 s if a loop is wedged on the abandoned lock.
// A watchdog exit (a stalled loop, a stuck lock) can't drain at all: it exits 70
// at once. Compose restarts either (`restart: unless-stopped`).

import "core:c/libc"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

import "../env"
import "../guard"
import "../obs"

DIRTY_HARD_EXIT :: 5500 * time.Millisecond
// What the watchdog's last line gets before the armed exit takes the process anyway.
FATAL_LOG_GRACE :: 1 * time.Second

// A dirty crash arms its exit, and writes the crash file, before it logs: a
// stalled log pipe holds the lock a blocked write took, and the exit must not
// wait behind it (M1-03). Its writes are bounded from here (obs.bound_writes).
@(private)
on_crash :: proc(c: ^guard.Crash) {
	if !c.dirty || sync.atomic_exchange(&st.stop_once, true) {
		guard.log_crash(c)
		return
	}
	obs.bound_writes()
	sync.atomic_store(&st.exit_code, guard.EXIT_DIRTY)
	id, route := obs.current_request()
	write_crash_file(c.why, id, route)
	thread.create_and_start(proc() {
		time.sleep(DIRTY_HARD_EXIT)
		obs.bound_writes()
		if l, ok := obs.begin(.Fatal, "app", "exit"); ok {
			obs.str(&l, "why", "the drain didn't finish")
			obs.end(&l)
		}
		obs.flush()
		os.exit(guard.EXIT_DIRTY)
	})
	guard.log_crash(c)
	sync.sema_post(&st.signalled)
}

// The watchdog's, before its own line: a stalled loop or a stuck lock, which
// nothing can drain. The crash file, and an exit the line can't hold up (M1-03).
@(private)
on_fatal :: proc(why, id, route: string) {
	write_crash_file(why, id, route)
	thread.create_and_start(proc() {
		time.sleep(FATAL_LOG_GRACE)
		os.exit(guard.EXIT_DIRTY)
	})
}

// The watchdog's thread has no request of its own, so the caller names it.
@(private)
write_crash_file :: proc(why, id, route: string) {
	path := env.str("CRASH_FILE")
	if path == "" { return }
	_ = os.write_entire_file(path, transmute([]byte)fmt.tprintf("%v exit 70: %s (route %q, request %s)\n", time.now(), why, route, id))
}

// SIGINT, and SIGTERM, which a container runtime sends PID 1 (F-10); a second
// signal exits at once. Async-signal context: only an atomic and a post.
@(private)
install_signals :: proc() {
	on_signal :: proc "c" (_: i32) {
		if sync.atomic_exchange(&signal_seen, true) {
			os.exit(1)
		}
		sync.sema_post(&st.signalled)
	}
	libc.signal(libc.SIGINT, on_signal)
	libc.signal(libc.SIGTERM, on_signal)
}

@(private) signal_seen: bool

// What a first signal does, from a request: /__test/shutdown's drain.
@(private)
request_shutdown :: proc() {
	if !sync.atomic_exchange(&signal_seen, true) { sync.sema_post(&st.signalled) }
}

// ---- each loop's 1 s tick: what the watchdog and /livez read, the log flush ------------

@(private, thread_local) tl_tick_op: ^nbio.Operation
@(private, thread_local) tl_stopping: bool

@(private)
arm_tick :: proc() {
	tl_tick_op = nbio.timeout_poly(time.Second, rawptr(nil), on_tick)
}

@(private)
on_tick :: proc(_: ^nbio.Operation, _: rawptr) {
	defer free_all(context.temp_allocator)
	tl_tick_op = nil
	if tl_stopping { return }
	guard.call(proc(_: rawptr) { obs.thread_tick() }, nil)
	arm_tick()
}

@(private)
disarm_tick :: proc() {
	tl_stopping = true
	if tl_tick_op != nil {
		nbio.remove(tl_tick_op)
		tl_tick_op = nil
	}
}
