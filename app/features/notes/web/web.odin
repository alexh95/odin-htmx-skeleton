package notes_web

// ---- notes: routes and handlers ----------------------------------------------------------

import "core:strings"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/store"
import "../../../platform/web"
import notes ".."
import m "../models"
import notes_views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Post, "/notes", add, .Public, {.Fragment}, 4096},
}

// The newest notes and the add form, for the home page.
home_card :: proc(b: ^strings.Builder, v: authz.Viewer) {
	list := make([dynamic]m.Note, context.temp_allocator)
	if notes.recent(&list) != .None {
		html.w(b, `<p class="muted">The notes can't be read right now.</p>`)
		return
	}
	notes_views.card(b, list[:])
}

// What an add carries to its continuation: the deferred response and the op.
@(private)
Adding :: struct {
	using add: m.Add,
	deferred:  web.Deferred,
}

// The one write. A refused note is a 422 with the reason: the form's
// hx-status:422 routes it to its error slot, and app.js resets a form only after
// a 2xx, so the input stays. A stored one answers its <li>, prepended.
add :: proc(req: ^web.Request, res: ^web.Response) {
	body, problem := notes.check(web.form(req)["body"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	op := store.new_op(Adding, 2 * len(body)) // the input, and the stored note it answers with
	op.body = strings.clone(body, store.op_allocator(op))
	op.done = added
	web.defer_response(req, res, &op.deferred)
	if !notes.add(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
added :: proc(o: ^store.Op) {
	op := (^Adding)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return } // the client left: the note is stored all the same
	if op.err != .None {
		web.respond_plain(res, "Something went wrong on our side. Try again in a moment.", .Internal_Server_Error)
	} else {
		b := strings.builder_make(context.temp_allocator)
		notes_views.li(&b, op.result)
		web.respond_html(res, strings.to_string(b))
	}
	web.finish(&op.deferred, res)
}
