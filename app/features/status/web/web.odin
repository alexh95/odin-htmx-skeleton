package status_web

// ---- status: /status and its board (PLAN §15.4, D36, D8) ------------------------------------
//
// The page's board is one multipart/parallel response, a part per probe into its card, each
// as its probe answers: the process's own at once, an external's when its prober next answers
// (or "no answer" at ANSWER_WITHIN); `?mode=poll` fetches the cards every 30 s instead, 304
// while no probe's state has changed.

import "base:runtime"
import "core:nbio"
import "core:strconv"
import "core:strings"
import "core:sync"

import "../../../platform/authz"
import "../../../platform/guard"
import "../../../platform/workers"
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

// A board on its way: the stream, the externals still owed a part, and one reference each for
// the stream, the cut-off timer and every external it waits on; the last to let go frees it.
@(private)
Waiting :: struct {
	c:       ^stream.Conn,
	loop:    ^nbio.Event_Loop,
	details: bool,
	open:    bool, // the stream: false once it ended or the client left
	owed:    int,
	pending: [status.MAX_EXTERNALS]bool,
	waiters: [status.MAX_EXTERNALS]status.Waiter,
	refs:    int, // atomic
}

// One part per probe, each into its own card, as it answers.
@(private)
parts :: proc(req: ^web.Request, res: ^web.Response) {
	wt := new(Waiting, runtime.heap_allocator())
	wt.details, wt.loop, wt.refs = authz.can(web.viewer(req), .Admin_Ops), nbio.current_thread_event_loop(), 1
	c := stream.multipart_begin(res, .Parallel, wt, proc(c: ^stream.Conn) {
		wt := (^Waiting)(c.user)
		wt.open = false
		let_go(wt)
	})
	if c == nil {
		free(wt, runtime.heap_allocator())
		return
	}
	wt.c, wt.open = c, true
	local := make([dynamic]status.Probe, context.temp_allocator)
	status.local(web.VERSION, &local)
	for p in local {
		if !part(wt, p) { return }
	}
	for i in 0 ..< status.externals_count() {
		p, fresh := status.external(i)
		if !fresh {
			wt.waiters[i] = {answered = answered, user = wt}
			sync.atomic_add(&wt.refs, 1)
			if status.wait_for(i, &wt.waiters[i]) {
				wt.pending[i] = true
				wt.owed += 1
				continue
			}
			sync.atomic_sub(&wt.refs, 1)
		}
		if !part(wt, p) { return }
	}
	if wt.owed == 0 {
		end(wt)
		return
	}
	sync.atomic_add(&wt.refs, 1)
	nbio.timeout_poly(status.ANSWER_WITHIN, wt, cut_off)
}

@(private)
part :: proc(wt: ^Waiting, p: status.Probe) -> bool {
	b := strings.builder_make(context.temp_allocator)
	status_views.card(&b, p, wt.details, false)
	target := strings.concatenate({"#st-", p.name}, context.temp_allocator)
	return stream.multipart_part(wt.c, strings.to_string(b), {{"HX-Target", target}, {"HX-Swap", "outerHTML"}})
}

@(private)
end :: proc(wt: ^Waiting) {
	if !wt.open { return }
	stream.multipart_end(wt.c) // its on_close lets go of the stream's reference
}

@(private)
let_go :: proc(wt: ^Waiting) {
	if sync.atomic_sub(&wt.refs, 1) == 1 { free(wt, runtime.heap_allocator()) }
}

// On the prober's thread: the answer goes to the page's loop.
@(private)
answered :: proc(w: ^status.Waiter) {
	if !workers.post((^Waiting)(w.user).loop, w, owed_part) { let_go((^Waiting)(w.user)) }
}

@(private)
owed_part :: proc(_: ^nbio.Operation, w: ^status.Waiter) {
	wt := (^Waiting)(w.user)
	guard.call(proc(data: rawptr) {
		w := (^status.Waiter)(data)
		wt := (^Waiting)(w.user)
		if !wt.open || !wt.pending[w.index] { return }
		wt.pending[w.index] = false
		wt.owed -= 1
		p, _ := status.external(w.index)
		if part(wt, p) && wt.owed == 0 { end(wt) }
	}, w)
	let_go(wt)
	free_all(context.temp_allocator)
}

// ANSWER_WITHIN passed: every external still owed is said to have no answer, and the board ends.
@(private)
cut_off :: proc(_: ^nbio.Operation, wt: ^Waiting) {
	guard.call(proc(data: rawptr) {
		wt := (^Waiting)(data)
		if !wt.open { return }
		for i in 0 ..< status.externals_count() {
			if !wt.pending[i] { continue }
			wt.pending[i] = false
			p, _ := status.external(i)
			p.state, p.message = "down", "no answer in 2 s"
			if !part(wt, p) { return }
		}
		end(wt)
	}, wt)
	let_go(wt)
	free_all(context.temp_allocator)
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
