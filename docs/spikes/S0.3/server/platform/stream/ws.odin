package stream

// WebSocket (RFC 6455) on an upgraded stream, server side only: client frames must be masked, ours
// are not. No extensions are negotiated (so every RSV bit must be zero) and no subprotocols.

import "base:runtime"
import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:nbio"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import http "fork:odin-http"

WS_GUID        :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX_MESSAGE :: 64 * 1024 // PLAN §9.4: a message past it closes 1009

WS_CONT  :: u8(0x0)
WS_TEXT  :: u8(0x1)
WS_BIN   :: u8(0x2)
WS_CLOSE :: u8(0x8)
WS_PING  :: u8(0x9)
WS_PONG  :: u8(0xA)

// Close codes the starter sends (PLAN §9.4). hx-ws reconnects on 1001, 1005, 1006 and 1011-1014.
WS_NORMAL       :: u16(1000)
WS_PROTOCOL     :: u16(1002)
WS_BAD_DATA     :: u16(1007)
WS_POLICY       :: u16(1008) // revoked auth, a kick, a flood: the client stops
WS_TOO_BIG      :: u16(1009) // the client stops
WS_INTERNAL     :: u16(1011) // a pure-zone crash in this stream
WS_RESTART      :: u16(1012) // drain and restart
WS_TRY_AGAIN    :: u16(1013) // a slow consumer

Ws_Message_Proc :: #type proc(w: ^Ws, text: bool, data: []byte)
Ws_Gone_Proc    :: #type proc(w: ^Ws)

Ws :: struct {
	stream:     ^http.Stream,
	frag:       [dynamic]byte,
	frag_op:    u8,
	closing:    bool, // our close frame is queued
	ended:      http.Stream_End, // why the stream ended, set before on_gone
	on_message: Ws_Message_Proc,
	on_gone:    Ws_Gone_Proc,
	user:       rawptr,
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

Upgrade_Error :: enum u8 { None, Not_Upgrade, Bad_Version, Bad_Key, Foreign_Origin }

// Answers the upgrade, or refuses it with a plain status, and returns the socket's Ws (nil when
// refused). `site_url` is the origin this host serves (SITE_URL, or SITE_URL_LAB on a lab host).
//
// The Origin check is the handshake's own: an upgrade is a GET, so the `front` chain's cross-site
// guard lets it through, and browsers send no Sec-Fetch-* on it (04 §4.4). Cookies ride along and
// the same-origin policy doesn't cover WebSockets, so a page on another site could otherwise open
// a socket as the user (cross-site WebSocket hijacking). A request without Origin is not from a
// browser and passes, as the cross-site guard lets such requests pass.
ws_upgrade :: proc(
	req: ^http.Request,
	res: ^http.Response,
	site_url: string,
	on_message: Ws_Message_Proc,
	on_gone: Ws_Gone_Proc = nil,
	user: rawptr = nil,
) -> (w: ^Ws, err: Upgrade_Error) {
	h := req.headers
	upgrade, _    := http.headers_get_unsafe(h, "upgrade")
	connection, _ := http.headers_get_unsafe(h, "connection")
	version, _    := http.headers_get_unsafe(h, "sec-websocket-version")
	key, _        := http.headers_get_unsafe(h, "sec-websocket-key")

	if !has_token(upgrade, "websocket") || !has_token(connection, "upgrade") {
		http.respond(res, http.Status.Bad_Request)
		return nil, .Not_Upgrade
	}
	if version != "13" {
		http.headers_set_unsafe(&res.headers, "sec-websocket-version", "13")
		http.respond(res, http.Status.Upgrade_Required)
		return nil, .Bad_Version
	}
	if raw, derr := base64.decode(key, allocator = context.temp_allocator); derr != nil || len(raw) != 16 {
		http.respond(res, http.Status.Bad_Request)
		return nil, .Bad_Key
	}
	if origin, ok := http.headers_get_unsafe(h, "origin"); ok && origin != site_url {
		http.respond(res, http.Status.Forbidden)
		return nil, .Foreign_Origin
	}

	ctx: sha1.Context
	digest: [sha1.DIGEST_SIZE]byte
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]byte)key)
	sha1.update(&ctx, transmute([]byte)string(WS_GUID))
	sha1.final(&ctx, digest[:])
	http.headers_set_unsafe(&res.headers, "upgrade", "websocket")
	http.headers_set_unsafe(&res.headers, "connection", "Upgrade")
	http.headers_set_unsafe(&res.headers, "sec-websocket-accept", base64.encode(digest[:], allocator = context.temp_allocator))

	w = new(Ws, heap())
	w.frag.allocator = heap()
	w.on_message, w.on_gone, w.user = on_message, on_gone, user
	w.stream = http.stream_begin(res, .Raw, w, ws_on_data, ws_on_close)
	w.stream.on_shutdown = proc(s: ^http.Stream) { ws_close((^Ws)(s.user), WS_RESTART) }
	return w, .None
}

ws_send :: proc(w: ^Ws, text: bool, data: []byte) -> bool {
	return ws_write_frame(w, ws_frame(WS_TEXT if text else WS_BIN, data))
}

ws_send_text :: proc(w: ^Ws, text: string) -> bool {
	return ws_write_frame(w, ws_frame(WS_TEXT, transmute([]byte)text))
}

// Writes a frame encoded once for many sockets (the hub's fan-out). A frame that would pass the
// stream's cap closes a slow consumer with 1013 instead (PLAN §9.4), with room kept for the close
// frame, and gives it WS_SLOW_DEADLINE to take what's queued before the fork cuts it off.
ws_write_frame :: proc(w: ^Ws, frame: string) -> bool {
	if w.closing { return false }
	if http.stream_would_overflow(w.stream, len(frame) + 64) {
		ws_close(w, WS_TRY_AGAIN, WS_SLOW_DEADLINE)
		return false
	}
	return http.stream_write_string(w.stream, frame)
}

WS_SLOW_DEADLINE :: 2 * time.Second

// Starts the closing handshake and hangs up once the frame is out (or at the deadline).
ws_close :: proc(w: ^Ws, code: u16, deadline: time.Duration = 0) {
	if w.closing { return }
	payload := [2]byte{byte(code >> 8), byte(code)}
	http.stream_write_string(w.stream, ws_frame(WS_CLOSE, payload[:]))
	w.closing = true
	http.stream_end(w.stream, deadline)
}

// One unmasked frame with FIN set, in the temp allocator.
ws_frame :: proc(op: u8, data: []byte) -> string {
	n := len(data)
	b := make([dynamic]byte, 0, n + 10, context.temp_allocator)
	append(&b, 0x80 | op)
	switch {
	case n < 126:   append(&b, byte(n))
	case n < 65536: append(&b, 126, byte(n >> 8), byte(n))
	case:
		append(&b, 127)
		for i := 7; i >= 0; i -= 1 { append(&b, byte(u64(n) >> (uint(i) * 8))) }
	}
	append(&b, ..data)
	return string(b[:])
}

@(private="file")
ws_on_close :: proc(s: ^http.Stream, why: http.Stream_End) {
	w := (^Ws)(s.user)
	w.closing = true
	w.ended = why
	if w.on_gone != nil { w.on_gone(w) }
	// Freed a tick later, like the stream: the frame parser may still be on the stack.
	nbio.next_tick_poly(w, proc(_: ^nbio.Operation, w: ^Ws) {
		delete(w.frag)
		free(w, heap())
	})
}

// 1004-1006 and 1015 are reserved for reports, never sent in a frame (RFC 6455 §7.4.1).
@(private="file")
valid_close_code :: proc(code: u16) -> bool {
	switch code {
	case 1000 ..= 1003, 1007 ..= 1014, 3000 ..= 4999: return true
	}
	return false
}

// Parses as many whole frames as `data` holds; the rest waits for the next read.
@(private="file")
ws_on_data :: proc(s: ^http.Stream, data: []byte) -> (consumed: int) {
	w := (^Ws)(s.user)
	if w.closing { return len(data) } // nothing after our close frame matters
	for !s.done && !w.closing {
		b := data[consumed:]
		if len(b) < 2 { return }
		fin    := b[0] & 0x80 != 0
		rsv    := b[0] & 0x70
		op     := b[0] & 0x0F
		masked := b[1] & 0x80 != 0
		plen   := u64(b[1] & 0x7F)
		pos    := 2
		if plen == 126 {
			if len(b) < 4 { return }
			plen, pos = u64(b[2]) << 8 | u64(b[3]), 4
		} else if plen == 127 {
			if len(b) < 10 { return }
			plen = 0
			for i in 0 ..< 8 { plen = plen << 8 | u64(b[2 + i]) }
			pos = 10
		}
		control := op & 0x8 != 0
		switch {
		case rsv != 0, !masked, control && (!fin || plen > 125), plen >> 63 != 0:
			ws_close(w, WS_PROTOCOL); return len(data)
		case plen > WS_MAX_MESSAGE:
			ws_close(w, WS_TOO_BIG); return len(data)
		}
		total := pos + 4 + int(plen)
		if len(b) < total { return }
		mask    := b[pos:][:4]
		payload := b[pos + 4:total]
		for i in 0 ..< len(payload) { payload[i] ~= mask[i & 3] }
		consumed += total

		switch op {
		case WS_CONT:
			if w.frag_op == 0 { ws_close(w, WS_PROTOCOL); return len(data) }
			append(&w.frag, ..payload)
			if len(w.frag) > WS_MAX_MESSAGE { ws_close(w, WS_TOO_BIG); return len(data) }
			if fin {
				deliver_message(w, w.frag_op, w.frag[:])
				clear(&w.frag)
				w.frag_op = 0
			}
		case WS_TEXT, WS_BIN:
			if w.frag_op != 0 { ws_close(w, WS_PROTOCOL); return len(data) }
			if fin {
				deliver_message(w, op, payload)
			} else {
				w.frag_op = op
				append(&w.frag, ..payload)
			}
		case WS_CLOSE:
			code := WS_NORMAL
			if len(payload) == 1 { ws_close(w, WS_PROTOCOL); return len(data) }
			if len(payload) >= 2 {
				code = u16(payload[0]) << 8 | u16(payload[1])
				if !valid_close_code(code) { ws_close(w, WS_PROTOCOL); return len(data) }
				if !utf8.valid_string(string(payload[2:])) { ws_close(w, WS_BAD_DATA); return len(data) }
			}
			ws_close(w, code) // the echo
			return len(data)
		case WS_PING:
			http.stream_write_string(s, ws_frame(WS_PONG, payload))
		case WS_PONG:
		case:
			ws_close(w, WS_PROTOCOL); return len(data)
		}
	}
	return
}

@(private="file")
deliver_message :: proc(w: ^Ws, op: u8, data: []byte) {
	if op == WS_TEXT && !utf8.valid_string(string(data)) {
		ws_close(w, WS_BAD_DATA)
		return
	}
	if w.on_message != nil && !w.closing { w.on_message(w, op == WS_TEXT, data) }
}

@(private="file")
has_token :: proc(value, token: string) -> bool {
	v := value
	for part in strings.split_iterator(&v, ",") {
		if strings.equal_fold(strings.trim_space(part), token) { return true }
	}
	return false
}
