package accounts_identity_nick

// ---- /login and /logout: the nickname form -----------------------------------------------
//
// Mounted by a profile on the nick identity as {"accounts", identity.ROUTES[:]}. front
// sends a Guest who lacks a route's perm to /login (§17.2), so this is where a LAN
// visitor picks a nickname and an off-LAN one learns that chat is open on the LAN.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import "../../../platform/web"

ROUTES := [?]web.Route {
	{.Get, "/login", page, .Public, {.Private}, 0},
	{.Post, "/login", pick_name, .Public, {.Fragment}, 1024},
	{.Post, "/logout", sign_out, .Public, {.Fragment}, 0},
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	b := strings.builder_make(context.temp_allocator)
	next := safe_next(web.query_get(req, "next"))
	switch {
	case c.viewer.id != 0:
		html.page_head(&b, "Nickname", fmt.tprintf("You are %s", c.viewer.name), "Pick another nickname, or sign out.")
		form(&b, c.viewer.name, next)
		html.w(&b, `<form class="nick-out" hx-post="/logout"><button class="btn btn-outline" type="submit">Sign out</button></form>`)
	case may_pick(c.client):
		html.page_head(&b, "Nickname", "Pick a nickname", "No account and no password: a nickname, kept in a cookie on this device, is enough to post on the LAN.")
		form(&b, "", next)
	case:
		lan_notice(&b)
	}
	web.render_page(req, res, "Nickname", "/login", "Pick a nickname to post.", strings.to_string(b))
}

// What an off-LAN visitor sees instead of a form (ANSWERS round 9); chat's own page
// shows the same.
lan_notice :: proc(b: ^strings.Builder) {
	html.page_head(b, "Nickname", "Chat is open on the LAN", "Posting needs a nickname, and nicknames are given on the local network only.")
	html.w(b, `<section class="block"><p class="muted">Connect from the LAN to pick one.</p></section>`)
}

@(private)
form :: proc(b: ^strings.Builder, current, next: string) {
	html.w(b, `<section class="block"><form class="nick-form card" hx-post="/login" hx-target="#nick-error" hx-swap="innerHTML">`)
	fmt.sbprintf(b, `<label for="nick">Nickname</label><input id="nick" name="nick" required maxlength="%d" autocomplete="nickname" value="`, MAX_NAME)
	html.esc(b, current)
	html.w(b, `"><input type="hidden" name="next" value="`)
	html.esc(b, next)
	html.w(b, `"><button class="btn btn-primary" type="submit">Use this nickname</button><p class="field-msg form-error" id="nick-error" role="alert"></p></form></section>`)
}

// POST /login, `nick` and `next`: the cookie, then off to `next`. A refused name is a
// 422 into the form's error slot.
@(private)
pick_name :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	f := web.form(req)
	if !may_pick(c.client) {
		web.respond_html(res, html.field_msg(false, "Nicknames are given on the LAN only."), .Forbidden)
		return
	}
	name, problem := check(f["nick"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	web.set_header(res, "set-cookie", pick(name, c.https, c.viewer.id))
	go(req, res, safe_next(f["next"]))
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

// A path on this site, or "/": never another origin (`//host`, `/\host`).
@(private)
safe_next :: proc(next: string) -> string {
	if len(next) == 0 || next[0] != '/' || len(next) > 1 && (next[1] == '/' || next[1] == '\\') { return "/" }
	for c in transmute([]byte)next {
		if c < 0x21 || c == 0x7f { return "/" }
	}
	return next
}
