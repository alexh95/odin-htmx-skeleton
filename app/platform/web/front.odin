package web

// ---- what front (platform/app) is made of ------------------------------------------
//
// The chain itself is platform/app's, because it calls the build's identity
// (§8.4); its steps that touch odin-http are here. In the skeleton's order
// (SK/app/src/controllers/middleware.odin:38-87): security headers, the
// Content-Length refusal, the canonical host, the cross-site write guard, the
// body, the handler, one access-log line.

import "core:crypto"
import "core:crypto/sha2"
import "core:encoding/base64"
import "core:hash"
import "core:net"
import "core:strings"

import http "../../vendor/odin-http"
import "../env"
import "../guard"
import "../html"
import "../obs"
import "../sys"

// The build, as CI names it: -define:VERSION=v2.0.0 (or a commit). Sent on every
// response (x-version) and logged at boot. A local build is "dev".
VERSION :: #config(VERSION, "dev")

// Which header set the profile sends (§12.2): `minimal` sends exactly the
// skeleton's; every other profile adds Permissions-Policy, COOP and CORP, static
// strings that change neither cost nor features (X35); `streams`, `lab` and
// `full` also ask browsers to report CSP violations to /csp-report (mounted from
// REPORT_ROUTES; D9, D20, X11).
Header_Set :: enum u8 {
	Skeleton,
	Standard,
	Reporting,
}

@(private)
sec: struct {
	csp:        string,
	nonce_head: string, // a .Nonce_Csp response's policy: head, the nonce, tail
	nonce_tail: string,
	set:        Header_Set,
	trusted:    []env.Cidr, // TRUST_PROXY
	cid_key:    u32, // per boot: the client id is a hash, never the address
}

// At boot. The CSP is the skeleton's hash policy verbatim: scripts from this
// origin plus the one inline script admitted by hash (html.THEME_PREPAINT_JS);
// style-src-attr stays 'unsafe-inline' for the style="--x:…" attributes the
// components set; images allow data: for the CSS's inline SVG icons. A fork that
// loads from elsewhere widens the one directive it needs, here.
security_init :: proc(set: Header_Set, trusted: []env.Cidr) {
	sum: [sha2.DIGEST_SIZE_256]byte
	c: sha2.Context_256
	sha2.init_256(&c)
	sha2.update(&c, transmute([]byte)string(html.THEME_PREPAINT_JS))
	sha2.final(&c, sum[:])
	hash := base64.encode(sum[:], allocator = context.temp_allocator)
	rest := "'; style-src 'self'; style-src-attr 'unsafe-inline'; img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
	report := "; report-to csp" if set == .Reporting else ""
	sec.csp = strings.concatenate({"default-src 'self'; script-src 'self' 'sha256-", hash, rest, report})
	// The nonce class (§12.2): scripts by nonce or the pre-paint hash, and nothing
	// else, not even 'self'.
	sec.nonce_head = "default-src 'self'; script-src 'nonce-"
	sec.nonce_tail = strings.concatenate({"' 'sha256-", hash, rest, report})
	sec.set = set
	sec.trusted = trusted
	sec.cid_key = u32(sys.now_unix_ns())
}

csp :: proc() -> string { return sec.csp }

// On every response, whatever produced it; a route's flags add their own. A
// .Nonce_Csp route's response gets a fresh nonce, returned for the page to stamp:
// base64url, so it can ride in a URL's query as it is (a stream that stamps the
// page's nonce is told it that way, §12.2), and still a CSP nonce. .Trusted_Types
// adds hx-csp's policy, the only one allowed to touch a DOM sink (11 §2.3).
security_headers :: proc(res: ^Response, flags: Route_Flags, path: string) -> (nonce: string) {
	h := &res.headers
	// Constant lowercase keys: the unsafe setter skips headers_set's lowercased copy of each,
	// which a profile of the write path put at 7 % (with F-15's header writing).
	http.headers_set_unsafe(h, "x-version", VERSION)
	if .Nonce_Csp in flags {
		raw: [16]byte
		crypto.rand_bytes(raw[:])
		nonce = base64.encode(raw[:], base64.ENC_URL_TABLE, context.temp_allocator)
		tt := "; require-trusted-types-for 'script'; trusted-types htmx" if .Trusted_Types in flags else ""
		http.headers_set_unsafe(h, "content-security-policy", strings.concatenate({sec.nonce_head, nonce, sec.nonce_tail, tt}, context.temp_allocator))
		http.headers_set_unsafe(h, "cache-control", "no-store")
	} else {
		http.headers_set_unsafe(h, "content-security-policy", sec.csp)
	}
	http.headers_set_unsafe(h, "x-content-type-options", "nosniff")
	http.headers_set_unsafe(h, "x-frame-options", "DENY")
	http.headers_set_unsafe(h, "referrer-policy", "strict-origin-when-cross-origin")
	if sec.set != .Skeleton {
		if sec.set == .Reporting { http.headers_set_unsafe(h, "reporting-endpoints", `csp="/csp-report"`) }
		http.headers_set_unsafe(h, "permissions-policy", "camera=(), microphone=(), geolocation=()")
		http.headers_set_unsafe(h, "cross-origin-opener-policy", "same-origin")
		// The social card and the favicons are fetched by other sites' previews.
		cross := path == "/static/og.png" || path == "/favicon.ico" || path == "/static/favicon.svg"
		http.headers_set_unsafe(h, "cross-origin-resource-policy", "cross-origin" if cross else "same-origin")
	}
	if .Private in flags {
		http.headers_set_unsafe(h, "cache-control", "no-store")
		http.headers_set_unsafe(h, "x-robots-tag", "noindex, nofollow")
	}
	// nginx (NPM) flushes each write instead of buffering the body, and no proxy
	// compresses or caches a live stream: Caddy's `encode` skips no-transform
	// (§8.2; 08 §3.2; S0.8).
	if .Stream in flags {
		http.headers_set_unsafe(h, "cache-control", "no-store, no-transform" if .Private in flags else "no-cache, no-transform")
		http.headers_set_unsafe(h, "x-accel-buffering", "no")
	}
	return
}

// ---- refusals before anything can answer --------------------------------------------

// odin-http frames a body by Content-Length, and after any response on a
// keep-alive connection it drains the unread body itself. The fork reads only
// plain digits within int (F-6); this refuses anything else first, with a closed
// connection, so no path ever frames a body by a bad length.
content_length_ok :: proc(req: ^Request) -> bool {
	cl, has := http.headers_get(req.headers, "content-length")
	if !has { return true }
	_, ok := parse_digits(cl)
	return ok
}

refuse_length :: proc(res: ^Response) {
	http.headers_set_close(&res.headers)
	respond_plain(res, "Malformed Content-Length.", .Bad_Request)
}

// The *.fly.dev hostname serves the same app as the canonical origin, so a
// crawler that finds both splits the site's ranking: a 301 collapses them. Off
// for a placeholder origin (example.com, .test …), which would send every visitor
// nowhere, and never for /healthz: Fly's probe must not follow a redirect off-host.
// Whether it answered with the redirect.
canonical_redirect :: proc(site: ^Site, req: ^Request, res: ^Response) -> bool {
	if !site.redirect || req.url.path == "/healthz" { return false }
	host, _ := http.headers_get(req.headers, "host")
	if !strings.has_suffix(host, ".fly.dev") { return false }
	target := strings.concatenate({site.origin, req.url.path}, context.temp_allocator)
	if req.url.query != "" {
		target = strings.concatenate({target, "?", req.url.query}, context.temp_allocator)
	}
	http.headers_set_unsafe(&res.headers, "location", target)
	http.respond(res, Status.Moved_Permanently)
	return true
}

// A write (any method but GET, HEAD, OPTIONS) must come from this site's own
// pages: Sec-Fetch-Site says so on every request since 2023, Origin on every
// POST long before. Neither header is not a browser (curl, k6), so it can't be a
// forgery riding a user's cookies, and passes; that is also why this doesn't
// demand HX-Request. Runs before the body is read.
same_origin :: proc(req: ^Request) -> bool {
	#partial switch req.line.(http.Requestline).method {
	case .Get, .Head, .Options:
		return true
	}
	if site, ok := http.headers_get(req.headers, "sec-fetch-site"); ok {
		return site == "same-origin" || site == "none" // "none": the user's own action
	}
	origin, has_origin := http.headers_get(req.headers, "origin")
	if !has_origin { return true }
	// Origin is scheme://host[:port], compared with Host, which TLS-terminating
	// proxies pass through unchanged.
	host, _ := http.headers_get(req.headers, "host")
	if i := strings.index(origin, "://"); i >= 0 { origin = origin[i + 3:] }
	return host != "" && strings.equal_fold(origin, host)
}

// An origin on a name reserved for examples and tests (RFC 2606, RFC 6761):
// nobody can be served from one, so the *.fly.dev redirect stays off for it.
placeholder_origin :: proc(origin: string) -> bool {
	host := origin
	if i := strings.index(host, "://"); i >= 0 { host = host[i + 3:] }
	if i := strings.index_any(host, "/:"); i >= 0 { host = host[:i] }
	host = strings.trim_suffix(strings.to_lower(host, context.temp_allocator), ".")
	for reserved in ([]string{"example.com", "example.net", "example.org"}) {
		if host == reserved || strings.has_suffix(host, strings.concatenate({".", reserved}, context.temp_allocator)) {
			return true
		}
	}
	for tld in ([]string{".example", ".test", ".invalid", ".localhost"}) {
		if strings.has_suffix(host, tld) || host == tld[1:] { return true }
	}
	return false
}

// ---- who is asking -------------------------------------------------------------------

method_of :: proc(req: ^Request) -> Method {
	return req.line.(http.Requestline).method
}

method_name :: proc(req: ^Request) -> string {
	return "HEAD" if req.is_head else http.method_string(method_of(req))
}

host_of :: proc(req: ^Request) -> string {
	h, _ := http.headers_get(req.headers, "host")
	if i := strings.last_index_byte(h, ':'); i >= 0 && !strings.has_suffix(h, "]") { h = h[:i] }
	return h
}

cookies_of :: proc(req: ^Request) -> string {
	c, _ := http.headers_get(req.headers, "cookie")
	return c
}

// The client: the TCP peer, unless the peer is a trusted proxy (TRUST_PROXY,
// empty = none), whose X-Real-IP and X-Forwarded-Proto then count (§17.8).
client_of :: proc(req: ^Request) -> (addr: net.Address, https: bool, trusted: bool) {
	addr = req.client.address
	if len(sec.trusted) == 0 || !env.contains(sec.trusted, addr) { return addr, false, false }
	if ip, ok := http.headers_get(req.headers, "x-real-ip"); ok {
		if a := net.parse_address(strings.trim_space(ip)); a != nil { addr = a }
	}
	proto, _ := http.headers_get(req.headers, "x-forwarded-proto")
	return addr, proto == "https", true
}

// A trusted proxy's X-Request-Id, if it looks like one, else a fresh
// `<boot>-<loop>-<seq>`; echoed as x-request-id.
request_id :: proc(req: ^Request, res: ^Response, trusted: bool) -> string {
	id := ""
	if trusted {
		if v, ok := http.headers_get(req.headers, "x-request-id"); ok && len(v) <= 32 && safe_id(v) { id = v }
	}
	if id == "" { id = obs.next_request_id() }
	http.headers_set_unsafe(&res.headers, "x-request-id", id)
	return id
}

@(private)
safe_id :: proc(s: string) -> bool {
	for c in transmute([]byte)s {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.':
		case: return false
		}
	}
	return s != ""
}

// The hashed client id the logs and limits use, never the raw address.
client_id :: proc(addr: net.Address, buf: []byte) -> string {
	h: u32
	switch a in addr {
	case net.IP4_Address: x := a; h = hash.fnv32a(x[:], sec.cid_key)
	case net.IP6_Address: x := transmute([16]u8)a; h = hash.fnv32a(x[:], sec.cid_key)
	}
	return string(buf[:obs.put_hex(buf, 0, u64(h), 8)])
}

// ---- the body --------------------------------------------------------------------------

// Only a request that announces a body is read: http.body on one that doesn't (a
// bare DELETE) makes odin-http drop the keep-alive connection without saying so.
has_body :: proc(req: ^Request) -> bool {
	#partial switch method_of(req) {
	case .Post, .Put, .Patch, .Delete:
		return http.headers_has(req.headers, "content-length") || http.headers_has(req.headers, "transfer-encoding")
	}
	return false
}

Body_Done :: #type proc(user: rawptr, body: string, ok: bool)

// Reads the body, capped at `cap` (413 past it, 400 if malformed, the connection
// then closed: its unread rest is still on the wire). `done` may run later, from
// the loop, so what it needs lives in `user`, in the request arena.
read_body :: proc(req: ^Request, res: ^Response, cap: int, user: rawptr, done: Body_Done) {
	Pending :: struct {
		res:  ^Response,
		user: rawptr,
		done: Body_Done,
	}
	p := new(Pending, context.temp_allocator)
	p^ = {res, user, done}
	http.body(req, cap, p, proc(u: rawptr, body: http.Body, err: http.Body_Error) {
		p := (^Pending)(u)
		if err != nil {
			http.headers_set_close(&p.res.headers)
			http.respond(p.res, http.body_error_status(err))
			p.done(p.user, "", false)
			return
		}
		p.done(p.user, string(body), true)
	})
}

// ---- deferred responses (F-13) ------------------------------------------------------------
//
// A handler whose answer comes from another thread (the writer task, a pool)
// defers it and returns; the continuation resumes it on the same loop, answers,
// then `finish`es it, which counts and logs it as front would have. The ref is
// generation-checked: a client that left costs a map lookup, never a
// use-after-free (S0.5). A resumed response's connection, and its request arena,
// are still there, so `resume` restores the request's context until `finish`:
// the continuation answers with the same helpers a handler uses.

Deferred :: struct {
	ref:    http.Response_Ref,
	ctx:    ^Req_Ctx, // valid only after a successful resume
	route:  ^Mounted,
	method: string,
	start:  i64,
	id:     [32]byte,
	id_len: int,
	client: net.Address,
}

// `watch` closes the connection as soon as the client leaves (F-13's poll): for work
// that takes seconds. A store write answers within its batch, so it doesn't watch.
defer_response :: proc(req: ^Request, res: ^Response, d: ^Deferred, on_gone: proc(user: rawptr) = nil, user: rawptr = nil, watch := false) {
	c := ctx()
	d.ctx = c
	d.route = c.route
	d.method = method_name(req)
	d.start = c_start
	d.id_len = copy(d.id[:], c.id)
	d.client = c.client
	d.ref = http.response_defer(res, on_gone, user, watch)
	c.deferred = true
}

// On the loop that deferred it. nil: the client left, or the connection moved
// on (and the request's context with it). From here the response is the
// continuation's: a crash before `finish` names this request and answers it
// with 500 (M1-04), as a crash in a handler does.
resume :: proc(d: ^Deferred) -> ^Response {
	res := http.response_resume(d.ref)
	if res != nil {
		tl_ctx = d.ctx
		obs.set_request(string(d.id[:d.id_len]), d.route.obs if d.route != nil else obs.NO_ROUTE)
		guard.set_unwind(proc(data: rawptr) {
			d := (^Deferred)(data)
			tl_ctx = nil
			obs.clear_request()
			http.response_crashed(d.ref)
		}, d)
	}
	return res
}

// The deferred request, after a successful resume.
request :: proc(d: ^Deferred) -> ^Request {
	return d.ctx.req
}

// After a resumed response was answered: its count and its access-log line.
finish :: proc(d: ^Deferred, res: ^Response) {
	defer {
		tl_ctx = nil
		obs.clear_request()
		guard.clear_unwind()
	}
	us := (sys.mono_ns() - d.start) / 1000
	if d.route != nil { obs.count_request(d.route.obs, us) }
	access_log(d.method, d.route.id if d.route != nil else "", "", int(res.status), us, string(d.id[:d.id_len]), d.client, "")
}

// The handler's start, for a deferral made inside it (front sets it).
@(private, thread_local) c_start: i64

mark_start :: proc(ns: i64) { c_start = ns }

// One line per request: `ev=req id=… m=GET route="GET /data" st=200 us=183 loop=3
// cid=…`, at info, so LOG_LEVEL=warn turns it off (it costs about 9 % on the light
// routes, 01 §10). `path` only for a request no route answered.
access_log :: proc(method, route, path: string, status: int, us: i64, id: string, client: net.Address, impl: string) {
	l, ok := obs.begin(.Info, "http", "req")
	if !ok { return }
	obs.str(&l, "id", id)
	obs.str(&l, "m", method)
	if route != "" { obs.str(&l, "route", route) } else { obs.str(&l, "path", path) }
	obs.num(&l, "st", i64(status))
	obs.num(&l, "us", us)
	obs.num(&l, "loop", i64(obs.current_loop()))
	cid: [8]byte
	obs.str(&l, "cid", client_id(client, cid[:]))
	if impl != "" { obs.str(&l, "impl", impl) }
	obs.end(&l)
}
