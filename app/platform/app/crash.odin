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

@(private)
on_crash :: proc(c: ^guard.Crash) {
	guard.log_crash(c)
	if !c.dirty { return }
	if sync.atomic_exchange(&st.stop_once, true) { return }
	sync.atomic_store(&st.exit_code, 70)
	write_crash_file(c.why)
	thread.create_and_start(proc() {
		time.sleep(DIRTY_HARD_EXIT)
		if l, ok := obs.begin(.Fatal, "app", "exit"); ok {
			obs.str(&l, "why", "the drain didn't finish")
			obs.end(&l)
		}
		obs.flush()
		os.exit(70)
	})
	sync.sema_post(&st.signalled)
}

// The watchdog's: a stalled loop or a stuck lock. Nothing can drain.
@(private)
on_fatal :: proc(why: string) {
	write_crash_file(why)
	obs.flush()
	os.exit(70)
}

@(private)
write_crash_file :: proc(why: string) {
	path := env.str("CRASH_FILE")
	if path == "" { return }
	id, route := obs.current_request()
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
