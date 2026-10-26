package workers

// ---- platform/workers: work off the event loops (L2) -----------------------
//
// S11, D16, PLAN §5.2. A loop must never block, so anything slow runs on a pool:
// argon2id verifies (accounts), the query pool's scans (store/sqlite), llama's
// glue, scheduled jobs. One mechanism serves them all:
//
//   submit(pool, task) on a loop ─► run(task) on a worker, inside the guard ─►
//   done(task) back on the submitting loop, through nbio.next_tick
//
// `run` and `done` are the caller's continuations (the only proc values kept in
// a task, as PLAN §6.1 allows). A web handler that defers its response (F-13)
// keeps the Response_Ref in its own task struct and resumes it in `done`, whose
// generation check makes a client that left cost a map lookup. A full queue is
// refused at once (`submit` returns false: answer 503), never waited on.

import "core:nbio"
import "core:strings"
import "core:sync"
import "core:thread"

import "../guard"
import "../obs"
import "../sys"

// Embed it first in the caller's own struct, so `done` can cast back:
//   Verify :: struct { using task: workers.Task, ref: http.Response_Ref, password: [256]byte, ok: bool }
Task :: struct {
	run:       proc(t: ^Task), // on a worker thread, inside the guard
	done:      proc(t: ^Task), // on the submitting loop, after run, or when cancelled before it ran
	loop:      ^nbio.Event_Loop,
	cancelled: bool, // atomic: the caller gave up (its client left, the pool drained)
	ran:       bool, // run returned
	crashed:   bool, // run trapped (a pure crash; a dirty one never gets here)
	queued_ns: i64,
}

Pool :: struct {
	name:     string,
	mutex:    sync.Mutex,
	cond:     sync.Cond,
	queue:    []^Task, // a ring
	head:     int,
	count:    int,
	stopping: bool,
	threads:  []^thread.Thread,
	depth:    obs.Gauge,
	refused:  obs.Counter,
	crashes:  obs.Counter,
}

// At boot, before the loops run: `threads` workers and room for `queue_cap`
// waiting tasks. Declares both as limits.
start :: proc(p: ^Pool, name: string, threads, queue_cap: int) {
	p.name = name
	p.queue = make([]^Task, queue_cap)
	p.threads = make([]^thread.Thread, threads)
	labels := strings.concatenate({`pool="`, name, `"`})
	p.depth = obs.register_gauge("app_worker_queue_depth", labels, "Tasks waiting per pool.")
	p.refused = obs.register_counter("app_worker_refused_total", labels, "Tasks refused because the queue was full or draining (503).")
	p.crashes = obs.register_counter("app_worker_crashes_total", labels, "Tasks whose run trapped (pure).")
	obs.limit(name, "threads", i64(threads))
	obs.limit(name, "queue", i64(queue_cap), "tasks")
	for &t in p.threads {
		t = thread.create_and_start_with_poly_data(p, worker, context)
	}
	sync.mutex_lock(&registry.mu)
	append(&registry.pools, p)
	sync.mutex_unlock(&registry.mu)
}

// Every started pool, so platform/app can drain them all at shutdown without
// knowing which features started which.
@(private)
registry: struct {
	mu:    sync.Mutex,
	pools: [dynamic]^Pool,
}

// From each loop's shutdown hook (F-4): idempotent.
drain_all :: proc() {
	sync.mutex_lock(&registry.mu)
	defer sync.mutex_unlock(&registry.mu)
	for p in registry.pools { drain(p) }
}

// On a loop thread. false: the queue is full or the pool is draining, and the
// caller answers 503 (nothing was queued, `done` will not run).
submit :: proc(p: ^Pool, t: ^Task) -> bool {
	t.loop = nbio.current_thread_event_loop()
	t.queued_ns = sys.mono_ns()
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	if p.stopping || p.count == len(p.queue) {
		obs.inc(p.refused)
		return false
	}
	p.queue[(p.head + p.count) % len(p.queue)] = t
	p.count += 1
	obs.set(p.depth, i64(p.count))
	sync.cond_signal(&p.cond)
	return true
}

// The caller gave up: a task that hasn't started skips `run`; `done` still runs.
cancel :: proc(t: ^Task) {
	sync.atomic_store(&t.cancelled, true)
}

// At the start of shutdown (F-4's on_thread_shutdown, before the loops wait on
// their requests): new submits are refused and every queued task is cancelled,
// so the workers post each reply within one task. A reply posted after its loop
// has left would land in a dead event loop: without this, S0.5's ASan run of the
// unpatched fork crashed in nbio's wake_up at shutdown.
drain :: proc(p: ^Pool) {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	if p.stopping { return }
	p.stopping = true
	for i in 0 ..< p.count {
		sync.atomic_store(&p.queue[(p.head + i) % len(p.queue)].cancelled, true)
	}
	sync.cond_broadcast(&p.cond)
}

// After the loops returned: every reply they were owed is in (F-13 waits).
stop :: proc(p: ^Pool) {
	drain(p)
	for t in p.threads {
		thread.join(t)
		thread.destroy(t)
	}
	delete(p.threads)
	delete(p.queue)
	p.threads, p.queue = nil, nil
	sync.mutex_lock(&registry.mu)
	for q, i in registry.pools {
		if q == p {
			unordered_remove(&registry.pools, i)
			break
		}
	}
	sync.mutex_unlock(&registry.mu)
}

depth :: proc(p: ^Pool) -> int {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	return p.count
}

@(private)
take :: proc(p: ^Pool) -> ^Task {
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	for p.count == 0 {
		if p.stopping { return nil }
		sync.cond_wait(&p.cond, &p.mutex)
	}
	t := p.queue[p.head]
	p.head = (p.head + 1) % len(p.queue)
	p.count -= 1
	obs.set(p.depth, i64(p.count))
	return t
}

// A worker task is an entry point (D15 rule 1): each run is guarded.
@(private)
worker :: proc(p: ^Pool) {
	guard.thread_init()
	for {
		t := take(p)
		if t == nil { break }
		if !sync.atomic_load(&t.cancelled) {
			if guard.call(proc(data: rawptr) { t := (^Task)(data); t.run(t) }, t) {
				t.ran = true
			} else {
				t.crashed = true
				obs.inc(p.crashes)
			}
		}
		// One op per result: at most `threads` posts in flight per pool.
		nbio.next_tick_poly(t, on_done, l = t.loop)
		free_all(context.temp_allocator)
	}
}

// On the submitting loop. Ends with free_all: nbio hands this callback the
// tick's context, whose temp allocator odin-http never frees (PLAN §5.4).
@(private)
on_done :: proc(_: ^nbio.Operation, t: ^Task) {
	defer free_all(context.temp_allocator)
	guard.call(proc(data: rawptr) { t := (^Task)(data); t.done(t) }, t)
}
