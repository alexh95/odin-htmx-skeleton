package web

// ---- the platform's own routes (§6.3; LC §7) ---------------------------------------
//
// ROUTES: a site's main host (health, metrics, the sitemap, the ownership
// proofs). PUBLIC_ROUTES: every host (assets, robots.txt, the favicon, the
// notices). A profile mounts both, one line each, in its routes.odin. Derived,
// never declared twice: robots.txt's Disallow lines come from the host's
// .Fragment rows and the sitemap from its nav.

import "core:crypto"
import "core:strings"

import http "../../vendor/odin-http"
import "../authz"
import "../obs"

ROUTES := [?]Route {
	{.Get, "/healthz", healthz, .Public, {}, 0},
	{.Get, "/livez", livez, .Public, {}, 0},
	{.Get, "/readyz", readyz, .Public, {}, 0},
	{.Get, "/metrics", metrics, .Public, {}, 0}, // admin or METRICS_TOKEN_FILE's bearer, checked inside
	{.Get, "/sitemap%.xml", sitemap_xml, .Public, {}, 0},
	{.Get, "/BingSiteAuth%.xml", bing_site_auth, .Public, {}, 0},
	{.Get, "/([%x]+)%.txt", indexnow_key, .Public, {}, 0}, // 404 unless it is the brand's key
}

PUBLIC_ROUTES := [?]Route {
	{.Get, "/static/(.+)", serve_static, .Public, {}, 0},
	{.Get, "/robots%.txt", robots_txt, .Public, {}, 0},
	{.Get, "/favicon%.ico", serve_favicon_ico, .Public, {}, 0},
	{.Get, "/licenses", licenses, .Public, {}, 0},
}

// The bearer /metrics accepts, read from METRICS_TOKEN_FILE at boot; "" = none.
metrics_token: string

@(private) NOTICES :: #load("../../../THIRD_PARTY_NOTICES", string)

// ---- health (§10.4) ----------------------------------------------------------------

// The skeleton's contract, which Fly and the CI smoke test compare: body exactly
// `ok` while every critical module answers (the store's SELECT 1), else 503. It
// is exempt from the canonical-host redirect: a probe that follows a redirect
// off-host fails the deploy.
healthz :: proc(req: ^Request, res: ^Response) {
	for h in obs.modules() {
		if h.critical && h.state == .Down {
			respond_plain(res, "store unavailable" if h.module == "store" else "unavailable", .Service_Unavailable)
			return
		}
	}
	respond_plain(res, "ok")
}

// No locks, no I/O: every loop ticked in the last 5 s. --healthcheck probes it.
livez :: proc(req: ^Request, res: ^Response) {
	_, age := obs.oldest_tick()
	if age > 5e9 {
		respond_plain(res, "stalled", .Service_Unavailable)
		return
	}
	respond_plain(res, "ok")
}

// Every critical module up and not draining; ?detail lists each module.
readyz :: proc(req: ^Request, res: ^Response) {
	ok, why := obs.ready()
	if obs.is_draining() { http.headers_set(&res.headers, "x-draining", "1") }
	if query_get(req, "detail") != "" || has_query_key(req, "detail") {
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, "ready\n" if ok else "not ready\n")
		obs.render_health(&b)
		respond_plain(res, strings.to_string(b), .OK if ok else .Service_Unavailable)
		return
	}
	if !ok {
		respond_plain(res, why, .Service_Unavailable)
		return
	}
	respond_plain(res, "ok")
}

@(private)
has_query_key :: proc(req: ^Request, key: string) -> bool {
	q := req.url.query
	for part in strings.split_by_byte_iterator(&q, '&') {
		k, _, _ := strings.partition(part, "=")
		if k == key { return true }
	}
	return false
}

// Prometheus text, to an Admin or to the bearer in METRICS_TOKEN_FILE. With
// neither configured it isn't there at all.
metrics :: proc(req: ^Request, res: ^Response) {
	allowed := tl_ctx != nil && authz.can(tl_ctx.viewer, .Admin_Ops)
	if !allowed && metrics_token != "" {
		auth, _ := http.headers_get(req.headers, "authorization")
		given := strings.trim_prefix(auth, "Bearer ")
		allowed = len(given) == len(metrics_token) &&
			crypto.compare_constant_time(transmute([]byte)given, transmute([]byte)metrics_token) == 1
		if !allowed {
			http.headers_set(&res.headers, "www-authenticate", "Bearer")
			respond_plain(res, "unauthorized", .Unauthorized)
			return
		}
	}
	if !allowed {
		not_found(req, res)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	obs.render(&b)
	res.status = .OK
	http.headers_set_content_type(&res.headers, "text/plain; version=0.0.4; charset=utf-8")
	http.body_set(res, strings.to_string(b))
	http.respond(res)
}

// ---- crawlers ----------------------------------------------------------------------

// The fragment routes answer with bare HTML built to be swapped into a page;
// indexed alone they'd be thin near-duplicates, so they are disallowed outright.
robots_txt :: proc(req: ^Request, res: ^Response) {
	respond_plain(res, ctx().site.robots)
}

// robots.txt for one host, at boot: a Disallow per .Fragment row's literal start,
// cut after its first segment when it has more ("/ui/modal" → "/ui/"), each once.
robots_for :: proc(site: ^Site, allocator := context.allocator) -> string {
	lines := make([dynamic]string, context.temp_allocator)
	outer: for m in site.router.rows {
		if .Fragment not_in m.flags { continue }
		p := disallow_prefix(m.pattern)
		for l in lines {
			if strings.has_prefix(p, l) { continue outer } // already covered
		}
		append(&lines, p)
	}
	b := strings.builder_make(allocator)
	strings.write_string(&b, "User-agent: *\nAllow: /\n")
	for l in lines {
		strings.write_string(&b, "Disallow: ")
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "\nSitemap: ")
	strings.write_string(&b, site.origin)
	strings.write_string(&b, "/sitemap.xml\n")
	return strings.to_string(b)
}

@(private)
disallow_prefix :: proc(pattern: string) -> string {
	lit := pattern
	if i := strings.index_any(pattern, MAGIC); i >= 0 { lit = pattern[:i] }
	if j := strings.index_byte(lit[1:], '/'); j >= 0 { return lit[:j + 2] }
	return lit
}

// The sitemap walks the host's nav, so a page can't be added to the nav and left
// out of the sitemap; absolute URLs on the canonical origin.
sitemap_xml :: proc(req: ^Request, res: ^Response) {
	site := ctx().site
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
`)
	for item in site.nav {
		strings.write_string(&b, "  <url><loc>")
		strings.write_string(&b, site.origin)
		strings.write_string(&b, item.href)
		strings.write_string(&b, "</loc></url>\n")
	}
	strings.write_string(&b, "</urlset>\n")
	http.respond_file_content(res, "sitemap.xml", transmute([]byte)strings.to_string(b))
}

// Bing verifies ownership by fetching this and matching the token; an unset token
// 404s, so a fork never advertises a stale one.
bing_site_auth :: proc(req: ^Request, res: ^Response) {
	token := ctx().site.brand.bing_site_auth
	if token == "" {
		not_found(req, res)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0"?>
<users>
	<user>`)
	strings.write_string(&b, token)
	strings.write_string(&b, `</user>
</users>
`)
	http.respond_file_content(res, "BingSiteAuth.xml", transmute([]byte)strings.to_string(b))
}

// IndexNow proves ownership by serving the key back, verbatim, at /<key>.txt.
indexnow_key :: proc(req: ^Request, res: ^Response) {
	key := ctx().site.brand.indexnow_key
	if key == "" || req.url_params[0] != key {
		not_found(req, res)
		return
	}
	respond_plain(res, key)
}

// The notices of what the binary contains (odin-http's MIT, Odin's zlib, …).
licenses :: proc(req: ^Request, res: ^Response) {
	respond_plain(res, NOTICES)
}
