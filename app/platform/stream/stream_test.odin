package stream

import "core:testing"

// ---- SSE ------------------------------------------------------------------------

@(test)
sse_splits_every_line_break :: proc(t: ^testing.T) {
	testing.expect_value(t, sse_event("", "", "a\rb\nc\r\nd"), "data: a\ndata: b\ndata: c\ndata: d\n\n")
	testing.expect_value(t, sse_event("", "", ""), "data: \n\n")
	testing.expect_value(t, sse_event("", "", "x\n"), "data: x\ndata: \n\n")
	testing.expect_value(t, sse_event("17-3", "resync", "chat.room:12"), "id: 17-3\nevent: resync\ndata: chat.room:12\n\n")
	// A CR in user text can't start a field of its own.
	testing.expect_value(t, sse_event("", "", "hi\revent: kicked"), "data: hi\ndata: event: kicked\n\n")
}

// ---- WebSocket: the handshake and our frames -------------------------------------

@(test)
accept_key_matches_rfc_6455 :: proc(t: ^testing.T) {
	// RFC 6455 §1.3's worked example.
	testing.expect_value(t, accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
}

@(test)
frame_lengths_use_each_encoding :: proc(t: ^testing.T) {
	for n in ([?]int{0, 125, 126, 65535, 65536}) {
		data := make([]byte, n, context.temp_allocator)
		f := ws_frame(WS_TEXT, data)
		header := 2 if n < 126 else 4 if n < 65536 else 10
		testing.expect_value(t, len(f), header + n)
		testing.expect_value(t, f[0], 0x81)
	}
	testing.expect_value(t, ws_frame(WS_CLOSE, []byte{0x03, 0xE8}), "\x88\x02\x03\xE8")
	testing.expect_value(t, ws_frame(WS_PING, nil), "\x89\x00")
}

// ---- WebSocket: client frames ------------------------------------------------------

// A client frame: masked unless told not to, with the given first byte's bits.
@(private = "file")
client_frame :: proc(op: u8, payload: string, fin := true, masked := true, rsv: u8 = 0) -> []byte {
	b := make([dynamic]byte, 0, len(payload) + 14, context.temp_allocator)
	append(&b, (0x80 if fin else 0) | rsv | op)
	m: u8 = 0x80 if masked else 0
	n := len(payload)
	switch {
	case n < 126:   append(&b, m | u8(n))
	case n < 65536: append(&b, m | 126, u8(n >> 8), u8(n))
	case:
		append(&b, m | 127)
		for i := 7; i >= 0; i -= 1 { append(&b, u8(u64(n) >> (uint(i) * 8))) }
	}
	mask := [4]byte{0x37, 0xfa, 0x21, 0x3d}
	if masked { append(&b, ..mask[:]) }
	for i in 0 ..< n { append(&b, payload[i] ~ (mask[i & 3] if masked else 0)) }
	return b[:]
}

@(test)
read_frame_unmasks_and_waits_for_the_rest :: proc(t: ^testing.T) {
	b := client_frame(WS_TEXT, "Hello")
	for cut in 0 ..< len(b) {
		_, n, fail := read_frame(b[:cut])
		testing.expect_value(t, n, 0)
		testing.expect_value(t, fail, 0)
	}
	f, n, fail := read_frame(b)
	testing.expect_value(t, fail, 0)
	testing.expect_value(t, n, len(b))
	testing.expect(t, f.fin && f.op == WS_TEXT)
	testing.expect_value(t, string(f.payload), "Hello")

	big := make([]byte, 70_000, context.temp_allocator)
	for &c in big { c = 'x' }
	f2, n2, fail2 := read_frame(client_frame(WS_BIN, string(big)), max = 80_000)
	testing.expect_value(t, fail2, 0)
	testing.expect_value(t, n2, 70_000 + 14)
	testing.expect_value(t, len(f2.payload), 70_000)
}

@(test)
read_frame_refuses_protocol_errors :: proc(t: ^testing.T) {
	cases := [?]struct{name: string, frame: []byte, code: u16}{
		{"unmasked", client_frame(WS_TEXT, "hi", masked = false), WS_PROTOCOL},
		{"RSV1", client_frame(WS_TEXT, "hi", rsv = 0x40), WS_PROTOCOL},
		{"RSV3", client_frame(WS_TEXT, "hi", rsv = 0x10), WS_PROTOCOL},
		{"fragmented ping", client_frame(WS_PING, "x", fin = false), WS_PROTOCOL},
		{"126-byte ping", client_frame(WS_PING, string(make([]byte, 126, context.temp_allocator))), WS_PROTOCOL},
		{"opcode 3", client_frame(3, "x"), WS_PROTOCOL},
		{"opcode 0xB", client_frame(0xB, ""), WS_PROTOCOL},
		{"64-bit length with its top bit set", {0x82, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 1}, WS_PROTOCOL},
		// Refused from the header alone: none of the 1 GB has to arrive.
		{"past the cap", {0x82, 0xFF, 0, 0, 0, 0, 0x40, 0, 0, 0}, WS_TOO_BIG},
	}
	for c in cases {
		_, n, fail := read_frame(c.frame)
		testing.expectf(t, fail == c.code && n == 0, "%s: fail %d, n %d", c.name, fail, n)
	}
}

// ---- WebSocket: messages -----------------------------------------------------------

@(private = "file")
frame_of :: proc(t: ^testing.T, b: []byte) -> Frame {
	f, _, fail := read_frame(b)
	testing.expect_value(t, fail, 0)
	return f
}

@(test)
assemble_joins_fragments_and_checks_utf8 :: proc(t: ^testing.T) {
	a: Assembly
	defer delete(a.frag)

	ev, text, data, _, fail := assemble(&a, frame_of(t, client_frame(WS_TEXT, "whole")))
	testing.expect(t, ev == .Message && text && fail == 0)
	testing.expect_value(t, string(data), "whole")

	// "é" (C3 A9) split across two fragments is valid once joined.
	ev, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_TEXT, "caf\xC3", fin = false)))
	testing.expect(t, ev == .None && fail == 0)
	ev, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_PING, "mid")))
	testing.expect(t, ev == .Ping && fail == 0) // control frames may come between fragments
	ev, text, data, _, fail = assemble(&a, frame_of(t, client_frame(WS_CONT, "\xA9!")))
	testing.expect(t, ev == .Message && text && fail == 0)
	testing.expect_value(t, string(data), "café!")

	ev, text, data, _, fail = assemble(&a, frame_of(t, client_frame(WS_BIN, "\xff\xfe")))
	testing.expect(t, ev == .Message && !text && fail == 0) // binary isn't checked
	testing.expect_value(t, len(data), 2)

	_, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_TEXT, "\xff")))
	testing.expect_value(t, fail, WS_BAD_DATA)
}

@(test)
assemble_refuses_bad_sequences :: proc(t: ^testing.T) {
	{
		a: Assembly
		defer delete(a.frag)
		_, _, _, _, fail := assemble(&a, frame_of(t, client_frame(WS_CONT, "x")))
		testing.expect_value(t, fail, WS_PROTOCOL) // a continuation with nothing to continue
	}
	{
		a: Assembly
		defer delete(a.frag)
		assemble(&a, frame_of(t, client_frame(WS_TEXT, "a", fin = false)))
		_, _, _, _, fail := assemble(&a, frame_of(t, client_frame(WS_TEXT, "b")))
		testing.expect_value(t, fail, WS_PROTOCOL) // a new message inside a fragmented one
	}
	{
		a: Assembly
		defer delete(a.frag)
		assemble(&a, frame_of(t, client_frame(WS_BIN, "12345", fin = false)), max = 8)
		_, _, _, _, fail := assemble(&a, frame_of(t, client_frame(WS_CONT, "6789")), max = 8)
		testing.expect_value(t, fail, WS_TOO_BIG) // fragments past the cap together
	}
}

@(test)
assemble_reads_close_frames :: proc(t: ^testing.T) {
	a: Assembly
	defer delete(a.frag)
	ev, _, _, code, fail := assemble(&a, frame_of(t, client_frame(WS_CLOSE, "")))
	testing.expect(t, ev == .Close && code == 0 && fail == 0)
	ev, _, _, code, fail = assemble(&a, frame_of(t, client_frame(WS_CLOSE, "\x0B\xB8bye")))
	testing.expect(t, ev == .Close && code == 3000 && fail == 0)
	_, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_CLOSE, "\x03")))
	testing.expect_value(t, fail, WS_PROTOCOL) // a one-byte body
	for bad in ([?]u16{0, 999, 1004, 1005, 1006, 1015, 1016, 2999, 5000}) {
		body := [2]byte{byte(bad >> 8), byte(bad)}
		_, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_CLOSE, string(body[:]))))
		testing.expectf(t, fail == WS_PROTOCOL, "close code %d: fail %d", bad, fail)
	}
	_, _, _, _, fail = assemble(&a, frame_of(t, client_frame(WS_CLOSE, "\x03\xE8\xff")))
	testing.expect_value(t, fail, WS_BAD_DATA) // a reason that isn't UTF-8
}

@(test)
rate_caps_frames_per_second :: proc(t: ^testing.T) {
	r := Rate{per_s = 3}
	for i in 0 ..< 3 { testing.expect(t, rate_ok(&r, 5e9 + i64(i))) }
	testing.expect(t, !rate_ok(&r, 5e9 + 900e6))
	testing.expect(t, rate_ok(&r, 6e9)) // a new second
	none: Rate
	for _ in 0 ..< 100 { testing.expect(t, rate_ok(&none, 1)) }
}

// ---- multipart ---------------------------------------------------------------------

@(test)
part_counts_bytes_and_frames_with_crlf :: proc(t: ^testing.T) {
	got := part_bytes("hx-0011", "<p>é</p>", {{"HX-Target", "#a"}, {"HX-Part-ID", "7"}})
	want := "--hx-0011\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 9\r\nHX-Target: #a\r\nHX-Part-ID: 7\r\n\r\n<p>é</p>\r\n"
	testing.expect_value(t, got, want)
}

// ---- a frame's JSON ---------------------------------------------------------------

@(test)
ws_json_refuses_deep_nesting_before_it_parses :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	In :: struct { body: string }
	v: In
	testing.expect(t, ws_json(transmute([]byte)string(`{"body":"hi","headers":{"a":"b"}}`), &v))
	testing.expect_value(t, v.body, "hi")
	// Brackets inside a string, and an escaped quote before them, aren't nesting.
	testing.expect(t, ws_json(transmute([]byte)string(`{"body":"[[[[[[[[[[[[[[[[[[[[\" {{{{{{{{{{{{{{{{{{"}`), &v))
	// M2-01's frame: past WS_JSON_DEPTH it is refused without a parse (which would recurse a level a bracket).
	deep := make([]byte, 64 * 1024, context.temp_allocator)
	copy(deep, `{"body":"x","headers":`)
	for i in 22 ..< len(deep) { deep[i] = '[' }
	testing.expect(t, !ws_json(deep, &v))
	testing.expect(t, !ws_json(transmute([]byte)string(`not json`), &v))
	// M2-22's frames: a `"` the scan took for a string's, hidden in a JSON5 comment, then the
	// brackets; and a frame of comments, which JSON5's tokenizer recursed through one by one.
	copy(deep, `{"body":"x","headers":/*"*/`)
	for i in 27 ..< len(deep) { deep[i] = '[' }
	testing.expect(t, !ws_json(deep, &v))
	copy(deep, `{"body":"x"`)
	for i := 11; i + 3 <= len(deep); i += 3 { copy(deep[i:], "//\n") }
	testing.expect(t, !ws_json(deep, &v))
	testing.expect(t, !ws_json(transmute([]byte)string(`{'body':'single quotes'}`), &v))
}

// What a replay and publish count is what the stream is sent: a line costs "data: " and its
// newline on top of its text (M2-23).
@(test)
sse_size_is_what_sse_event_writes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for data in ([]string{"", "a", "a\nb", "a\r\nb", "a\rb", "a\n", "\n\n\n", "<p>one</p>"}) {
		for id in ([]string{"", "1761500000123-42"}) {
			testing.expectf(t, sse_size(id, "resync", data) == len(sse_event(id, "resync", data)), "%q %q", id, data)
			testing.expectf(t, sse_size(id, "", data) == len(sse_event(id, "", data)), "%q %q", id, data)
		}
	}
}
