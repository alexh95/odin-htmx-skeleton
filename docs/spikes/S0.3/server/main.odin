// Spike S0.3's server: the `platform/stream` and `platform/hub` prototypes on the fork, routes for
// 03's 29 contract checks, and pages that use hx-sse, hx-ws and hx-multipart as PLAN §9.1 says
// pages will. Throwaway; docs/spikes/S0.3.md says how to build and run it.
package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:nbio"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import http "fork:odin-http"
import "platform/hub"
import "platform/stream"

// htmx 4.0.0 and the three stream extensions, fetched and SHA-256 checked by prepare.sh, as one
// bundle loaded with `defer`: separate deferred files race htmx's init (04 §2.3; PLAN §12.1).
BUNDLE_JS ::
	"/* exts: sse ws hx-multipart */\n" +
	#load("static/htmx.min.js", string) + "\n;\n" +
	#load("static/hx-sse.min.js", string) + "\n;\n" +
	#load("static/hx-ws.min.js", string) + "\n;\n" +
	#load("static/hx-multipart.min.js", string) + "\n"

// The skeleton's policy without its pre-paint hash: this origin's scripts only, and `connect-src`
// falls back to 'self', which has to admit the page's own ws:// socket in every engine.
CSP :: "default-src 'self'; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

server:   http.Server
site_url: string // the Origin a WebSocket handshake must carry

heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

main :: proc() {
	context.logger = log.create_console_logger(.Info)

	port := 8199
	if len(os.args) > 1 { port, _ = strconv.parse_int(os.args[1], 10) }
	if p := os.get_env("PORT", context.temp_allocator); p != "" { port, _ = strconv.parse_int(p, 10) }
	threads := 4
	if t := os.get_env("THREADS", context.temp_allocator); t != "" { threads, _ = strconv.parse_int(t, 10) }
	site_url = os.get_env("SITE_URL", context.allocator)
	if site_url == "" { site_url = fmt.aprintf("http://127.0.0.1:%d", port) }
	stats.connects = make(map[string]int, heap())
	stats.seen = make(map[string][dynamic]string, heap())
	hub.init()

	r: http.Router
	http.router_init(&r)
	route_get :: proc(r: ^http.Router, p: string, h: http.Handle_Proc) { http.route_get(r, p, http.handler(h)) }
	route_post :: proc(r: ^http.Router, p: string, h: http.Handle_Proc) { http.route_post(r, p, http.handler(h)) }
	route_get(&r, "/healthz", proc(_: ^http.Request, res: ^http.Response) { http.respond_plain(res, "ok") })
	route_get(&r, "/stats", page_stats)
	route_get(&r, "/static/bundle.js", proc(_: ^http.Request, res: ^http.Response) {
		http.respond_file_content(res, "bundle.js", transmute([]byte)string(BUNDLE_JS))
	})
	route_get(&r, "/", page_index)
	route_get(&r, "/p/live", page_live)
	route_get(&r, "/p/chat", page_chat)
	route_get(&r, "/p/mp", page_mp)
	route_get(&r, "/p/blank", proc(_: ^http.Request, res: ^http.Response) {
		b := strings.builder_make(context.temp_allocator)
		page_open(&b, "blank")
		page_close(res, &b)
	})
	route_get(&r, "/frag/feed", proc(req: ^http.Request, res: ^http.Response) {
		b := strings.builder_make(context.temp_allocator)
		w(&b, `<p class="refetched">refetched `)
		esc(&b, q(req, "t"))
		w(&b, `</p>`)
		http.respond_html(res, strings.to_string(b))
	})
	route_get(&r, "/events", sse_events)
	route_get(&r, "/sse/bus", sse_events)
	route_get(&r, "/sse/tick", sse_tick)
	route_post(&r, "/sse/tick", sse_tick)
	route_post(&r, "/publish", publish_handler)
	route_post(&r, "/admin/close", proc(req: ^http.Request, res: ^http.Response) {
		hub.close_topic(q(req, "t"), u16(qint(req, "code", 1000)))
		http.respond(res, http.Status.No_Content)
	})
	route_post(&r, "/admin/shutdown", proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "bye")
		http.server_shutdown(&server)
	})
	route_get(&r, "/ws/echo", ws_echo)
	route_get(&r, "/ws/chat", ws_chat)
	route_get(&r, "/multipart", multipart_parts)
	route_get(&r, "/mp/count", multipart_count)

	// A producer that is not an event-loop thread, standing in for a worker or the games poller.
	producer := thread.create_and_start(proc() {
		for i := 1; !http.server_is_closing(&server); i += 1 {
			time.sleep(500 * time.Millisecond)
			hub.publish("bus", fmt.tprintf("<p>beat %d from the producer thread</p>", i))
			free_all(context.temp_allocator)
		}
	})

	opts := http.Default_Server_Opts
	opts.thread_count = threads
	opts.on_thread_init = proc(_: ^http.Server, _: int) { hub.thread_init() }
	opts.on_thread_shutdown = proc(_: ^http.Server, _: int) { hub.thread_shutdown() }
	address: net.Address = net.IP4_Loopback
	if os.get_env("BIND_ALL", context.temp_allocator) != "" { address = net.IP4_Any }
	log.infof("listening on port %d with %d threads, SITE_URL %s", port, threads, site_url)
	err := http.listen_and_serve(&server, http.router_handler(&r), net.Endpoint{address = address, port = port}, opts)
	thread.join(producer)
	log.infof("server stopped: %v", err)
}

// ---- small helpers -----------------------------------------------------------------------------

w :: proc(b: ^strings.Builder, s: string) { strings.write_string(b, s) }

esc :: proc(b: ^strings.Builder, s: string) {
	for c in transmute([]byte)s {
		switch c {
		case '<':  w(b, "&lt;")
		case '>':  w(b, "&gt;")
		case '&':  w(b, "&amp;")
		case '"':  w(b, "&quot;")
		case '\'': w(b, "&#39;")
		case:      strings.write_byte(b, c)
		}
	}
}

json_str :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for c in transmute([]byte)s {
		switch c {
		case '"', '\\': strings.write_byte(b, '\\'); strings.write_byte(b, c)
		case 0 ..< 0x20: fmt.sbprintf(b, "\\u%04x", c)
		case:           strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
}

q :: proc(req: ^http.Request, key: string) -> string {
	v, _ := http.query_get_percent_decoded(req.url, key)
	return v
}

qint :: proc(req: ^http.Request, key: string, def: int) -> int {
	if v, ok := strconv.parse_int(q(req, key), 10); ok { return v }
	return def
}

itoa :: proc(n: int) -> string { return fmt.tprintf("%d", n) }

// ---- stats: what the specs read back ------------------------------------------------------------

stats: struct {
	open, opened: int,                   // atomic
	ended:        [http.Stream_End]int,  // atomic
	mu:           sync.Mutex,
	connects:     map[string]int,        // per `tag` query value: the specs count reconnects
	seen:         map[string][dynamic]string, // per tag: the resume headers each connect carried
}

stream_opened :: proc() {
	sync.atomic_add(&stats.open, 1)
	sync.atomic_add(&stats.opened, 1)
}

stream_ended :: proc(why: http.Stream_End) {
	sync.atomic_sub(&stats.open, 1)
	sync.atomic_add(&stats.ended[why], 1)
}

// Returns how many connects this tag has had, this one included.
note_connect :: proc(tag, what: string) -> int {
	if tag == "" { return 0 }
	sync.lock(&stats.mu)
	defer sync.unlock(&stats.mu)
	if tag not_in stats.connects {
		key := strings.clone(tag, heap())
		stats.connects[key] = 0
		stats.seen[key] = make([dynamic]string, heap())
	}
	stats.connects[tag] += 1
	list := stats.seen[tag]
	append(&list, strings.clone(what, heap()))
	stats.seen[tag] = list
	return stats.connects[tag]
}

page_stats :: proc(_: ^http.Request, res: ^http.Response) {
	n := hub.numbers()
	b := strings.builder_make(context.temp_allocator)
	w(&b, `{"os":`); json_str(&b, ODIN_OS_STRING)
	fmt.sbprintf(&b, `,"epoch":%d,"seq":%d,"loops":%d,"loops_with_subs":%d,"open":%d,"opened":%d`,
		n.epoch, n.seq, n.loops, n.loops_with_subs, sync.atomic_load(&stats.open), sync.atomic_load(&stats.opened))
	w(&b, `,"ended":{`)
	for why in http.Stream_End {
		if why != .Ended { w(&b, ",") }
		json_str(&b, fmt.tprint(why))
		fmt.sbprintf(&b, ":%d", sync.atomic_load(&stats.ended[why]))
	}
	w(&b, `},"connects":{`)
	sync.lock(&stats.mu)
	first := true
	for tag, count in stats.connects {
		if !first { w(&b, ",") }
		first = false
		json_str(&b, tag)
		fmt.sbprintf(&b, ":%d", count)
	}
	w(&b, `},"seen":{`)
	first = true
	for tag, list in stats.seen {
		if !first { w(&b, ",") }
		first = false
		json_str(&b, tag)
		w(&b, ":[")
		for s, i in list {
			if i > 0 { w(&b, ",") }
			json_str(&b, s)
		}
		w(&b, "]")
	}
	sync.unlock(&stats.mu)
	w(&b, "}}")
	http.respond_file_content(res, "stats.json", b.buf[:])
}

// ---- SSE ----------------------------------------------------------------------------------------

// The layout stream (PLAN §9.1): /events?t=<topic>,<topic>&after=<epoch>-<seq>. /sse/bus is the
// same stream on the producer's topic, for 03's checks.
sse_events :: proc(req: ^http.Request, res: ^http.Response) {
	topics := make([dynamic]string, context.temp_allocator)
	t := q(req, "t")
	if req.url.path == "/sse/bus" || t == "" { t = "bus" }
	for topic in strings.split_iterator(&t, ",") {
		if topic != "" && len(topic) <= 64 { append(&topics, topic) }
	}
	lei, _ := http.headers_get_unsafe(req.headers, "last-event-id")
	after := q(req, "after")
	note_connect(q(req, "tag"), strings.concatenate({"last-event-id=", lei, " after=", after}, context.temp_allocator))

	s := stream.sse_begin(res, on_close = proc(s: ^http.Stream, why: http.Stream_End) {
		hub.unsubscribe((^hub.Sub)(s.user))
		stream_ended(why)
	})
	stream_opened()
	sub, _ := hub.subscribe(s, .Sse, topics[:], last_event_id = lei, after = after)
	s.user = sub
}

// /sse/tick?n=5&ms=200: a per-stream timer writes n events, then ends. Also a POST, the way a bot
// answers an hx-post with a stream.
Ticker :: struct {
	s:     ^http.Stream,
	op:    ^nbio.Operation,
	n, i:  int,
	every: time.Duration,
}

sse_tick :: proc(req: ^http.Request, res: ^http.Response) {
	t := new(Ticker, heap())
	t.n = qint(req, "n", 5)
	t.every = time.Duration(qint(req, "ms", 100)) * time.Millisecond
	t.s = stream.sse_begin(res, t, proc(s: ^http.Stream, why: http.Stream_End) {
		t := (^Ticker)(s.user)
		if t.op != nil { nbio.remove(t.op) }
		free(t, heap())
		stream_ended(why)
	})
	stream_opened()
	t.op = nbio.timeout_poly(t.every, t, tick)

	tick :: proc(_: ^nbio.Operation, t: ^Ticker) {
		t.op = nil // fired: no longer removable
		defer free_all(context.temp_allocator)
		t.i += 1
		if !http.stream_write_string(t.s, stream.sse_event(itoa(t.i), "", fmt.tprintf("<b>tick %d</b>", t.i))) { return }
		if t.n > 0 && t.i >= t.n {
			http.stream_end(t.s)
			return
		}
		t.op = nbio.timeout_poly(t.every, t, tick)
	}
}

// POST /publish?t=<topic>: the body, a fragment, to the topic's subscribers on every loop.
publish_handler :: proc(req: ^http.Request, res: ^http.Response) {
	Pending :: struct { res: ^http.Response, topic: string }
	p := new(Pending, context.temp_allocator) // http.body may finish on a later tick
	p.res, p.topic = res, q(req, "t")
	if p.topic == "" { p.topic = "bus" }
	http.body(req, 128 * 1024, p, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		p := (^Pending)(user)
		if err != nil {
			http.respond(p.res, http.body_error_status(err))
			return
		}
		hub.publish(p.topic, body)
		http.respond(p.res, http.Status.No_Content)
	})
}

// ---- WebSocket ----------------------------------------------------------------------------------

ws_echo :: proc(req: ^http.Request, res: ^http.Response) {
	wsock, _ := stream.ws_upgrade(req, res, site_url, proc(w: ^stream.Ws, text: bool, data: []byte) {
		stream.ws_send(w, text, data)
	}, proc(w: ^stream.Ws) { stream_ended(w.ended) })
	if wsock != nil { stream_opened() }
}

Room :: struct {
	sub:  ^hub.Sub,
	name: string,
}

// /ws/chat?room=<topic>&hello=1: hx-ws sends {...form values, headers}; the answer is an escaped OOB
// fragment that every socket in the room receives through the hub. With hello, the socket first
// gets a JSON envelope routed to #ws-status, as a room's snapshot would be.
ws_chat :: proc(req: ^http.Request, res: ^http.Response) {
	room := q(req, "room")
	if room == "" { room = "chat" }
	tag := q(req, "tag")
	n := note_connect(strings.concatenate({"ws:", tag}, context.temp_allocator) if tag != "" else "", "ws")
	wsock, _ := stream.ws_upgrade(req, res, site_url, proc(ws: ^stream.Ws, text: bool, data: []byte) {
		In :: struct { message: string }
		msg: In
		if !text || json.unmarshal(data, &msg, allocator = context.temp_allocator) != nil || msg.message == "" { return }
		b := strings.builder_make(context.temp_allocator)
		w(&b, `<div id="chat" hx-swap-oob="beforeend"><p>`)
		esc(&b, msg.message)
		w(&b, `</p></div>`)
		hub.publish((^Room)(ws.user).name, strings.to_string(b))
	}, proc(ws: ^stream.Ws) {
		r := (^Room)(ws.user)
		hub.unsubscribe(r.sub)
		delete(r.name, heap())
		free(r, heap())
		stream_ended(ws.ended)
	})
	if wsock == nil { return }
	stream_opened()
	r := new(Room, heap())
	r.name = strings.clone(room, heap())
	wsock.user = r
	r.sub, _ = hub.subscribe(wsock.stream, .Ws, {room}, ws = wsock)
	if q(req, "hello") != "" {
		b := strings.builder_make(context.temp_allocator)
		w(&b, `{"content":"<span class=\"hello\">connected `)
		w(&b, itoa(n))
		w(&b, `</span>","target":"#ws-status","swap":"innerHTML"}`)
		stream.ws_send_text(wsock, strings.to_string(b))
	}
}

// ---- multipart ----------------------------------------------------------------------------------

// /multipart?n=3&ms=100&end_ms=0: n parts `ms` apart, then the closing boundary `end_ms` after the
// last. Part 1 goes to #mp-a, part 2 is appended to #mp-b, part 3 has no HX-Target and lands in
// the request's own target.
Parts :: struct {
	s:        ^http.Stream,
	op:       ^nbio.Operation,
	b:        stream.Boundary,
	n, i:     int,
	every:    time.Duration,
	end_wait: time.Duration,
}

multipart_parts :: proc(req: ^http.Request, res: ^http.Response) {
	p := new(Parts, heap())
	p.n = qint(req, "n", 3)
	p.every = time.Duration(qint(req, "ms", 100)) * time.Millisecond
	p.end_wait = time.Duration(qint(req, "end_ms", 0)) * time.Millisecond
	p.s = stream.multipart_begin(res, &p.b, .Mixed, p, proc(s: ^http.Stream, why: http.Stream_End) {
		p := (^Parts)(s.user)
		if p.op != nil { nbio.remove(p.op) }
		free(p, heap())
		stream_ended(why)
	})
	stream_opened()
	p.op = nbio.timeout_poly(p.every, p, part)

	part :: proc(_: ^nbio.Operation, p: ^Parts) {
		p.op = nil
		defer free_all(context.temp_allocator)
		if p.i >= p.n {
			stream.multipart_end(p.s, &p.b)
			return
		}
		p.i += 1
		id := itoa(p.i)
		body := fmt.tprintf(`<p class="part" data-n="%d">part %d of %d</p>`, p.i, p.i, p.n)
		headers: []stream.Part_Header
		switch p.i {
		case 1:  headers = {{"HX-Target", "#mp-a"}, {"HX-Part-ID", id}}
		case 2:  headers = {{"HX-Target", "#mp-b"}, {"HX-Swap", "beforeend"}, {"HX-Part-ID", id}}
		case:    headers = {{"HX-Part-ID", id}}
		}
		if !stream.multipart_part(p.s, &p.b, body, headers) { return }
		p.op = nbio.timeout_poly(p.every if p.i < p.n else p.end_wait, p, part)
	}
}

// /mp/count?n=2&max=6: an hx-multipart:connect feed. Each connect sends the next n counts after
// the HX-Last-Part-ID it carries, then ends, and hx-multipart reconnects; past `max` a last part
// triggers `mp-done`, which the element's hx-multipart:close answers.
Counter :: struct {
	s:         ^http.Stream,
	op:        ^nbio.Operation,
	b:         stream.Boundary,
	next, end: int,
	done:      bool,
}

multipart_count :: proc(req: ^http.Request, res: ^http.Response) {
	lpi, _ := http.headers_get_unsafe(req.headers, "hx-last-part-id")
	note_connect(q(req, "tag"), strings.concatenate({"hx-last-part-id=", lpi}, context.temp_allocator))
	last, _ := strconv.parse_int(lpi, 10)
	max := qint(req, "max", 6)
	c := new(Counter, heap())
	c.next = last + 1
	c.end = min(last + qint(req, "n", 2), max)
	c.done = c.end >= max
	c.s = stream.multipart_begin(res, &c.b, .Mixed, c, proc(s: ^http.Stream, why: http.Stream_End) {
		c := (^Counter)(s.user)
		if c.op != nil { nbio.remove(c.op) }
		free(c, heap())
		stream_ended(why)
	})
	stream_opened()
	c.op = nbio.timeout_poly(100 * time.Millisecond, c, count)

	count :: proc(_: ^nbio.Operation, c: ^Counter) {
		c.op = nil
		defer free_all(context.temp_allocator)
		if c.next > c.end {
			if c.done { stream.multipart_part(c.s, &c.b, "", {{"HX-Trigger", "mp-done"}}) }
			stream.multipart_end(c.s, &c.b)
			return
		}
		id := itoa(c.next)
		body := fmt.tprintf(`<p id="c-%d" class="count">%d</p>`, c.next, c.next)
		if !stream.multipart_part(c.s, &c.b, body, {{"HX-Target", "#counts"}, {"HX-Swap", "beforeend"}, {"HX-Part-ID", id}}) { return }
		c.next += 1
		c.op = nbio.timeout_poly(100 * time.Millisecond, c, count)
	}
}

// ---- pages --------------------------------------------------------------------------------------

page_open :: proc(b: ^strings.Builder, title: string) {
	w(b, `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>`)
	esc(b, title)
	// The allowlist names exactly the bundle's extensions (registration names, 04 §2.2).
	w(b, `</title><meta name="htmx-config" content='{"extensions":"sse, ws, hx-multipart"}'>`)
	w(b, `<script src="/static/bundle.js" defer></script></head><body>`)
}

// The layout's one SSE stream (PLAN §9.1): the page's topics and the render-time cursor.
live_div :: proc(b: ^strings.Builder, topics, tag, after: string) {
	w(b, `<div id="live" hx-sse:connect="/events?t=`)
	esc(b, topics)
	w(b, `&amp;tag=`)
	esc(b, tag)
	w(b, `&amp;after=`)
	esc(b, after)
	w(b, `"></div>`)
}

page_close :: proc(res: ^http.Response, b: ^strings.Builder) {
	w(b, `</body></html>`)
	http.headers_set_unsafe(&res.headers, "content-security-policy", CSP)
	http.respond_html(res, strings.to_string(b^))
}

after_or_now :: proc(req: ^http.Request) -> string {
	after := q(req, "after")
	return after if after != "" else hub.cursor_now()
}

// /p/live?t=<topic>&tag=<tag>[&after=<cursor>]: the layout stream feeding a live log by OOB, a
// fragment refetched on `resync`, and a button whose hx-post answers with a stream.
page_live :: proc(req: ^http.Request, res: ^http.Response) {
	t := q(req, "t")
	b := strings.builder_make(context.temp_allocator)
	page_open(&b, "live")
	live_div(&b, t, q(req, "tag"), after_or_now(req))
	w(&b, `<main><h1>live</h1><div id="feed" role="log"></div>`)
	w(&b, `<div id="refetch" hx-get="/frag/feed?t=`)
	esc(&b, t)
	w(&b, `" hx-trigger="resync from:body"></div>`)
	w(&b, `<button id="ask" hx-post="/sse/tick?n=3&amp;ms=150" hx-target="#tokens" hx-swap="beforeend">Ask</button>`)
	w(&b, `<div id="tokens" role="log"></div></main>`)
	page_close(res, &b)
}

// /p/chat?room=<topic>&tag=<tag>: one hx-ws:connect, inside the swapped region.
page_chat :: proc(req: ^http.Request, res: ^http.Response) {
	b := strings.builder_make(context.temp_allocator)
	page_open(&b, "chat")
	room_section(&b, q(req, "room"), q(req, "tag"))
	page_close(res, &b)
}

room_section :: proc(b: ^strings.Builder, room, tag: string) {
	w(b, `<section id="room" hx-ws:connect="/ws/chat?room=`)
	esc(b, room)
	w(b, `&amp;tag=`)
	esc(b, tag)
	w(b, `&amp;hello=1"><p id="ws-status"></p><div id="chat" role="log"></div>`)
	w(b, `<form id="say" hx-ws:send><textarea name="message" id="message"></textarea><button id="send">Send</button></form></section>`)
}

// /p/mp?tag=<tag>[&count=1]: a one-shot multipart request, and the hx-multipart:connect feed.
page_mp :: proc(req: ^http.Request, res: ^http.Response) {
	b := strings.builder_make(context.temp_allocator)
	page_open(&b, "multipart")
	mp_panel(&b, q(req, "tag"), q(req, "count") != "")
	page_close(res, &b)
}

mp_panel :: proc(b: ^strings.Builder, tag: string, count: bool) {
	w(b, `<section id="mp"><button id="build" hx-get="/multipart?n=3&amp;ms=300&amp;end_ms=1500" hx-target="#mp-default">Build</button>`)
	w(b, `<button id="slow" hx-get="/multipart?n=1&amp;ms=3000" hx-target="#mp-default">Slow</button>`)
	w(b, `<div id="mp-a"></div><div id="mp-b" role="log"></div><div id="mp-default"></div>`)
	if count {
		w(b, `<div id="counter" hx-multipart:connect="/mp/count?n=2&amp;max=6&amp;tag=`)
		esc(b, tag)
		w(b, `" hx-multipart:close="mp-done"></div>`)
	}
	w(b, `<div id="counts" role="log"></div></section>`)
}

// /?tag=<tag>&room=<room>: the page contract in one page: the layout stream, one socket in the
// main region, and a multipart panel.
page_index :: proc(req: ^http.Request, res: ^http.Response) {
	tag, room := q(req, "tag"), q(req, "room")
	if room == "" { room = "lobby" }
	b := strings.builder_make(context.temp_allocator)
	page_open(&b, "S0.3")
	live_div(&b, strings.concatenate({"notice:", tag}, context.temp_allocator), tag, after_or_now(req))
	w(&b, `<main><h1>S0.3</h1><div id="feed" role="log"></div>`)
	w(&b, `<div id="refetch" hx-get="/frag/feed?t=notice" hx-trigger="resync from:body"></div>`)
	room_section(&b, room, tag)
	mp_panel(&b, tag, false)
	w(&b, `</main>`)
	page_close(res, &b)
}
