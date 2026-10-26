package workers

import "base:runtime"
import "core:nbio"
import "core:sync"
import "core:testing"
import "core:time"

import "../guard"
import "../obs"

@(private = "file")
Sum :: struct {
	using task: Task,
	n, out:     int,
	gate:       ^sync.Sema, // run waits on it, when set
	replies:    ^int,
}

@(private = "file")
sum_run :: proc(t: ^Task) {
	s := (^Sum)(t)
	if s.gate != nil { sync.sema_wait(s.gate) }
	if s.n < 0 { panic("negative") }
	for i in 1 ..= s.n { s.out += i }
}

@(private = "file")
sum_done :: proc(t: ^Task) {
	s := (^Sum)(t)
	// A reply runs on the loop that submitted it.
	assert(nbio.current_thread_event_loop() == s.task.loop)
	s.replies^ += 1
}

@(private = "file")
wait_replies :: proc(t: ^testing.T, replies: ^int, want: int) {
	deadline := time.tick_now()
	for replies^ < want && time.tick_since(deadline) < 5 * time.Second {
		nbio.tick(10 * time.Millisecond)
	}
	testing.expect_value(t, replies^, want)
}

// One test, in order: the guard and obs registries are process-wide.
@(test)
pool_and_scheduler :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	replies := 0
	p: Pool
	start(&p, "test", 2, 4)

	// Results come back on this loop.
	sums: [4]Sum
	for &s, i in sums {
		s = {task = {run = sum_run, done = sum_done}, n = 100 * (i + 1), replies = &replies}
		testing.expect(t, submit(&p, &s))
	}
	wait_replies(t, &replies, 4)
	testing.expect_value(t, sums[0].out, 5050)
	testing.expect_value(t, sums[3].out, 80200)
	for s in sums { testing.expect(t, s.ran && !s.crashed) }

	// A run that traps is pure: the reply still comes, marked.
	bad := Sum{task = {run = sum_run, done = sum_done}, n = -1, replies = &replies}
	testing.expect(t, submit(&p, &bad))
	wait_replies(t, &replies, 5)
	testing.expect(t, bad.crashed && !bad.ran)

	// Both workers held at a gate, four queued: the fifth is refused at once.
	gate: sync.Sema
	held: [2]Sum
	for &h in held {
		h = {task = {run = sum_run, done = sum_done}, n = 1, gate = &gate, replies = &replies}
		testing.expect(t, submit(&p, &h))
	}
	for depth(&p) > 0 { time.sleep(time.Millisecond) } // both taken
	queued: [5]Sum
	for &q, i in queued {
		q = {task = {run = sum_run, done = sum_done}, n = 1, replies = &replies}
		testing.expect_value(t, submit(&p, &q), i < 4)
	}

	// Draining cancels what is queued: those replies come back unrun.
	drain(&p)
	sync.sema_post(&gate, 2)
	wait_replies(t, &replies, 5 + 2 + 4)
	for h in held { testing.expect(t, h.ran) }
	for q in queued[:4] { testing.expect(t, q.cancelled && !q.ran) }
	extra := Sum{task = {run = sum_run, done = sum_done}, replies = &replies}
	testing.expect(t, !submit(&p, &extra), "a drained pool refuses")
	stop(&p)

	// The scheduler: a job runs every wake, and run_now is honoured.
	@(static) ran: int
	@(static) JOBS := [?]Job{{id = "test.tick", every = 0, run = proc() { sync.atomic_add(&ran, 1) }}}
	schedule({JOBS[:]})
	testing.expect(t, run_now("test.tick"))
	testing.expect(t, !run_now("test.nope"))
	for i := 0; sync.atomic_load(&ran) < 2 && i < 40; i += 1 { time.sleep(100 * time.Millisecond) }
	unschedule()
	testing.expect(t, sync.atomic_load(&ran) >= 2)
	st, ok := job_state("test.tick")
	testing.expect(t, ok && st.runs >= 2 && st.crashes == 0)
}
