package accounts_identity_accounts

// ---- /login, /logout and the member's sessions ---------------------------------------------
//
// Mounted by a profile on the accounts identity as {"accounts", identity.ROUTES[:]}. A sign-in
// is two hops off the loop, answered through one deferred response: the password's verify on
// the argon pool, then the session's write on the writer task.

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/html"
import "../../../platform/password"
import "../../../platform/store"
import "../../../platform/web"
import "../../../platform/workers"
import accounts ".."
import m "../models"
import views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/login", page, .Public, {.Private}, 0},
	{.Post, "/login", sign_in, .Public, {.Fragment}, 2048},
	{.Post, "/logout", sign_out, .Public, {.Fragment}, 0},
	{.Get, "/accounts/sessions", sessions_page, .Account_Self, {.Private}, 0},
	{.Post, "/accounts/sessions/revoke", revoke, .Account_Self, {.Fragment}, 256},
}

// §17.5: attempts, right or wrong, per client and from everyone (n set at init).
@(private)
WINDOW :: 15 * time.Minute
@(private)
logins_client := web.Limit{n = 5, window = WINDOW}
@(private)
logins_all := web.Limit{n = 40, window = WINDOW}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	b := strings.builder_make(context.temp_allocator)
	if c.viewer.id != 0 {
		html.page_head(&b, "Account", fmt.tprintf("Signed in as %s", c.viewer.name), "Sign out here, or see where else you are signed in.")
		views.signed_in(&b)
	} else {
		html.page_head(&b, "Account", "Sign in", "With the username and password an admin gave you.")
		views.login_form(&b, safe_next(web.query_get(req, "next")), insecure())
	}
	web.render_page(req, res, "Sign in", "/login", "Sign in to your account.", strings.to_string(b))
}

// ---- signing in ---------------------------------------------------------------------------

// On the heap from the handler to the answer: the pool's task, then the session's op.
@(private)
Login :: struct {
	using verify: password.Verify,
	deferred:     web.Deferred,
	user_id:      i64,
	failed:       int,
	known:        bool, // an enabled user by that name: a wrong password counts against it
	https:        bool,
	next:         [512]byte,
	next_len:     int,
	old:          [64]byte, // the session the request carried, closed by the sign-in
	old_len:      int,
}

@(private)
Opening :: struct {
	using open: m.Open_Session,
	login:      ^Login,
	token:      string, // the cookie's, in the op's arena
}

// POST /login, `username`, `password` and `next`.
@(private)
sign_in :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	if ok, retry := web.limit_hit(&logins_client, web.client_key(c.client)); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins from here: wait a little, then try again."))
		return
	}
	if ok, retry := web.limit_hit(&logins_all, 0); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins right now: wait a little, then try again."))
		return
	}
	f := web.form(req)
	name, pw := strings.trim_space(f["username"]), f["password"]
	if name == "" || pw == "" {
		web.respond_html(res, html.field_msg(false, "Enter your username and password."), .Unprocessable_Content)
		return
	}
	u, err := accounts.user_by_name(name)
	if err != .None && err != .Not_Found {
		web.respond_store_error(req, res, err)
		return
	}
	known := err == .None && u.disabled_at == 0
	if now := accounts.now_ms(); known && u.backoff_until > now {
		web.respond_limited(res, time.Duration(u.backoff_until - now) * time.Millisecond,
			html.field_msg(false, "Too many wrong passwords: wait a little, then try again."))
		return
	}

	l := new(Login, runtime.heap_allocator())
	l.user_id, l.failed, l.known, l.https = u.id, u.failed_logins, known, c.https
	l.next_len = copy(l.next[:], safe_next(f["next"]))
	if token := web.cookie(req, COOKIE); len(token) == accounts.TOKEN_TEXT {
		l.old_len = copy(l.old[:], accounts.hash_token(token))
	}
	web.defer_response(req, res, &l.deferred)
	// An unknown name is verified against the dummy all the same: the answer's time is the same.
	if !password.submit(&l.verify, pw, u.pw_hash if known else "", verified) {
		if r := web.resume(&l.deferred); r != nil {
			web.respond_html(r, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
			web.finish(&l.deferred, r)
		}
		free(l, runtime.heap_allocator())
	}
}

// Back on the loop from the pool.
@(private)
verified :: proc(t: ^workers.Task) {
	l := (^Login)(t)
	if !l.ok {
		if l.known && l.ran { count_failure(l.user_id, l.failed + 1) }
		if r := web.resume(&l.deferred); r != nil {
			if l.ran {
				web.respond_html(r, html.field_msg(false, "Wrong username or password."), .Unprocessable_Content)
			} else {
				web.respond_html(r, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
			}
			web.finish(&l.deferred, r)
		}
		free(l, runtime.heap_allocator())
		return
	}
	now := accounts.now_ms()
	token, hash := accounts.new_token()
	old := string(l.old[:l.old_len])
	op := store.new_op(Opening, len(token) + len(hash) + len(old))
	a := store.op_allocator(op)
	op.login = l
	op.token, op.token_hash, op.old_hash = strings.clone(token, a), strings.clone(hash, a), strings.clone(old, a)
	op.user_id, op.now = l.user_id, now
	op.expires_at, op.idle_before = now + accounts.lifetimes.max_ms, now - accounts.lifetimes.idle_ms
	op.done = opened
	if !accounts.open_session(op) {
		if r := web.resume(&l.deferred); r != nil {
			web.respond_store_error(web.request(&l.deferred), r, .Busy)
			web.finish(&l.deferred, r)
		}
		store.free_op(op)
		free(l, runtime.heap_allocator())
	}
}

@(private)
opened :: proc(o: ^store.Op) {
	op := (^Opening)(o)
	l := op.login
	defer {
		store.free_op(op)
		free(l, runtime.heap_allocator())
	}
	// A client that left has a session row it never got: it dies idle, or at its next sign-in's sweep.
	res := web.resume(&l.deferred)
	if res == nil { return }
	req := web.request(&l.deferred)
	if op.err != .None {
		web.respond_store_error(req, res, op.err)
	} else {
		web.set_header(res, "set-cookie", issue(op.token, l.https))
		go(req, res, string(l.next[:l.next_len]))
	}
	web.finish(&l.deferred, res)
}

// One more wrong password, and the account's door shut a little longer.
@(private)
count_failure :: proc(user_id: i64, failed: int) {
	op := store.new_op(m.Login_Failed, 0)
	op.user_id = user_id
	op.backoff_until = accounts.now_ms() + accounts.backoff_ms(failed)
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !accounts.login_failed(op) { store.free_op(op) }
}

// A session seen again, written at most once a minute (load_viewer).
@(private)
touch :: proc(token_hash: string, now: i64) {
	op := store.new_op(m.Touch_Session, len(token_hash))
	op.token_hash = strings.clone(token_hash, store.op_allocator(op))
	op.now = now
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !accounts.touch_session(op) { store.free_op(op) }
}

// ---- signing out and the sessions page ----------------------------------------------------

@(private)
sign_out :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	token := web.cookie(req, COOKIE)
	if c.viewer.id == 0 || len(token) != accounts.TOKEN_TEXT {
		web.set_header(res, "set-cookie", forget(c.https))
		go(req, res, "/")
		return
	}
	closing(req, res, accounts.hash_token(token), "/")
}

@(private)
sessions_page :: proc(req: ^web.Request, res: ^web.Response) {
	list := make([dynamic]m.Session, context.temp_allocator)
	if err := accounts.sessions_of(i64(web.ctx().viewer.id), &list); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Your sessions", "Every device signed in as you. Revoke one you don't recognise; it is signed out at its next request.")
	views.sessions(&b, list[:], current_hash(req))
	web.render_page(req, res, "Your sessions", "/accounts/sessions", "The devices signed in to your account.", strings.to_string(b))
}

// POST /accounts/sessions/revoke, `session`: one of the member's own (the store checks whose).
// Revoking this one is signing out.
@(private)
revoke :: proc(req: ^web.Request, res: ^web.Response) {
	h := web.form(req)["session"]
	if len(h) != 64 {
		web.respond_html(res, html.field_msg(false, "No such session."), .Unprocessable_Content)
		return
	}
	closing(req, res, h, "/login" if h == current_hash(req) else "")
}

@(private)
Closing :: struct {
	using close: m.Close_Session,
	deferred:    web.Deferred,
	current:     string, // this request's session, for the list's mark
	to:          string, // "" = answer the list again; else the cookie ends and the page goes there
	https:       bool,
}

@(private)
closing :: proc(req: ^web.Request, res: ^web.Response, token_hash, to: string) {
	c := web.ctx()
	current := current_hash(req)
	op := store.new_op(Closing, len(token_hash) + len(current) + len(to))
	a := store.op_allocator(op)
	op.token_hash, op.current, op.to = strings.clone(token_hash, a), strings.clone(current, a), strings.clone(to, a)
	op.user_id, op.https = i64(c.viewer.id), c.https
	op.done = closed
	web.defer_response(req, res, &op.deferred)
	if !accounts.close_session(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
closed :: proc(o: ^store.Op) {
	op := (^Closing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return }
	req := web.request(&op.deferred)
	switch {
	case op.err != .None:
		web.respond_store_error(req, res, op.err)
	case op.to != "":
		web.set_header(res, "set-cookie", forget(op.https))
		go(req, res, op.to)
	case:
		list := make([dynamic]m.Session, context.temp_allocator)
		if err := accounts.sessions_of(op.user_id, &list); err != .None {
			web.respond_store_error(req, res, err)
		} else {
			b := strings.builder_make(context.temp_allocator)
			views.sessions(&b, list[:], op.current)
			web.respond_html(res, strings.to_string(b))
		}
	}
	web.finish(&op.deferred, res)
}

// ---- helpers ------------------------------------------------------------------------------

// The hash of the session this request carries, or "".
@(private)
current_hash :: proc(req: ^web.Request) -> string {
	token := web.cookie(req, COOKIE)
	return accounts.hash_token(token) if len(token) == accounts.TOKEN_TEXT else ""
}

// Where an htmx form lands: HX-Redirect; a plain form post: 303.
@(private)
go :: proc(req: ^web.Request, res: ^web.Response, to: string) {
	if web.is_htmx(req) {
		web.set_header(res, "hx-redirect", to)
		web.respond_status(res, .No_Content)
		return
	}
	web.set_header(res, "location", to)
	web.respond_status(res, .See_Other)
}

// A path on this site, or "/": never another origin.
@(private)
safe_next :: proc(next: string) -> string {
	return next if html.site_path(next) else "/"
}
