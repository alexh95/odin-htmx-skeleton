package controllers

import "core:fmt"
import "core:hash"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

import http "../../odin-http"
import "../models"
import "../repository"
import "../services"
import "../views"

// ---- controllers --------------------------------------------------------
//
// The HTTP layer. Each handler parses the request, calls a service, renders a
// view and responds. Nothing here knows how the store works; nothing in the
// services knows it is being driven over HTTP.

// ---- request helpers ----------------------------------------------------

// Read a single query parameter, percent-decoded. odin-http hands us the raw
// query string (everything after '?'); we walk it once rather than building a
// map for the one key we want.
query_get :: proc(req: ^http.Request, key: string) -> string {
	q := req.url.query
	for part in strings.split_by_byte_iterator(&q, '&') {
		eq := strings.index_byte(part, '=')
		k := eq < 0 ? part : part[:eq]
		if k == key {
			return query_decode(eq < 0 ? "" : part[eq + 1:])
		}
	}
	return ""
}

query_int :: proc(req: ^http.Request, key: string, fallback: int) -> int {
	s := query_get(req, key)
	if s == "" {
		return fallback
	}
	return to_int(s)
}

@(private = "file")
to_int :: proc(s: string) -> int {
	n, _ := strconv.parse_int(s, 10)
	return n
}

@(private = "file")
query_decode :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	t := s
	if strings.index_byte(s, '+') >= 0 {
		t, _ = strings.replace_all(s, "+", " ", context.temp_allocator)
	}
	dec, ok := net.percent_decode(t, context.temp_allocator)
	return ok ? dec : t
}

// Parse an application/x-www-form-urlencoded body into key→value. Unlike
// http.body_url_encoded, this decodes '+' as space — htmx 4 sends spaces as '+'
// (the form-encoding standard) and odin-http's parser only percent-decodes. Uses
// the same '+'-aware decode as query strings (query_decode), so a literal '+'
// sent as %2B still round-trips.
@(private = "file")
body_form :: proc(body: http.Body) -> map[string]string {
	m := make(map[string]string, context.temp_allocator)
	s := string(body)
	for part in strings.split_by_byte_iterator(&s, '&') {
		if part == "" {
			continue
		}
		eq := strings.index_byte(part, '=')
		key := eq < 0 ? part : part[:eq]
		val := eq < 0 ? "" : part[eq + 1:]
		m[query_decode(key)] = query_decode(val)
	}
	return m
}

render_page :: proc(res: ^http.Response, title, active, description, content: string) {
	http.respond_html(res, views.layout(title, active, description, content))
}

// ---- pages --------------------------------------------------------------

page_dashboard :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"Dashboard",
		"/",
		"A proof-of-concept component kit served from a single Odin binary and wired up with HTMX: dashboard, data table with CRUD, forms with live validation, and a vibrant component gallery.",
		views.view_dashboard(),
	)
}

page_components :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"Components",
		"/components",
		"A gallery of UI components built with Odin + HTMX — buttons, badges, avatars, progress, tabs, accordions, dialogs, drawers and toasts, each swapped in over a single request.",
		views.view_components(),
	)
}

page_forms :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"Forms",
		"/forms",
		"Forms with live inline validation powered by HTMX over an Odin backend: email checks as you type, selects, switches, a range slider, and a real submit that creates a contact.",
		views.view_forms(),
	)
}

page_data :: proc(req: ^http.Request, res: ^http.Response) {
	sort := query_get(req, "sort")
	if sort == "" {
		sort = "name"
	}
	p := services.service_page(query_get(req, "q"), query_get(req, "status"), sort, 1)
	render_page(
		res,
		"Data & CRUD",
		"/data",
		"A live contacts table over a SQLite store: filter, sort and paginate, plus create, update and delete — all over HTMX with no full-page reloads.",
		views.view_data(p),
	)
}

page_about :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"About",
		"/about",
		"About this project — a starter skeleton for simple, server-rendered websites: an Odin backend rendering HTML with HTMX over a SQLite store, in one self-contained binary. Links to the source on GitHub.",
		views.view_about(),
	)
}

// ---- search -------------------------------------------------------------

frag_search :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, views.view_search_results(query_get(req, "q")))
}

Contact_DTO :: struct {
	id:     int,
	name:   string,
	email:  string,
	role:   string,
	status: string,
	score:  int,
}

// The non-HTMX surface: same data, plain JSON. Proves the service layer stands
// on its own.
api_search :: proc(req: ^http.Request, res: ^http.Response) {
	q := strings.trim_space(query_get(req, "q"))
	rn := models.ROLE_NAMES
	sn := models.STATUS_NAMES
	out := make([dynamic]Contact_DTO, context.temp_allocator)
	for c in repository.repo_list() {
		if q == "" || services.contact_matches(c, q) {
			append(&out, Contact_DTO{c.id, c.name, c.email, rn[c.role], sn[c.status], c.score})
		}
	}
	http.respond_json(res, out[:])
}

// ---- contacts table + CRUD ----------------------------------------------

frag_contacts :: proc(req: ^http.Request, res: ^http.Response) {
	sort := query_get(req, "sort")
	if sort == "" {
		sort = "name"
	}
	p := services.service_page(query_get(req, "q"), query_get(req, "status"), sort, query_int(req, "page", 1))
	http.respond_html(res, views.view_contacts_region(p))
}

// Drilldown: the full contact record + a derived activity trail + related
// contacts, rendered as a drawer into #overlay.
contact_detail :: proc(req: ^http.Request, res: ^http.Response) {
	id := to_int(req.url_params[0])
	c, ok := repository.repo_get(id)
	if !ok {
		http.respond(res, http.Status.Not_Found)
		return
	}
	tl := services.service_timeline(c)
	rel := services.service_related(c, 4)
	// frag=1 → just the <aside> (in-place swap of an open drawer); edit=1 → edit form.
	if query_get(req, "frag") == "1" {
		http.respond_html(res, views.view_contact_detail_frag(c, tl, rel, query_get(req, "edit") == "1"))
	} else {
		http.respond_html(res, views.view_contact_detail(c, tl, rel))
	}
}

// contacts_update is the only body handler that needs more than the response in
// its callback (the row id from the path), so it threads this small struct through
// http.body's user pointer — allocated in the request arena, so it outlives the
// possibly-deferred callback. Handlers that need only the response pass `res`
// itself as the user pointer (see contacts_create), the same way odin-http does.
@(private = "file")
Form_Ctx :: struct {
	res: ^http.Response,
	id:  int,
}

contacts_create :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user
		if err != nil {
			http.respond(res, http.Status.Bad_Request)
			return
		}
		form := body_form(body)
		name := form["name"]
		email := form["email"]

		errs := services.validate_contact(name, email)
		if len(errs) > 0 {
			http.respond_html(res, views.view_toast("error", errs[0].msg, true))
			return
		}

		role, _ := models.role_from(form["role"])
		c := repository.repo_create(strings.trim_space(name), strings.trim_space(email), role, .Invited, 50)

		b := strings.builder_make(context.temp_allocator)
		views.view_contact_row(&b, c, true)
		strings.write_string(&b, views.view_toast("success", "Contact added.", true))
		http.respond_html(res, strings.to_string(b))
	})
}

contacts_update :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	ctx.id = to_int(req.url_params[0])
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Form_Ctx)user
		res := ctx.res

		form := body_form(body)
		action := form["action"]
		// view=detail → respond with the re-rendered detail drawer (the action came
		// from the drawer); otherwise the table row.
		is_detail := form["view"] == "detail"

		c: models.Contact
		ok: bool
		edit_errs: []services.Field_Error
		if action == "cycle" {
			if cur, found := repository.repo_get(ctx.id); found {
				next := models.Status((int(cur.status) + 1) % len(models.Status))
				c, ok = repository.repo_set_status(ctx.id, next)
			}
		} else if name := strings.trim_space(form["name"]); name != "" {
			// full edit from the detail drawer
			email := strings.trim_space(form["email"])
			edit_errs = services.validate_contact(name, email)
			if len(edit_errs) == 0 {
				role, _ := models.role_from(form["role"])
				status, _ := models.status_from(form["status"])
				score := clamp(to_int(form["score"]), 0, 100)
				c, ok = repository.repo_update(ctx.id, name, email, role, status, score)
			} else {
				c, ok = repository.repo_get(ctx.id) // invalid (the form guards this, but be graceful)
			}
		} else {
			c, ok = repository.repo_get(ctx.id)
		}

		if !ok {
			http.respond(res, http.Status.Not_Found)
			return
		}
		if is_detail {
			// the re-rendered drawer (main swap into the open drawer), plus a refresh of
			// the table row behind it. A plain `hx-swap-oob` <tr> can't ride along: a
			// response that starts with the non-table <aside> is body-parsed, which drops
			// a trailing <tr>; and a <template> wrapper hides it from htmx's OOB
			// querySelectorAll (which doesn't descend into templates). htmx 4's
			// <hx-partial> is built for this — it becomes a <template> (so the <tr>
			// survives parsing) that htmx explicitly processes into hx-target/hx-swap.
			b := strings.builder_make(context.temp_allocator)
			strings.write_string(&b, views.view_contact_detail_frag(c, services.service_timeline(c), services.service_related(c, 4), false))
			fmt.sbprintf(&b, `<hx-partial hx-target="#contact-%d" hx-swap="outerHTML">`, c.id)
			views.view_contact_row(&b, c, false)
			strings.write_string(&b, `</hx-partial>`)
			if len(edit_errs) > 0 {
				strings.write_string(&b, views.view_toast("error", edit_errs[0].msg, true))
			}
			http.respond_html(res, strings.to_string(b))
		} else {
			b := strings.builder_make(context.temp_allocator)
			views.view_contact_row(&b, c, false)
			http.respond_html(res, strings.to_string(b))
		}
	})
}

contacts_delete :: proc(req: ^http.Request, res: ^http.Response) {
	id := to_int(req.url_params[0])
	if !repository.repo_delete(id) {
		http.respond(res, http.Status.Not_Found)
		return
	}
	// From the table row: empty body, the outerHTML swap removes the row. From the
	// detail drawer: the empty primary body closes the overlay, and an OOB swap
	// removes the now-stale table row behind it.
	if query_get(req, "from") == "drawer" {
		http.respond_html(res, fmt.tprintf(`<tr id="contact-%d" hx-swap-oob="delete"></tr>`, id))
	} else {
		http.respond_html(res, "")
	}
}

// ---- forms --------------------------------------------------------------

validate_email_field :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user
		form := body_form(body)
		email := strings.trim_space(form["email"])
		if email == "" {
			http.respond_html(res, "")
			return
		}
		if services.valid_email(email) {
			http.respond_html(res, views.view_field_msg(true, "Looks good."))
		} else {
			http.respond_html(res, views.view_field_msg(false, "That doesn't look like an email."))
		}
	})
}

forms_submit :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user
		form := body_form(body)
		name := form["name"]
		email := form["email"]

		errs := services.validate_contact(name, email)
		if len(errs) > 0 {
			http.respond_html(res, views.view_form_errors(errs))
			return
		}

		role, _ := models.role_from(form["role"])
		status, _ := models.status_from(form["status"])
		score := clamp(to_int(form["score"]), 0, 100)
		c := repository.repo_create(strings.trim_space(name), strings.trim_space(email), role, status, score)

		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, views.view_form_result(c))
		strings.write_string(&b, views.view_toast("success", "Saved to the SQLite store.", true))
		http.respond_html(res, strings.to_string(b))
	})
}

// ---- ui fragments -------------------------------------------------------

ui_modal :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, views.view_modal())
}

ui_drawer :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, views.view_drawer())
}

ui_clear :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, "")
}

ui_tab :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, views.tab_panel(req.url_params[0]))
}

ui_toast :: proc(req: ^http.Request, res: ^http.Response) {
	kind := query_get(req, "kind")
	msg := kind == "error" ? "Something went sideways." : "That worked nicely."
	http.respond_html(res, views.view_toast(kind, msg, false))
}

ui_ping :: proc(req: ^http.Request, res: ^http.Response) {
	token := time.now()._nsec / 1_000_000
	rps := 40 + int(token % 60)
	http.respond_html(res, views.view_ping(token, rps))
}

// ---- health -------------------------------------------------------------

// Liveness probe for the platform load balancer / health checks. Cheap, no
// allocations, 200 while the process is up.
health :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, "ok")
}

// ---- static -------------------------------------------------------------

// Every asset is embedded into the binary at compile time (#load; paths are
// relative to this file: src/controllers -> app/static) and served from memory.
// The binary is fully self-contained: nothing is read from disk at runtime, so a
// redeploy is the only way assets change — which matches the deployment model.
// prepare.* fetches htmx before the first build.
HTMX_JS :: #load("../../static/htmx.min.js")
APP_CSS :: #load("../../static/app.css")
APP_JS :: #load("../../static/app.js")
FAVICON :: #load("../../static/favicon.svg")

// Strong ETags (content hashes) computed once at startup. They let the browser
// cache assets and, after max-age, revalidate with a cheap 304 instead of
// re-downloading. A redeploy changes the bytes, hence the ETag, so clients pick
// up new assets without ever serving stale ones.
@(private = "file")
etag_htmx, etag_css, etag_js, etag_favicon: string

// Fingerprinted asset names ("htmx.<hash>.min.js", "app.<hash>.css", "app.<hash>.js")
// computed once at startup; the layout links these and serve_static also accepts them.
@(private = "file")
asset_htmx, asset_css, asset_js: string

@(private = "file")
etag :: proc(blob: []byte) -> string {
	return fmt.aprintf(`"%08x"`, hash.crc32(blob))
}

// Computed once at startup (call from main, which has a context for the
// allocations). The ETags then live for the process lifetime.
init_etags :: proc() {
	etag_htmx = etag(HTMX_JS)
	etag_css = etag(APP_CSS)
	etag_js = etag(APP_JS)
	etag_favicon = etag(FAVICON)
	// Content-addressed asset names: a changed asset (an htmx upgrade included) gets
	// a new URL, so the page <head> cache-busts with a clean path instead of a ?v=
	// query — and these URLs can be cached immutably (see serve_static).
	asset_htmx = fmt.aprintf("htmx.%08x.min.js", hash.crc32(HTMX_JS))
	asset_css = fmt.aprintf("app.%08x.css", hash.crc32(APP_CSS))
	asset_js = fmt.aprintf("app.%08x.js", hash.crc32(APP_JS))
	views.HTMX_HREF = fmt.aprintf("/static/%s", asset_htmx)
	views.CSS_HREF = fmt.aprintf("/static/%s", asset_css)
	views.JS_HREF = fmt.aprintf("/static/%s", asset_js)
}

serve_static :: proc(req: ^http.Request, res: ^http.Response) {
	name := req.url_params[0]
	blob: []byte
	tag: string
	fingerprinted := false // a hashed name → the URL is content-addressed, cache it forever
	switch {
	case name == "htmx.min.js", name == asset_htmx:
		blob, tag, fingerprinted = HTMX_JS, etag_htmx, name == asset_htmx
	case name == "app.css", name == asset_css:
		blob, tag, fingerprinted = APP_CSS, etag_css, name == asset_css
	case name == "app.js", name == asset_js:
		blob, tag, fingerprinted = APP_JS, etag_js, name == asset_js
	case name == "favicon.svg":
		blob, tag = FAVICON, etag_favicon
	case:
		http.respond(res, http.Status.Not_Found)
		return
	}

	if fingerprinted {
		// The hash is in the path, so the bytes for this URL can never change.
		http.headers_set(&res.headers, "cache-control", "public, max-age=31536000, immutable")
	} else {
		// Bare name: revalidate after max-age with a cheap 304.
		http.headers_set(&res.headers, "cache-control", "public, max-age=3600")
		http.headers_set(&res.headers, "etag", tag)
		if match, ok := http.headers_get(req.headers, "if-none-match"); ok && match == tag {
			http.respond(res, http.Status.Not_Modified)
			return
		}
	}
	// respond_file_content sets the content-type from the name's extension.
	http.respond_file_content(res, name, blob)
}
