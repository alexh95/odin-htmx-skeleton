package stream

// multipart/mixed (or /parallel) for hx-multipart: one response, its parts sent
// over time, each swapped on its own (04 §4.3).
//
// - CRLF everywhere: the parser takes nothing else (an LF-only body swapped nothing).
// - A Content-Length on every part: with it the parser finishes a part as soon as
//   its bytes are in; without it a part waits for the next boundary.
// - One chunk per part, written at once: F-1's chunked stream flushes each write.
// - A random boundary per response, so no body line can pass for one.

import "core:crypto"
import "core:strconv"
import "core:strings"

import "../web"

Multipart_Kind :: enum u8 {
	Mixed,    // the client swaps a part before it reads the next
	Parallel, // the client reads on while a part swaps (status's probes)
}

BOUNDARY_LEN :: 19 // "hx-" and 16 hex digits

Part_Header :: struct {
	name, value: string, // HX-Target, HX-Swap, HX-Select, HX-Trigger, HX-Part-ID …
}

multipart_begin :: proc(res: ^web.Response, kind := Multipart_Kind.Mixed, user: rawptr = nil, on_close: Close_Proc = nil) -> ^Conn {
	HEX := "0123456789abcdef"
	rnd: [8]byte
	crypto.rand_bytes(rnd[:])
	boundary: [BOUNDARY_LEN]byte
	copy(boundary[:], "hx-")
	for x, i in rnd {
		boundary[3 + 2 * i] = HEX[x >> 4]
		boundary[4 + 2 * i] = HEX[x & 15]
	}
	type := "multipart/mixed; boundary=" if kind == .Mixed else "multipart/parallel; boundary="
	web.set_header(res, "content-type", strings.concatenate({type, string(boundary[:])}, context.temp_allocator))
	c := open(res, .Chunked, .Multipart, user, on_close)
	c.boundary = boundary
	// A preamble, which the parser discards (RFC 2046 §5.1.1), goes out with the
	// headers: WebKit resolves a streamed fetch only at its first body bytes (S0.3).
	write(c, "\r\n")
	return c
}

// Writes one part as one chunk; false once the stream is gone or too slow.
multipart_part :: proc(c: ^Conn, body: string, headers: []Part_Header = nil) -> bool {
	return write(c, part_bytes(string(c.boundary[:]), body, headers))
}

// The closing boundary, then the end of the stream.
multipart_end :: proc(c: ^Conn) {
	if c.gone { return }
	write(c, closing_boundary(c))
	web.stream_end(c.s)
}

// One part. Header names and values are the server's and never hold a line break.
part_bytes :: proc(boundary, body: string, headers: []Part_Header, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(0, len(body) + 128, allocator)
	strings.write_string(&b, "--")
	strings.write_string(&b, boundary)
	strings.write_string(&b, "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ")
	n: [32]byte
	strings.write_string(&b, strconv.write_int(n[:], i64(len(body)), 10))
	strings.write_string(&b, "\r\n")
	for h in headers {
		assert(strings.index_any(h.name, "\r\n") < 0 && strings.index_any(h.value, "\r\n") < 0)
		strings.write_string(&b, h.name)
		strings.write_string(&b, ": ")
		strings.write_string(&b, h.value)
		strings.write_string(&b, "\r\n")
	}
	strings.write_string(&b, "\r\n")
	strings.write_string(&b, body)
	strings.write_string(&b, "\r\n")
	return strings.to_string(b)
}

@(private)
closing_boundary :: proc(c: ^Conn) -> string {
	return strings.concatenate({"--", string(c.boundary[:]), "--\r\n"}, context.temp_allocator)
}
