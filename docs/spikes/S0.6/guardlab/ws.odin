package guardlab

// ---- WebSocket (RFC 6455) on top of an upgraded http.Stream (from 03's prototype) ------------
//
// Server side only: frames from the client must be masked, ours are not. No extensions
// (permessage-deflate is never negotiated, so RSV bits must be zero) and no subprotocols.

import "core:crypto/legacy/sha1"
import "core:nbio"
import "core:encoding/base64"
import "core:strings"
import "core:unicode/utf8"

import http "vendor_fork:odin-http"

WS_GUID        :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX_MESSAGE :: 64 * 1024

WS_CONT  :: u8(0x0)
WS_TEXT  :: u8(0x1)
WS_BIN   :: u8(0x2)
WS_CLOSE :: u8(0x8)
WS_PING  :: u8(0x9)
WS_PONG  :: u8(0xA)

Ws_Message_Proc :: #type proc(w: ^Ws, text: bool, data: []byte)
Ws_Gone_Proc    :: #type proc(w: ^Ws)

Ws :: struct {
	stream:     ^http.Stream,
	frag:       [dynamic]byte,
	frag_op:    u8,
	closing:    bool, // our close frame is queued
	on_message: Ws_Message_Proc,
	on_gone:    Ws_Gone_Proc,
	user:       rawptr,
}

// Answers the upgrade (or refuses it with a plain status) and returns the socket's Ws.
ws_upgrade :: proc(req: ^http.Request, res: ^http.Response, on_message: Ws_Message_Proc, on_gone: Ws_Gone_Proc = nil, user: rawptr = nil) -> ^Ws {
	h := req.headers
	upgrade, _    := http.headers_get_unsafe(h, "upgrade")
	connection, _ := http.headers_get_unsafe(h, "connection")
	version, _    := http.headers_get_unsafe(h, "sec-websocket-version")
	key, _        := http.headers_get_unsafe(h, "sec-websocket-key")

	if !has_token(upgrade, "websocket") || !has_token(connection, "upgrade") {
		http.respond(res, http.Status.Bad_Request)
		return nil
	}
	if version != "13" {
		http.headers_set_unsafe(&res.headers, "sec-websocket-version", "13")
		http.respond(res, http.Status.Upgrade_Required)
		return nil
	}
	if raw, err := base64.decode(key, allocator = context.temp_allocator); err != nil || len(raw) != 16 {
		http.respond(res, http.Status.Bad_Request)
		return nil
	}
	// Cookies ride along on the handshake and the same-origin policy doesn't cover WebSockets, so a
	// browser's Origin must be this host (cross-site WebSocket hijacking). No Origin: not a browser.
	if origin, ok := http.headers_get_unsafe(h, "origin"); ok {
		host, _ := http.headers_get_unsafe(h, "host")
		if origin != strings.concatenate({"http://", host}, context.temp_allocator) &&
		   origin != strings.concatenate({"https://", host}, context.temp_allocator) {
			http.respond(res, http.Status.Forbidden)
			return nil
		}
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

	w := new(Ws, heap())
	w.frag.allocator = heap()
	w.on_message, w.on_gone, w.user = on_message, on_gone, user
	w.stream = http.stream_begin(res, .Raw, w, ws_on_data, ws_on_close)
	w.stream.on_shutdown = proc(s: ^http.Stream) { ws_close((^Ws)(s.user), 1001) }
	return w
}

ws_send :: proc(w: ^Ws, text: bool, data: []byte) -> bool {
	if w.closing { return false }
	return http.stream_write_string(w.stream, ws_frame(WS_TEXT if text else WS_BIN, data))
}

// Starts the closing handshake and hangs up once the frame is out.
ws_close :: proc(w: ^Ws, code: u16) {
	if w.closing { return }
	payload := [2]byte{byte(code >> 8), byte(code)}
	http.stream_write_string(w.stream, ws_frame(WS_CLOSE, payload[:]))
	w.closing = true
	http.stream_end(w.stream)
}

// One unmasked frame, FIN set, in the temp allocator.
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
	if w.on_gone != nil { w.on_gone(w) }
	// Freed a tick later, like the stream: the frame parser may still be on the stack.
	nbio.next_tick_poly(w, proc(_: ^nbio.Operation, w: ^Ws) {
		delete(w.frag)
		free(w, heap())
	})
}

@(private="file")
valid_close_code :: proc(code: u16) -> bool {
	switch code {
	case 1000 ..= 1003, 1007 ..= 1014, 3000 ..= 4999: return true
	}
	return false
}

@(private="file")
ws_on_data :: proc(s: ^http.Stream, data: []byte) -> (consumed: int) {
	w := (^Ws)(s.user)
	for !s.done {
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
		case rsv != 0, !masked, control && (!fin || plen > 125):
			ws_close(w, 1002); return len(data)
		case plen > WS_MAX_MESSAGE:
			ws_close(w, 1009); return len(data)
		}
		total := pos + 4 + int(plen)
		if len(b) < total { return }
		mask    := b[pos:][:4]
		payload := b[pos + 4:total]
		for i in 0 ..< len(payload) { payload[i] ~= mask[i & 3] }
		consumed += total

		switch op {
		case WS_CONT:
			if w.frag_op == 0 { ws_close(w, 1002); return len(data) }
			append(&w.frag, ..payload)
			if len(w.frag) > WS_MAX_MESSAGE { ws_close(w, 1009); return len(data) }
			if fin {
				deliver_message(w, w.frag_op, w.frag[:])
				clear(&w.frag)
				w.frag_op = 0
			}
		case WS_TEXT, WS_BIN:
			if w.frag_op != 0 { ws_close(w, 1002); return len(data) }
			if fin {
				deliver_message(w, op, payload)
			} else {
				w.frag_op = op
				append(&w.frag, ..payload)
			}
		case WS_CLOSE:
			code := u16(1000)
			if len(payload) == 1 { ws_close(w, 1002); return len(data) }
			if len(payload) >= 2 {
				code = u16(payload[0]) << 8 | u16(payload[1])
				if !valid_close_code(code) { ws_close(w, 1002); return len(data) }
				if !utf8.valid_string(string(payload[2:])) { ws_close(w, 1007); return len(data) }
			}
			ws_close(w, code) // echo it; a no-op if we started the handshake
			return len(data)
		case WS_PING:
			if !w.closing { http.stream_write_string(s, ws_frame(WS_PONG, payload)) }
		case WS_PONG:
		case:
			ws_close(w, 1002); return len(data)
		}
	}
	return
}

@(private="file")
deliver_message :: proc(w: ^Ws, op: u8, data: []byte) {
	if op == WS_TEXT && !utf8.valid_string(string(data)) {
		ws_close(w, 1007)
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
