package lab_web

// ---- lab: the stream contract pages and their endpoints (PLAN §15.5) ---------------------
//
// /lab/streams and its pages use hx-sse, hx-ws and hx-multipart against the
// platform's streams and hub as a real page would; the endpoints beside them are
// what 03's 29 contract checks and the extension specs drive (e2e/tests/lab/):
// a ticking SSE answer, a WebSocket echo (the nightly Autobahn run's target), a
// room, multipart parts and a resumable multipart feed, publish and close for a
// topic, and the numbers a spec reads back. The lab is a public origin with no
// sessions, so nothing here takes markup from a request: published text is
// escaped into a fixed fragment, and a topic key is short and plain.

import "base:runtime"
import "core:encoding/json"
import "core:nbio"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/guard"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/stream"
import "../../../platform/web"
import "../../../platform/workers"
import lab_views "../views"

EXTS :: web.Exts{.Sse, .Ws, .Multipart}

ROUTES := [?]web.Route {
	{.Get, "/lab", index, .Public, {}, 0},
	{.Get, "/lab/streams", page_all, .Public, {}, 0},
	{.Get, "/lab/streams/live", page_live, .Public, {}, 0},
	{.Get, "/lab/streams/chat", page_chat, .Public, {}, 0},
	{.Get, "/lab/streams/mp", page_mp, .Public, {}, 0},
	{.Get, "/lab/streams/blank", page_blank, .Public, {}, 0},
	{.Get, "/lab/feed", frag_feed, .Public, {.Fragment}, 0},
	{.Post, "/lab/publish", publish, .Public, {.Fragment}, 0},
	{.Post, "/lab/close", close_topic, .Public, {.Fragment}, 0},
	{.Get, "/lab/stats", stats, .Public, {.Fragment}, 0},
	{.Get, "/lab/sse/tick", sse_tick, .Public, {.Stream, .Fragment}, 0},
	{.Post, "/lab/sse/tick", sse_tick, .Public, {.Stream, .Fragment}, 0},
	{.Get, "/lab/ws/echo", ws_echo, .Public, {.Stream, .Fragment}, 0},
	{.Get, "/lab/ws/chat", ws_chat, .Public, {.Stream, .Fragment}, 0},
	{.Get, "/lab/multipart", multipart_parts, .Public, {.Stream, .Fragment}, 0},
	{.Get, "/lab/mp/count", multipart_count, .Public, {.Stream, .Fragment}, 0},
}

// lab.bus: the producer job's beats. lab.feed:<key> and lab.room:<key>: a page's
// live log and a room, whose keys the page (or a spec) picks.
TOPICS := [?]hub.Topic {
	{family = "lab.bus", policy = .Queue},
	{family = "lab.feed", policy = .Queue},
	{family = "lab.room", policy = .Queue},
}

// A publisher that is no event loop, as a worker or a poller would be.
JOBS := [?]workers.Job {
	{"lab.bus", 500 * time.Millisecond, beat},
}

@(private)
beat :: proc() {
	@(static) n: int
	n += 1
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p>beat `)
	strings.write_int(&b, n)
	html.w(&b, ` from the producer job</p>`)
	hub.publish("lab.bus", strings.to_string(b))
}

// ---- pages -------------------------------------------------------------------------------

index :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Lab", "/lab", INDEX_DESCRIPTION, lab_views.index_page())
}

// The same page as a host's root (the lab profile's, until landing at M3): its
// canonical URL is the root's.
root :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Lab", "/", INDEX_DESCRIPTION, lab_views.index_page())
}

@(private)
INDEX_DESCRIPTION :: "The starter's stream contract: SSE, WebSocket and multipart from an Odin server to htmx 4, in real pages."

page_all :: proc(req: ^web.Request, res: ^web.Response) {
	tag := key_or(req, "tag", "lab")
	room := key_or(req, "room", "lobby")
	web.render_page(req, res, "Streams", "/lab/streams", "One layout SSE stream, one WebSocket and a multipart panel on one page.",
		lab_views.all_page(topic("lab.feed", tag), tag, room, tag, after(req)))
}

page_live :: proc(req: ^web.Request, res: ^web.Response) {
	key := key_or(req, "t", "live")
	web.render_page(req, res, "hx-sse", "/lab/streams/live", "A live log over the layout's SSE stream: replay, resume and resync.",
		lab_views.live_page(topic("lab.feed", key), key, after(req)))
}

page_chat :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "hx-ws", "/lab/streams/chat", "A room over one WebSocket: JSON in, escaped HTML out.",
		lab_views.chat_page(key_or(req, "room", "lobby"), key_or(req, "tag", "")))
}

page_mp :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "hx-multipart", "/lab/streams/mp", "One response in parts, each into its own target.",
		lab_views.mp_page(key_or(req, "tag", ""), web.query_get(req, "count") != ""))
}

page_blank :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Blank", "/lab/streams/blank", "An empty lab page.", lab_views.blank_page())
}

frag_feed :: proc(req: ^web.Request, res: ^web.Response) {
	web.respond_html(res, lab_views.refetched(key_or(req, "t", "")))
}

// ---- publish and close --------------------------------------------------------------------

// POST /lab/publish?t=lab.feed:<key> with `id` and `text`: one line to the feed's
// subscribers, escaped into its fragment; ?t=lab.room:<key> with `text`: a room
// message. Up to 60,000 bytes of text, so a spec can fill a slow consumer's queue.
publish :: proc(req: ^web.Request, res: ^web.Response) {
	t := web.query_get(req, "t")
	family, key := split(t)
	f := web.form(req)
	text := f["text"]
	if !plain(key) || len(text) > 60_000 {
		web.respond_status(res, .Bad_Request)
		return
	}
	switch family {
	case "lab.feed":
		if !plain(f["id"]) {
			web.respond_status(res, .Bad_Request)
			return
		}
		hub.publish(t, lab_views.feed_item(f["id"], text))
	case "lab.room":
		hub.publish(t, lab_views.room_message(text))
	case:
		web.respond_status(res, .Bad_Request)
		return
	}
	web.respond_status(res, .No_Content)
}

// POST /lab/close?t=lab.<family>:<key>&code=<code>: ends that topic's streams,
// as a kick does: SSE gets `kicked` and reconnects, a socket closes with the code.
close_topic :: proc(req: ^web.Request, res: ^web.Response) {
	t := web.query_get(req, "t")
	family, key := split(t)
	code := web.query_int(req, "code", 1000)
	if (family != "lab.feed" && family != "lab.room") || !plain(key) || code < 1000 || code > 4999 {
		web.respond_status(res, .Bad_Request)
		return
	}
	hub.kick(t, u16(code))
	web.respond_status(res, .No_Content)
}

// ---- SSE ------------------------------------------------------------------------------------

// /lab/sse/tick?n=5&ms=200: `n` events `ms` apart, then the end. Also a POST,
// the way the bot answers its form with a stream.
@(private)
Ticker :: struct {
	c:     ^stream.Conn,
	op:    ^nbio.Operation,
	n, i:  int,
	every: time.Duration,
}

sse_tick :: proc(req: ^web.Request, res: ^web.Response) {
	t := new(Ticker, heap())
	t.n = clamp(web.query_int(req, "n", 5), 1, 100)
	t.every = time.Duration(clamp(web.query_int(req, "ms", 100), 0, 5000)) * time.Millisecond
	t.c = stream.sse_begin(res, t, proc(c: ^stream.Conn) {
		t := (^Ticker)(c.user)
		if t.op != nil { nbio.remove(t.op) }
		free(t, heap())
	})
	if t.c == nil {
		free(t, heap())
		return
	}
	t.op = nbio.timeout_poly(t.every, t, tick)
}

@(private)
tick :: proc(_: ^nbio.Operation, t: ^Ticker) {
	t.op = nil // fired: no longer removable
	guard.call(proc(data: rawptr) {
		t := (^Ticker)(data)
		t.i += 1
		buf: [24]byte
		if !stream.sse_send(t.c, strconv.write_int(buf[:], i64(t.i), 10), "", lab_views.tick(t.i)) { return }
		if t.i >= t.n {
			stream.end(t.c)
			return
		}
		t.op = nbio.timeout_poly(t.every, t, tick)
	}, t)
	free_all(context.temp_allocator)
}

// ---- WebSocket ------------------------------------------------------------------------------

// The echo the nightly Autobahn|Testsuite run fuzzes (§19.1.9): every message back
// as it came, with no frame-rate cap.
ws_echo :: proc(req: ^web.Request, res: ^web.Response) {
	stream.ws_upgrade(req, res, proc(c: ^stream.Conn, text: bool, data: []byte) {
		stream.ws_send(c, text, data)
	})
}

@(private)
Room :: struct {
	sub:   ^hub.Sub,
	topic: string,
}

// /lab/ws/chat?room=<key>&tag=<tag>&hello=1: hx-ws sends {message, headers};
// every socket in the room gets the message back as an escaped OOB fragment,
// through the hub. With hello the socket first gets a JSON envelope for
// #ws-status, as a room's snapshot would come.
ws_chat :: proc(req: ^web.Request, res: ^web.Response) {
	room := topic("lab.room", key_or(req, "room", "lobby"))
	tag := key_or(req, "tag", "")
	hello := web.query_get(req, "hello") != ""
	c, err := stream.ws_upgrade(req, res, proc(c: ^stream.Conn, text: bool, data: []byte) {
		In :: struct { message: string }
		m: In
		if !text || json.unmarshal(data, &m, allocator = context.temp_allocator) != nil || m.message == "" { return }
		hub.publish((^Room)(c.user).topic, lab_views.room_message(m.message))
	}, proc(c: ^stream.Conn) {
		r := (^Room)(c.user)
		hub.unsubscribe(r.sub)
		delete(r.topic, heap())
		free(r, heap())
	}, max_rate = 20)
	if err != .None { return }
	r := new(Room, heap())
	r.topic = strings.clone(room, heap())
	c.user = r
	r.sub = hub.subscribe(c, {r.topic})
	n := note_connect(strings.concatenate({"ws:", tag}, context.temp_allocator)) if tag != "" else 1
	if hello { stream.ws_send_text(c, lab_views.hello(n)) }
}

// ---- multipart ------------------------------------------------------------------------------

// /lab/multipart?n=3&ms=100&end_ms=0: `n` parts `ms` apart, then the closing
// boundary `end_ms` after the last. Part 1 targets #mp-a, part 2 is appended to
// #mp-b, the rest land in the request's own target.
@(private)
Parts :: struct {
	c:        ^stream.Conn,
	op:       ^nbio.Operation,
	n, i:     int,
	every:    time.Duration,
	end_wait: time.Duration,
}

multipart_parts :: proc(req: ^web.Request, res: ^web.Response) {
	p := new(Parts, heap())
	p.n = clamp(web.query_int(req, "n", 3), 1, 50)
	p.every = time.Duration(clamp(web.query_int(req, "ms", 100), 0, 10_000)) * time.Millisecond
	p.end_wait = time.Duration(clamp(web.query_int(req, "end_ms", 0), 0, 10_000)) * time.Millisecond
	p.c = stream.multipart_begin(res, .Mixed, p, proc(c: ^stream.Conn) {
		p := (^Parts)(c.user)
		if p.op != nil { nbio.remove(p.op) }
		free(p, heap())
	})
	if p.c == nil {
		free(p, heap())
		return
	}
	p.op = nbio.timeout_poly(p.every, p, part)
}

@(private)
part :: proc(_: ^nbio.Operation, p: ^Parts) {
	p.op = nil
	guard.call(proc(data: rawptr) {
		p := (^Parts)(data)
		if p.i >= p.n {
			stream.multipart_end(p.c)
			return
		}
		p.i += 1
		buf: [24]byte
		id := strconv.write_int(buf[:], i64(p.i), 10)
		headers: []stream.Part_Header
		switch p.i {
		case 1: headers = {{"HX-Target", "#mp-a"}, {"HX-Part-ID", id}}
		case 2: headers = {{"HX-Target", "#mp-b"}, {"HX-Swap", "beforeend"}, {"HX-Part-ID", id}}
		case:   headers = {{"HX-Part-ID", id}}
		}
		if !stream.multipart_part(p.c, lab_views.part(p.i, p.n), headers) { return }
		p.op = nbio.timeout_poly(p.every if p.i < p.n else p.end_wait, p, part)
	}, p)
	free_all(context.temp_allocator)
}

// /lab/mp/count?n=2&max=6&ms=100&tag=<tag>: an hx-multipart:connect feed. Each
// connect sends the next `n` counts, `ms` apart, after the HX-Last-Part-ID it carries, then ends, and
// hx-multipart reconnects; past `max` a last part triggers `mp-done`, which the
// element's hx-multipart:close answers.
@(private)
Counter :: struct {
	c:         ^stream.Conn,
	op:        ^nbio.Operation,
	next, end: int,
	done:      bool,
	every:     time.Duration,
}

multipart_count :: proc(req: ^web.Request, res: ^web.Response) {
	last := 0
	if lpi, ok := web.header(req, "hx-last-part-id"); ok {
		if n, nok := web.parse_digits(lpi); nok { last = n }
	}
	if tag := key_or(req, "tag", ""); tag != "" { note_connect(tag) }
	max_n := clamp(web.query_int(req, "max", 6), 1, 1000)
	c := new(Counter, heap())
	c.next = min(last, max_n) + 1
	c.end = min(last + clamp(web.query_int(req, "n", 2), 1, 100), max_n)
	c.done = c.end >= max_n
	c.every = time.Duration(clamp(web.query_int(req, "ms", 100), 0, 5000)) * time.Millisecond
	c.c = stream.multipart_begin(res, .Mixed, c, proc(conn: ^stream.Conn) {
		c := (^Counter)(conn.user)
		if c.op != nil { nbio.remove(c.op) }
		free(c, heap())
	})
	if c.c == nil {
		free(c, heap())
		return
	}
	c.op = nbio.timeout_poly(c.every, c, count)
}

@(private)
count :: proc(_: ^nbio.Operation, c: ^Counter) {
	c.op = nil
	guard.call(proc(data: rawptr) {
		c := (^Counter)(data)
		if c.next > c.end {
			if c.done { stream.multipart_part(c.c, "", {{"HX-Trigger", "mp-done"}}) }
			stream.multipart_end(c.c)
			return
		}
		buf: [24]byte
		id := strconv.write_int(buf[:], i64(c.next), 10)
		if !stream.multipart_part(c.c, lab_views.count(c.next), {{"HX-Target", "#counts"}, {"HX-Swap", "beforeend"}, {"HX-Part-ID", id}}) { return }
		c.next += 1
		c.op = nbio.timeout_poly(c.every, c, count)
	}, c)
	free_all(context.temp_allocator)
}

// ---- numbers a spec reads back ------------------------------------------------------------------

// Connects per tag: the WebSocket room and the multipart feed count theirs, so a
// spec can tell a reconnect from a socket that stayed down. Bounded: the lab is
// public, and a spec's tags are random.
@(private)
tags: struct {
	mu:    guard.Mutex,
	count: map[string]int,
}

@(private)
note_connect :: proc(tag: string) -> int {
	guard.lock(&tags.mu)
	defer guard.unlock(&tags.mu)
	if tags.count == nil { tags.count = make(map[string]int, heap()) }
	if len(tags.count) >= 4096 {
		for k in tags.count { delete(k, heap()) }
		clear(&tags.count)
	}
	if tag not_in tags.count { tags.count[strings.clone(tag, heap())] = 0 }
	tags.count[tag] += 1
	return tags.count[tag]
}

// GET /lab/stats: JSON with the server's OS, the hub's cursor and loops, how many
// streams are open and how they ended, and the connects per tag.
stats :: proc(req: ^web.Request, res: ^web.Response) {
	n := hub.numbers()
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `{"os":"`)
	html.w(&b, ODIN_OS_STRING)
	html.w(&b, `","cursor":"`)
	html.w(&b, n.cursor)
	html.w(&b, `","loops":`)
	strings.write_int(&b, n.loops)
	html.w(&b, `,"loops_with_subs":`)
	strings.write_int(&b, n.loops_with_subs)
	html.w(&b, `,"open":`)
	strings.write_int(&b, stream.open_total())
	html.w(&b, `,"ended":{`)
	for why, i in web.Stream_End {
		if i > 0 { html.w(&b, ",") }
		html.w(&b, `"`)
		strings.write_string(&b, END_NAMES[why])
		html.w(&b, `":`)
		strings.write_u64(&b, stream.ended(why))
	}
	html.w(&b, `},"connects":{`)
	guard.lock(&tags.mu)
	first := true
	for tag, c in tags.count {
		if !first { html.w(&b, ",") }
		first = false
		html.w(&b, `"`)
		html.json_esc(&b, tag)
		html.w(&b, `":`)
		strings.write_int(&b, c)
	}
	guard.unlock(&tags.mu)
	html.w(&b, `}}`)
	web.respond_file(res, "stats.json", b.buf[:])
}

@(private, rodata)
END_NAMES := [web.Stream_End]string {
	.Ended       = "Ended",
	.Peer_Closed = "Peer_Closed",
	.Send_Failed = "Send_Failed",
	.Too_Slow    = "Too_Slow",
	.Shutdown    = "Shutdown",
	.Crashed     = "Crashed",
}

// Stream state outlives its request: the heap, never the request arena or
// whatever context.allocator a callback runs with.
@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

// ---- keys -----------------------------------------------------------------------------------

// A topic key or an id: 1-40 of [a-z0-9-], so it is safe anywhere it lands.
@(private)
plain :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 40 { return false }
	for c in transmute([]byte)s {
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '-':
		case:
			return false
		}
	}
	return true
}

@(private)
key_of :: proc(req: ^web.Request, name: string) -> (string, bool) {
	k := web.query_get(req, name)
	return k, plain(k)
}

// The query's key, or `fallback` when it is absent or not plain.
@(private)
key_or :: proc(req: ^web.Request, name, fallback: string) -> string {
	if k, ok := key_of(req, name); ok { return k }
	return fallback
}

@(private)
topic :: proc(family, key: string) -> string {
	return strings.concatenate({family, ":", key}, context.temp_allocator)
}

@(private)
split :: proc(t: string) -> (family, key: string) {
	i := strings.index_byte(t, ':')
	if i < 0 { return t, "" }
	return t[:i], t[i + 1:]
}

// The page's render-time cursor: `after` when the request names one (a spec
// replaying from a point), else the hub's now.
@(private)
after :: proc(req: ^web.Request) -> string {
	if a := web.query_get(req, "after"); a != "" { return a }
	return hub.cursor_now()
}
