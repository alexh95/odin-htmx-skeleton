package scripting_web

// ---- scripting: the nonce class's routes (PLAN §12.2, §15.5) ------------------------------
//
// Every row is .Nonce_Csp, so each response gets its own nonce and the pages
// load the Scripting bundle (hx-csp first), and .Lab_Host: eval-capable pages
// never share an origin with sessions (D20). The streams send research 11 §2.2's
// four buttons once and stay open; the page's nonce reaches them in the connect
// URL, as hx-csp leaves a stream no other way to learn it.

import "../../../platform/stream"
import "../../../platform/web"
import scripting_views "../views"

// Every page is on the fixed Scripting bundle (§12.1), so Main needs nothing from it.
EXTS :: web.Exts{}
BUNDLES :: bit_set[web.Bundle]{.Scripting}

ROUTES := [?]web.Route {
	{.Get, "/scripting", index, .Public, {.Nonce_Csp, .Lab_Host}, 0},
	{.Get, "/scripting/live", live, .Public, {.Nonce_Csp, .Lab_Host}, 0},
	{.Get, "/scripting/streams", streams, .Public, {.Nonce_Csp, .Lab_Host}, 0},
	{.Get, "/scripting/tt", tt, .Public, {.Nonce_Csp, .Lab_Host, .Trusted_Types}, 0},
	{.Get, "/scripting/hello", hello, .Public, {.Nonce_Csp, .Lab_Host, .Fragment}, 0},
	{.Post, "/scripting/score", score, .Public, {.Nonce_Csp, .Lab_Host, .Fragment}, 0},
	{.Get, "/scripting/streams/sse", stream_sse, .Public, {.Nonce_Csp, .Lab_Host, .Stream, .Fragment}, 0},
	{.Get, "/scripting/streams/ws", stream_ws, .Public, {.Nonce_Csp, .Lab_Host, .Stream, .Fragment}, 0},
	{.Get, "/scripting/streams/mp", stream_mp, .Public, {.Nonce_Csp, .Lab_Host, .Stream, .Fragment}, 0},
}

index :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Scripting", "/scripting", "The nonce class: hx-csp, hx-on, trigger filters and js: values under a per-response nonce, on an origin with no sessions.",
		scripting_views.index_page(), bundle = .Scripting)
}

live :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "hx-live", "/scripting", "One password-rules widget in plain JavaScript, a hyperscript behaviour and hx-live bindings.",
		scripting_views.live_page(), bundle = .Scripting)
}

streams :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Streams under hx-csp", "/scripting", "SSE, WebSocket and multipart fragments under hx-csp: which buttons the gate strips, and the connects it never gates.",
		scripting_views.streams_page(), bundle = .Scripting)
}

tt :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Trusted Types", "/scripting", "The nonce class with Trusted Types enforced: htmx swaps and hx-live bindings through hx-csp's policy, and no hyperscript.",
		scripting_views.tt_page(), bundle = .Scripting)
}

// GET /scripting/hello?v=<key>
hello :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.query_get(req, "v")
	if !plain(v) {
		web.respond_status(res, .Bad_Request)
		return
	}
	web.respond_html(res, scripting_views.hello(v))
}

// POST /scripting/score with `score`, which hs-include took from the hyperscript
// card's element scope: 0-4, or the answer says none came.
score :: proc(req: ^web.Request, res: ^web.Response) {
	n, ok := web.parse_digits(web.form(req)["score"])
	web.respond_html(res, scripting_views.score(n, ok && n <= 4))
}

// ---- the streams ----------------------------------------------------------------------------

// GET /scripting/streams/sse?pn=<page nonce>: one event with the four buttons,
// then the stream stays open (heartbeats keep it), so hx-sse doesn't reconnect
// and resend them; with end=1 it ends after the event, as a load scenario wants.
stream_sse :: proc(req: ^web.Request, res: ^web.Response) {
	c := stream.sse_begin(res)
	if c == nil { return }
	if stream.sse_send(c, "", "", scripting_views.stream_buttons("sse", web.ctx().nonce, page_nonce(req))) && web.query_get(req, "end") == "1" {
		stream.end(c)
	}
}

// GET /scripting/streams/ws?pn=<page nonce>: the buttons as one raw HTML
// message, which hx-ws swaps into the connecting element; whatever the page
// sends is ignored.
stream_ws :: proc(req: ^web.Request, res: ^web.Response) {
	own, page := web.ctx().nonce, page_nonce(req)
	c, err := stream.ws_upgrade(req, res, proc(_: ^stream.Conn, _: bool, _: []byte) {})
	if err != .None { return }
	stream.ws_send_text(c, scripting_views.stream_buttons("ws", own, page))
}

// GET /scripting/streams/mp?pn=<page nonce>: one part into the request's target, then the end.
stream_mp :: proc(req: ^web.Request, res: ^web.Response) {
	c := stream.multipart_begin(res)
	if c == nil { return }
	if stream.multipart_part(c, scripting_views.stream_buttons("mp", web.ctx().nonce, page_nonce(req)), {}) {
		stream.multipart_end(c)
	}
}

// The page's nonce as the connect URL carried it: base64url of 16 bytes (front's
// shape), or "" for anything else, which leaves that button without a working nonce.
@(private)
page_nonce :: proc(req: ^web.Request) -> string {
	pn := web.query_get(req, "pn")
	if len(pn) < 16 || len(pn) > 32 { return "" }
	for c in pn {
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '='
		if !ok { return "" }
	}
	return pn
}

// A demo key: 1-40 of [a-z0-9-], as the lab's keys are.
@(private)
plain :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 40 { return false }
	for c in s {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') { return false }
	}
	return true
}
