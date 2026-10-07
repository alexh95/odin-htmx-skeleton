package controllers

import "core:crypto/sha2"
import "core:encoding/base64"
import "core:log"
import "core:net"
import "core:strings"
import "core:time"

import http "../../odin-http"
import "../views"

// ---- middleware: what every request passes through ----------------------
//
// One wrapper around the router (main.odin installs it). It is shared by the
// demo and the `init --minimal` starter, so it stays entity-agnostic.
//
// In order: the security headers every response carries, the *.fly.dev
// redirect (canonical_host), the cross-site guard on writes (same_origin), then
// the body of every request that can carry one, read before routing and capped
// at MAX_BODY. Doing that here rather than per handler means the cap and the
// guard hold for every route, including the ones a fork adds, and a handler gets
// the parsed form synchronously from request_form() instead of wiring its own
// async read. Every way out writes one access-log line (access_log).

// The build, as CI names it: `odin build src -define:VERSION=1.2.0` (or a commit).
// Sent on every response (x-version) and logged at boot, so a log or a curl says
// which release answered. A local build is "dev".
VERSION :: #config(VERSION, "dev")

// Far above any form this app posts (the longest field is capped in services),
// so it only ever stops abuse. A larger body is refused with 413 before a byte
// of it is read: odin-http checks Content-Length against the cap first.
MAX_BODY :: 64 * 1024

front :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	next := handler.next.(^http.Handler)
	start := time.tick_now()
	security_headers(res)
	if canonical_host(req, res) {
		access_log(req, res, start)
		return
	}
	if !same_origin(req) {
		http.respond_plain(res, "Cross-site request refused.", .Forbidden)
		access_log(req, res, start)
		return
	}
	if !has_body(req) {
		next.handle(next, req, res)
		access_log(req, res, start)
		return
	}
	// http.body may finish later, from the event loop, so what the callback
	// needs lives in the request arena, not on this stack frame.
	p := new(Pending, context.temp_allocator)
	p^ = {next, req, res, start}
	http.body(req, MAX_BODY, p, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		p := (^Pending)(user)
		defer access_log(p.req, p.res, p.start)
		if err != nil {
			// The unread rest of the body is still on the wire, so odin-http will close
			// the connection; say so, or a keep-alive client reuses a dead socket.
			http.headers_set_close(&p.res.headers)
			http.respond(p.res, http.body_error_status(err)) // 413 past the cap, 400 if malformed
			return
		}
		// The body rides down the (synchronous) handler call in context.user_ptr,
		// which is scoped to this call and so can't leak into the next request.
		text := string(body)
		context.user_ptr = &text
		p.next.handle(p.next, p.req, p.res)
	})
}

// One line per request: method, path (not the query, which can carry what a
// user typed), status and the time spent in the app. Logged once the handler
// has returned; every handler here responds before it does, so the status is
// final. At .Info, so LOG_LEVEL=warn silences it (see main).
@(private = "file")
access_log :: proc(req: ^http.Request, res: ^http.Response, start: time.Tick) {
	method := req.is_head ? "HEAD" : http.method_string(req.line.(http.Requestline).method)
	ms := time.duration_milliseconds(time.tick_since(start))
	log.infof("%s %s %d %.2fms", method, req.url.path, int(res.status), ms)
}

// The current request's form fields, '+'- and percent-decoded. Empty for a
// request without a body.
request_form :: proc() -> map[string]string {
	if context.user_ptr == nil {
		return make(map[string]string, context.temp_allocator)
	}
	return body_form((^string)(context.user_ptr)^)
}

// ---- security headers ---------------------------------------------------
//
// On every response, whatever produced it:
// - a Content-Security-Policy that runs only this origin's script files plus
//   the one inline script admitted by hash (views.THEME_PREPAINT_JS), so an
//   injected <script> or on*= attribute doesn't execute. style-src-attr stays
//   'unsafe-inline' for the style="--h:…" attributes the components set;
//   <style> elements are still refused. Images allow data: for the CSS's inline
//   SVG icons.
// - nosniff, so a response is only ever used as the type it says it is;
// - no framing (frame-ancestors, and X-Frame-Options for older browsers);
// - the full Referer only within this origin.
//
// A fork that loads anything from elsewhere (fonts, analytics) widens the one
// directive it needs, in init_security, and nothing else.

@(private = "file") csp: string

// Computed once at boot (main calls it, with a context for the allocation).
init_security :: proc() {
	sum: [sha2.DIGEST_SIZE_256]byte
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, transmute([]byte)string(views.THEME_PREPAINT_JS))
	sha2.final(&ctx, sum[:])
	csp = strings.concatenate(
		{
			"default-src 'self'; script-src 'self' 'sha256-",
			base64.encode(sum[:]),
			"'; style-src 'self'; style-src-attr 'unsafe-inline'; img-src 'self' data:; ",
			"object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
		},
	)
}

@(private = "file")
security_headers :: proc(res: ^http.Response) {
	http.headers_set(&res.headers, "x-version", VERSION)
	http.headers_set(&res.headers, "content-security-policy", csp)
	http.headers_set(&res.headers, "x-content-type-options", "nosniff")
	http.headers_set(&res.headers, "x-frame-options", "DENY")
	http.headers_set(&res.headers, "referrer-policy", "strict-origin-when-cross-origin")
}

// ---- cross-site request guard -------------------------------------------
//
// A write (any method but GET/HEAD/OPTIONS) must come from this site's own
// pages. Browsers say where a request comes from: Sec-Fetch-Site on every
// request since 2023, Origin on every POST long before that. A request that is
// cross-site by either is refused with 403, before its body is read.
//
// A request with neither header isn't from a browser (curl, k6, a server-side
// client), so it can't be a forgery riding a user's cookies, and passes. That
// is also why this doesn't demand htmx's HX-Request header: it would refuse
// every non-browser client without stopping any browser attack the two checks
// above don't. The demo has no sessions yet; the first fork that adds a cookie
// gets this for free, and should still mark it SameSite=Lax. A per-session
// token on top only matters for browsers older than both headers.
@(private = "file")
same_origin :: proc(req: ^http.Request) -> bool {
	#partial switch req.line.(http.Requestline).method {
	case .Get, .Head, .Options:
		return true
	}
	if site, ok := http.headers_get(req.headers, "sec-fetch-site"); ok {
		// "none" is the user's own action: a typed URL, a bookmark.
		return site == "same-origin" || site == "none"
	}
	origin, has_origin := http.headers_get(req.headers, "origin")
	if !has_origin {
		return true
	}
	// Origin is scheme://host[:port]; compare its host[:port] with Host, which
	// TLS-terminating proxies (Fly, Cloudflare) pass through unchanged.
	host, _ := http.headers_get(req.headers, "host")
	if i := strings.index(origin, "://"); i >= 0 {
		origin = origin[i + 3:]
	}
	return host != "" && strings.equal_fold(origin, host)
}

// ---- canonical host -----------------------------------------------------
//
// The platform hostname serves the very same app as the custom domain, so a
// crawler that finds both indexes the site twice and splits its ranking signals.
// A 301 collapses them onto views.SITE_URL and passes the accumulated authority
// along with it — a canonical tag alone only hints, and only to search engines.
//
// Off while SITE_URL is a placeholder (main decides at boot). `init` writes
// https://<name>.example.com until the fork has a domain, and redirecting there
// sent every visitor of a fork on *.fly.dev to a site that doesn't exist, while
// the exempt health check kept the deploy green.
//
// Scoped to *.fly.dev rather than "any host that isn't canonical": localhost and
// a LAN IP have to keep working for development, and a future domain must not
// start bouncing the moment DNS points at it. /healthz is exempt regardless —
// Fly's own health check calls it, and a probe that follows a redirect off-host
// would fail the deploy rather than the request.

canonical_redirect := false

// Whether the request was answered with the redirect.
@(private = "file")
canonical_host :: proc(req: ^http.Request, res: ^http.Response) -> bool {
	if !canonical_redirect || req.url.path == "/healthz" {
		return false
	}
	host, _ := http.headers_get(req.headers, "host")
	if !strings.has_suffix(host, ".fly.dev") {
		return false
	}
	target := strings.concatenate({views.SITE_URL, req.url.path}, context.temp_allocator)
	if req.url.query != "" {
		target = strings.concatenate({target, "?", req.url.query}, context.temp_allocator)
	}
	http.headers_set(&res.headers, "location", target)
	http.respond(res, http.Status.Moved_Permanently)
	return true
}

// An origin on a name reserved for examples and tests (RFC 2606, RFC 6761):
// example.com/.net/.org and their subdomains, and the .example, .test,
// .invalid and .localhost TLDs. Nobody can be served from one.
placeholder_origin :: proc(origin: string) -> bool {
	host := origin
	if i := strings.index(host, "://"); i >= 0 {
		host = host[i + 3:]
	}
	if i := strings.index_any(host, "/:"); i >= 0 {
		host = host[:i]
	}
	host = strings.trim_suffix(strings.to_lower(host, context.temp_allocator), ".")
	for reserved in ([]string{"example.com", "example.net", "example.org"}) {
		if host == reserved || strings.has_suffix(host, strings.concatenate({".", reserved}, context.temp_allocator)) {
			return true
		}
	}
	for tld in ([]string{".example", ".test", ".invalid", ".localhost"}) {
		if strings.has_suffix(host, tld) || host == tld[1:] {
			return true
		}
	}
	return false
}

@(private = "file")
Pending :: struct {
	next:  ^http.Handler,
	req:   ^http.Request,
	res:   ^http.Response,
	start: time.Tick,
}

// Only a request that announces a body is read. http.body on one that doesn't
// (a bare DELETE) leaves odin-http thinking the read failed, and it then drops
// the keep-alive connection without saying so in the response.
@(private = "file")
has_body :: proc(req: ^http.Request) -> bool {
	#partial switch req.line.(http.Requestline).method {
	case .Post, .Put, .Patch, .Delete:
		return http.headers_has(req.headers, "content-length") || http.headers_has(req.headers, "transfer-encoding")
	}
	return false
}

// Parse an application/x-www-form-urlencoded body into key→value. Unlike
// http.body_url_encoded, this decodes '+' as space — htmx 4 sends spaces as '+'
// (the form-encoding standard) and odin-http's parser only percent-decodes. Uses
// the same decode as query strings, so a literal '+' sent as %2B round-trips.
@(private = "file")
body_form :: proc(s: string) -> map[string]string {
	m := make(map[string]string, context.temp_allocator)
	s := s
	for part in strings.split_by_byte_iterator(&s, '&') {
		if part == "" {
			continue
		}
		eq := strings.index_byte(part, '=')
		key := eq < 0 ? part : part[:eq]
		val := eq < 0 ? "" : part[eq + 1:]
		m[form_decode(key)] = form_decode(val)
	}
	return m
}

// A row id from a path capture. Rowids are 64-bit and positive. Not
// strconv.parse_int: it wraps silently past 64 bits (18446744073709551617
// parses as 1), and an ownership check on one id must not act on another.
parse_id :: proc(s: string) -> (id: int, ok: bool) {
	if s == "" {
		return 0, false
	}
	for i in 0 ..< len(s) {
		if s[i] < '0' || s[i] > '9' {
			return 0, false
		}
		d := int(s[i] - '0')
		if id > (max(int) - d) / 10 {
			return 0, false
		}
		id = id * 10 + d
	}
	return id, id > 0
}

// '+'→space, then percent-decode; a malformed escape is kept as typed.
form_decode :: proc(s: string) -> string {
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
