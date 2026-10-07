package controllers

import "core:fmt"
import "core:hash"
import "core:strconv"
import "core:strings"
import "core:time"

import http "../../odin-http"
import "../models"
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
			return form_decode(eq < 0 ? "" : part[eq + 1:])
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

render_page :: proc(res: ^http.Response, title, active, description, content: string) {
	respond_html(res, views.layout(title, active, description, content))
}

// Answer a store failure the handler can't recover from. A missing row keeps
// its plain 404. Anything else gets a status, and a body by kind of request:
// htmx 4 swaps error responses too, so an htmx request gets only an
// out-of-band toast (a response that is all OOB leaves its target alone), and
// a page load gets an error page.
respond_store_error :: proc(req: ^http.Request, res: ^http.Response, err: services.Store_Error) {
	status := http.Status.Internal_Server_Error
	msg := "Something went wrong on our side. Try again in a moment."
	#partial switch err {
	case .Not_Found:
		not_found(req, res)
		return
	case .Constraint:
		status, msg = .Conflict, "That change conflicts with what is already stored."
	}
	if http.headers_has(req.headers, "hx-request") {
		respond_html(res, views.view_toast("error", msg, true), status)
	} else {
		respond_html(res, views.layout("Error", "", msg, views.view_error("That didn't work", msg)), status)
	}
}

// ---- pages --------------------------------------------------------------

page_dashboard :: proc(req: ^http.Request, res: ^http.Response) {
	stats, err := services.dashboard_stats()
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	render_page(
		res,
		"Dashboard",
		"/",
		"A server-rendered web stack in one binary: an Odin backend renders the HTML, HTMX handles the interaction, SQLite holds the data. Click through the worked example.",
		views.view_dashboard(stats),
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
	p, err := services.service_page(query_get(req, "q"), query_get(req, "status"), sort, 1)
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
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
	q := query_get(req, "q")
	rows, err := services.service_search(strings.trim_space(q), services.SEARCH_LIMIT)
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	respond_html(res, views.view_search_results(q, rows))
}

Contact_DTO :: struct {
	id:     int,
	name:   string,
	email:  string,
	role:   string,
	status: string,
	score:  int,
	notes:  string,
	notify: bool,
}

// The non-HTMX surface: same data, plain JSON. Proves the service layer stands
// on its own.
api_search :: proc(req: ^http.Request, res: ^http.Response) {
	q := strings.trim_space(query_get(req, "q"))
	rn := models.ROLE_NAMES
	sn := models.STATUS_NAMES
	rows, err := services.search_all(q)
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	out := make([dynamic]Contact_DTO, context.temp_allocator)
	for c in rows {
		append(&out, Contact_DTO{c.id, c.name, c.email, rn[c.role], sn[c.status], c.score, c.notes, c.notify})
	}
	http.respond_json(res, out[:])
}

// ---- contacts table + CRUD ----------------------------------------------

frag_contacts :: proc(req: ^http.Request, res: ^http.Response) {
	sort := query_get(req, "sort")
	if sort == "" {
		sort = "name"
	}
	p, err := services.service_page(query_get(req, "q"), query_get(req, "status"), sort, query_int(req, "page", 1))
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	respond_html(res, views.view_contacts_region(p))
}

// Drilldown: the full contact record + a derived activity trail + related
// contacts, rendered as a drawer into #overlay.
contact_detail :: proc(req: ^http.Request, res: ^http.Response) {
	id, ok := parse_id(req.url_params[0])
	if !ok {
		not_found(req, res)
		return
	}
	d, err := services.contact_detail(id)
	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	// frag=1 → just the <aside> (in-place swap of an open drawer); edit=1 → edit form.
	if query_get(req, "frag") == "1" {
		respond_html(res, views.view_contact_detail_frag(d.contact, d.timeline, d.related, query_get(req, "edit") == "1"))
	} else {
		respond_html(res, views.view_contact_detail(d.contact, d.timeline, d.related))
	}
}

contacts_create :: proc(req: ^http.Request, res: ^http.Response) {
	form := request_form()
	role, _ := models.role_from(form["role"])
	c, errs, err := services.create_contact(form["name"], form["email"], role, .Invited, 50)
	if len(errs) > 0 {
		// 422, not 200: app.js resets a form only after a 2xx, so the user's input
		// survives, and the form's hx-status:422 routes this into its error slot.
		respond_html(res, views.view_field_msg(false, errs[0].msg), .Unprocessable_Content)
		return
	}
	if err != .None {
		respond_store_error(req, res, err)
		return
	}

	b := strings.builder_make(context.temp_allocator)
	views.view_contact_row(&b, c, true)
	strings.write_string(&b, views.view_toast("success", "Contact added.", true))
	respond_html(res, strings.to_string(b))
}

contacts_update :: proc(req: ^http.Request, res: ^http.Response) {
	id, ok := parse_id(req.url_params[0])
	if !ok {
		not_found(req, res)
		return
	}
	form := request_form()
	action := form["action"]
	// view=detail → respond with the re-rendered detail drawer (the action came
	// from the drawer); otherwise the table row.
	is_detail := form["view"] == "detail"

	c: models.Contact
	err: services.Store_Error
	edit_errs: []services.Field_Error
	typed: models.Contact
	if action == "cycle" {
		c, err = services.cycle_status(id)
	} else if _, editing := form["name"]; editing {
		// full edit from the detail drawer
		role, _ := models.role_from(form["role"])
		status, _ := models.status_from(form["status"])
		score := clamp(to_int(form["score"]), 0, 100)
		typed = {id = id, name = form["name"], email = form["email"], role = role, status = status, score = score}
		c, edit_errs, err = services.update_contact(id, typed.name, typed.email, role, status, score)
	} else {
		c, err = services.get_contact(id)
	}

	if err != .None {
		respond_store_error(req, res, err)
		return
	}
	if len(edit_errs) > 0 {
		// The edit form comes back as typed, with the reason, in place of the one
		// that was sent: a refused edit keeps its input. 422 skips app.js's reset.
		if is_detail {
			respond_html(res, views.view_contact_edit_rejected(c, typed, edit_errs[0].msg), .Unprocessable_Content)
		} else {
			respond_html(res, views.view_field_msg(false, edit_errs[0].msg), .Unprocessable_Content)
		}
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
		d, derr := services.contact_detail(c.id)
		if derr != .None {
			respond_store_error(req, res, derr)
			return
		}
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, views.view_contact_detail_frag(d.contact, d.timeline, d.related, false))
		fmt.sbprintf(&b, `<hx-partial hx-target="#contact-%d" hx-swap="outerHTML">`, c.id)
		views.view_contact_row(&b, c, false)
		strings.write_string(&b, `</hx-partial>`)
		respond_html(res, strings.to_string(b))
	} else {
		b := strings.builder_make(context.temp_allocator)
		views.view_contact_row(&b, c, false)
		respond_html(res, strings.to_string(b))
	}
}

contacts_delete :: proc(req: ^http.Request, res: ^http.Response) {
	id, ok := parse_id(req.url_params[0])
	if !ok {
		not_found(req, res)
		return
	}
	if err := services.delete_contact(id); err != .None {
		respond_store_error(req, res, err)
		return
	}
	// From the table row: empty body, the outerHTML swap removes the row. From the
	// detail drawer: the empty primary body closes the overlay, and an OOB swap
	// removes the now-stale table row behind it.
	if query_get(req, "from") == "drawer" {
		respond_html(res, fmt.tprintf(`<tr id="contact-%d" hx-swap-oob="delete"></tr>`, id))
	} else {
		respond_html(res, "")
	}
}

// ---- forms --------------------------------------------------------------

validate_email_field :: proc(req: ^http.Request, res: ^http.Response) {
	email := strings.trim_space(request_form()["email"])
	if email == "" {
		respond_html(res, "")
		return
	}
	if services.valid_email(email) {
		respond_html(res, views.view_field_msg(true, "Looks good."))
	} else {
		respond_html(res, views.view_field_msg(false, "That doesn't look like an email."))
	}
}

forms_submit :: proc(req: ^http.Request, res: ^http.Response) {
	form := request_form()
	role, _ := models.role_from(form["role"])
	status, _ := models.status_from(form["status"])
	// An unticked checkbox isn't posted at all; a ticked one posts "on".
	notify := form["notify"] == "on"
	c, errs, err := services.create_contact(form["name"], form["email"], role, status, to_int(form["score"]), form["notes"], notify)
	if len(errs) > 0 {
		// Lands in #form-result like a success would; 422 keeps the form unreset.
		respond_html(res, views.view_form_errors(errs), .Unprocessable_Content)
		return
	}
	if err != .None {
		respond_store_error(req, res, err)
		return
	}

	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, views.view_form_result(c))
	strings.write_string(&b, views.view_toast("success", "Saved to the SQLite store.", true))
	respond_html(res, strings.to_string(b))
}

// ---- ui fragments -------------------------------------------------------

ui_modal :: proc(req: ^http.Request, res: ^http.Response) {
	respond_html(res, views.view_modal())
}

ui_drawer :: proc(req: ^http.Request, res: ^http.Response) {
	respond_html(res, views.view_drawer())
}

ui_clear :: proc(req: ^http.Request, res: ^http.Response) {
	respond_html(res, "")
}

ui_tab :: proc(req: ^http.Request, res: ^http.Response) {
	respond_html(res, views.tab_panel(req.url_params[0]))
}

ui_toast :: proc(req: ^http.Request, res: ^http.Response) {
	kind := query_get(req, "kind")
	msg := kind == "error" ? "Something went sideways." : "That worked nicely."
	respond_html(res, views.view_toast(kind, msg, false))
}

ui_ping :: proc(req: ^http.Request, res: ^http.Response) {
	token := time.now()._nsec / 1_000_000
	rps := 40 + int(token % 60)
	respond_html(res, views.view_ping(token, rps))
}

// ---- health -------------------------------------------------------------

// Health probe for the platform load balancer: 200 "ok" while the process is up
// and its store answers, 503 when the store doesn't, so a broken database
// fails the check instead of passing it. The build is in the x-version header
// (set for every response by the middleware). Cheap: one SELECT 1.
health :: proc(req: ^http.Request, res: ^http.Response) {
	if !services.store_ok() {
		respond_plain(res, "store unavailable", .Service_Unavailable)
		return
	}
	respond_plain(res, "ok")
}

// ---- seo ----------------------------------------------------------------
//
// robots.txt and sitemap.xml are generated, never files on disk: the sitemap
// walks the same views.NAV the header renders from, so a page cannot be added
// to the nav and silently left out of the sitemap. Both emit absolute URLs on
// the canonical origin — a sitemap advertising a different host than the
// canonical tag is discarded rather than followed.

robots_txt :: proc(req: ^http.Request, res: ^http.Response) {
	b := strings.builder_make(context.temp_allocator)
	// The fragment routes answer with bare HTML built to be swapped into a page.
	// Indexed standalone they are thin, near-duplicate pages competing with the
	// real ones, so they are disallowed outright rather than left to a canonical.
	strings.write_string(&b, `User-agent: *
Allow: /
Disallow: /ui/
Disallow: /api/
Disallow: /search
Disallow: /contacts
Disallow: /validate/
Disallow: /forms/submit

Sitemap: `)
	strings.write_string(&b, views.SITE_URL)
	strings.write_string(&b, "/sitemap.xml\n")
	respond_plain(res, strings.to_string(b))
}

sitemap_xml :: proc(req: ^http.Request, res: ^http.Response) {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
`)
	for item in views.NAV {
		strings.write_string(&b, "  <url><loc>")
		strings.write_string(&b, views.SITE_URL)
		strings.write_string(&b, item.href)
		strings.write_string(&b, "</loc></url>\n")
	}
	strings.write_string(&b, "</urlset>\n")
	// respond_file_content takes the content type from the extension: text/xml.
	http.respond_file_content(res, "sitemap.xml", transmute([]byte)strings.to_string(b))
}

// Bing verifies ownership by fetching this file and matching the token inside.
// Google's equivalent is the DNS TXT record, which needs no code. Serving it
// from the binary rather than as a static asset keeps it beside the token it
// renders; an unset token 404s, so a fork does not advertise a stale one.
bing_site_auth :: proc(req: ^http.Request, res: ^http.Response) {
	if views.BING_SITE_AUTH == "" {
		not_found(req, res)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0"?>
<users>
	<user>`)
	strings.write_string(&b, views.BING_SITE_AUTH)
	strings.write_string(&b, `</user>
</users>
`)
	http.respond_file_content(res, "BingSiteAuth.xml", transmute([]byte)strings.to_string(b))
}

// Served from the site root, not /static: that is where browsers and crawlers
// look for it by default, and a favicon Google cannot fetch is why a result
// shows the generic globe.
favicon_ico :: proc(req: ^http.Request, res: ^http.Response) {
	http.headers_set(&res.headers, "cache-control", "public, max-age=86400")
	http.headers_set(&res.headers, "etag", etag_favicon_ico)
	if match, ok := http.headers_get(req.headers, "if-none-match"); ok && match == etag_favicon_ico {
		http.respond(res, http.Status.Not_Modified)
		return
	}
	http.respond_file_content(res, "favicon.ico", FAVICON_ICO)
}

// IndexNow proves ownership by serving the key back as plain text at /<key>.txt.
// The body is the key and nothing else — the search engines compare it verbatim,
// so no trailing newline and no XML wrapper here.
indexnow_key :: proc(req: ^http.Request, res: ^http.Response) {
	respond_plain(res, views.INDEXNOW_KEY)
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
// Search engines look for /favicon.ico at the site root and are far more
// reliable with a raster .ico than with an SVG; browsers prefer the SVG. Both
// are served, and the link tags offer each to whichever wants it.
FAVICON_ICO :: #load("../../static/favicon.ico")
OG_IMAGE :: #load("../../static/og.png")

// Strong ETags (content hashes) computed once at startup. They let the browser
// cache assets and, after max-age, revalidate with a cheap 304 instead of
// re-downloading. A redeploy changes the bytes, hence the ETag, so clients pick
// up new assets without ever serving stale ones.
@(private = "file")
etag_htmx, etag_css, etag_js, etag_favicon, etag_favicon_ico, etag_og: string

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
	etag_favicon_ico = etag(FAVICON_ICO)
	etag_og = etag(OG_IMAGE)
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
	// Unfingerprinted on purpose: og:image is cached by social platforms against
	// its URL, so the path has to stay put across redeploys (see OG_IMAGE_HREF).
	case name == "og.png":
		blob, tag = OG_IMAGE, etag_og
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
