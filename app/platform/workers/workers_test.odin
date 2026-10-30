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

	// The scheduler: a job runs every wake, and run_now is honoured. A frequent job's runs are
	// kept only when asked for by hand; a long one reports progress and a log, and stops when
	// cancelled; a queued run cancelled never runs. A job whose `due` says no is skipped until
	// asked for by hand; one that calls `fail` ends failed.
	@(static) ran: int
	@(static) later: int
	@(static) JOBS := [?]Job{
		{id = "test.tick", every = 0, run = proc() { sync.atomic_add(&ran, 1) }},
		{id = "test.slow", every = time.Hour, run = proc() {
			for i in 0 ..< 400 {
				if cancelled() { return }
				progress(i64(i), 400)
				log("step %d", i)
				time.sleep(10 * time.Millisecond)
			}
		}},
		{id = "test.later", every = 0, run = proc() { sync.atomic_add(&later, 1) }, due = proc() -> bool { return false }},
		{id = "test.bad", every = time.Hour, run = proc() { fail("it went wrong") }},
	}
	schedule({JOBS[:]})
	tick, tick_ok := run_now("test.tick")
	testing.expect(t, tick_ok && tick != 0)
	_, nope := run_now("test.nope")
	testing.expect(t, !nope)
	settle :: proc(id: u64, want: Run_State) -> Run {
		r: Run
		for i := 0; i < 100; i += 1 {
			r, _ = run_of(id)
			if r.state == want { break }
			time.sleep(50 * time.Millisecond)
		}
		return r
	}
	testing.expect_value(t, settle(tick, .Done).state, Run_State.Done)
	for i := 0; sync.atomic_load(&ran) < 2 && i < 40; i += 1 { time.sleep(100 * time.Millisecond) }

	slow, _ := run_now("test.slow")
	running := settle(slow, .Running)
	testing.expect_value(t, running.state, Run_State.Running)
	// The slow run is on the long-run thread: the frequent job goes on beside it (M5-03).
	before := sync.atomic_load(&ran)
	time.sleep(1200 * time.Millisecond)
	testing.expect(t, sync.atomic_load(&ran) > before)
	qd, _ := run_now("test.tick") // a kept run, behind the slow one: one long run at a time
	testing.expect(t, cancel_run(qd))
	testing.expect_value(t, settle(qd, .Cancelled).state, Run_State.Cancelled)
	time.sleep(100 * time.Millisecond)
	testing.expect(t, cancel_run(slow))
	done := settle(slow, .Cancelled)
	testing.expect_value(t, done.state, Run_State.Cancelled)
	testing.expect(t, done.total == 400 && done.done > 0 && done.done < 399)
	testing.expect(t, done.log_len > 0 && string(done.log[:7]) == "step 0\n")
	testing.expect(t, !cancel_run(slow)) // ended

	testing.expect_value(t, sync.atomic_load(&later), 0) // due said no at every wake
	by_hand, _ := run_now("test.later")
	testing.expect_value(t, settle(by_hand, .Done).state, Run_State.Done)
	testing.expect_value(t, sync.atomic_load(&later), 1)
	broke, _ := run_now("test.bad")
	failed := settle(broke, .Failed)
	testing.expect_value(t, failed.state, Run_State.Failed)
	testing.expect_value(t, string(failed.log[:failed.log_len]), "it went wrong\n")

	got := make([dynamic]Run, context.temp_allocator)
	v := runs_since(0, &got)
	testing.expect(t, v > 0 && len(got) == 5) // the frequent job's own runs were never kept
	testing.expect(t, got[0].id == tick && got[1].id == slow && got[2].id == qd && got[3].id == by_hand && got[4].id == broke)
	testing.expect(t, got[0].by_hand && got[1].by_hand)
	clear(&got)
	testing.expect_value(t, runs_since(v, &got), v)
	testing.expect_value(t, len(got), 0)
	unschedule()
	testing.expect(t, sync.atomic_load(&ran) >= 2)
	st, ok := job_state("test.tick")
	testing.expect(t, ok && st.runs >= 2 && st.crashes == 0)
}
