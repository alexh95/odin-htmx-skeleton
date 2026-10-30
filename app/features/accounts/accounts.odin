package accounts

// ---- accounts: users and their sessions (PLAN §17.1, D35) ---------------------------------
//
// The domain under `identity_accounts`, which is how a profile reaches it: the feature has no
// web package of its own. A session is an opaque 32-byte token in the `sid` cookie; the store
// keeps only its SHA-256. A session ends 14 days after it was last seen or 30 after it began,
// whichever is first (ACCOUNTS_SESSION_IDLE and ACCOUNTS_SESSION_MAX shorten them for tests).
// Wrong passwords back an account off exponentially, never lock it.

import "core:crypto"
import "core:crypto/hash"
import "core:encoding/base64"
import "core:encoding/hex"
import "core:strings"
import "core:time"

import "../../platform/password"
import m "models"
import accounts_store "store:accounts"

// The token's bytes; as unpadded base64url it is TOKEN_TEXT characters.
TOKEN_LEN :: 32
TOKEN_TEXT :: 43

// A username longer than this names no one (the login form's cap).
MAX_USERNAME :: 64
MAX_PASSWORD :: password.MAX_LEN

// A session's last_seen is written at most this often: a page view isn't a write.
TOUCH_EVERY_MS :: 60_000

Lifetimes :: struct {
	idle_ms, max_ms: i64,
}

// Set by the identity at boot, from its env rows.
lifetimes := Lifetimes{idle_ms = 14 * 86_400_000, max_ms = 30 * 86_400_000}

now_ms :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1e6 }

// A new token for the cookie, and the hash the store keeps, both in the temp allocator.
new_token :: proc() -> (token, token_hash: string) {
	raw: [TOKEN_LEN]byte
	crypto.rand_bytes(raw[:])
	token = base64.encode(raw[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})
	return token, hash_token(token)
}

// The hex SHA-256 of a cookie's token.
hash_token :: proc(token: string) -> string {
	sum: [32]byte
	hash.hash_string_to_buffer(.SHA256, token, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

// Whether a session is still good at `now`: before its absolute end and seen within the idle one.
live :: proc(s: m.Session, now: i64) -> bool {
	return now < s.expires_at && now - s.last_seen < lifetimes.idle_ms
}

// The live session a cookie's token names, and its enabled user.
// .Not_Found: no such session, or it ended, or its user is disabled; any other error is the
// store's, and says nothing about the session.
signed_in :: proc(token: string, now: i64) -> (u: m.User, s: m.Session, err: m.Error) {
	if len(token) != TOKEN_TEXT { return {}, {}, .Not_Found }
	s, err = accounts_store.session(hash_token(token))
	if err != .None { return }
	if !live(s, now) { return {}, {}, .Not_Found }
	u, err = accounts_store.user_by_id(s.user_id)
	if err != .None { return }
	if u.disabled_at != 0 { return {}, {}, .Not_Found }
	return u, s, .None
}

// How long a wrong password shuts an account's door: the first three are free, then 1 s,
// doubling, at most 5 min. Slow enough to stop guessing, never a lockout (07 §5.2).
backoff_ms :: proc(failed: int) -> i64 {
	if failed < 3 { return 0 }
	return min(i64(1000) << uint(min(failed - 3, 20)), 300_000)
}

user_by_id :: proc(id: i64) -> (m.User, m.Error) {
	return accounts_store.user_by_id(id)
}

user_by_name :: proc(username: string) -> (m.User, m.Error) {
	if len(username) > MAX_USERNAME { return {}, .Not_Found }
	return accounts_store.user_by_name(username)
}

sessions_of :: proc(user_id: i64, into: ^[dynamic]m.Session) -> m.Error {
	return accounts_store.sessions_of(user_id, into)
}

count_admins :: proc() -> (int, m.Error) {
	return accounts_store.count_admins()
}

// At boot, after the migrations: the first admin from ACCOUNTS_ADMIN_HASH.
bootstrap_admin :: proc(username, pw_hash: string) -> (created: bool, err: m.Error) {
	return accounts_store.bootstrap_admin(username, pw_hash)
}

recovery_left :: proc(user_id: i64) -> (int, m.Error) {
	return accounts_store.recovery_left(user_id)
}

// ---- recovery codes ---------------------------------------------------------------------

// Ten codes like `k7mq-x2rf`: 40 random bits each, from an alphabet with no look-alikes. Shown
// once, at enrolment; the store keeps their hashes.
@(private)
CODE_ALPHABET :: "abcdefghjkmnpqrstuvwxyz023456789" // 32: no i, l, o or 1

new_recovery_codes :: proc() -> (codes: [m.RECOVERY_CODES]string) {
	for &c in codes {
		raw: [8]byte
		crypto.rand_bytes(raw[:])
		b: [9]byte
		for i in 0 ..< 8 {
			at := i if i < 4 else i + 1
			alphabet := CODE_ALPHABET
			b[at] = alphabet[raw[i] & 31]
		}
		b[4] = '-'
		c = strings.clone(string(b[:]), context.temp_allocator)
	}
	return
}

// The hash of a typed code: any case, the dash and spaces ignored; "" when it can't be one.
hash_recovery :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]byte)text {
		switch c {
		case '-', ' ':
		case 'A' ..= 'Z': strings.write_byte(&b, c + 32)
		case: strings.write_byte(&b, c)
		}
	}
	norm := strings.to_string(b)
	if len(norm) != 8 { return "" }
	return hash_token(norm)
}

// The writes: each queued to the writer, false when the store is busy (`done` won't run).
login_failed :: proc(op: ^m.Login_Failed) -> bool { return accounts_store.login_failed(op) }
open_session :: proc(op: ^m.Open_Session) -> bool { return accounts_store.open_session(op) }
touch_session :: proc(op: ^m.Touch_Session) -> bool { return accounts_store.touch_session(op) }
close_session :: proc(op: ^m.Close_Session) -> bool { return accounts_store.close_session(op) }
set_totp :: proc(op: ^m.Set_Totp) -> bool { return accounts_store.set_totp(op) }
step_up :: proc(op: ^m.Step_Up) -> bool { return accounts_store.step_up(op) }
