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
	p := services.service_page(query_get(req, "q"), "name", 1)
	render_page(
		res,
		"Data & CRUD",
		"/data",
		"A live contacts table over an in-memory Odin store: filter, sort and paginate, plus create, update and delete — all over HTMX with no full-page reloads.",
		views.view_data(p),
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
	p := services.service_page(query_get(req, "q"), sort, query_int(req, "page", 1))
	http.respond_html(res, views.view_contacts_region(p))
}

// user_data passed through http.body. Allocated in the request arena so it
// survives until the (possibly deferred) body callback runs.
@(private = "file")
Form_Ctx :: struct {
	res: ^http.Response,
	id:  int,
}

contacts_create :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Form_Ctx)user
		res := ctx.res
		if err != nil {
			http.respond(res, http.Status.Bad_Request)
			return
		}
		form, ok := http.body_url_encoded(body)
		name := ok ? form["name"] : ""
		email := ok ? form["email"] : ""

		errs := services.validate_contact(name, email)
		if len(errs) > 0 {
			http.respond_html(res, views.view_toast("error", errs[0].msg, true))
			return
		}

		role, _ := models.role_from(ok ? form["role"] : "")
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

		form, _ := http.body_url_encoded(body)
		action := form["action"]

		c: models.Contact
		ok: bool
		if action == "cycle" {
			if cur, found := repository.repo_get(ctx.id); found {
				next := models.Status((int(cur.status) + 1) % len(models.Status))
				c, ok = repository.repo_set_status(ctx.id, next)
			}
		} else {
			c, ok = repository.repo_get(ctx.id)
		}

		if !ok {
			http.respond(res, http.Status.Not_Found)
			return
		}
		b := strings.builder_make(context.temp_allocator)
		views.view_contact_row(&b, c, false)
		http.respond_html(res, strings.to_string(b))
	})
}

contacts_delete :: proc(req: ^http.Request, res: ^http.Response) {
	id := to_int(req.url_params[0])
	if !repository.repo_delete(id) {
		http.respond(res, http.Status.Not_Found)
		return
	}
	// Empty body: the outerHTML swap replaces the row with nothing.
	http.respond_html(res, "")
}

// ---- forms --------------------------------------------------------------

validate_email_field :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := (cast(^Form_Ctx)user).res
		form, _ := http.body_url_encoded(body)
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
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := (cast(^Form_Ctx)user).res
		form, _ := http.body_url_encoded(body)
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
		strings.write_string(&b, views.view_toast("success", "Saved to the in-memory store.", true))
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
}

serve_static :: proc(req: ^http.Request, res: ^http.Response) {
	name := req.url_params[0]
	blob: []byte
	tag: string
	switch name {
	case "htmx.min.js":
		blob, tag = HTMX_JS, etag_htmx
	case "app.css":
		blob, tag = APP_CSS, etag_css
	case "app.js":
		blob, tag = APP_JS, etag_js
	case "favicon.svg":
		blob, tag = FAVICON, etag_favicon
	case:
		http.respond(res, http.Status.Not_Found)
		return
	}

	http.headers_set(&res.headers, "cache-control", "public, max-age=3600")
	http.headers_set(&res.headers, "etag", tag)
	if match, ok := http.headers_get(req.headers, "if-none-match"); ok && match == tag {
		http.respond(res, http.Status.Not_Modified)
		return
	}
	// respond_file_content sets the content-type from the name's extension.
	http.respond_file_content(res, name, blob)
}
