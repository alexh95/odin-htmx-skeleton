package controllers

import "core:fmt"
import "core:hash"
import "core:net"
import "core:strings"

import http "../../odin-http"
import "../services"
import "../views"

// ---- controllers --------------------------------------------------------
//
// The HTTP layer. Each handler parses the request, calls a service, renders a
// view and responds. Nothing here knows how the store works; nothing in the
// services knows it is being driven over HTTP.

// Parse an application/x-www-form-urlencoded body into key→value. Decodes '+' as
// space (htmx 4 sends spaces as '+', the form-encoding standard) and percent-
// escapes, so a literal '+' sent as %2B still round-trips.
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
		m[decode(key)] = decode(val)
	}
	return m
}

@(private = "file")
decode :: proc(s: string) -> string {
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

page_home :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"Home",
		"/",
		"A minimal Odin + HTMX + SQLite starter: one page, one entity, over a single self-contained binary.",
		views.view_home(services.list_notes()),
	)
}

page_about :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(
		res,
		"About",
		"/about",
		"About this project — a minimal starter built on an Odin backend rendering HTML with HTMX over a SQLite store, in one self-contained binary.",
		views.view_about(),
	)
}

// The one write path. Append the new note's <li> to the list on success; an
// empty note appends nothing (the input's `required` guards it client-side too).
notes_create :: proc(req: ^http.Request, res: ^http.Response) {
	http.body(req, -1, res, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)user
		if err != nil {
			http.respond(res, http.Status.Bad_Request)
			return
		}
		note, ok := services.create_note(body_form(body)["body"])
		if !ok {
			http.respond_html(res, "")
			return
		}
		b := strings.builder_make(context.temp_allocator)
		views.view_note_li(&b, note)
		http.respond_html(res, strings.to_string(b))
	})
}

// ---- health -------------------------------------------------------------

// Liveness probe for the platform. Cheap, no allocations, 200 while up.
health :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, "ok")
}

// ---- static -------------------------------------------------------------
//
// Every asset is embedded into the binary at compile time (#load; paths relative
// to this file: src/controllers -> app/static) and served from memory, so the
// binary is fully self-contained. prepare.* fetches htmx before the first build.
HTMX_JS :: #load("../../static/htmx.min.js")
APP_CSS :: #load("../../static/app.css")
APP_JS :: #load("../../static/app.js")
FAVICON :: #load("../../static/favicon.svg")

// Strong ETags (content hashes) computed once at startup; they let the browser
// revalidate with a cheap 304 after max-age instead of re-downloading.
@(private = "file")
etag_htmx, etag_css, etag_js, etag_favicon: string

// Fingerprinted asset names ("app.<hash>.css", …) — the layout links these and
// serve_static also accepts them, so a changed asset gets a new (immutable) URL.
@(private = "file")
asset_htmx, asset_css, asset_js: string

@(private = "file")
etag :: proc(blob: []byte) -> string {
	return fmt.aprintf(`"%08x"`, hash.crc32(blob))
}

// Computed once at startup (call from main, which has a context for allocations).
init_etags :: proc() {
	etag_htmx = etag(HTMX_JS)
	etag_css = etag(APP_CSS)
	etag_js = etag(APP_JS)
	etag_favicon = etag(FAVICON)
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
		http.headers_set(&res.headers, "cache-control", "public, max-age=31536000, immutable")
	} else {
		http.headers_set(&res.headers, "cache-control", "public, max-age=3600")
		http.headers_set(&res.headers, "etag", tag)
		if match, ok := http.headers_get(req.headers, "if-none-match"); ok && match == tag {
			http.respond(res, http.Status.Not_Modified)
			return
		}
	}
	http.respond_file_content(res, name, blob)
}
