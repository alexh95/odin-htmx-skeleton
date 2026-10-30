package totp

import "core:testing"

// A typed secret and a typed code are a member's text: any of it answers, never traps (M4-13).
@(test)
decode_and_verify_take_any_text :: proc(t: ^testing.T) {
	SECRET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz234567 -=="
	CODE :: "0123456789 -"
	d := Draw{0xD1B54A32D192ED03}
	buf: [64]byte
	key: [SECRET_LEN]byte
	for _ in 0 ..< 100_000 {
		secret, ok := decode(string(draw(&d, buf[:], SECRET)))
		if ok { key = secret }
		_, _ = verify(key[:], string(draw(&d, buf[:12], CODE)), i64(next(&d) >> 30))
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
