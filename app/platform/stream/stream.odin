package stream

// ---- platform/stream: SSE, WebSocket and multipart on the fork's streams (L3) ----
//
// PLAN §8.2, D12. The protocols on top of F-1, which they reach through
// platform/web's re-export (only web imports odin-http):
//
//   sse.odin        the SSE encoder: CR, LF and CRLF each start a `data:` line;
//   ws.odin         the handshake with its own Origin check, and a strict RFC 6455 codec;
//   multipart.odin  multipart/mixed and /parallel: CRLF framing, a Content-Length per part.
//
// Every stream is a Conn registered on its loop. One timer per loop, armed while
// the loop has streams, sends SSE a comment line and a socket a ping every
// STREAM_HEARTBEAT_S (20 s, under NPM's 90 s, Fly's 60 s and Cloudflare's 125 s
// idle cuts), and closes a socket the peer has sent nothing on for
// WS_PONG_DEADLINE (§9.4). Admission caps every stream (limits.odin). A stream
// answers only from a `.Stream` row: front sends its no-buffering headers.
//
// Allocation (§5.4): a Conn and its buffers come from the heap and are freed one
// tick after the stream closes, because a close can run inside the frame parser.
// Not a virtual.Arena per stream: each would commit a 4 KiB page, and F-1's
// Stream already holds a 4 KiB receive buffer, so the pair would pass §18.4's
// 6 KiB a stream. Nothing of a stream lives in the request arena, which is
// per-callback scratch once the handler returns.

import "base:runtime"
import "core:nbio"
import "core:time"

import "../guard"
import "../obs"
import "../sys"
import "../web"

// A socket that has sent nothing for this long is closed (§9.4); the heartbeat's
// ping, every STREAM_HEARTBEAT_S (20 s), is what a live browser answers.
WS_PONG_DEADLINE :: 45 * time.Second

Proto :: enum u8 {
	Sse,
	Ws,
	Multipart,
}

// After the stream has gone: c.ended says why. The Conn is freed a tick later.
Close_Proc :: #type proc(c: ^Conn)

Conn :: struct {
	s:          ^web.Stream,
	proto:      Proto,
	user:       rawptr,
	on_close:   Close_Proc,
	ended:      web.Stream_End, // set before on_close
	gone:       bool,           // on_close has run: nothing more is written
	slot:       int,            // its index in this loop's list
	client:     u64,            // admission's keys (limits.odin)
	member:     u64,

	// WebSocket (ws.odin)
	on_message: Message_Proc,
	assembly:   Assembly,
	closing:    bool, // our close frame is queued
	seen_ns:    i64,  // the peer's last frame, against the pong deadline
	rate:       Rate, // frames a second, when the route caps them (chat: 20, then 1008)

	// multipart (multipart.odin)
	boundary:   [BOUNDARY_LEN]byte,
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

// This loop's streams and its heartbeat.
@(private, thread_local)
here: struct {
	conns:    [dynamic]^Conn,
	beat:     ^nbio.Operation,
	stopping: bool, // the server is shutting down: no timer is armed again
	stat:     ^Loop_Stat,
}

// Queues bytes on the stream; false once it is ending, gone or too slow.
write :: proc(c: ^Conn, data: string) -> bool {
	if c.gone { return false }
	return web.stream_write_string(c.s, data)
}

// Ends the stream the way its protocol ends: SSE's body ends, a socket closes
// with 1000, a multipart body gets its closing boundary.
end :: proc(c: ^Conn) {
	if c.gone { return }
	switch c.proto {
	case .Sse:       web.stream_end(c.s)
	case .Ws:        ws_close(c, WS_NORMAL)
	case .Multipart: multipart_end(c)
	}
}

// The bytes this stream has waiting for its peer.
queued :: proc(c: ^Conn) -> int { return 0 if c.gone else web.stream_queued(c.s) }

// ---- the Conn's life ------------------------------------------------------------

// nil when admission refused the stream: the response has been sent.
@(private)
open :: proc(res: ^web.Response, kind: web.Stream_Kind, proto: Proto, content_type: string, user: rawptr, on_close: Close_Proc) -> ^Conn {
	assert(inited, "platform/stream: call hub.init() (or stream.init()) at boot, before app.check")
	client, member, ok := admit(res)
	if !ok { return nil }
	if content_type != "" { web.set_header(res, "content-type", content_type) }
	if here.stat == nil {
		here.stat = new(Loop_Stat, heap())
		guard.lock(&adm.mu)
		if adm.loops.allocator.procedure == nil { adm.loops.allocator = heap() }
		append(&adm.loops, here.stat)
		guard.unlock(&adm.mu)
	}
	c := new(Conn, heap())
	c.proto, c.user, c.on_close = proto, user, on_close
	c.client, c.member = client, member
	c.seen_ns = sys.mono_ns()
	c.s = web.stream_begin(res, kind, c, ws_on_data if proto == .Ws else nil, closed, lim.max_queued)
	c.s.on_shutdown = shutdown
	c.s.on_crash = crashed
	if here.conns.allocator.procedure == nil { here.conns.allocator = heap() }
	c.slot = len(here.conns)
	append(&here.conns, c)
	if here.beat == nil && !here.stopping { here.beat = nbio.timeout(lim.heartbeat, beat) }
	obs.inc(counters.opened)
	return c
}

@(private)
closed :: proc(s: ^web.Stream, why: web.Stream_End) {
	c := (^Conn)(s.user)
	c.gone, c.closing, c.ended = true, true, why
	last := pop(&here.conns)
	if last != c {
		here.conns[c.slot] = last
		last.slot = c.slot
	}
	if len(here.conns) == 0 && here.beat != nil {
		nbio.remove(here.beat)
		here.beat = nil
	}
	release(c)
	obs.inc(counters.ended[why])
	if c.on_close != nil { c.on_close(c) }
	nbio.next_tick_poly(c, proc(_: ^nbio.Operation, c: ^Conn) {
		delete(c.assembly.frag)
		free(c, heap())
	})
}

// F-9: the server is shutting down; F-1 ends the stream after this returns.
@(private)
shutdown :: proc(s: ^web.Stream) {
	here.stopping = true
	if here.beat != nil {
		nbio.remove(here.beat)
		here.beat = nil
	}
	c := (^Conn)(s.user)
	switch c.proto {
	case .Sse:
	case .Ws:        ws_close(c, WS_RESTART) // hx-ws reconnects on 1012
	case .Multipart: write(c, closing_boundary(c)) // the body ends well formed; hx-multipart:connect reconnects
	}
}

// F-5: a callback on this stream crashed and the guard recovered it (a pure
// crash, §10). A socket hears 1011, on which hx-ws reconnects.
@(private)
crashed :: proc(s: ^web.Stream) {
	c := (^Conn)(s.user)
	if c.proto == .Ws { ws_close(c, WS_INTERNAL) }
}

// ---- the heartbeat ---------------------------------------------------------------

@(private)
beat :: proc(_: ^nbio.Operation) {
	here.beat = nil
	guard.call(proc(_: rawptr) { beat_all() }, nil)
	free_all(context.temp_allocator)
	if len(here.conns) > 0 && !here.stopping { here.beat = nbio.timeout(lim.heartbeat, beat) }
}

// Backwards, and re-checking the length: a write can close a stream, which
// moves the list's last entry into its slot.
@(private)
beat_all :: proc() {
	now := sys.mono_ns()
	ping := ws_frame(WS_PING, nil)
	for i := len(here.conns) - 1; i >= 0; i -= 1 {
		if i >= len(here.conns) { continue }
		c := here.conns[i]
		switch c.proto {
		case .Sse:
			write(c, SSE_HEARTBEAT)
		case .Ws:
			if c.closing { continue }
			if now - c.seen_ns > i64(WS_PONG_DEADLINE) {
				ws_close(c, WS_GOING_AWAY, WS_SLOW_DEADLINE)
				continue
			}
			ws_write_frame(c, ping)
		case .Multipart:
			// No comment syntax between parts; a feed that sits idle sends its own (chat's transport D).
		}
	}
	refresh_queued()
}

// How many streams this loop holds.
count :: proc() -> int { return len(here.conns) }
