package controllers

import "core:net"
import "core:strings"

import http "../../odin-http"

// ---- middleware: what every request passes through ----------------------
//
// One wrapper around the router (main.odin installs it). It is shared by the
// demo and the `init --minimal` starter, so it stays entity-agnostic.
//
// It reads the body of every request that can carry one before routing, capped
// at MAX_BODY. Doing it here rather than per handler means the cap holds for
// every route, including the ones a fork adds, and a handler gets the parsed
// form synchronously from request_form() instead of wiring its own async read.

// Far above any form this app posts (the longest field is capped in services),
// so it only ever stops abuse. A larger body is refused with 413 before a byte
// of it is read: odin-http checks Content-Length against the cap first.
MAX_BODY :: 64 * 1024

front :: proc(handler: ^http.Handler, req: ^http.Request, res: ^http.Response) {
	next := handler.next.(^http.Handler)
	if !has_body(req) {
		next.handle(next, req, res)
		return
	}
	// http.body may finish later, from the event loop, so what the callback
	// needs lives in the request arena, not on this stack frame.
	p := new(Pending, context.temp_allocator)
	p^ = {next, req, res}
	http.body(req, MAX_BODY, p, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		p := (^Pending)(user)
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

// The current request's form fields, '+'- and percent-decoded. Empty for a
// request without a body.
request_form :: proc() -> map[string]string {
	if context.user_ptr == nil {
		return make(map[string]string, context.temp_allocator)
	}
	return body_form((^string)(context.user_ptr)^)
}

@(private = "file")
Pending :: struct {
	next: ^http.Handler,
	req:  ^http.Request,
	res:  ^http.Response,
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
