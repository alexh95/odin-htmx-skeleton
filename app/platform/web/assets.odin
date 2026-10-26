package web

// ---- assets: embedded, fingerprinted, precompressed (§12.1) -----------------------
//
// Every asset is in the binary and served from memory; nothing is read from disk
// at runtime. prepare runs tools/bundle, which writes a profile's bundle, its CSS
// and its client's app.js to app/build/<profile>/ with a .br and a .gz beside
// each; build.sh names that folder (-define:BUILD_DIR), and each file is #loaded
// under `when #exists`, so a build before prepare still compiles and boot then
// refuses it ("run prepare", boot check 6). Odin has no brotli, so compression
// happens there, once.
//
// A bundle, the CSS and app.js are served under a name with the crc32 of their
// bytes in it ("htmx.<crc>.min.js": one URL for every encoding), cached for good,
// and under their bare names with an ETag and an hour's max-age (the load tests
// and old links ask for those). br > gzip > identity by Accept-Encoding, with
// Vary. og.png keeps one stable, unfingerprinted URL: social platforms cache a
// preview against it.

import "core:fmt"
import "core:hash"
import "core:strconv"
import "core:strings"

import http "../../vendor/odin-http"
import "../ext"

BUILD_DIR :: #config(BUILD_DIR, "../../build/none")

when #exists(BUILD_DIR + "/main.js") { @(private) MAIN_JS :: #load(BUILD_DIR + "/main.js", string) } else { @(private) MAIN_JS :: "" }
when #exists(BUILD_DIR + "/main.js.br") { @(private) MAIN_JS_BR :: #load(BUILD_DIR + "/main.js.br", string) } else { @(private) MAIN_JS_BR :: "" }
when #exists(BUILD_DIR + "/main.js.gz") { @(private) MAIN_JS_GZ :: #load(BUILD_DIR + "/main.js.gz", string) } else { @(private) MAIN_JS_GZ :: "" }
when #exists(BUILD_DIR + "/app.css") { @(private) APP_CSS :: #load(BUILD_DIR + "/app.css", string) } else { @(private) APP_CSS :: "" }
when #exists(BUILD_DIR + "/app.css.br") { @(private) APP_CSS_BR :: #load(BUILD_DIR + "/app.css.br", string) } else { @(private) APP_CSS_BR :: "" }
when #exists(BUILD_DIR + "/app.css.gz") { @(private) APP_CSS_GZ :: #load(BUILD_DIR + "/app.css.gz", string) } else { @(private) APP_CSS_GZ :: "" }
when #exists(BUILD_DIR + "/app.js") { @(private) APP_JS :: #load(BUILD_DIR + "/app.js", string) } else { @(private) APP_JS :: "" }
when #exists(BUILD_DIR + "/app.js.br") { @(private) APP_JS_BR :: #load(BUILD_DIR + "/app.js.br", string) } else { @(private) APP_JS_BR :: "" }
when #exists(BUILD_DIR + "/app.js.gz") { @(private) APP_JS_GZ :: #load(BUILD_DIR + "/app.js.gz", string) } else { @(private) APP_JS_GZ :: "" }

@(private) FAVICON_SVG :: #load("../static/favicon.svg", string)
// Crawlers look for /favicon.ico at the root and handle a raster .ico far better
// than an SVG; browsers prefer the SVG. Both are served.
@(private) FAVICON_ICO :: #load("../static/favicon.ico", string)
@(private) OG_PNG :: #load("../static/og.png", string)

Asset :: struct {
	name:         string, // the bare name: "htmx.min.js"
	hashed:       string, // "htmx.<crc>.min.js", or "" for an asset served under one name only
	identity:     []byte,
	br, gz:       []byte, // empty when prepare had no compressor
	etag:         [3]string, // identity, br, gz
	content_type: string,
}

@(private)
assets: struct {
	table:                     [6]Asset,
	n:                         int,
	css_href, htmx_href, js_href: string, // what the layout links
}

// At boot: names, ETags and hrefs, computed once from the embedded bytes.
assets_init :: proc() {
	add :: proc(name: string, identity, br, gz: string, fingerprint: bool) -> string {
		crc := hash.crc32(transmute([]byte)identity)
		a := &assets.table[assets.n]
		assets.n += 1
		a.name, a.identity, a.br, a.gz = name, transmute([]byte)identity, transmute([]byte)br, transmute([]byte)gz
		a.content_type = http.mime_to_content_type(http.mime_from_extension(name))
		a.etag = {fmt.aprintf(`"%08x"`, crc), fmt.aprintf(`"%08x-br"`, crc), fmt.aprintf(`"%08x-gz"`, crc)}
		if !fingerprint { return strings.concatenate({"/static/", name}) }
		dot := strings.index_byte(name, '.')
		a.hashed = fmt.aprintf("%s.%08x%s", name[:dot], crc, name[dot:])
		return strings.concatenate({"/static/", a.hashed})
	}
	assets.htmx_href = add("htmx.min.js", MAIN_JS, MAIN_JS_BR, MAIN_JS_GZ, true)
	assets.css_href = add("app.css", APP_CSS, APP_CSS_BR, APP_CSS_GZ, true)
	assets.js_href = add("app.js", APP_JS, APP_JS_BR, APP_JS_GZ, true)
	add("favicon.svg", FAVICON_SVG, "", "", false)
	add("favicon.ico", FAVICON_ICO, "", "", false)
	add("og.png", OG_PNG, "", "", false)
}

// Whether prepare built this profile's assets (boot check 6 refuses a build without them).
assets_bundle_present :: proc() -> bool { return len(MAIN_JS) > 0 }

// The extensions the embedded main bundle carries: boot check 6 compares them
// with main's BUNDLE_EXTS. A bare htmx.min.js has no header: the empty set.
bundle_exts :: proc() -> (set: ext.Exts, ok: bool) {
	return ext.parse_header(MAIN_JS)
}

// GET /static/(.+)
serve_static :: proc(req: ^Request, res: ^Response) {
	name := req.url_params[0]
	for &a in assets.table[:assets.n] {
		if name == a.name {
			send_asset(req, res, &a, false)
			return
		}
		if a.hashed != "" && name == a.hashed {
			send_asset(req, res, &a, true)
			return
		}
	}
	http.respond(res, Status.Not_Found)
}

// /favicon.ico at the root, where browsers and crawlers look by default.
serve_favicon_ico :: proc(req: ^Request, res: ^Response) {
	for &a in assets.table[:assets.n] {
		if a.name == "favicon.ico" {
			send_asset(req, res, &a, false)
			return
		}
	}
}

@(private)
send_asset :: proc(req: ^Request, res: ^Response, a: ^Asset, fingerprinted: bool) {
	body, enc := a.identity, 0
	if len(a.br) > 0 || len(a.gz) > 0 {
		http.headers_set_unsafe(&res.headers, "vary", "Accept-Encoding")
		accept, _ := http.headers_get(req.headers, "accept-encoding")
		switch {
		case len(a.br) > 0 && accepts(accept, "br"):   body, enc = a.br, 1
		case len(a.gz) > 0 && accepts(accept, "gzip"): body, enc = a.gz, 2
		}
	}
	if fingerprinted {
		// The hash is in the path, so the bytes for this URL can never change.
		http.headers_set_unsafe(&res.headers, "cache-control", "public, max-age=31536000, immutable")
	} else {
		// A bare name: revalidate after max-age with a cheap 304.
		http.headers_set_unsafe(&res.headers, "cache-control", "public, max-age=3600" if a.name != "favicon.ico" else "public, max-age=86400")
		http.headers_set_unsafe(&res.headers, "etag", a.etag[enc])
		if match, ok := http.headers_get(req.headers, "if-none-match"); ok && match == a.etag[enc] {
			http.respond(res, Status.Not_Modified)
			return
		}
	}
	if enc != 0 { http.headers_set_unsafe(&res.headers, "content-encoding", "br" if enc == 1 else "gzip") }
	res.status = .OK
	http.headers_set_content_type(&res.headers, a.content_type)
	http.body_set(res, body)
	http.respond(res)
}

// Whether an Accept-Encoding value lists `coding` with a q above 0.
@(private)
accepts :: proc(header, coding: string) -> bool {
	rest := header
	for part in strings.split_iterator(&rest, ",") {
		name, _, params := strings.partition(strings.trim_space(part), ";")
		if strings.trim_space(name) != coding { continue }
		params = strings.trim_space(params)
		if !strings.has_prefix(params, "q=") { return true }
		q, ok := strconv.parse_f64(params[2:])
		return ok && q > 0
	}
	return false
}
