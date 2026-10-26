package main

// ---- hub: publish from any thread, fan out per event-loop thread -------------------------------
//
// One cross-thread operation per *loop* per burst, never per connection: a publish appends the
// message to every registered loop's inbox and queues a drain op only if none is pending (the
// nbio cross-thread queue holds 128 ops, and exec spins when it is full). The drain runs on the
// loop's own thread and writes into that thread's streams. Messages are refcounted: one ref per
// inbox plus one for the replay ring that serves Last-Event-ID.

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:strings"
import "core:sync"
import "core:time"

import http "vendor_fork:odin-http"

Topic :: enum u8 { Bus, Chat }
Transport :: enum u8 { Sse, Ws }

Msg :: struct {
	refs:  int,
	topic: Topic,
	id:    u64,
	html:  string,
}

Inbox :: struct {
	loop:  ^nbio.Event_Loop,
	mu:    sync.Mutex,
	items: [dynamic]^Msg, // producers append here under mu
	spare: [dynamic]^Msg, // the drain's side of the double buffer
	armed: bool,
}

REPLAY    :: 64
MAX_LOOPS :: 64
HEARTBEAT :: 15 * time.Second

Hub :: struct {
	mu:      sync.Mutex,
	inboxes: [MAX_LOOPS]^Inbox,
	n:       int,
	next_id: u64,
	ring:    [REPLAY]^Msg,
}

hub: Hub

Sub :: struct {
	stream:    ^http.Stream,
	topic:     Topic,
	transport: Transport,
	last_id:   u64, // what replay already sent: a live copy of it is skipped
}

// Per event-loop thread.
Local :: struct {
	inbox: ^Inbox,
	subs:  [dynamic]^Sub,
}

@(thread_local)
local: Local

heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

publish :: proc(topic: Topic, html: string) {
	if sync.atomic_load(&server.closing.raw) { return }
	m := new(Msg, heap())
	m.topic = topic
	m.html = strings.clone(html, heap())

	boxes: [MAX_LOOPS]^Inbox
	sync.lock(&hub.mu)
	hub.next_id += 1
	m.id = hub.next_id
	n := hub.n
	boxes = hub.inboxes
	m.refs = n + 1
	slot := &hub.ring[m.id % REPLAY]
	old := slot^
	slot^ = m
	sync.unlock(&hub.mu)

	if old != nil { msg_release(old) }
	for b in boxes[:n] {
		sync.lock(&b.mu)
		append(&b.items, m)
		wake := !b.armed
		b.armed = true
		sync.unlock(&b.mu)
		if wake { nbio.next_tick_poly(b, inbox_drain, l = b.loop) }
	}
}

msg_release :: proc(m: ^Msg) {
	if sync.atomic_sub(&m.refs, 1) == 1 {
		delete(m.html, heap())
		free(m, heap())
	}
}

@(private="file")
inbox_drain :: proc(_: ^nbio.Operation, b: ^Inbox) {
	defer free_all(context.temp_allocator) // the tick's context: this thread's own temp allocator
	sync.lock(&b.mu)
	b.items, b.spare = b.spare, b.items
	b.armed = false
	sync.unlock(&b.mu)
	for m in b.spare {
		deliver(m)
		msg_release(m)
	}
	clear(&b.spare)
}

@(private="file")
deliver :: proc(m: ^Msg) {
	sse, ws: string
	// Backwards: a write can drop a too-slow stream, whose close unsubscribes it with an
	// unordered_remove that only moves already-visited entries.
	for i := len(local.subs) - 1; i >= 0; i -= 1 {
		sub := local.subs[i]
		if sub.topic != m.topic || m.id <= sub.last_id { continue }
		switch sub.transport {
		case .Sse:
			if sse == "" { sse = sse_event(m.id, "", m.html) }
			http.stream_write_string(sub.stream, sse)
		case .Ws:
			if ws == "" { ws = ws_frame(WS_TEXT, transmute([]byte)m.html) }
			http.stream_write_string(sub.stream, ws)
		}
	}
}

ensure_local :: proc() {
	if local.inbox != nil { return }
	b := new(Inbox, heap())
	b.loop = nbio.current_thread_event_loop()
	b.items = make([dynamic]^Msg, heap())
	b.spare = make([dynamic]^Msg, heap())
	local.inbox = b
	local.subs = make([dynamic]^Sub, heap())
	sync.lock(&hub.mu)
	assert(hub.n < MAX_LOOPS)
	hub.inboxes[hub.n] = b
	hub.n += 1
	sync.unlock(&hub.mu)
	nbio.timeout(HEARTBEAT, heartbeat)
}

// One timer per thread, not per connection. SSE gets a comment line, WebSocket a ping: both keep
// proxies (nginx's 60 s proxy_read_timeout) from timing an idle stream out, and both surface a
// dead peer as a send error.
@(private="file")
heartbeat :: proc(_: ^nbio.Operation) {
	if sync.atomic_load(&server.closing.raw) { return } // a pending timer would keep the loop alive
	ping := ws_frame(WS_PING, nil)
	for i := len(local.subs) - 1; i >= 0; i -= 1 {
		sub := local.subs[i]
		http.stream_write_string(sub.stream, ": hb\n\n" if sub.transport == .Sse else ping)
	}
	free_all(context.temp_allocator)
	nbio.timeout(HEARTBEAT, heartbeat)
}

subscribe :: proc(s: ^http.Stream, topic: Topic, transport: Transport, last_id: u64 = 0) -> ^Sub {
	ensure_local()
	sub := new(Sub, heap())
	sub^ = {s, topic, transport, 0}
	append(&local.subs, sub)

	if transport == .Sse && last_id > 0 {
		sync.lock(&hub.mu)
		defer sync.unlock(&hub.mu)
		first := last_id + 1
		if hub.next_id >= REPLAY && first <= hub.next_id - REPLAY {
			// The gap is older than the ring: tell the page to refetch instead of pretending.
			http.stream_write_string(s, sse_event(0, "resync", ""))
			first = hub.next_id - REPLAY + 1
		}
		for id := first; id <= hub.next_id; id += 1 {
			m := hub.ring[id % REPLAY]
			if m != nil && m.id == id && m.topic == topic {
				http.stream_write_string(s, sse_event(m.id, "", m.html))
				sub.last_id = m.id
			}
		}
	}
	return sub
}

unsubscribe :: proc(sub: ^Sub) {
	for s, i in local.subs {
		if s == sub {
			unordered_remove(&local.subs, i)
			break
		}
	}
	free(sub, heap())
}

// ---- SSE framing ----------------------------------------------------------------------------

// CR, LF and CRLF all end an SSE line, so every one of them in the payload starts a new `data:`
// line. Splitting on LF alone would let a stray CR in user text inject an `event:` or `id:` field.
sse_event :: proc(id: u64, event, data: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	if id > 0 { fmt.sbprintf(&b, "id: %d\n", id) }
	if event != "" { fmt.sbprintf(&b, "event: %s\n", event) }
	start := 0
	for i := 0; i <= len(data); i += 1 {
		if i < len(data) && data[i] != '\r' && data[i] != '\n' { continue }
		strings.write_string(&b, "data: ")
		strings.write_string(&b, data[start:i])
		strings.write_byte(&b, '\n')
		if i + 1 < len(data) && data[i] == '\r' && data[i + 1] == '\n' { i += 1 }
		start = i + 1
	}
	strings.write_byte(&b, '\n')
	return strings.to_string(b)
}
