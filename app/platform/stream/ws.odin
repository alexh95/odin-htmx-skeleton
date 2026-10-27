package stream

// WebSocket (RFC 6455), server side: client frames must be masked, ours are not.
// No extensions are negotiated, so every RSV bit must be zero, and no
// subprotocols. The codec is strict (§8.2): a protocol error closes 1002, text
// that isn't UTF-8 1007, a message past WS_MAX_MESSAGE 1009. spark's wsserver's
// RFC 6455 coverage table is the checklist its unit tests follow (03 §5.1, X24).

import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:encoding/json"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "../sys"
import "../web"

WS_GUID        :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX_MESSAGE :: 64 * 1024 // §9.4: a message past it closes 1009

WS_CONT  :: u8(0x0)
WS_TEXT  :: u8(0x1)
WS_BIN   :: u8(0x2)
WS_CLOSE :: u8(0x8)
WS_PING  :: u8(0x9)
WS_PONG  :: u8(0xA)

// A text frame's JSON nests at most this deep: core:encoding/json recurses a level per
// bracket with no limit, and a 64 KiB frame of `[` overflowed a loop's stack (M2-01).
WS_JSON_DEPTH :: 16

// A text frame's JSON, unmarshalled into `out` (strings in the request's temp arena), or
// false: not JSON, the wrong shape, or nested past WS_JSON_DEPTH, which is refused by a
// scan before anything parses it. Every handler reads a client's JSON through this. Strict
// JSON: core's default is JSON5, whose comments and single-quoted strings hid a `"` from the
// scan and every bracket after it, and whose tokenizer recursed once per comment (M2-22).
ws_json :: proc(data: []byte, out: ^$T) -> bool {
	depth := 0
	in_str, escaped := false, false
	for c in data {
		switch {
		case in_str:
			if escaped {
				escaped = false
			} else if c == '\\' {
				escaped = true
			} else if c == '"' {
				in_str = false
			}
		case c == '"':
			in_str = true
		case c == '[' || c == '{':
			depth += 1
			if depth > WS_JSON_DEPTH { return false }
		case c == ']' || c == '}':
			depth -= 1
		}
	}
	return json.unmarshal(data, out, spec = .JSON, allocator = context.temp_allocator) == nil
}

// The close codes the starter sends (§9.4). hx-ws reconnects on 1001, 1005,
// 1006 and 1011-1014, and stops for good on the rest.
WS_NORMAL     :: u16(1000)
WS_GOING_AWAY :: u16(1001) // the peer passed the pong deadline
WS_PROTOCOL   :: u16(1002)
WS_BAD_DATA   :: u16(1007)
WS_POLICY     :: u16(1008) // revoked auth, a kick, a frame flood: the client stops
WS_TOO_BIG    :: u16(1009) // the client stops
WS_INTERNAL   :: u16(1011) // a pure crash in this stream
WS_RESTART    :: u16(1012) // drain and restart
WS_TRY_AGAIN  :: u16(1013) // a slow consumer

// A consumer closed with 1013 gets this long to take what's queued before the
// fork cuts it off (F-1's stream_end deadline; S0.3).
WS_SLOW_DEADLINE :: 2 * time.Second

Message_Proc :: #type proc(c: ^Conn, text: bool, data: []byte)

Upgrade_Error :: enum u8 {
	None,
	Not_Upgrade,
	Bad_Version,
	Bad_Key,
	Foreign_Origin,
	Refused, // admission: 503 or 429 (limits.odin)
}

// Answers the upgrade, or refuses it with a status, and returns the socket's
// Conn (nil when refused). `max_rate` caps frames a second (0: none); past it the
// socket closes 1008.
//
// The Origin check is the handshake's own: an upgrade is a GET, so front's
// cross-site guard lets it through, and browsers send no Sec-Fetch-* on it (04
// §4.4). Cookies ride along and the same-origin policy doesn't cover WebSockets,
// so a page on another site could open a socket as the user (cross-site
// WebSocket hijacking). A handshake without Origin is not a browser's, can't be
// that, and passes, as the cross-site guard lets such requests pass; a device
// client authenticates by token instead (S0.3). The origin is the host's own
// (SITE_URL, or SITE_URL_LAB on a lab host, §7.3); while that is still the
// brand's placeholder (a dev run with no SITE_URL), an Origin naming the
// request's own Host passes instead, as the browser's page came from it.
ws_upgrade :: proc(
	req: ^web.Request,
	res: ^web.Response,
	on_message: Message_Proc,
	on_close: Close_Proc = nil,
	user: rawptr = nil,
	max_rate := 0,
) -> (c: ^Conn, err: Upgrade_Error) {
	upgrade, _ := web.header(req, "upgrade")
	connection, _ := web.header(req, "connection")
	version, _ := web.header(req, "sec-websocket-version")
	key, _ := web.header(req, "sec-websocket-key")

	if !has_token(upgrade, "websocket") || !has_token(connection, "upgrade") {
		web.respond_status(res, .Bad_Request)
		return nil, .Not_Upgrade
	}
	if version != "13" {
		web.set_header(res, "sec-websocket-version", "13")
		web.respond_status(res, .Upgrade_Required)
		return nil, .Bad_Version
	}
	if raw, derr := base64.decode(key, allocator = context.temp_allocator); derr != nil || len(raw) != 16 {
		web.respond_status(res, .Bad_Request)
		return nil, .Bad_Key
	}
	if origin, ok := web.header(req, "origin"); ok && !own_origin(req, origin) {
		web.respond_status(res, .Forbidden)
		return nil, .Foreign_Origin
	}

	c = open(res, .Raw, .Ws, "", user, on_close, key)
	if c == nil { return nil, .Refused }
	c.on_message = on_message
	c.assembly.frag.allocator = heap()
	c.rate.per_s = max_rate
	return c, .None
}

// Sec-WebSocket-Accept: base64(SHA-1(key + GUID)), in the temp allocator.
accept_key :: proc(key: string) -> string {
	ctx: sha1.Context
	digest: [sha1.DIGEST_SIZE]byte
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]byte)key)
	sha1.update(&ctx, transmute([]byte)string(WS_GUID))
	sha1.final(&ctx, digest[:])
	return base64.encode(digest[:], allocator = context.temp_allocator)
}

ws_send :: proc(c: ^Conn, text: bool, data: []byte) -> bool {
	return ws_write_frame(c, ws_frame(WS_TEXT if text else WS_BIN, data))
}

ws_send_text :: proc(c: ^Conn, text: string) -> bool {
	return ws_write_frame(c, ws_frame(WS_TEXT, transmute([]byte)text))
}

// Writes a frame, possibly encoded once for many sockets (the hub's fan-out). A
// frame that would pass the stream's cap closes the slow consumer with 1013
// instead, room kept for the close frame, and gives it WS_SLOW_DEADLINE to take
// what's queued (§9.4); F-1's own cap stays as the backstop.
ws_write_frame :: proc(c: ^Conn, frame: string) -> bool {
	if c.closing { return false }
	if web.stream_would_overflow(c.s, len(frame) + 64) {
		ws_close(c, WS_TRY_AGAIN, WS_SLOW_DEADLINE)
		return false
	}
	return web.stream_write_string(c.s, frame)
}

// Starts the closing handshake and hangs up once the frame is out, or at the
// deadline. Code 0 sends a close frame without one (the echo of a close that had
// none: 1005 is never sent).
ws_close :: proc(c: ^Conn, code: u16, deadline: time.Duration = 0) {
	if c.closing { return }
	payload := [2]byte{byte(code >> 8), byte(code)}
	web.stream_write_string(c.s, ws_frame(WS_CLOSE, payload[:] if code != 0 else nil))
	c.closing = true
	web.stream_end(c.s, deadline)
}

// One unmasked frame with FIN set, in the temp allocator.
ws_frame :: proc(op: u8, data: []byte, allocator := context.temp_allocator) -> string {
	n := len(data)
	b := make([dynamic]byte, 0, n + 10, allocator)
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

// ---- the codec, apart from the socket (unit-tested) ---------------------------------

Frame :: struct {
	fin:     bool,
	op:      u8,
	payload: []byte,
}

// Reads one client frame from the front of `b` and unmasks its payload in
// place. n = 0: the frame isn't all here yet. fail: the close code it earns,
// decided from the header alone where it can be, so a 2 GB length is refused
// before a byte of it arrives.
read_frame :: proc(b: []byte, max := WS_MAX_MESSAGE) -> (f: Frame, n: int, fail: u16) {
	if len(b) < 2 { return }
	f.fin = b[0] & 0x80 != 0
	rsv := b[0] & 0x70
	f.op = b[0] & 0x0F
	masked := b[1] & 0x80 != 0
	plen := u64(b[1] & 0x7F)
	pos := 2
	if plen == 126 {
		if len(b) < 4 { return }
		plen, pos = u64(b[2]) << 8 | u64(b[3]), 4
	} else if plen == 127 {
		if len(b) < 10 { return }
		plen = 0
		for i in 0 ..< 8 { plen = plen << 8 | u64(b[2 + i]) }
		pos = 10
	}
	control := f.op & 0x8 != 0
	switch {
	case rsv != 0, !masked, plen >> 63 != 0:
		return f, 0, WS_PROTOCOL
	case control && (!f.fin || plen > 125):
		return f, 0, WS_PROTOCOL
	case f.op > WS_BIN && f.op < WS_CLOSE, f.op > WS_PONG:
		return f, 0, WS_PROTOCOL
	case plen > u64(max):
		return f, 0, WS_TOO_BIG
	}
	total := pos + 4 + int(plen)
	if len(b) < total { return }
	mask := b[pos:][:4]
	f.payload = b[pos + 4:total]
	for i in 0 ..< len(f.payload) { f.payload[i] ~= mask[i & 3] }
	return f, total, 0
}

// A message being put together from its frames. `frag` is the socket's; the
// data `assemble` returns is valid until the next call.
Assembly :: struct {
	frag: [dynamic]byte,
	op:   u8, // the message's opcode while fragments arrive; 0 between messages
}

Event :: enum u8 {
	None,    // a fragment: the message isn't finished
	Message, // text or binary, whole
	Ping,
	Pong,
	Close,   // `code` is the peer's, 0 when it sent none
}

// Folds one frame into the message under way.
assemble :: proc(a: ^Assembly, f: Frame, max := WS_MAX_MESSAGE) -> (ev: Event, text: bool, data: []byte, code: u16, fail: u16) {
	if a.op == 0 && len(a.frag) > 0 { clear(&a.frag) } // the last message has been read
	switch f.op {
	case WS_CONT:
		if a.op == 0 { return .None, false, nil, 0, WS_PROTOCOL }
		if len(a.frag) + len(f.payload) > max { return .None, false, nil, 0, WS_TOO_BIG }
		append(&a.frag, ..f.payload)
		if !f.fin { return }
		text = a.op == WS_TEXT
		a.op = 0
		data = a.frag[:]
	case WS_TEXT, WS_BIN:
		if a.op != 0 { return .None, false, nil, 0, WS_PROTOCOL }
		if !f.fin {
			a.op = f.op
			append(&a.frag, ..f.payload)
			return
		}
		text, data = f.op == WS_TEXT, f.payload
	case WS_CLOSE:
		switch len(f.payload) {
		case 0:
			return .Close, false, nil, 0, 0
		case 1:
			return .None, false, nil, 0, WS_PROTOCOL
		}
		code = u16(f.payload[0]) << 8 | u16(f.payload[1])
		if !valid_close_code(code) { return .None, false, nil, 0, WS_PROTOCOL }
		if !utf8.valid_string(string(f.payload[2:])) { return .None, false, nil, 0, WS_BAD_DATA }
		return .Close, false, nil, code, 0
	case WS_PING:
		return .Ping, false, f.payload, 0, 0
	case WS_PONG:
		return .Pong, false, nil, 0, 0
	case:
		return .None, false, nil, 0, WS_PROTOCOL
	}
	if text && !utf8.valid_string(string(data)) { return .None, false, nil, 0, WS_BAD_DATA }
	return .Message, text, data, 0, 0
}

// 1004-1006 and 1015 are reserved for reports and never sent in a frame; 1016
// to 2999 are unassigned (RFC 6455 §7.4; IANA's registry adds 1012-1014).
valid_close_code :: proc(code: u16) -> bool {
	switch code {
	case 1000 ..= 1003, 1007 ..= 1014, 3000 ..= 4999: return true
	}
	return false
}

// Frames a second, in whole-second windows.
Rate :: struct {
	per_s:  int, // 0: no cap
	window: i64, // the second this count is for
	n:      int,
}

rate_ok :: proc(r: ^Rate, now_ns: i64) -> bool {
	if r.per_s <= 0 { return true }
	if s := now_ns / 1e9; s != r.window {
		r.window, r.n = s, 0
	}
	r.n += 1
	return r.n <= r.per_s
}

// ---- the socket ------------------------------------------------------------------

// Parses every whole frame `data` holds; the rest waits for the next read.
@(private)
ws_on_data :: proc(s: ^web.Stream, data: []byte) -> (consumed: int) {
	c := (^Conn)(s.user)
	if c.closing { return len(data) } // nothing after our close frame matters
	for !s.done && !c.closing {
		f, n, fail := read_frame(data[consumed:])
		if fail != 0 {
			ws_close(c, fail)
			return len(data)
		}
		if n == 0 { return }
		consumed += n
		c.seen_ns = sys.mono_ns()
		if !rate_ok(&c.rate, c.seen_ns) {
			ws_close(c, WS_POLICY)
			return len(data)
		}
		ev, text, msg, code, afail := assemble(&c.assembly, f)
		if afail != 0 {
			ws_close(c, afail)
			return len(data)
		}
		switch ev {
		case .None, .Pong:
		case .Message:
			if c.on_message != nil { c.on_message(c, text, msg) }
		case .Ping:
			web.stream_write_string(s, ws_frame(WS_PONG, msg))
		case .Close:
			ws_close(c, code) // the echo
			return len(data)
		}
	}
	return
}

@(private)
own_origin :: proc(req: ^web.Request, origin: string) -> bool {
	site := web.ctx().site.origin
	if origin == site { return true }
	if !web.placeholder_origin(site) { return false }
	host, _ := web.header(req, "host")
	for scheme in ([?]string{"http://", "https://"}) {
		if len(origin) == len(scheme) + len(host) && strings.has_prefix(origin, scheme) && origin[len(scheme):] == host { return true }
	}
	return false
}

@(private)
has_token :: proc(value, token: string) -> bool {
	v := value
	for part in strings.split_iterator(&v, ",") {
		if strings.equal_fold(strings.trim_space(part), token) { return true }
	}
	return false
}
