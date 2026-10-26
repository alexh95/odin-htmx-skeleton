package app

// ---- front: what every request passes through (§8.4) ----------------------------------
//
// The skeleton's order (SK/app/src/controllers/middleware.odin:38-87), with the
// host picked first and the route found before anything answers, so its flags
// set the headers and its perm is checked before the body is read:
//
//   1. the host by Host (an unknown one is the main host), the route, the request
//      id, the security headers by the route's flags;
//   2. a malformed Content-Length gets 400 and a closed connection, first;
//   3. the *.fly.dev → canonical origin 301;
//   4. no route: 405 with Allow when another method serves the path, else 404;
//   5. the viewer, by the build's identity on a host that runs one, and the route's
//      perm (401 or 403), .Lan_Only (404 off the LAN);
//   6. the cross-site write guard, before the body;
//   7. the body, capped by the route (413 past it), then the handler;
//   8. one access-log line, unless the handler deferred its response: its
//      continuation logs it when it answers.

import "core:strings"

import "../authz"
import "../obs"
import "../sys"
import "../web"
import identity "identity:."

@(private)
front :: proc(req: ^web.Request, res: ^web.Response) {
	start := sys.mono_ns()
	web.mark_start(start)
	c := new(web.Req_Ctx, context.temp_allocator)
	c.req, c.res, c.start = req, res, start
	c.site = pick_site(req)
	trusted: bool
	c.client, c.https, trusted = web.client_of(req)
	c.id = web.request_id(req, res, trusted)
	m, params, allow := web.router_find(&c.site.router, web.method_of(req), req.url.path)
	c.route = m
	obs.set_request(c.id, m.obs if m != nil else obs.NO_ROUTE)
	web.security_headers(res, m.flags if m != nil else {}, req.url.path)
	web.set_ctx(c)
	defer web.set_ctx(nil)

	switch {
	case !web.content_length_ok(req):
		web.refuse_length(res)
	case web.canonical_redirect(c.site, req, res):
	case m == nil && len(allow) > 0:
		web.set_header(res, "allow", strings.join(allow, ", ", context.temp_allocator))
		web.respond_plain(res, "Method not allowed.", .Method_Not_Allowed)
	case m == nil:
		web.not_found(req, res)
	case:
		req.url_params = params
		if !admit(c, req, res) { break }
		if !web.has_body(req) {
			call(c)
			return
		}
		web.read_body(req, res, m.body_cap if m.body_cap > 0 else web.MAX_BODY, c, proc(user: rawptr, body: string, ok: bool) {
			c := (^web.Req_Ctx)(user)
			if !ok {
				done(c)
				return
			}
			c.body = body
			call(c)
		})
		return
	}
	done(c)
}

// The host whose origin's hostname is Host's; the main host (the first) otherwise,
// where the canonical-host redirect still applies.
@(private)
pick_site :: proc(req: ^web.Request) -> ^web.Site {
	if len(st.sites) > 1 {
		h := web.host_of(req)
		for &s in st.sites[1:] {
			if s.hostname == h { return &s }
		}
	}
	return &st.sites[0]
}

// The viewer and the route's access rules, before a byte of the body is read.
@(private)
admit :: proc(c: ^web.Req_Ctx, req: ^web.Request, res: ^web.Response) -> bool {
	c.viewer = authz.GUEST
	if c.site.identity {
		v, cookie := identity.load_viewer({cookies = web.cookies_of(req), client = c.client, https = c.https})
		c.viewer = v
		if cookie != "" { web.set_header(res, "set-cookie", cookie) }
	}
	m := c.route
	if .Lan_Only in m.flags && !is_lan(c.client) {
		web.not_found(req, res)
		return false
	}
	if !authz.can(c.viewer, m.perm) {
		// A guest is sent to sign in; anyone else is refused (§17.2).
		if c.viewer.role == .Guest {
			if web.is_htmx(req) {
				web.set_header(res, "hx-redirect", "/login")
				web.respond_plain(res, "Sign in first.", .Unauthorized)
			} else {
				web.set_header(res, "location", "/login")
				web.respond_status(res, .Found)
			}
		} else {
			web.respond_plain(res, "Not allowed.", .Forbidden)
		}
		return false
	}
	if !web.same_origin(req) {
		web.respond_plain(res, "Cross-site request refused.", .Forbidden)
		return false
	}
	return true
}

@(private)
call :: proc(c: ^web.Req_Ctx) {
	web.set_ctx(c)
	c.route.handler(c.req, c.res)
	web.set_ctx(nil)
	if !c.deferred { done(c) }
}

@(private)
done :: proc(c: ^web.Req_Ctx) {
	us := (sys.mono_ns() - c.start) / 1000
	route := ""
	if c.route != nil {
		obs.count_request(c.route.obs, us)
		route = c.route.id
	}
	cid: [8]byte
	web.access_log(web.method_name(c.req), route, c.req.url.path, int(c.res.status), us, c.id, web.client_id(c.client, cid[:]), c.impl)
	obs.clear_request()
}
