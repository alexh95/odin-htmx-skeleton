package status_web

// ---- status: /status and its board (PLAN §15.4, D36, D8) ------------------------------------
//
// The page's board is one multipart/parallel response, a part per probe into its card, each
// as its probe answers (all at once at M2: every probe is in the process); `?mode=poll`
// fetches the cards every 30 s instead, 304 while no probe's state has changed.

import "core:strconv"
import "core:strings"

import "../../../platform/authz"
import "../../../platform/stream"
import "../../../platform/web"
import status ".."
import status_views "../views"

EXTS :: web.Exts{.Multipart, .Ptag}

ROUTES := [?]web.Route {
	{.Get, "/status", page, .Public, {}, 0},
	{.Get, "/status/parts", parts, .Public, {.Stream, .Fragment}, 0},
	{.Get, "/status/board", board, .Public, {.Fragment}, 0},
}

init :: proc() {
	status.init()
}

@(private)
probes :: proc() -> []status.Probe {
	out := make([dynamic]status.Probe, context.temp_allocator)
	status.board(web.VERSION, &out)
	return out[:]
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	poll := web.query_get(req, "mode") == "poll"
	web.impl(res, "status.mode", "poll" if poll else "parallel")
	wiring := ` hx-get="/status/board" hx-trigger="load, every 30s" hx-swap="none" hx-ptag="0"` if poll else ` hx-get="/status/parts" hx-trigger="load" hx-swap="none"`
	web.render_page(req, res, "Status", "/status", "Whether this site and its parts are up.", status_views.page(probes(), wiring, poll))
}

// One part per probe, each into its own card.
@(private)
parts :: proc(req: ^web.Request, res: ^web.Response) {
	details := authz.can(web.viewer(req), .Admin_Ops)
	ps := probes()
	c := stream.multipart_begin(res, .Parallel)
	if c == nil { return }
	for p in ps {
		b := strings.builder_make(context.temp_allocator)
		status_views.card(&b, p, details, false)
		target := strings.concatenate({"#st-", p.name}, context.temp_allocator)
		if !stream.multipart_part(c, strings.to_string(b), {{"HX-Target", target}, {"HX-Swap", "outerHTML"}}) { return }
	}
	stream.multipart_end(c)
}

// Every card out of band, unless the poller has these states (HX-PTag).
@(private)
board :: proc(req: ^web.Request, res: ^web.Response) {
	ps := probes()
	tag := status.tag(ps)
	if have, ok := strconv.parse_u64_of_base(web.header(req, "hx-ptag"), 10); ok && have == tag {
		web.respond_status(res, .Not_Modified)
		return
	}
	details := authz.can(web.viewer(req), .Admin_Ops)
	b := strings.builder_make(context.temp_allocator)
	for p in ps { status_views.card(&b, p, details, true) }
	buf: [24]byte
	web.set_header(res, "hx-ptag", strconv.write_uint(buf[:], tag, 10))
	web.respond_html(res, strings.to_string(b))
}
