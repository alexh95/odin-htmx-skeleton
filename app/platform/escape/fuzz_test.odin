package escape

import "core:testing"

// Whatever a cookie, a form or a header holds, b64_decode answers without a trap (M4-02), and
// what it accepts decodes to no more than the text could hold.
@(test)
b64_decode_takes_any_text :: proc(t: ^testing.T) {
	ALPHABET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_=="
	d := Draw{0x9E3779B97F4A7C15}
	buf: [96]byte
	for i in 0 ..< 200_000 {
		s := string(draw(&d, buf[:], ALPHABET))
		out, ok := b64_decode(s, i & 1 == 0)
		if ok && len(out) > len(s) * 3 / 4 + 1 {
			testing.expectf(t, false, "%q decoded to %d bytes", s, len(out))
			break
		}
		free_all(context.temp_allocator)
	}
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
