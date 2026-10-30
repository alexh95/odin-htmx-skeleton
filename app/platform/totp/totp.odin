package totp

// ---- platform/totp: one-time codes (L2) ----------------------------------------------------
//
// RFC 6238 over RFC 4226 (PLAN §17.1, Q11): HMAC-SHA1, 30-second steps, 6 digits, the
// parameters every authenticator app defaults to. A secret is 20 random bytes, shown as
// unpadded base32 and in an `otpauth://` URI for manual entry (no QR encoder). A code is
// accepted for the step before and after this one, for a phone's clock; `verify` says which
// step matched, so the caller can refuse that step a second time.

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base32"
import "core:strings"
import "core:time"

import "../escape"

SECRET_LEN :: 20
STEP :: 30
DIGITS :: 6

new_secret :: proc() -> (s: [SECRET_LEN]byte) {
	crypto.rand_bytes(s[:])
	return
}

// The secret as an authenticator app takes it: base32, no padding (20 bytes need none).
encode :: proc(secret: []byte, allocator := context.temp_allocator) -> string {
	return base32.encode(secret, allocator = allocator)
}

// A typed secret back: any case, spaces and dashes ignored.
decode :: proc(text: string) -> (secret: [SECRET_LEN]byte, ok: bool) {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]byte)text {
		switch c {
		case ' ', '-':
		case 'a' ..= 'z': strings.write_byte(&b, c - 32)
		case: strings.write_byte(&b, c)
		}
	}
	raw, err := base32.decode(strings.to_string(b), allocator = context.temp_allocator)
	if err != .None || len(raw) != SECRET_LEN { return }
	copy(secret[:], raw)
	return secret, true
}

// RFC 4226's HOTP: the code for one counter value.
hotp :: proc(secret: []byte, counter: u64, digits := DIGITS) -> u32 {
	msg: [8]byte
	for i in 0 ..< 8 { msg[i] = byte(counter >> uint(56 - 8 * i)) }
	mac: [20]byte
	hmac.sum(hash.Algorithm.Insecure_SHA1, mac[:], msg[:], secret)
	off := mac[19] & 0x0f
	bin := u32(mac[off] & 0x7f) << 24 | u32(mac[off + 1]) << 16 | u32(mac[off + 2]) << 8 | u32(mac[off + 3])
	mod: u32 = 1
	for _ in 0 ..< digits { mod *= 10 }
	return bin % mod
}

// RFC 6238's TOTP at a unix time, in seconds.
at :: proc(secret: []byte, unix: i64, digits := DIGITS) -> u32 {
	return hotp(secret, u64(unix / STEP), digits)
}

// Whether `text` (6 digits, spaces ignored) is the code for the step at `unix` or a neighbour;
// `step` is the one that matched. Constant time in the code compared.
verify :: proc(secret: []byte, text: string, unix: i64) -> (step: i64, ok: bool) {
	want: u32
	n := 0
	for c in transmute([]byte)text {
		switch c {
		case ' ':
		case '0' ..= '9':
			want = want * 10 + u32(c - '0')
			n += 1
		case: return 0, false
		}
	}
	if n != DIGITS { return 0, false }
	now := unix / STEP
	for d in i64(-1) ..= 1 {
		got := transmute([4]byte)hotp(secret, u64(now + d))
		w := transmute([4]byte)want
		if crypto.compare_constant_time(got[:], w[:]) == 1 { step, ok = now + d, true }
	}
	return
}

now :: proc() -> i64 { return time.time_to_unix(time.now()) }

// The URI an authenticator app takes by hand (`otpauth://totp/Issuer:account?…`).
uri :: proc(issuer, account, secret_text: string) -> string {
	return strings.concatenate({
		"otpauth://totp/", escape.url_encode(issuer), ":", escape.url_encode(account),
		"?secret=", secret_text, "&issuer=", escape.url_encode(issuer), "&algorithm=SHA1&digits=6&period=30",
	}, context.temp_allocator)
}
