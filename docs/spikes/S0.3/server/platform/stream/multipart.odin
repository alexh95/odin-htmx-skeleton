package stream

// multipart/mixed (or multipart/parallel) for hx-multipart: one response, parts sent over time,
// each swapped on its own (04 §4.3).
//
// - CRLF everywhere: the parser takes nothing else (an LF-only body swapped nothing, 04 §4.3).
// - A Content-Length on every part: with it the parser finishes a part as soon as its bytes are in;
//   without it a part waits for the next boundary (hx-multipart.js:636-652, 693-720).
// - One chunk per part, written at once: the fork's chunked stream flushes each write.
// - A random boundary per response, so no body line can pass for one.

import "core:crypto"
import "core:strconv"
import "core:strings"

import http "fork:odin-http"

Multipart_Kind :: enum u8 {
	Mixed,    // the client swaps a part before it reads the next
	Parallel, // the client reads on while a part swaps
}

Boundary :: struct {
	buf: [19]byte, // "hx-" and 16 hex digits
}

boundary_string :: proc(b: ^Boundary) -> string { return string(b.buf[:]) }

Part_Header :: struct {
	name, value: string, // HX-Target, HX-Swap, HX-Select, HX-Trigger, HX-Part-ID …
}

multipart_begin :: proc(
	res: ^http.Response,
	b: ^Boundary,
	kind := Multipart_Kind.Mixed,
	user: rawptr = nil,
	on_close: http.Stream_Close_Proc = nil,
) -> ^http.Stream {
	HEX := "0123456789abcdef"
	rnd: [8]byte
	crypto.rand_bytes(rnd[:])
	copy(b.buf[:], "hx-")
	for x, i in rnd {
		b.buf[3 + 2 * i] = HEX[x >> 4]
		b.buf[4 + 2 * i] = HEX[x & 15]
	}
	type := "multipart/mixed; boundary=" if kind == .Mixed else "multipart/parallel; boundary="
	stream_headers(res, strings.concatenate({type, boundary_string(b)}, context.temp_allocator))
	s := http.stream_begin(res, .Chunked, user, on_close = on_close)
	// A preamble, which the parser discards (RFC 2046 §5.1.1), goes out with the headers: WebKit
	// resolves a streamed fetch only at its first body bytes (S0.3; see sse_begin).
	http.stream_write_string(s, "\r\n")
	return s
}

// Writes one part as one chunk. False once the stream is gone or too slow (as http.stream_write).
// Header names and values come from the server and never hold a line break.
multipart_part :: proc(s: ^http.Stream, b: ^Boundary, body: string, headers: []Part_Header = nil) -> bool {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "--")
	strings.write_string(&sb, boundary_string(b))
	strings.write_string(&sb, "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ")
	n: [32]byte
	strings.write_string(&sb, strconv.write_int(n[:], i64(len(body)), 10))
	strings.write_string(&sb, "\r\n")
	for h in headers {
		assert(strings.index_any(h.name, "\r\n") < 0 && strings.index_any(h.value, "\r\n") < 0)
		strings.write_string(&sb, h.name)
		strings.write_string(&sb, ": ")
		strings.write_string(&sb, h.value)
		strings.write_string(&sb, "\r\n")
	}
	strings.write_string(&sb, "\r\n")
	strings.write_string(&sb, body)
	strings.write_string(&sb, "\r\n")
	return http.stream_write_string(s, strings.to_string(sb))
}

// The closing boundary, then the end of the stream.
multipart_end :: proc(s: ^http.Stream, b: ^Boundary) {
	http.stream_write_string(s, strings.concatenate({"--", boundary_string(b), "--\r\n"}, context.temp_allocator))
	http.stream_end(s)
}
