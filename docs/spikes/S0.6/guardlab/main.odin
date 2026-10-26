package guardlab

// M0 spikes S0.6 (the guard in the fork, and the watchdog) and S0.7 (drain and restart).
//
// A small server on the vendored fork (app/vendor/odin-http) with the guard as its F-5 invoke hook,
// the crash routes M1 puts behind -define:TEST_ROUTES, a WAL store with one reader connection per
// event loop, a watchdog, and the SSE and WebSocket streams the drain test holds open.
//
// Env: PORT (8095), THREADS (4), DB_PATH (guardlab.db), NO_RESET=1 (skip the pulled reset after a
// pure crash, to show what it prevents), BIND_RETRY_MS (F-12's retry; 0 turns it off),
// HEADER_TIMEOUT_MS, IDLE_TIMEOUT_MS, BODY_TIMEOUT_MS (F-7), GUARD_BURST (100: pure recoveries per minute before they
// count as dirty), CRASH_FILE (where the watchdog and a dirty crash write
// last-crash.txt; default next to the DB).

import "core:fmt"
import "core:log"
import "core:nbio"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sync"
import "core:thread"
import "core:time"

import http "vendor_fork:odin-http"

import "guard"

server: http.Server
exit_code: int // 70 after a dirty crash or a watchdog exit (PLAN §10.2)
boot_tick: time.Tick

MAX_LOOPS :: 64
DRAIN_HARD_EXIT :: 5500 * time.Millisecond // a dirty exit drains, but never past this

// The loop the current callback runs on, and the route it serves (for the crash line).
@(thread_local) tl_loop: int
@(thread_local) tl_route: string

main :: proc() {
	context.logger = log.create_console_logger(.Info if os.get_env("LOG_LEVEL", context.temp_allocator) == "info" else .Warning)
	boot_tick = time.tick_now()

	port := env_int("PORT", 8095)
	threads := env_int("THREADS", 4)
	raise_nofile() // PLAN §8.6 step 2: soft = hard, so F-8's cap is the hard limit less 64

	// GUARD_BURST raises the 100-per-minute limit for the WAL check, which crashes 1000 times.
	guard.install(on_crash, env_int("GUARD_BURST", guard.RECOVERY_BURST))
	db_path := os.get_env("DB_PATH", context.allocator)
	if db_path == "" { db_path = "guardlab.db" }
	store_open(db_path)

	r: http.Router
	http.router_init(&r)
	routes(&r)
	route_handler := http.router_handler(&r)
	front := http.middleware_proc(&route_handler, proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
		tl_route = req.url.path
		next := h.next.(^http.Handler)
		next.handle(next, req, res)
	})

	opts := http.Default_Server_Opts
	opts.thread_count = threads
	opts.auto_expect_continue = false
	opts.invoke = guard.invoke
	opts.on_thread_init = on_thread_init
	opts.on_thread_shutdown = on_thread_shutdown
	if ms := env_int("BIND_RETRY_MS", -1); ms >= 0 { opts.bind_retry = time.Duration(ms) * time.Millisecond }
	// F-7's timeouts, as PLAN §8.5's env rows name them.
	if ms := env_int("HEADER_TIMEOUT_MS", -1); ms >= 0 { opts.header_timeout = time.Duration(ms) * time.Millisecond }
	if ms := env_int("IDLE_TIMEOUT_MS", -1); ms >= 0 { opts.idle_timeout = time.Duration(ms) * time.Millisecond }
	if ms := env_int("BODY_TIMEOUT_MS", -1); ms >= 0 { opts.body_timeout = time.Duration(ms) * time.Millisecond }

	http.server_shutdown_on_interrupt(&server)
	watchdog := thread.create_and_start(watchdog_run)

	address: net.Address = net.IP4_Loopback
	if os.get_env("BIND_ALL", context.temp_allocator) != "" { address = net.IP4_Any }
	fmt.eprintfln("guardlab: listening on %d with %d threads, pid %d", port, threads, os.get_pid())
	err := http.listen_and_serve(&server, front, net.Endpoint{address = address, port = port}, opts)
	if err != nil {
		fmt.eprintfln("guardlab: server error: %v", err)
		os.exit(1)
	}
	// Not joined: it sleeps a second between checks, and the drain's bound counts to the exit.
	sync.atomic_store(&watchdog_stop, true)
	_ = watchdog
	fmt.eprintfln("guardlab: exit %d after %v", exit_code, time.tick_since(boot_tick))
	os.exit(exit_code)
}

env_int :: proc(name: string, def: int) -> int {
	if v := os.get_env(name, context.temp_allocator); v != "" {
		if n, ok := strconv.parse_int(v, 10); ok { return n }
	}
	return def
}

// ---- crashes ---------------------------------------------------------------------------------

dirty_once: bool
drain_started: time.Tick

on_crash :: proc(c: ^guard.Crash) {
	fmt.eprintln(guard.crash_line(c, tl_route))
	if !c.dirty {
		loop_crashes[tl_loop] += 1
		return
	}
	if sync.atomic_exchange(&dirty_once, true) { return }
	dirty_exit("dirty crash")
}

// Dirty: drain and exit 70; a thread wedged on the abandoned lock can't drain, so a hard exit
// follows after DRAIN_HARD_EXIT whatever happens.
dirty_exit :: proc(why: string) {
	exit_code = 70
	write_last_crash(why)
	thread.create_and_start(proc() {
		time.sleep(DRAIN_HARD_EXIT)
		fmt.eprintfln("guardlab: hard exit 70, drain didn't finish")
		os.exit(70)
	})
	http.server_shutdown(&server)
}

write_last_crash :: proc(why: string) {
	path := os.get_env("CRASH_FILE", context.temp_allocator)
	if path == "" { path = "last-crash.txt" }
	_ = os.write_entire_file(path, fmt.tprintf("%v %s\n", time.now(), why))
}

// ---- per-loop tick timers (F-4) and the watchdog -----------------------------------------------

loop_ticks: [MAX_LOOPS]i64 // ns since boot of each loop's last timer tick
loop_timer: [MAX_LOOPS]^nbio.Operation
loops: int
watchdog_stop: bool

WATCHDOG_STALL :: 10 * time.Second
WATCHDOG_LOCK  :: 5 * time.Second

on_thread_init :: proc(s: ^http.Server, i: int) {
	guard.thread_init()
	tl_loop = i
	sync.atomic_add(&loops, 1)
	sync.atomic_store(&loop_ticks[i], i64(time.tick_since(boot_tick)))
	loop_timer[i] = nbio.timeout_poly(time.Second, i, loop_tick)
}

on_thread_shutdown :: proc(s: ^http.Server, i: int) {
	if loop_timer[i] != nil {
		nbio.remove(loop_timer[i])
		loop_timer[i] = nil
	}
	drain_streams_on_this_loop()
}

loop_tick :: proc(_: ^nbio.Operation, i: int) {
	loop_timer[i] = nil
	// An app timer is an entry point too: it runs under the guard.
	guard.invoke(proc(a, b: rawptr) {
		i := int(uintptr(a))
		sync.atomic_store(&loop_ticks[i], i64(time.tick_since(boot_tick)))
		store_reader_tick()
		free_all(context.temp_allocator)
	}, rawptr(uintptr(i)), nil)
	if http.server_is_closing(&server) { return }
	loop_timer[i] = nbio.timeout_poly(time.Second, i, loop_tick)
}

// Wakes every second. A loop that hasn't ticked for 10 s, or the store's write lock held for 5 s:
// log, write last-crash.txt, exit 70 (PLAN §10.2 rule 4). Docker never restarts an unhealthy
// container outside Swarm, so the watchdog is what turns a hang into a restart.
watchdog_run :: proc() {
	for !sync.atomic_load(&watchdog_stop) {
		time.sleep(time.Second)
		if http.server_is_closing(&server) { continue }
		now := i64(time.tick_since(boot_tick))
		n := sync.atomic_load(&loops)
		for i in 0 ..< n {
			age := time.Duration(now - sync.atomic_load(&loop_ticks[i]))
			if age > WATCHDOG_STALL {
				why := fmt.tprintf("watchdog: loop %d stalled for %v", i, age)
				fmt.eprintfln("lvl=fatal mod=watchdog ev=stall loop=%d age=%v", i, age)
				write_last_crash(why)
				fmt.eprintfln("guardlab: exit 70 after %v", time.tick_since(boot_tick))
				os.exit(70)
			}
		}
		if held := guard.held_for(&store.writer_mu); held > WATCHDOG_LOCK {
			fmt.eprintfln("lvl=fatal mod=watchdog ev=lock held=%v", held)
			write_last_crash("watchdog: write lock held")
			os.exit(70)
		}
	}
}

// ---- small helpers ------------------------------------------------------------------------------

query_int :: proc(req: ^http.Request, key: string, def: int) -> int {
	q := req.url.query
	for len(q) > 0 {
		kv := q
		if i := index_byte(q, '&'); i >= 0 { kv, q = q[:i], q[i + 1:] } else { q = "" }
		if len(kv) > len(key) && kv[:len(key)] == key && kv[len(key)] == '=' {
			if v, ok := strconv.parse_int(kv[len(key) + 1:], 10); ok { return v }
		}
	}
	return def
}

index_byte :: proc(s: string, b: byte) -> int {
	for i in 0 ..< len(s) { if s[i] == b { return i } }
	return -1
}
