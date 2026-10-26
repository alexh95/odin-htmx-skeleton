package http

import "core:log"
import "core:nbio"
import "core:net"

// F-13: deferred responses. A handler that answers from another thread (a worker pool) calls
// `response_defer` and returns. The worker hands the `Response_Ref` back to the connection's loop
// (`nbio.next_tick_poly(job, done, l = ref.loop)`), where `response_resume` returns the Response,
// or nil when the connection is gone or has moved on. A ref never points into the connection, so
// a stale one costs a map lookup instead of a use-after-free.
//
// While a response is deferred the server watches the socket: a peer that leaves closes the
// connection at once and `on_gone` runs on the loop, so the application can drop the work. The
// thread's shutdown waits (up to `drain_deadline`) until every ref it handed out was resumed, so
// a reply never targets a loop that has gone away.
Response_Ref :: struct {
	loop:   ^nbio.Event_Loop,
	socket: net.TCP_Socket,
	gen:    u64,
}

@(private)
Deferred :: struct {
	active:  bool,
	watch:   ^nbio.Operation,
	on_gone: proc(user: rawptr),
	user:    rawptr,
}

// Call on the connection's loop, before returning from the handler without responding.
// `on_gone` runs on the loop when the connection closes before `response_resume`.
response_defer :: proc(res: ^Response, on_gone: proc(user: rawptr) = nil, user: rawptr = nil, loc := #caller_location) -> Response_Ref {
	assert_has_td(loc)
	c := res._conn
	assert(c.state == .Active && !res.sent && !c.deferred.active, "response_defer: the response is not open", loc)

	c.deferred = {active = true, on_gone = on_gone, user = user}
	td.deferred += 1
	// A body read still in flight owns the socket's read side; the watch starts only on an idle scanner.
	if c.scanner.recv_op == nil { _deferred_watch(c) }
	return {loop = td.event_loop, socket = c.socket, gen = c.gen}
}

// Call exactly once per ref, on `ref.loop`. nil: the peer left, or the connection is closing.
// A non-nil Response must be answered (or deferred again) before the callback returns.
response_resume :: proc(ref: Response_Ref, loc := #caller_location) -> ^Response {
	assert_has_td(loc)
	assert(ref.loop == td.event_loop, "response_resume: called off the connection's loop", loc)
	td.deferred -= 1

	c, ok := td.conns[ref.socket]
	if !ok || c.gen != ref.gen || c.state != .Active || !c.deferred.active || c.loop.res.sent {
		return nil
	}
	_deferred_end(c, gone = false)
	return &c.loop.res
}

@(private)
_deferred_watch :: proc(c: ^Connection) {
	c.deferred.watch = nbio.poll_poly(c.socket, .Receive, c, _on_deferred_ready)
}

@(private)
_on_deferred_ready :: proc(op: ^nbio.Operation, c: ^Connection) {
	c.deferred.watch = nil
	if !_invoke(c.server, proc(a, b: rawptr) { _deferred_ready((^nbio.Operation)(a), (^Connection)(b)) }, op, c) {
		connection_crashed(c)
	}
}

@(private)
_deferred_ready :: proc(op: ^nbio.Operation, c: ^Connection) {
	if !c.deferred.active { return }

	if op.poll.result == .Ready {
		// Readable is either the peer's next bytes (a pipelined request: keep them for the scanner
		// and stop watching) or its close. A read can't block here, so read to tell which.
		s := &c.scanner
		if len(s.buf) - s.end < INIT_BUF_SIZE / 2 {
			non_zero_resize(&s.buf, max(INIT_BUF_SIZE, len(s.buf) * 2))
		}
		n, err := net.recv_tcp(c.socket, s.buf[s.end:])
		switch {
		case err == nil && n > 0:
			s.end += n
			return
		case err == .Would_Block, err == .Interrupted:
			_deferred_watch(c)
			return
		}
	}

	log.debugf("deferred response: peer %i left", c.socket)
	_deferred_end(c, gone = true)
	connection_close(c)
}

// Stops the watch; `gone` also tells the application through `on_gone`.
@(private)
_deferred_end :: proc(c: ^Connection, gone: bool) {
	d := c.deferred
	if !d.active { return }
	c.deferred = {}
	if d.watch != nil { nbio.remove(d.watch) }
	if gone && d.on_gone != nil { d.on_gone(d.user) }
}
