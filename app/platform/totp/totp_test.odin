package totp

import "core:fmt"
import "core:testing"

// RFC 4226 Appendix D and RFC 6238 Appendix B (SHA-1, 8 digits), over the RFCs' own secret.
@(private = "file")
RFC_SECRET :: "12345678901234567890"

@(test)
hotp_matches_rfc_4226 :: proc(t: ^testing.T) {
	want := [?]u32{755224, 287082, 359152, 969429, 338314, 254676, 287922, 162583, 399871, 520489}
	for w, i in want { testing.expect_value(t, hotp(transmute([]byte)string(RFC_SECRET), u64(i)), w) }
}

@(test)
totp_matches_rfc_6238 :: proc(t: ^testing.T) {
	cases := [?]struct { unix: i64, code: u32 } {
		{59, 94287082}, {1111111109, 7081804}, {1111111111, 14050471},
		{1234567890, 89005924}, {2000000000, 69279037}, {20000000000, 65353130},
	}
	for c in cases { testing.expect_value(t, at(transmute([]byte)string(RFC_SECRET), c.unix, 8), c.code) }
}

@(test)
verify_takes_a_neighbouring_step_and_nothing_else :: proc(t: ^testing.T) {
	secret := transmute([]byte)string(RFC_SECRET)
	now: i64 = 1111111111
	code :: proc(secret: []byte, unix: i64) -> string { return fmt.tprintf("%06d", at(secret, unix)) }
	step, ok := verify(secret, code(secret, now), now)
	testing.expect(t, ok && step == now / STEP)
	_, ok = verify(secret, code(secret, now - STEP), now)
	testing.expect(t, ok) // a phone a step behind
	_, ok = verify(secret, code(secret, now - 3 * STEP), now)
	testing.expect(t, !ok)
	_, ok = verify(secret, "12345", now)
	testing.expect(t, !ok)
	_, ok = verify(secret, "12a456", now)
	testing.expect(t, !ok)
}

@(test)
a_secret_survives_its_text :: proc(t: ^testing.T) {
	s := new_secret()
	text := encode(s[:])
	testing.expect_value(t, len(text), 32)
	back, ok := decode(text)
	testing.expect(t, ok && back == s)
	lower, lok := decode("gezd gnbv-gy3t qojq gezd gnbv gy3t qojq") // RFC_SECRET, typed loosely
	testing.expect(t, lok && string(lower[:]) == RFC_SECRET)
	_, bad := decode("not base32!")
	testing.expect(t, !bad)
}
