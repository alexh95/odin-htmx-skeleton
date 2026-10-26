// S0.5 prototype: argon2id verifies on a bounded pool, answered on the request's loop through
// `nbio.next_tick_poly(l = loop)`, with the F-13 generation check (fork.diff) dropping the answer
// of a client that left. Build against the fork with fork.diff applied:
//
//   odin build . -o:speed -collection:vendor_fork=<fork copy>/..
//
// Defines: F13=false builds against the fork as it is (the raw ^Response is kept, as in 12 §4's
// prototype); GEN_CHECK=false keeps F-13's watch but answers through the raw pointer (the
// negative control, which ASan must catch).
//
// Env: PORT (8080), THREADS (2), ACCOUNTS_ARGON_THREADS (2), ARGON_QUEUE (32), ARGON_PRESET
// (owasp | small | 64m), INLINE=1 hashes on the loop instead (the reference arm), BIND_ALL=1,
// FAKE_HASH_MS=n sleeps instead of hashing (the pool's mechanics at full speed under ASan, where
// a real verify is about 25 times slower), ARGON_SCHED=idle|nice lowers the workers' priority, PIN=1
// puts the loops on CPUs 0-1 and the workers on 2-3 (Linux).
package s05

import "core:crypto"
import "core:crypto/argon2id"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:nbio"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sync"
import "core:thread"
import "core:time"

import http "vendor_fork:odin-http"

F13       :: #config(F13, true)
GEN_CHECK :: #config(GEN_CHECK, true)

// ---- configuration --------------------------------------------------------

env_int :: proc(name: string, def: int) -> int {
	v := os.get_env(name, context.temp_allocator)
	n, ok := strconv.parse_int(v, 10)
	return n if ok else def
}

params:   argon2id.Parameters
inline:   bool
fake_ms:  int
salt:     [16]byte
stored:   [32]byte // the account's tag, derived at boot from PASSWORD
PASSWORD :: "correct horse battery staple"

argon_buf_size :: proc() -> int { return int(params.memory_size) * 1024 + 64 * 1024 }

// One verify into a caller-owned buffer, reused across calls (bench: fewer page faults than a
// fresh 19 MiB allocation each time).
verify :: proc(password: []byte, buf: []byte) -> bool {
	if fake_ms > 0 {
		time.sleep(time.Duration(fake_ms) * time.Millisecond)
		return string(password) == PASSWORD
	}
	arena: mem.Arena
	mem.arena_init(&arena, buf)
	tag: [32]byte
	if argon2id.derive(&params, password, salt[:], tag[:], allocator = mem.arena_allocator(&arena)) != nil {
		return false
	}
	return crypto.compare_constant_time(tag[:], stored[:]) == 1
}

// ---- counters (GET /stats) ------------------------------------------------

Stats :: struct {
	submitted, busy, verified, ok, cancelled, gone_replies, on_gone: int,
	wait_ns, hash_ns:                                               i64,
	max_depth:                                                      int,
}
stats: Stats

// ---- the argon pool ---------------------------------------------------------

when F13 { Ref :: http.Response_Ref } else { Ref :: struct {} }

Job :: struct {
	ref:       Ref,
	loop:      ^nbio.Event_Loop,
	res:       ^http.Response, // only the F13=false and GEN_CHECK=false builds read it
	password:  [256]byte,
	pw_len:    int,
	cancelled: bool, // atomic: set on the loop by on_gone, read by the worker
	hashed:    bool,
	ok:        bool,
	queued_at: time.Tick,
}

Pool :: struct {
	mutex:    sync.Mutex,
	cond:     sync.Cond,
	queue:    []^Job, // ring
	head:     int,
	count:    int,
	stopping: bool,
	threads:  []^thread.Thread,
}

pool: Pool

pool_start :: proc(p: ^Pool, n, queue_cap: int) {
	p.queue   = make([]^Job, queue_cap)
	p.threads = make([]^thread.Thread, n)
	for &t in p.threads {
		t = thread.create_and_start_with_poly_data(p, worker, context)
	}
}

// Full queue → false, and the caller answers 503.
pool_submit :: proc(p: ^Pool, job: ^Job) -> bool {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	if p.stopping || p.count == len(p.queue) { return false }
	p.queue[(p.head + p.count) % len(p.queue)] = job
	p.count += 1
	stats.max_depth = max(stats.max_depth, p.count)
	sync.cond_signal(&p.cond)
	return true
}

pool_take :: proc(p: ^Pool) -> ^Job {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	for p.count == 0 {
		if p.stopping { return nil }
		sync.cond_wait(&p.cond, &p.mutex)
	}
	job := p.queue[p.head]
	p.head = (p.head + 1) % len(p.queue)
	p.count -= 1
	return job
}

// At the start of shutdown (from F-4's on_thread_shutdown, before the loops wait on their
// requests): new submits get 503 and queued jobs are cancelled, so the workers post every reply
// within one verify. A reply posted after its loop has left would write into a dead event loop:
// without this, the ASan run of the unpatched fork crashed in nbio's wake_up at shutdown.
pool_drain :: proc(p: ^Pool) {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	if p.stopping { return }
	p.stopping = true
	for i in 0 ..< p.count {
		sync.atomic_store(&p.queue[(p.head + i) % len(p.queue)].cancelled, true)
	}
	sync.cond_broadcast(&p.cond)
}

// After `serve` returns: the queue is empty, the workers are idle or finishing a reply.
pool_stop :: proc(p: ^Pool) {
	pool_drain(p)
	for t in p.threads { thread.join(t); thread.destroy(t) }
}

// A worker task is an entry point (PLAN §10.2): the guard wraps one iteration in M1.
worker :: proc(p: ^Pool) {
	worker_priority()
	buf := make([]byte, argon_buf_size())
	defer delete(buf)
	for {
		job := pool_take(p)
		if job == nil { break }
		start := time.tick_now()
		sync.atomic_add(&stats.wait_ns, i64(time.tick_diff(job.queued_at, start)))
		if !sync.atomic_load(&job.cancelled) {
			job.ok = verify(job.password[:job.pw_len], buf)
			job.hashed = true
			sync.atomic_add(&stats.hash_ns, i64(time.tick_since(start)))
		}
		// One op per result: at most ACCOUNTS_ARGON_THREADS posts in flight, far below the ring's 128.
		nbio.next_tick_poly(job, on_verified, l = job.loop)
		free_all(context.temp_allocator)
	}
}

// Runs on the request's loop. Ends with free_all: nbio gives this callback the tick's context,
// whose temp allocator odin-http never frees (PLAN §5.4).
on_verified :: proc(_: ^nbio.Operation, job: ^Job) {
	defer free_all(context.temp_allocator)
	defer free(job)

	if job.hashed { sync.atomic_add(&stats.verified, 1) } else { sync.atomic_add(&stats.cancelled, 1) }
	if job.ok { sync.atomic_add(&stats.ok, 1) }

	res: ^http.Response
	when F13 {
		res = http.response_resume(job.ref)
		when !GEN_CHECK { res = job.res } // negative control: answer whatever the pointer points at
	} else {
		res = job.res
	}
	if res == nil {
		sync.atomic_add(&stats.gone_replies, 1)
		return
	}
	if !job.hashed { // cancelled by the drain, and the client is still there
		http.headers_set(&res.headers, "retry-after", "1")
		http.respond_plain(res, "busy, retry", .Service_Unavailable)
	} else if job.ok {
		http.respond_plain(res, "welcome")
	} else {
		http.respond_plain(res, "wrong password", .Unauthorized)
	}
}

on_gone :: proc(user: rawptr) {
	job := (^Job)(user)
	sync.atomic_store(&job.cancelled, true)
	sync.atomic_add(&stats.on_gone, 1)
}

// ---- handlers -----------------------------------------------------------------

// The skeleton's /ui/ping fragment, verbatim in shape (controllers.ui_ping + views.view_ping).
ui_ping :: proc(req: ^http.Request, res: ^http.Response) {
	token := time.now()._nsec / 1_000_000
	rps := 40 + int(token % 60)
	http.respond_html(res, fmt.tprintf(
		`<div class="ping-ok"><svg class="icon" aria-hidden="true"><use href="#i-check"></use></svg><div><strong>200 OK</strong><small>uptime token %d · %d req/s synthetic</small></div></div>`,
		token, rps))
}

@(thread_local) inline_buf: []byte

login :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, 1024, res, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := (^http.Response)(user)
		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}
		form, _ := http.body_url_encoded(body)
		pass := form["pass"]
		if len(pass) < 10 || len(pass) > 256 {
			http.respond_plain(res, "bad password length", .Bad_Request)
			return
		}
		sync.atomic_add(&stats.submitted, 1)

		if inline {
			if inline_buf == nil { inline_buf = make([]byte, argon_buf_size()) }
			start := time.tick_now()
			ok := verify(transmute([]byte)pass, inline_buf)
			sync.atomic_add(&stats.hash_ns, i64(time.tick_since(start)))
			sync.atomic_add(&stats.verified, 1)
			http.respond_plain(res, "welcome" if ok else "wrong password", .OK if ok else .Unauthorized)
			return
		}

		job := new(Job)
		job.pw_len = copy(job.password[:], pass)
		job.queued_at = time.tick_now()
		job.loop = nbio.current_thread_event_loop()
		job.res = res
		when F13 { job.ref = http.response_defer(res, on_gone, job) }

		if !pool_submit(&pool, job) {
			when F13 { res = http.response_resume(job.ref) } // undo the deferral: answer now
			free(job)
			sync.atomic_add(&stats.busy, 1)
			http.headers_set(&res.headers, "retry-after", "1")
			http.respond_plain(res, "busy, retry", .Service_Unavailable)
		}
	})
}

stats_handler :: proc(req: ^http.Request, res: ^http.Response) {
	s := stats
	sync.mutex_lock(&pool.mutex)
	depth := pool.count
	sync.mutex_unlock(&pool.mutex)
	http.respond_plain(res, fmt.tprintf(
		`{{"submitted":%d,"busy":%d,"verified":%d,"ok":%d,"cancelled":%d,"gone_replies":%d,"on_gone":%d,"max_depth":%d,"depth":%d,"mean_wait_ms":%.2f,"mean_hash_ms":%.2f}}`,
		s.submitted, s.busy, s.verified, s.ok, s.cancelled, s.gone_replies, s.on_gone, s.max_depth, depth,
		f64(s.wait_ns) / 1e6 / f64(max(1, s.verified + s.cancelled)), f64(s.hash_ns) / 1e6 / f64(max(1, s.verified))))
}

// ---- main -------------------------------------------------------------------------

main :: proc() {
	context.logger = log.create_console_logger(.Warning)

	switch os.get_env("ARGON_PRESET", context.temp_allocator) {
	case "small": params = argon2id.PARAMS_OWASP_SMALL
	case "64m":   params = {memory_size = 64 * 1024, passes = 3, parallelism = 1}
	case:         params = argon2id.PARAMS_OWASP
	}
	inline = os.get_env("INLINE", context.temp_allocator) == "1"
	fake_ms = env_int("FAKE_HASH_MS", 0)
	crypto.rand_bytes(salt[:])
	_ = argon2id.derive(&params, transmute([]byte)string(PASSWORD), salt[:], stored[:])

	argon_threads := env_int("ACCOUNTS_ARGON_THREADS", 2)
	if !inline { pool_start(&pool, argon_threads, env_int("ARGON_QUEUE", 32)) }

	router: http.Router
	http.router_init(&router)
	http.route_get(&router, "/ui/ping", http.handler(ui_ping))
	http.route_post(&router, "/login", http.handler(login))
	http.route_get(&router, "/stats", http.handler(stats_handler))

	s: http.Server
	http.server_shutdown_on_interrupt(&s)
	opts := http.Default_Server_Opts
	opts.thread_count = env_int("THREADS", 2)
	opts.on_thread_init = proc(_: ^http.Server, _: int) { loop_pin() }
	opts.on_thread_shutdown = proc(_: ^http.Server, _: int) { if !inline { pool_drain(&pool) } }
	addr := net.IP4_Any if os.get_env("BIND_ALL", context.temp_allocator) != "" else net.IP4_Loopback
	port := env_int("PORT", 8080)
	fmt.printfln("s05 on :%d threads=%d argon=%v inline=%v F13=%v GEN_CHECK=%v", port, opts.thread_count, params, inline, F13, GEN_CHECK)
	free_all(context.temp_allocator)

	err := http.listen_and_serve(&s, http.router_handler(&router), net.Endpoint{address = addr, port = port}, opts)
	if err != nil { fmt.eprintln("listen:", err) }
	// The loops waited (F-13) for every reply they were owed, so the workers have nothing left to post.
	if !inline { pool_stop(&pool) }
	fmt.printfln("stopped: %v", stats)
}
