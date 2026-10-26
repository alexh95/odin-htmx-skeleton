package main

// Prototype: SSE, WebSocket and multipart/mixed streaming on odin-http (fac113f + stream.odin),
// one port, N event-loop threads, a cross-thread hub. Throwaway; see docs/research/03-realtime.md.
//
// S0.8 changes: every SSE event, multipart part and /ws/tick frame carries `t=<unix µs>`, the
// server's clock just before stream_write, so a client on the same box measures write-to-arrival.
// `pad=<bytes>` adds a compressible HTML fragment, `ms=` sets the interval, `nt=1` sends
// `Cache-Control: no-cache, no-transform`. `/now` answers the clock for offset calibration and
// `/page` is the same-origin page for the browser run (`pad=` makes it a compressible HTML body).

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

import http "vendor_fork:odin-http"

server: http.Server

stats: struct {
	open:   int,
	opened: int,
	ended:  [http.Stream_End]int,
}

main :: proc() {
	context.logger = log.create_console_logger(.Info)

	port := 8099
	if len(os.args) > 1 { port, _ = strconv.parse_int(os.args[1], 10) }
	threads := 4
	if t := os.get_env("THREADS", context.temp_allocator); t != "" { threads, _ = strconv.parse_int(t, 10) }

	r: http.Router
	http.router_init(&r)
	http.route_get(&r, "/healthz", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "ok")
	}))
	http.route_get(&r, "/stats", http.handler(page_stats))
	http.route_get(&r, "/sse/tick", http.handler(sse_tick))
	http.route_get(&r, "/sse/bus", http.handler(sse_bus))
	http.route_post(&r, "/publish", http.handler(publish_handler))
	http.route_get(&r, "/ws/echo", http.handler(ws_echo))
	http.route_get(&r, "/ws/chat", http.handler(ws_chat))
	http.route_get(&r, "/ws/tick", http.handler(ws_tick))
	http.route_get(&r, "/multipart", http.handler(multipart))
	http.route_get(&r, "/now", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.headers_set_unsafe(&res.headers, "cache-control", "no-store")
		http.respond_plain(res, fmt.tprintf("%d", now_us()))
	}))
	http.route_get(&r, "/page", http.handler(proc(req: ^http.Request, res: ^http.Response) {
		html := strings.concatenate({"<!doctype html><meta charset=utf-8><title>S0.8</title><ul>", padding(query_int(req, "pad", 0)), "</ul>"}, context.temp_allocator)
		http.respond_html(res, html)
	}))
	http.route_get(&r, "/admin/shutdown", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "bye")
		http.server_shutdown(&server)
	}))

	// A producer that is not an event-loop thread: stands in for llama.cpp, a Pi console, a job.
	producer := thread.create_and_start(proc() {
		for i := 1; !sync.atomic_load(&server.closing.raw); i += 1 {
			time.sleep(500 * time.Millisecond)
			publish(.Bus, fmt.tprintf("<p>beat %d from the producer thread</p>", i))
			free_all(context.temp_allocator)
		}
	})

	opts := http.Default_Server_Opts
	opts.thread_count = threads
	log.infof("listening on 127.0.0.1:%d with %d threads", port, threads)
	address: net.Address = net.IP4_Loopback
	if os.get_env("BIND_ALL", context.temp_allocator) != "" { address = net.IP4_Any }
	err := http.listen_and_serve(&server, http.router_handler(&r), net.Endpoint{address = address, port = port}, opts)
	thread.join(producer)
	log.infof("server stopped: %v, streams ended %v", err, stats.ended)
}

counted :: proc(why: http.Stream_End) {
	sync.atomic_sub(&stats.open, 1)
	sync.atomic_add(&stats.ended[why], 1)
}

stream_opened :: proc() {
	sync.atomic_add(&stats.open, 1)
	sync.atomic_add(&stats.opened, 1)
}

page_stats :: proc(_: ^http.Request, res: ^http.Response) {
	sync.lock(&hub.mu)
	loops := hub.n
	sync.unlock(&hub.mu)
	http.respond_plain(res, fmt.tprintf("open=%d opened=%d loops_with_subs=%d ended=%v\n", sync.atomic_load(&stats.open), sync.atomic_load(&stats.opened), loops, stats.ended))
}

sse_headers :: proc(res: ^http.Response, no_transform := false) {
	http.headers_set_unsafe(&res.headers, "content-type", "text/event-stream")
	stream_headers(res, no_transform)
}

stream_headers :: proc(res: ^http.Response, no_transform: bool) {
	http.headers_set_unsafe(&res.headers, "cache-control", "no-cache, no-transform" if no_transform else "no-cache")
	http.headers_set_unsafe(&res.headers, "x-accel-buffering", "no") // nginx (NPM) would buffer otherwise
}

now_us :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1000 }

// A compressible HTML fragment of about n bytes, like a list a stream would swap in.
padding :: proc(n: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	for k := 0; strings.builder_len(b) < n; k += 1 {
		fmt.sbprintf(&b, `<li class="row" id="r-%d">item %d</li>`, k, k)
	}
	return strings.to_string(b)
}

// What each event, part and frame carries: the write time first, so the client parses one prefix.
stamped :: proc(i: int, pad: int) -> string {
	return fmt.tprintf("t=%d i=%d %s", now_us(), i, padding(pad))
}

query_int :: proc(req: ^http.Request, key: string, def: int) -> int {
	q := req.url.query
	for kv in strings.split_iterator(&q, "&") {
		if strings.has_prefix(kv, key) && len(kv) > len(key) && kv[len(key)] == '=' {
			if v, ok := strconv.parse_int(kv[len(key) + 1:], 10); ok { return v }
		}
	}
	return def
}

// ---- /sse/tick: a per-stream timer writes n events, then ends (n=0: forever) --------------

Ticker :: struct {
	stream: ^http.Stream,
	op:     ^nbio.Operation,
	n, i:   int,
	pad:    int,
	every:  time.Duration,
}

sse_tick :: proc(req: ^http.Request, res: ^http.Response) {
	sse_headers(res, query_int(req, "nt", 0) == 1)
	t := new(Ticker, heap())
	t.n = query_int(req, "n", 5)
	t.pad = query_int(req, "pad", 0)
	t.every = time.Duration(query_int(req, "ms", 100)) * time.Millisecond
	t.stream = http.stream_begin(res, .Chunked, t, on_close = proc(s: ^http.Stream, why: http.Stream_End) {
		t := (^Ticker)(s.user)
		if t.op != nil { nbio.remove(t.op) }
		free(t, heap())
		counted(why)
	})
	stream_opened()
	t.op = nbio.timeout_poly(t.every, t, tick)

	tick :: proc(_: ^nbio.Operation, t: ^Ticker) {
		t.op = nil // fired: no longer removable, and the close below must not try
		defer free_all(context.temp_allocator)
		t.i += 1
		s := t.stream
		if !http.stream_write_string(s, sse_event(u64(t.i), "", stamped(t.i, t.pad))) { return }
		if t.n > 0 && t.i >= t.n {
			http.stream_end(s)
			return
		}
		t.op = nbio.timeout_poly(t.every, t, tick)
	}
}

// ---- /sse/bus: the hub's Bus topic, resumable with Last-Event-ID ---------------------------

sse_bus :: proc(req: ^http.Request, res: ^http.Response) {
	last: u64
	if v, ok := http.headers_get_unsafe(req.headers, "last-event-id"); ok { last, _ = strconv.parse_u64(v, 10) }
	sse_headers(res)
	s := http.stream_begin(res, .Chunked, on_close = proc(s: ^http.Stream, why: http.Stream_End) {
		unsubscribe((^Sub)(s.user))
		counted(why)
	})
	stream_opened()
	s.user = subscribe(s, .Bus, .Sse, last)
}

// POST /publish: publish the body (fragment) to Bus; runs on whichever thread got the request.
publish_handler :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, 64 * 1024, res, proc(res: rawptr, body: http.Body, err: http.Body_Error) {
		res := (^http.Response)(res)
		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}
		publish(.Bus, body)
		http.respond(res, http.Status.No_Content)
	})
}

// ---- WebSocket routes ----------------------------------------------------------------------

ws_echo :: proc(req: ^http.Request, res: ^http.Response) {
	w := ws_upgrade(req, res, proc(w: ^Ws, text: bool, data: []byte) {
		ws_send(w, text, data)
	}, proc(w: ^Ws) { counted(.Ended) })
	if w != nil { stream_opened() }
}

// htmx's hx-ws sends {"message": "...", "headers": {...}}; the answer is an OOB fragment that
// every chat socket on every thread receives through the hub.
ws_chat :: proc(req: ^http.Request, res: ^http.Response) {
	w := ws_upgrade(req, res, proc(w: ^Ws, text: bool, data: []byte) {
		In :: struct { message: string }
		msg: In
		if !text || json.unmarshal(data, &msg, allocator = context.temp_allocator) != nil { return }
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, `<div id="chat" hx-swap-oob="beforeend"><p>`)
		strings.write_string(&b, html_escape(msg.message))
		strings.write_string(&b, `</p></div>`)
		publish(.Chat, strings.to_string(b))
	}, proc(w: ^Ws) {
		unsubscribe((^Sub)(w.user))
		counted(.Ended)
	})
	if w == nil { return }
	stream_opened()
	w.user = subscribe(w.stream, .Chat, .Ws)
}

// ---- /ws/tick: n stamped text frames, server to client, then a 1000 close ---------------------

Ws_Ticker :: struct {
	ws:    ^Ws,
	op:    ^nbio.Operation,
	n, i:  int,
	pad:   int,
	every: time.Duration,
}

ws_tick :: proc(req: ^http.Request, res: ^http.Response) {
	t := new(Ws_Ticker, heap())
	t.n = query_int(req, "n", 5)
	t.pad = query_int(req, "pad", 0)
	t.every = time.Duration(query_int(req, "ms", 100)) * time.Millisecond
	w := ws_upgrade(req, res, proc(w: ^Ws, text: bool, data: []byte) {}, proc(w: ^Ws) {
		t := (^Ws_Ticker)(w.user)
		if t.op != nil { nbio.remove(t.op) }
		free(t, heap())
		counted(.Ended)
	}, t)
	if w == nil {
		free(t, heap())
		return
	}
	t.ws = w
	stream_opened()
	t.op = nbio.timeout_poly(t.every, t, frame)

	frame :: proc(_: ^nbio.Operation, t: ^Ws_Ticker) {
		t.op = nil
		defer free_all(context.temp_allocator)
		t.i += 1
		msg := stamped(t.i, t.pad)
		if !ws_send(t.ws, true, transmute([]byte)msg) { return }
		if t.i >= t.n {
			ws_close(t.ws, 1000)
			return
		}
		t.op = nbio.timeout_poly(t.every, t, frame)
	}
}

html_escape :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]byte)s {
		switch c {
		case '<':  strings.write_string(&b, "&lt;")
		case '>':  strings.write_string(&b, "&gt;")
		case '&':  strings.write_string(&b, "&amp;")
		case '"':  strings.write_string(&b, "&quot;")
		case '\'': strings.write_string(&b, "&#39;")
		case:      strings.write_byte(&b, c)
		}
	}
	return strings.to_string(b)
}

// ---- /multipart: multipart/mixed parts over time ------------------------------------------
//
// Each part carries Content-Length, so the client can swap it as soon as its last byte arrives
// instead of waiting for the next boundary to prove the part is over.

BOUNDARY :: "hx-part-7f3a"

Parts :: struct {
	stream: ^http.Stream,
	op:     ^nbio.Operation,
	n, i:   int,
	pad:    int,
	every:  time.Duration,
}

multipart :: proc(req: ^http.Request, res: ^http.Response) {
	http.headers_set_unsafe(&res.headers, "content-type", "multipart/mixed; boundary=" + BOUNDARY)
	stream_headers(res, query_int(req, "nt", 0) == 1)
	p := new(Parts, heap())
	p.n = query_int(req, "n", 3)
	p.pad = query_int(req, "pad", 0)
	p.every = time.Duration(query_int(req, "ms", 100)) * time.Millisecond
	p.stream = http.stream_begin(res, .Chunked, p, on_close = proc(s: ^http.Stream, why: http.Stream_End) {
		p := (^Parts)(s.user)
		if p.op != nil { nbio.remove(p.op) }
		free(p, heap())
		counted(why)
	})
	stream_opened()
	p.op = nbio.timeout_poly(p.every, p, part)

	part :: proc(_: ^nbio.Operation, p: ^Parts) {
		p.op = nil
		defer free_all(context.temp_allocator)
		p.i += 1
		body := stamped(p.i, p.pad)
		head := fmt.tprintf("--%s\r\nContent-Type: text/html\r\nContent-Length: %d\r\nHX-Target: #status\r\nHX-Part-ID: %d\r\n\r\n", BOUNDARY, len(body), p.i)
		if !http.stream_write_string(p.stream, strings.concatenate({head, body, "\r\n"}, context.temp_allocator)) { return }
		if p.i >= p.n {
			http.stream_write_string(p.stream, "--" + BOUNDARY + "--\r\n")
			http.stream_end(p.stream)
			return
		}
		p.op = nbio.timeout_poly(p.every, p, part)
	}
}
