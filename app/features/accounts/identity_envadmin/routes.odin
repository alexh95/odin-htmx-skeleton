package accounts_identity_envadmin

// ---- /login, /logout and /step-up: the admin's password -------------------------------------
//
// Mounted by a profile on the envadmin identity as {"accounts", identity.ROUTES[:]}. The
// password is verified on the argon pool behind a deferred response; sign-ins are limited per
// client and overall (§17.5) and go to the audit log (a log line on a memory build).

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/html"
import "../../../platform/password"
import "../../../platform/web"
import "../../../platform/workers"
import audit_store "store:audit"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/login", page, .Public, {.Private}, 0},
	{.Post, "/login", sign_in, .Public, {.Fragment}, 2048},
	{.Post, "/logout", sign_out, .Public, {.Fragment}, 0},
	{.Get, "/step%-up", step_up_page, .Account_Self, {.Private}, 0},
	{.Post, "/step%-up", sign_in, .Account_Self, {.Fragment}, 2048},
}

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
		html.page_head(&b, "Admin", fmt.tprintf("Signed in as %s", c.viewer.name), "This browser stays signed in until you sign out or the cookie ends.")
		html.w(&b, `<section class="block"><form hx-post="/logout"><button class="btn btn-outline" type="submit">Sign out</button></form></section>`)
	} else {
		html.page_head(&b, "Admin", "Sign in", "This site has one admin.")
		form(&b, "/login", safe_next(web.query_get(req, "next")), "Sign in")
	}
	web.render_page(req, res, "Sign in", "/login", "Sign in.", strings.to_string(b))
}

@(private)
step_up_page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Confirm it's you", "This needs a recent password.")
	form(&b, "/step-up", safe_next(web.query_get(req, "next")), "Confirm")
	web.render_page(req, res, "Confirm it's you", "/step-up", "Confirm it's you.", strings.to_string(b))
}

@(private)
form :: proc(b: ^strings.Builder, action, next, button: string) {
	fmt.sbprintf(b, `<section class="block"><form class="card login-form" hx-post="%s"
      hx-status:4xx="target:#login-error swap:innerHTML" hx-status:5xx="target:#login-error swap:innerHTML">`, action)
	fmt.sbprintf(b, `<label class="field"><span>Password</span><input id="password" name="password" type="password" required maxlength="%d" autocomplete="current-password"></label>`, password.MAX_LEN)
	html.w(b, `<input type="hidden" name="next" value="`)
	html.esc(b, next)
	fmt.sbprintf(b, `"><button class="btn btn-primary" type="submit">%s</button><p class="field-msg form-error" id="login-error" role="alert"></p></form></section>`, button)
}

@(private)
Login :: struct {
	using verify: password.Verify,
	deferred:     web.Deferred,
	https:        bool,
	client:       u64,
	next:         [512]byte,
	next_len:     int,
}

// POST /login and POST /step-up: `password` and `next`. Either way a right password is a fresh
// cookie, so a step-up is a sign-in.
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
	if f["password"] == "" {
		web.respond_html(res, html.field_msg(false, "Enter the password."), .Unprocessable_Content)
		return
	}
	l := new(Login, runtime.heap_allocator())
	l.https, l.client = c.https, web.client_key(c.client)
	l.next_len = copy(l.next[:], safe_next(f["next"]))
	web.defer_response(req, res, &l.deferred)
	// With no hash set, the dummy: the answer is no, in the same time.
	if !password.submit(&l.verify, f["password"], st.hash, verified) {
		answer(l, "Busy: try again in a moment.", .Service_Unavailable)
	}
}

@(private)
verified :: proc(t: ^workers.Task) {
	l := (^Login)(t)
	client := fmt.tprintf("%016x", l.client)
	switch {
	case !l.ran:
		answer(l, "Busy: try again in a moment.", .Service_Unavailable)
	case !l.ok:
		audit_store.append({client = client}, "accounts.sign_in_failed", {"user", 1}, "", "factor=password")
		answer(l, "That isn't the password.", .Unprocessable_Content)
	case:
		defer free(l, runtime.heap_allocator())
		res := web.resume(&l.deferred)
		if res == nil { return }
		audit_store.append({1, st.name, client}, "accounts.sign_in", {"session", 0}, "", "")
		web.set_header(res, "set-cookie", issue(l.https))
		go(web.request(&l.deferred), res, string(l.next[:l.next_len]))
		web.finish(&l.deferred, res)
	}
}

@(private)
answer :: proc(l: ^Login, why: string, status: web.Status) {
	if r := web.resume(&l.deferred); r != nil {
		web.respond_html(r, html.field_msg(false, why), status)
		web.finish(&l.deferred, r)
	}
	free(l, runtime.heap_allocator())
}

@(private)
sign_out :: proc(req: ^web.Request, res: ^web.Response) {
	web.set_header(res, "set-cookie", forget(web.ctx().https))
	go(req, res, "/")
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

@(private)
safe_next :: proc(next: string) -> string {
	return next if html.site_path(next) else "/"
}
