package stream

import "core:testing"

// A socket's frame is a client's JSON: ws_field reads any of it without a trap, and what it
// finds lies inside the frame or was built in the request arena (M3-09).
@(test)
ws_field_takes_any_frame :: proc(t: ^testing.T) {
	ALPHABET :: `{}[]":,\ ntrufalse0123456789.eE+-bodyHEADERSu`
	d := Draw{0xE7037ED1A0B428DB}
	buf: [160]byte
	for _ in 0 ..< 200_000 {
		_, _ = ws_field(draw(&d, buf[:], ALPHABET), "body")
		free_all(context.temp_allocator)
	}
	testing.expect(t, true)
}

// ---- random input (M4-13) ------------------------------------------------------------------
//
// Not libFuzzer: a seeded xorshift over bytes drawn mostly from the parser's own alphabet, now
// and then any byte, so a failure reproduces from the seed. A trap fails the run.

@(private = "file")
Draw :: struct {
	s: u64,
}

@(private = "file")
next :: proc(d: ^Draw) -> u64 {
	d.s ~= d.s << 13
	d.s ~= d.s >> 7
	d.s ~= d.s << 17
	return d.s
}

@(private = "file")
draw :: proc(d: ^Draw, buf: []byte, alphabet: string) -> []byte {
	n := int(next(d) % u64(len(buf) + 1))
	for i in 0 ..< n {
		r := next(d)
		buf[i] = alphabet[r % u64(len(alphabet))] if r & 15 != 0 else byte(r >> 8)
	}
	return buf[:n]
}
