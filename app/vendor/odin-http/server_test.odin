package http

import "core:nbio"
import "core:testing"
import "core:time"

// F-23: work a callback queues for its own loop runs on the loop's next turn, not after the
// loop's next unrelated event. Here a 100 ms timer is that event, as the 1 s timers are on a
// quiet server: 50 next ticks in a row took 50 of its periods on Linux before.
@(test)
queued_work_runs_without_waiting :: proc(t: ^testing.T) {
	testing.expect(t, nbio.acquire_thread_event_loop() == nil)
	defer nbio.release_thread_event_loop()

	c := Chain{left = 50}
	c.beat = nbio.timeout_poly(100 * time.Millisecond, &c, chain_beat)
	nbio.next_tick_poly(&c, chain_hop)
	start := time.tick_now()
	for !c.done && time.tick_since(start) < 10 * time.Second { testing.expect(t, _server_tick() == nil) }
	took := time.tick_since(start)
	testing.expect(t, c.done)
	testing.expectf(t, took < 100 * time.Millisecond, "50 queued next ticks took %v", took)
	for nbio.num_waiting() > 0 { nbio.tick(10 * time.Millisecond) }
}

@(private = "file")
Chain :: struct {
	left: int,
	beat: ^nbio.Operation,
	done: bool,
}

@(private = "file")
chain_hop :: proc(_: ^nbio.Operation, c: ^Chain) {
	c.left -= 1
	if c.left > 0 {
		nbio.next_tick_poly(c, chain_hop)
		return
	}
	c.done = true
	nbio.remove(c.beat)
}

@(private = "file")
chain_beat :: proc(_: ^nbio.Operation, c: ^Chain) {
	if !c.done { c.beat = nbio.timeout_poly(100 * time.Millisecond, c, chain_beat) }
}
