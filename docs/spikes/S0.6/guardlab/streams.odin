package guardlab

// The routes, and the streams the drain test (S0.7) holds open. At shutdown the fork calls each
// stream's on_shutdown (F-9): SSE gets one event carrying `retry:` with per-client jitter (sent with
// `data:`, because a lone `retry:` is ignored) and then its terminal chunk; a WebSocket gets close
// 1012. The fork ends the stream after 2 s whatever the peer does.

import "core:fmt"
import "core:math/rand"
import "core:sync"

import http "vendor_fork:odin-http"

stats: struct {
	sse_open, ws_open: int,
}

heap :: proc() -> type_of(context.allocator) { return context.allocator }

routes :: proc(r: ^http.Router) {
	crash_init()
	http.route_get(r, "/healthz", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "ok")
	}))
	http.route_get(r, "/ui/ping", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "pong")
	}))
	http.route_get(r, "/stats", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, fmt.tprintf("sse=%d ws=%d", sync.atomic_load(&stats.sse_open), sync.atomic_load(&stats.ws_open)))
	}))
	http.route_get(r, "/crash/([%w_]+)", http.handler(crash_route))
	http.route_post(r, "/w", http.handler(store_write))
	http.route_get(r, "/r", http.handler(store_read))
	http.route_get(r, "/wal", http.handler(store_wal))
	http.route_get(r, "/sse", http.handler(sse_hold))
	http.route_get(r, "/ws", http.handler(ws_hold))
	http.route_post(r, "/body", http.handler(read_body))
	http.route_get(r, "/admin/shutdown", http.handler(proc(_: ^http.Request, res: ^http.Response) {
		http.respond_plain(res, "draining")
		http.server_shutdown(&server)
	}))
}

// The fork already ends every stream at shutdown; nothing else to tell on this loop.
drain_streams_on_this_loop :: proc() {}

sse_hold :: proc(req: ^http.Request, res: ^http.Response) {
	http.headers_set_unsafe(&res.headers, "content-type", "text/event-stream")
	http.headers_set_unsafe(&res.headers, "cache-control", "no-cache")
	http.headers_set_unsafe(&res.headers, "x-accel-buffering", "no")
	s := http.stream_begin(res, .Chunked, on_close = proc(s: ^http.Stream, why: http.Stream_End) {
		sync.atomic_sub(&stats.sse_open, 1)
	})
	s.on_shutdown = proc(s: ^http.Stream) {
		http.stream_write_string(s, fmt.tprintf("retry: %d\ndata: restarting\n\n", 500 + rand.int_max(2500)))
	}
	sync.atomic_add(&stats.sse_open, 1)
	http.stream_write_string(s, ": open\n\n")
}

ws_hold :: proc(req: ^http.Request, res: ^http.Response) {
	w := ws_upgrade(req, res, proc(w: ^Ws, text: bool, data: []byte) {
		ws_send(w, text, data)
	}, proc(w: ^Ws) {
		sync.atomic_sub(&stats.ws_open, 1)
	})
	if w == nil { return }
	w.stream.on_shutdown = proc(s: ^http.Stream) { ws_close((^Ws)(s.user), 1012) }
	sync.atomic_add(&stats.ws_open, 1)
}

// POST /body: reads the body (the half-body case: a client that sends part of it and stops).
read_body :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, 1 << 20, res, proc(res: rawptr, body: http.Body, err: http.Body_Error) {
		res := (^http.Response)(res)
		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}
		http.respond_plain(res, fmt.tprintf("%d", len(body)))
	})
}
