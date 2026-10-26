package http

// F-1: streams, a response that stays open after the handler returns.
//
// A handler calls stream_begin instead of respond. The status line and headers go out at once;
// the connection then belongs to the Stream until stream_end (a chunked stream goes back to
// keep-alive) or the peer leaves. Everything runs on the connection's own event-loop thread:
// another thread reaches a stream only by queueing work onto that loop (stream_loop).
//
// Only the generic part lives here: framing (chunked, close-delimited, raw), the send queue and its
// cap, reads for a raw stream, and the shutdown grace. Protocols (SSE, WebSocket, multipart) are the
// application's.
//
// Allocator rule: after the handler returns, the connection's arena is scratch. It is the
// temp_allocator inside on_data and is freed after every on_data call, so copy anything you need
// from the request (url params, headers) before the handler returns.

import "core:bytes"
import "core:mem"
import "core:mem/virtual"
import "core:nbio"
import "core:strconv"
import "core:time"

Stream_Kind :: enum u8 {
	Chunked, // a body of unknown length: SSE, multipart/mixed, a slow HTML stream
	Raw,     // the socket after a 101 Switching Protocols: WebSocket
}

Stream_End :: enum u8 {
	Ended,       // stream_end and everything flushed
	Peer_Closed, // EOF or a receive error
	Send_Failed,
	Too_Slow,    // the send queue passed max_queued, or the peer sent more than STREAM_MAX_INBOUND unread
	Shutdown,    // the server is shutting down and the grace period ran out
	Crashed,     // F-5: a callback on this stream crashed and the guard recovered
}

// Returns how many bytes of `data` it consumed; the rest is kept for the next call.
Stream_Data_Proc     :: #type proc(s: ^Stream, data: []byte) -> (consumed: int)
Stream_Close_Proc    :: #type proc(s: ^Stream, why: Stream_End)
Stream_Shutdown_Proc :: #type proc(s: ^Stream)

STREAM_MAX_QUEUED     :: 256 * 1024
STREAM_MAX_INBOUND    :: 128 * 1024
STREAM_SHUTDOWN_GRACE :: 2 * time.Second

Stream :: struct {
	conn:        ^Connection,
	loop:        ^nbio.Event_Loop,
	alloc:       mem.Allocator,
	kind:        Stream_Kind,
	user:        rawptr,
	on_data:     Stream_Data_Proc,
	on_close:    Stream_Close_Proc,
	// The server is shutting down (a WebSocket sends its close frame here); stream_end follows.
	on_shutdown: Stream_Shutdown_Proc,
	// A callback on this stream crashed (F-5). The stream ends after this returns; write a last
	// message if the protocol has one (a WebSocket close frame with 1011).
	on_crash:    Stream_Shutdown_Proc,
	max_queued:  int,

	framed:      bool, // chunked framing; false for a raw stream and for an HTTP/1.0 peer (F-2)
	queue:       [dynamic]byte, // waiting for the socket
	flight:      [dynamic]byte, // handed to the kernel, untouchable until the send completes
	inbound:     [dynamic]byte, // received, not yet consumed by on_data
	send_op:     ^nbio.Operation,
	recv_op:     ^nbio.Operation,
	aux_op:      ^nbio.Operation, // the first-feed tick, then the shutdown deadline
	ending:      bool,
	close_after: bool, // the request asked for it, its body was never read, or the peer is HTTP/1.0
	shutting:    bool,
	done:        bool,
	recv_buf:    [4096]byte,
}

stream_begin :: proc(
	res: ^Response,
	kind: Stream_Kind,
	user: rawptr = nil,
	on_data: Stream_Data_Proc = nil,
	on_close: Stream_Close_Proc = nil,
	max_queued := STREAM_MAX_QUEUED,
	loc := #caller_location,
) -> ^Stream {
	assert_has_td(loc)
	assert(!res.sent, "response has already been sent", loc)
	res.sent = true
	conn := res._conn
	req := &conn.loop.req

	// F-2: HTTP/1.0 has no chunked encoding. A proxy that speaks 1.0 upstream (nginx without
	// "Websockets Support") gets a body delimited by the connection closing.
	http10 := false
	if line, ok := req.line.?; ok && line.version == {1, 0} { http10 = true }

	// Decided before the heading is written: response_must_close may add `connection: close`.
	_, body_read := req._body_ok.?
	unread_body := !body_read && (headers_has_unsafe(req.headers, "content-length") || headers_has_unsafe(req.headers, "transfer-encoding"))
	close_after := kind == .Raw || http10 || unread_body || response_must_close(req, res)
	if close_after && kind == .Chunked { headers_set_close(&res.headers) }

	switch kind {
	case .Chunked:
		if res.status == .Not_Found { res.status = .OK }
		if !http10 { headers_set_unsafe(&res.headers, "transfer-encoding", "chunked") }
	case .Raw:
		res.status = .Switching_Protocols
	}
	_response_write_heading(res, -1)

	alloc := conn.server.conn_allocator
	s := new(Stream, alloc)
	s.conn, s.loop, s.alloc, s.kind, s.close_after = conn, td.event_loop, alloc, kind, close_after
	s.framed = kind == .Chunked && !http10
	s.user, s.on_data, s.on_close, s.max_queued = user, on_data, on_close, max_queued
	s.queue.allocator, s.flight.allocator, s.inbound.allocator = alloc, alloc, alloc
	append(&s.queue, ..bytes.buffer_to_bytes(&res._buf))

	// Bytes the client sent right behind its request (a WebSocket's first frames) are already
	// in the scanner's buffer.
	if kind == .Raw {
		sc := &conn.scanner
		if sc.end > sc.start { append(&s.inbound, ..sc.buf[sc.start:sc.end]) }
		sc.start = sc.end
	}

	conn.stream = s
	connection_set_state(conn, .Streaming)
	_stream_kick(s)
	_stream_recv(s)
	if len(s.inbound) > 0 {
		s.aux_op = nbio.next_tick_poly(s, proc(_: ^nbio.Operation, s: ^Stream) {
			_stream_invoke(s, proc(s: ^Stream) {
				s.aux_op = nil
				_stream_feed(s)
			})
		})
	}
	return s
}

// Queues bytes; a chunked stream frames them as one chunk. False once the stream is ending or
// gone, or when this write would pass max_queued (the stream is then closed as Too_Slow).
stream_write :: proc(s: ^Stream, data: []byte) -> bool {
	if s.done || s.ending { return false }
	if len(data) == 0 { return true }
	if len(s.queue) + len(s.flight) + len(data) + 32 > s.max_queued {
		_stream_finish(s, .Too_Slow)
		return false
	}
	if s.framed {
		size: [16]byte
		append(&s.queue, strconv.write_int(size[:], i64(len(data)), 16))
		append(&s.queue, "\r\n")
		append(&s.queue, ..data)
		append(&s.queue, "\r\n")
	} else {
		append(&s.queue, ..data)
	}
	_stream_kick(s)
	return true
}

stream_write_string :: proc(s: ^Stream, str: string) -> bool {
	return stream_write(s, transmute([]byte)str)
}

// Ends the stream once everything queued is sent. A chunked stream then serves the
// connection's next request; a raw or close-delimited one closes it. With a deadline, a peer that
// hasn't taken the rest by then is cut off and the stream ends as Too_Slow: a protocol can then
// queue a last message to a slow consumer (a WebSocket's close 1013) and still bound the wait.
stream_end :: proc(s: ^Stream, deadline: time.Duration = 0) {
	if s.done || s.ending { return }
	if s.framed { append(&s.queue, "0\r\n\r\n") }
	s.ending = true
	if s.send_op == nil && len(s.queue) == 0 {
		_stream_finish(s, .Ended)
		return
	}
	_stream_kick(s)
	if deadline > 0 && s.aux_op == nil {
		s.aux_op = nbio.timeout_poly(deadline, s, proc(_: ^nbio.Operation, s: ^Stream) {
			_stream_invoke(s, proc(s: ^Stream) {
				s.aux_op = nil
				_stream_finish(s, .Too_Slow)
			})
		})
	}
}

// True when writing `n` more bytes would pass the stream's cap, so a protocol can end the stream
// with a last message (and stream_end's deadline) instead of having stream_write drop it.
stream_would_overflow :: proc(s: ^Stream, n: int) -> bool {
	return stream_queued(s) + n + 32 > s.max_queued
}

stream_queued :: proc(s: ^Stream) -> int { return len(s.queue) + len(s.flight) }

// The event loop the stream lives on: what another thread passes as `l` to nbio to reach it.
stream_loop :: proc(s: ^Stream) -> ^nbio.Event_Loop { return s.loop }

// Called by the server's shutdown loop on every tick until the stream is gone.
@(private)
stream_shutdown :: proc(s: ^Stream) {
	if s == nil || s.done || s.shutting { return }
	s.shutting = true
	if s.on_shutdown != nil { s.on_shutdown(s) }
	stream_end(s)
	if s.done { return }
	if s.aux_op != nil { nbio.remove(s.aux_op) }
	s.aux_op = nbio.timeout_poly(STREAM_SHUTDOWN_GRACE, s, proc(_: ^nbio.Operation, s: ^Stream) {
		_stream_invoke(s, proc(s: ^Stream) {
			s.aux_op = nil
			_stream_finish(s, .Shutdown)
		})
	})
}

// F-5: a callback on this stream crashed and the guard recovered. Unread input is dropped, the
// application may queue a last message, and the stream ends once that is flushed (or the
// shutdown grace runs out).
@(private)
stream_crashed :: proc(s: ^Stream) {
	if s.done { return }
	clear(&s.inbound)
	if s.on_crash != nil && !s.ending {
		on_crash := s.on_crash
		s.on_crash = nil // a crash inside on_crash doesn't loop
		on_crash(s)
	}
	s.close_after = true
	if !s.ending { stream_end(s) }
	if s.done { return }
	if s.aux_op != nil { nbio.remove(s.aux_op) }
	s.aux_op = nbio.timeout_poly(STREAM_SHUTDOWN_GRACE, s, proc(_: ^nbio.Operation, s: ^Stream) {
		_stream_invoke(s, proc(s: ^Stream) {
			s.aux_op = nil
			_stream_finish(s, .Crashed)
		})
	})
}

// Runs a stream callback through the server's invoke (F-5).
@(private)
_stream_invoke :: proc(s: ^Stream, fn: proc(s: ^Stream)) {
	if !_invoke(s.conn.server, proc(a, b: rawptr) { (proc(s: ^Stream))(a)((^Stream)(b)) }, rawptr(fn), s) {
		stream_crashed(s)
	}
}

@(private)
_stream_kick :: proc(s: ^Stream) {
	if s.done || s.send_op != nil || len(s.queue) == 0 { return }
	s.queue, s.flight = s.flight, s.queue // flight is empty here: swap instead of copying
	s.send_op = nbio.send_poly(s.conn.socket, {s.flight[:]}, s, proc(op: ^nbio.Operation, s: ^Stream) {
		if !_invoke(s.conn.server, proc(a, b: rawptr) { _stream_on_sent((^nbio.Operation)(a), (^Stream)(b)) }, op, s) {
			stream_crashed(s)
		}
	})
}

@(private)
_stream_on_sent :: proc(op: ^nbio.Operation, s: ^Stream) {
	s.send_op = nil
	if op.send.err != nil {
		_stream_finish(s, .Send_Failed)
		return
	}
	clear(&s.flight)
	if len(s.queue) > 0 {
		_stream_kick(s)
	} else if s.ending {
		_stream_finish(s, .Ended)
	}
}

@(private)
_stream_recv :: proc(s: ^Stream) {
	if s.done || s.recv_op != nil { return }
	s.recv_op = nbio.recv_poly(s.conn.socket, {s.recv_buf[:]}, s, proc(op: ^nbio.Operation, s: ^Stream) {
		s.recv_op = nil
		if !_invoke(s.conn.server, proc(a, b: rawptr) { _stream_on_recv((^nbio.Operation)(a), (^Stream)(b)) }, op, s) {
			stream_crashed(s)
		}
	})
}

// A chunked stream reads only to notice the peer leaving; a raw one feeds on_data.
@(private)
_stream_on_recv :: proc(op: ^nbio.Operation, s: ^Stream) {
	if op.recv.err != nil || op.recv.received == 0 {
		_stream_finish(s, .Peer_Closed)
		return
	}
	if s.kind == .Raw && s.on_data != nil {
		append(&s.inbound, ..s.recv_buf[:op.recv.received])
		_stream_feed(s)
		if s.done { return }
		if len(s.inbound) > STREAM_MAX_INBOUND {
			_stream_finish(s, .Too_Slow)
			return
		}
	}
	_stream_recv(s)
}

@(private)
_stream_feed :: proc(s: ^Stream) {
	arena := &s.conn.temp_allocator
	context.temp_allocator = virtual.arena_allocator(arena)
	defer free_all(context.temp_allocator)

	for len(s.inbound) > 0 && !s.done {
		n := s.on_data(s, s.inbound[:])
		if n <= 0 || s.done { break }
		remove_range(&s.inbound, 0, n)
	}
}

// The stream is freed a tick later, so a callback that ended it can still read s.done.
@(private)
_stream_finish :: proc(s: ^Stream, why: Stream_End) {
	if s.done { return }
	s.done = true
	for op in ([3]^^nbio.Operation{&s.recv_op, &s.send_op, &s.aux_op}) {
		if op^ != nil { nbio.remove(op^); op^ = nil }
	}
	if s.on_close != nil { s.on_close(s, why) }

	conn := s.conn
	conn.stream = nil
	if why == .Ended && s.framed && !s.close_after && !s.shutting {
		connection_set_state(conn, .Active)
		clean_request_loop(conn)
	} else {
		connection_close(conn)
	}

	nbio.next_tick_poly(s, proc(_: ^nbio.Operation, s: ^Stream) {
		delete(s.queue)
		delete(s.flight)
		delete(s.inbound)
		free(s, s.alloc)
	})
}
