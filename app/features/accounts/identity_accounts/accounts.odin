package accounts_identity_accounts

// ---- accounts: usernames, passwords and server-side sessions (PLAN §17.1, D35) --------------
//
// A member of the `identity:` family, `full`'s (LC §3), on SQLite. A member signs in at /login
// with a username and a password (argon2id on platform/password's pool) and gets an opaque
// token in the `sid` cookie: `HttpOnly; SameSite=Lax; Path=/`, no Domain (host-only, so it never
// reaches `full`'s lab host), `Secure` per COOKIE_SECURE. The store keeps only the token's
// SHA-256. The token rotates on every sign-in; a privilege change rotates it too (slice 6).
// The first admin comes from ACCOUNTS_ADMIN_HASH, made with `--hash-password`.

import "core:crypto"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/obs"
import "../../../platform/password"
import accounts ".."

NAME :: "accounts"
SETS_COOKIE :: true

COOKIE :: "sid"

ENV := [?]env.Row {
	{name = "ACCOUNTS_ADMIN_HASH", kind = .Secret, def = "", doc = "the bootstrap admin's argon2id hash (bin --hash-password), used while no enabled admin exists"},
	{name = "ACCOUNTS_ADMIN_NAME", kind = .String, def = "admin", doc = "the bootstrap admin's username"},
	{name = "ACCOUNTS_ARGON_THREADS", kind = .Int, def = "0", doc = "argon2id pool threads, each holding 19 MiB: 0 = 1 with two cores or fewer, else 2"},
	{name = "ACCOUNTS_SESSION_IDLE", kind = .Duration, def = "14d", doc = "a session ends this long after it was last seen"},
	{name = "ACCOUNTS_SESSION_MAX", kind = .Duration, def = "30d", doc = "a session ends this long after sign-in, seen or not"},
	{name = "ACCOUNTS_LOGIN_PER_CLIENT", kind = .Int, def = "5", doc = "sign-in attempts per client per 15 min"},
	{name = "ACCOUNTS_LOGIN_OVERALL", kind = .Int, def = "40", doc = "sign-in attempts from everyone per 15 min"},
	{name = "ACCOUNTS_ADMIN_TOTP", kind = .Enum, def = "required", choices = "required|optional", doc = "required: an Admin without TOTP is a Member until they turn it on (§17.1)"},
	{name = "ACCOUNTS_STEP_UP_WINDOW", kind = .Duration, def = "10m", doc = "how recent a password or code a .Step_Up route asks for"},
	{name = "ACCOUNTS_REGISTRATION", kind = .Enum, def = "invite", choices = "invite|open|closed", doc = "who may register at /register: with an invite (Q10), anyone, or no one"},
	{name = "ACCOUNTS_REGISTER_PER_HOUR", kind = .Int, def = "3", doc = "registrations tried per client per hour"},
	{name = "ACCOUNTS_CODES_PER_HOUR", kind = .Int, def = "10", doc = "invite and reset codes tried per client per hour"},
}

COOKIE_ENV := [?]env.Row {
	{name = "COOKIE_SECURE", kind = .Enum, def = "auto", choices = "auto|1|0", doc = "Secure on the session cookie: auto = when the request came as https through a trusted proxy; 0 warns at every boot"},
}

Secure :: enum u8 {
	Auto,
	Always,
	Never,
}

@(private)
st: struct {
	secure:      Secure,
	admin_totp:  bool,     // an Admin needs TOTP to be one
	pending_key: [32]byte, // signs a sign-in's pending second step; a restart drops them all
}

// At boot, from app.boot: the env rows, the lifetimes and the argon pool.
init :: proc() {
	env.record("ACCOUNTS_", ENV[:])
	env.record("", COOKIE_ENV[:])
	switch env.str("COOKIE_SECURE") {
	case "1": st.secure = .Always
	case "0":
		st.secure = .Never
		// Plain-http stages need it (07 §5.5); say so every boot, so it isn't forgotten.
		if l, ok := obs.begin(.Warning, "accounts", "cookie_insecure"); ok {
			obs.str(&l, "msg", "COOKIE_SECURE=0: the session cookie travels over plain http")
			obs.end(&l)
		}
	}
	accounts.lifetimes = {
		idle_ms = i64(env.duration("ACCOUNTS_SESSION_IDLE") / time.Millisecond),
		max_ms = i64(env.duration("ACCOUNTS_SESSION_MAX") / time.Millisecond),
	}
	st.admin_totp = env.str("ACCOUNTS_ADMIN_TOTP") == "required"
	switch env.str("ACCOUNTS_REGISTRATION") {
	case "open":   accounts.registration = .Open
	case "closed": accounts.registration = .Closed
	case:          accounts.registration = .Invite
	}
	registers.n = env.int_("ACCOUNTS_REGISTER_PER_HOUR")
	codes_tried.n = env.int_("ACCOUNTS_CODES_PER_HOUR")
	authz.step_up_window = i64(env.duration("ACCOUNTS_STEP_UP_WINDOW") / time.Second)
	crypto.rand_bytes(st.pending_key[:])
	logins_client.n = env.int_("ACCOUNTS_LOGIN_PER_CLIENT")
	logins_all.n = env.int_("ACCOUNTS_LOGIN_OVERALL")
	threads := env.int_("ACCOUNTS_ARGON_THREADS")
	if threads <= 0 { threads = 1 if os.get_processor_core_count() <= 2 else 2 }
	password.start(threads)
	obs.limit("argon", "memory", i64(threads) * 19 * 1024 * 1024, "bytes")
}

// The identity's own CLI flag: `--hash-password` reads a password from stdin (one line) and
// prints its PHC string, for ACCOUNTS_ADMIN_HASH, and to stderr how long the derive took,
// which says what a sign-in costs on this machine (§17.1: ≤ 100 ms wanted).
cli :: proc() {
	for a in os.args[1:] {
		if a != "--hash-password" { continue }
		buf: [password.MAX_LEN + 2]byte
		n, _ := os.read(os.stdin, buf[:])
		pw := strings.trim_right(string(buf[:max(n, 0)]), "\r\n")
		switch password.check(pw) {
		case .Too_Short:
			fmt.eprintfln("--hash-password: at least %d bytes", password.MIN_LEN)
			os.exit(2)
		case .Too_Long:
			fmt.eprintfln("--hash-password: at most %d bytes", password.MAX_LEN)
			os.exit(2)
		case .Ok:
		}
		start := time.tick_now()
		phc := password.hash(pw)
		took := time.tick_since(start)
		fmt.println(phc)
		fmt.eprintfln("derive: %.1f ms", time.duration_milliseconds(took))
		os.exit(0)
	}
}

// From main, after the migrations: the first admin, while no enabled one exists. A hash that
// isn't one of platform/password's refuses to boot; no admin and no hash warns.
bootstrap :: proc() {
	phc := env.str("ACCOUNTS_ADMIN_HASH")
	if phc == "" {
		if n, _ := accounts.count_admins(); n == 0 {
			if l, ok := obs.begin(.Warning, "accounts", "no_admin"); ok {
				obs.str(&l, "msg", "no admin yet: set ACCOUNTS_ADMIN_HASH (bin --hash-password)")
				obs.end(&l)
			}
		}
		return
	}
	if _, _, _, ok := password.decode(phc); !ok {
		fmt.eprintln("accounts: ACCOUNTS_ADMIN_HASH is not an argon2id hash from --hash-password")
		os.exit(78)
	}
	made, err := accounts.bootstrap_admin(env.str("ACCOUNTS_ADMIN_NAME"), phc)
	if err != .None {
		fmt.eprintln("accounts: the bootstrap admin could not be written")
		os.exit(70)
	}
	if made {
		if l, ok := obs.begin(.Info, "accounts", "admin_created"); ok {
			obs.str(&l, "name", env.str("ACCOUNTS_ADMIN_NAME"))
			obs.end(&l)
		}
	}
}

// The viewer a request's `sid` names; a cookie whose session has ended is cleared.
load_viewer :: proc(ask: authz.Ask) -> (v: authz.Viewer, set_cookie: string) {
	token := authz.cookie(ask.cookies, COOKIE)
	if token == "" { return authz.GUEST, "" }
	now := accounts.now_ms()
	u, s, err := accounts.signed_in(token, now)
	#partial switch err {
	case .None:
	case .Not_Found:
		return authz.GUEST, forget(ask.https)
	case:
		// The store failed, not the session: a guest this once, and the cookie kept.
		if l, ok := obs.begin(.Warning, "accounts", "session_read"); ok {
			obs.str(&l, "err", fmt.tprint(err))
			obs.end(&l)
		}
		return authz.GUEST, ""
	}
	if now - s.last_seen >= accounts.TOUCH_EVERY_MS { touch(s.token_hash, now) }
	role := u.role
	// An Admin is one only with a second factor; until then /accounts/totp says why.
	if role == .Admin && u.totp_secret == "" && st.admin_totp { role = .User }
	return authz.Viewer{id = u64(u.id), name = u.display, role = role, step_up_at = s.step_up_at / 1000}, ""
}

// ---- the cookie -------------------------------------------------------------------------

secure :: proc(https: bool) -> bool {
	switch st.secure {
	case .Always: return true
	case .Never:  return false
	case .Auto:
	}
	return https
}

insecure :: proc() -> bool { return st.secure == .Never }

// A Set-Cookie value for a new session's token; it lasts as long as the session can.
issue :: proc(token: string, https: bool) -> string {
	buf: [24]byte
	age := strconv.write_int(buf[:], accounts.lifetimes.max_ms / 1000, 10)
	return strings.concatenate({COOKIE, "=", token, "; Path=/; Max-Age=", age, "; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else ""}, context.temp_allocator)
}

// A Set-Cookie value that ends the cookie.
forget :: proc(https: bool) -> string {
	return strings.concatenate({COOKIE, "=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else ""}, context.temp_allocator)
}
