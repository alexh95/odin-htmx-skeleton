// platform/hub, the minimum spike S0.3 needs (PLAN §9.2, §9.3; D13): publish from any thread, one
// inbox per event loop, fan-out on the loop's own thread, a replay ring and the `<epoch>-<seq>`
// cursor. Not here (M2): per-topic rings and policies (.Latest, .Sample), TOPICS tables and their
// perm checks, keyset replay from a store, the stream limits past the fork's per-stream cap, the
// WS pong deadline, and the guarded mutex.
package hub

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import http "fork:odin-http"
import "../stream"

RING       :: 256 // one ring for every topic here; PLAN §9.4's HUB_RING is per topic
MAX_LOOPS  :: 64
MAX_TOPICS :: 8
HEARTBEAT  :: 20 * time.Second // under NPM's 90 s, Fly's 60 s and Cloudflare's 125 s idle cuts

Kind :: enum u8 {
	Html,  // swapped by the page: an SSE `data:` block, a WS text frame
	Close, // ends the topic's streams: SSE ends, a socket closes with `code` (a kick, a revoke)
}

Msg :: struct {
	refs:  int,
	kind:  Kind,
	code:  u16,
	seq:   u64, // 0 for a Close, which never enters the ring
	topic: string,
	html:  string,
}

Transport :: enum u8 { Sse, Ws }

Sub :: struct {
	out:       ^http.Stream,
	ws:        ^stream.Ws, // nil for SSE
	transport: Transport,
	topics:    [MAX_TOPICS]string,
	n_topics:  int,
	last:      u64, // the newest seq this subscriber has: a live copy at or below it is skipped
}

Inbox :: struct {
	loop:  ^nbio.Event_Loop,
	mu:    sync.Mutex,
	items: [dynamic]^Msg, // publishers append under mu
	spare: [dynamic]^Msg, // the drain's half of the double buffer
	armed: bool,          // a drain is queued on the loop
	subs:  int,           // atomic, for /stats
}

@(private)
Hub :: struct {
	mu:      sync.Mutex,
	inboxes: [MAX_LOOPS]^Inbox,
	n:       int,
	seq:     u64,
	ring:    [RING]^Msg,
	epoch:   u64,
	closing: bool, // atomic
}

@(private)
hub: Hub

// Per event-loop thread.
@(private)
Local :: struct {
	inbox:     ^Inbox,
	subs:      [dynamic]^Sub,
	heartbeat: ^nbio.Operation,
}

@(private, thread_local)
local: Local

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

// Once, before the server starts. The epoch makes a cursor from an earlier process recognisable:
// its ids restarted at 1, so without it a stale Last-Event-ID would replay the wrong messages.
// Milliseconds, not seconds: a restart inside the same second reused the epoch in S0.3's restart
// spec, and the stale cursor was then served from the new process's ring instead of a resync.
init :: proc() {
	hub.epoch = u64(time.time_to_unix_nano(time.now()) / 1_000_000)
}

// F-4's on_thread_init: this loop's inbox and heartbeat.
thread_init :: proc() {
	b := new(Inbox, heap())
	b.loop = nbio.current_thread_event_loop()
	b.items.allocator, b.spare.allocator = heap(), heap()
	local.inbox = b
	local.subs = make([dynamic]^Sub, heap())
	sync.lock(&hub.mu)
	assert(hub.n < MAX_LOOPS)
	hub.inboxes[hub.n] = b
	hub.n += 1
	sync.unlock(&hub.mu)
	local.heartbeat = nbio.timeout(HEARTBEAT, heartbeat)
}

// F-4's on_thread_shutdown: no new messages, and no timer left to keep the loop alive.
thread_shutdown :: proc() {
	sync.atomic_store(&hub.closing, true)
	if local.heartbeat != nil {
		nbio.remove(local.heartbeat)
		local.heartbeat = nil
	}
}

// ---- cursors ----------------------------------------------------------------------------------

cursor :: proc(seq: u64, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%d-%d", hub.epoch, seq, allocator = allocator)
}

// The hub sequence now, as a cursor: what a page renders as `after`.
cursor_now :: proc(allocator := context.temp_allocator) -> string {
	sync.lock(&hub.mu)
	seq := hub.seq
	sync.unlock(&hub.mu)
	return cursor(seq, allocator)
}

// ours: the cursor names this process's epoch, so its seq can be looked up in the ring.
parse_cursor :: proc(s: string) -> (seq: u64, ours: bool) {
	dash := strings.index_byte(s, '-')
	if dash < 0 { return }
	epoch, e_ok := strconv.parse_u64(s[:dash], 10)
	n, n_ok := strconv.parse_u64(s[dash + 1:], 10)
	if !e_ok || !n_ok || epoch != hub.epoch { return }
	return n, true
}

// ---- publish ----------------------------------------------------------------------------------

// From any thread. Returns the message's seq.
publish :: proc(topic, html: string) -> u64 {
	return post(.Html, topic, html, 0)
}

// Ends every stream subscribed to `topic`: SSE ends (the client reconnects with its
// Last-Event-ID), a socket closes with `code` (hx-ws reconnects only on 1001, 1005, 1006, 1011-1014).
close_topic :: proc(topic: string, code: u16) {
	post(.Close, topic, "", code)
}

@(private)
post :: proc(kind: Kind, topic, html: string, code: u16) -> (seq: u64) {
	if sync.atomic_load(&hub.closing) { return }
	m := new(Msg, heap())
	m.kind, m.code = kind, code
	m.topic = strings.clone(topic, heap())
	m.html = strings.clone(html, heap())

	boxes: [MAX_LOOPS]^Inbox
	old: ^Msg
	sync.lock(&hub.mu)
	n := hub.n
	boxes = hub.inboxes
	m.refs = n
	if kind == .Html {
		hub.seq += 1
		m.seq = hub.seq
		m.refs += 1
		slot := &hub.ring[m.seq % RING]
		old = slot^
		slot^ = m
	}
	sync.unlock(&hub.mu)

	if old != nil { release(old) }
	// One cross-thread operation per loop per burst, never per connection: nbio's cross-thread
	// queue holds 128 slots and spins when full (07 §0.2).
	for b in boxes[:n] {
		sync.lock(&b.mu)
		append(&b.items, m)
		wake := !b.armed
		b.armed = true
		sync.unlock(&b.mu)
		if wake { nbio.next_tick_poly(b, drain, l = b.loop) }
	}
	return m.seq
}

@(private)
release :: proc(m: ^Msg) {
	if sync.atomic_sub(&m.refs, 1) == 1 {
		delete(m.topic, heap())
		delete(m.html, heap())
		free(m, heap())
	}
}

@(private)
drain :: proc(_: ^nbio.Operation, b: ^Inbox) {
	defer free_all(context.temp_allocator) // the tick's context: this thread's temp allocator
	sync.lock(&b.mu)
	b.items, b.spare = b.spare, b.items
	b.armed = false
	sync.unlock(&b.mu)
	for m in b.spare {
		deliver(m)
		release(m)
	}
	clear(&b.spare)
}

@(private)
wants :: proc(sub: ^Sub, topic: string) -> bool {
	for t in sub.topics[:sub.n_topics] {
		if t == topic { return true }
	}
	return false
}

// Encodes once per transport, then writes to this loop's subscribers. Backwards: a write can end
// a stream, whose close unsubscribes it with an unordered_remove that only moves visited entries.
@(private)
deliver :: proc(m: ^Msg) {
	sse, ws: string
	for i := len(local.subs) - 1; i >= 0; i -= 1 {
		sub := local.subs[i]
		if !wants(sub, m.topic) { continue }
		switch m.kind {
		case .Html:
			if m.seq <= sub.last { continue }
			sub.last = m.seq
			switch sub.transport {
			case .Sse:
				if sse == "" { sse = stream.sse_event(cursor(m.seq), "", m.html) }
				http.stream_write_string(sub.out, sse)
			case .Ws:
				if ws == "" { ws = stream.ws_frame(stream.WS_TEXT, transmute([]byte)m.html) }
				stream.ws_write_frame(sub.ws, ws)
			}
		case .Close:
			switch sub.transport {
			case .Sse: http.stream_end(sub.out)
			case .Ws:  stream.ws_close(sub.ws, m.code)
			}
		}
	}
}

// One timer per loop, not per connection: SSE gets a comment line, a socket a ping.
@(private)
heartbeat :: proc(_: ^nbio.Operation) {
	local.heartbeat = nil
	if sync.atomic_load(&hub.closing) { return }
	ping := stream.ws_frame(stream.WS_PING, nil)
	for i := len(local.subs) - 1; i >= 0; i -= 1 {
		sub := local.subs[i]
		switch sub.transport {
		case .Sse: http.stream_write_string(sub.out, stream.SSE_HEARTBEAT)
		case .Ws:  stream.ws_write_frame(sub.ws, ping)
		}
	}
	free_all(context.temp_allocator)
	local.heartbeat = nbio.timeout(HEARTBEAT, heartbeat)
}

// ---- subscribe --------------------------------------------------------------------------------

Resume :: enum u8 {
	None,     // no cursor: live messages only
	Replayed, // the cursor was inside the ring: what it missed was written first
	Resync,   // a foreign epoch or a gap older than the ring: `event: resync` per topic
}

// On the stream's own loop, from its handler. `topics` are copied. For SSE, D13's connect
// procedure without the store step: a Last-Event-ID from this epoch inside the ring replays from
// the ring; otherwise `after` (the page's render-time cursor) does; otherwise a cursor that can't
// be served gets `event: resync`, which the page answers by refetching. The ring refs are copied
// out under the mutex and written after it is released (PLAN §9.2).
subscribe :: proc(
	s: ^http.Stream,
	transport: Transport,
	topics: []string,
	ws: ^stream.Ws = nil,
	last_event_id := "",
	after := "",
) -> (sub: ^Sub, resume: Resume) {
	sub = new(Sub, heap())
	sub.out, sub.ws, sub.transport = s, ws, transport
	for t in topics {
		if sub.n_topics == MAX_TOPICS { break }
		sub.topics[sub.n_topics] = strings.clone(t, heap())
		sub.n_topics += 1
	}
	append(&local.subs, sub)
	sync.atomic_add(&local.inbox.subs, 1)

	given := last_event_id if last_event_id != "" else after
	from, ours := parse_cursor(given)

	replay: [RING]^Msg
	n := 0
	sync.lock(&hub.mu)
	snapshot := hub.seq
	switch {
	case transport != .Sse || given == "":
		resume = .None
	case !ours || from > snapshot || snapshot - from > RING:
		resume = .Resync
	case:
		resume = .Replayed
		for seq := from + 1; seq <= snapshot; seq += 1 {
			m := hub.ring[seq % RING]
			if m == nil || m.seq != seq || !wants(sub, m.topic) { continue }
			sync.atomic_add(&m.refs, 1)
			replay[n] = m
			n += 1
		}
	}
	sync.unlock(&hub.mu)

	// Anything at or below the snapshot that is still in this loop's inbox is skipped by `last`;
	// anything above it reaches the inbox after this callback returns.
	sub.last = snapshot
	for m in replay[:n] {
		http.stream_write_string(s, stream.sse_event(cursor(m.seq), "", m.html))
		release(m)
	}
	if resume == .Resync {
		// The id moves the client's cursor to now, so its next reconnect replays from the ring
		// instead of asking for a resync again.
		for t in sub.topics[:sub.n_topics] {
			http.stream_write_string(s, stream.sse_event(cursor(snapshot), "resync", t))
		}
	}
	return
}

// From the stream's on_close, on its loop.
unsubscribe :: proc(sub: ^Sub) {
	for s, i in local.subs {
		if s == sub {
			unordered_remove(&local.subs, i)
			sync.atomic_sub(&local.inbox.subs, 1)
			break
		}
	}
	for t in sub.topics[:sub.n_topics] { delete(t, heap()) }
	free(sub, heap())
}

// ---- numbers for /stats -----------------------------------------------------------------------

Numbers :: struct {
	epoch:           u64,
	seq:             u64,
	loops:           int,
	loops_with_subs: int,
}

numbers :: proc() -> (r: Numbers) {
	sync.lock(&hub.mu)
	defer sync.unlock(&hub.mu)
	r.epoch, r.seq, r.loops = hub.epoch, hub.seq, hub.n
	for b in hub.inboxes[:hub.n] {
		if sync.atomic_load(&b.subs) > 0 { r.loops_with_subs += 1 }
	}
	return
}
