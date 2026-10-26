package contacts_web

// ---- contacts: routes and handlers ------------------------------------------------------------
//
// The skeleton's exact URLs (§6.3: parity needs them as they were): the data
// page, the table fragment, the detail drawer and the writes on /contacts, the
// search dropdown on /search and the JSON surface on /api/search. Every write
// commits on the writer task; its handler defers the response (F-13) and the
// write's continuation, a named proc below, answers once the batch commits.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import "../../../platform/store"
import "../../../platform/web"
import contacts ".."
import m "../models"
import contacts_views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/data", page_data, .Public, {}, 0},
	{.Get, "/contacts", frag_contacts, .Public, {.Fragment}, 0},
	{.Get, "/contacts/(%d+)", detail, .Public, {.Fragment}, 0},
	{.Post, "/contacts", create, .Public, {.Fragment}, 0},
	{.Post, "/contacts/(%d+)", update, .Public, {.Fragment}, 0},
	{.Delete, "/contacts/(%d+)", delete, .Public, {.Fragment}, 0},
	{.Get, "/search", frag_search, .Public, {.Fragment}, 0},
	{.Get, "/api/search", api_search, .Public, {.Fragment}, 0},
}

// The demo rows, into empty tables only.
seed :: proc() {
	contacts.seed()
}

// ---- reads --------------------------------------------------------------------------------------

page_data :: proc(req: ^web.Request, res: ^web.Response) {
	sort := web.query_get(req, "sort")
	if sort == "" { sort = "name" }
	p, err := contacts.page(web.query_get(req, "q"), web.query_get(req, "status"), sort, 1)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Data & CRUD", "/data",
		"A live contacts table over a SQLite store: filter, sort and paginate, plus create, update and delete — all over HTMX with no full-page reloads.",
		contacts_views.data_page(p))
}

frag_contacts :: proc(req: ^web.Request, res: ^web.Response) {
	sort := web.query_get(req, "sort")
	if sort == "" { sort = "name" }
	p, err := contacts.page(web.query_get(req, "q"), web.query_get(req, "status"), sort, web.query_int(req, "page", 1))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.respond_html(res, contacts_views.region(p))
}

// The drilldown: the full record, its interactions and related contacts, as a
// drawer into #overlay. frag=1: just the <aside> (an open drawer swapped in
// place); edit=1: the edit form.
detail :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	d, err := contacts.detail(id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if web.query_get(req, "frag") == "1" {
		web.respond_html(res, contacts_views.detail_frag(d.contact, d.timeline, d.related, web.query_get(req, "edit") == "1"))
	} else {
		web.respond_html(res, contacts_views.detail(d.contact, d.timeline, d.related))
	}
}

frag_search :: proc(req: ^web.Request, res: ^web.Response) {
	q := web.query_get(req, "q")
	rows, err := contacts.search(strings.trim_space(q), contacts.SEARCH_LIMIT)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.respond_html(res, contacts_views.search_results(q, rows))
}

Contact_DTO :: struct {
	id:     i64,
	name:   string,
	email:  string,
	role:   string,
	status: string,
	score:  int,
	notes:  string,
	notify: bool,
}

// The same data as plain JSON: proof that the domain stands on its own.
api_search :: proc(req: ^web.Request, res: ^web.Response) {
	rows, err := contacts.search_all(strings.trim_space(web.query_get(req, "q")))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	out := make([dynamic]Contact_DTO, context.temp_allocator)
	for c in rows {
		append(&out, Contact_DTO{c.id, c.name, c.email, m.ROLE_NAMES[c.role], m.STATUS_NAMES[c.status], c.score, c.notes, c.notify})
	}
	web.respond_json(res, out[:])
}

// ---- writes ----------------------------------------------------------------------------------------

// A write in flight: the op, the deferred response, and what the answer needs.
@(private)
Writing :: struct {
	using write: m.Write,
	deferred:    web.Deferred,
	from_drawer: bool, // view=detail: answer with the drawer, not the row
}

// Queues `op`, its response deferred until `done` answers it; a full queue
// answers 503 at once.
@(private)
queue :: proc(req: ^web.Request, res: ^web.Response, op: ^Writing, done: proc(o: ^store.Op)) {
	op.done = done
	web.defer_response(req, res, &op.deferred)
	if !contacts.write(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
new_write :: proc(kind: m.Write_Kind, input: m.Contact = {}, id: i64 = 0) -> ^Writing {
	op := store.new_op(Writing, contacts.op_bytes(input))
	a := store.op_allocator(op)
	op.kind, op.id, op.input = kind, id, input
	op.input.name = strings.clone(input.name, a)
	op.input.email = strings.clone(input.email, a)
	op.input.notes = strings.clone(input.notes, a)
	return op
}

// The table's inline add. A refused contact is a 422 into the form's error slot
// (hx-status:422), and app.js resets a form only after a 2xx, so the input stays.
create :: proc(req: ^web.Request, res: ^web.Response) {
	form := web.form(req)
	role, _ := m.role_from(form["role"])
	c, errs := contacts.check_create(form["name"], form["email"], role, .Invited, 50)
	if len(errs) > 0 {
		web.respond_html(res, html.field_msg(false, errs[0].msg), .Unprocessable_Content)
		return
	}
	queue(req, res, new_write(.Create, c), created)
}

@(private)
created :: proc(o: ^store.Op) {
	op := (^Writing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return }
	defer web.finish(&op.deferred, res)
	if o.err != .None {
		answer_error(op, res, o.err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	contacts_views.row(&b, op.result, true)
	strings.write_string(&b, html.toast("success", "Contact added.", true))
	web.respond_html(res, strings.to_string(b))
}

// A cycle (action=cycle), or the drawer's full edit (a name field present), or a
// re-read of the row. view=detail answers with the drawer and the refreshed row
// behind it; otherwise the table row.
update :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	form := web.form(req)
	from_drawer := form["view"] == "detail"
	if form["action"] == "cycle" {
		op := new_write(.Cycle, id = id)
		op.from_drawer = from_drawer
		queue(req, res, op, updated)
		return
	}
	name, editing := form["name"]
	if !editing {
		c, err := contacts.get(id)
		if err != .None {
			web.respond_store_error(req, res, err)
			return
		}
		answer_updated(nil, res, c, from_drawer)
		return
	}
	role, _ := m.role_from(form["role"])
	status, _ := m.status_from(form["status"])
	score := clamp(web.to_int(form["score"]), 0, 100)
	c, errs := contacts.check_update(name, form["email"], role, status, score)
	if len(errs) > 0 {
		// The edit form comes back as typed, with the reason: a refused edit
		// keeps its input. 422 skips app.js's reset.
		stored, err := contacts.get(id)
		if err != .None {
			web.respond_store_error(req, res, err)
			return
		}
		if from_drawer {
			typed := m.Contact{id = id, name = name, email = form["email"], role = role, status = status, score = score}
			web.respond_html(res, contacts_views.edit_rejected(stored, typed, errs[0].msg), .Unprocessable_Content)
		} else {
			web.respond_html(res, html.field_msg(false, errs[0].msg), .Unprocessable_Content)
		}
		return
	}
	op := new_write(.Update, c, id)
	op.from_drawer = from_drawer
	queue(req, res, op, updated)
}

@(private)
updated :: proc(o: ^store.Op) {
	op := (^Writing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return }
	defer web.finish(&op.deferred, res)
	if o.err != .None {
		answer_error(op, res, o.err)
		return
	}
	answer_updated(op, res, op.result, op.from_drawer)
}

// The drawer re-rendered (the main swap into the open drawer), plus the table
// row behind it refreshed. A plain hx-swap-oob <tr> can't ride along: a response
// that starts with the non-table <aside> is body-parsed, which drops a trailing
// <tr>, and a <template> hides it from htmx's OOB query; htmx 4's <hx-partial>
// becomes a <template> that htmx processes into hx-target and hx-swap itself.
@(private)
answer_updated :: proc(op: ^Writing, res: ^web.Response, c: m.Contact, from_drawer: bool) {
	b := strings.builder_make(context.temp_allocator)
	if !from_drawer {
		contacts_views.row(&b, c, false)
		web.respond_html(res, strings.to_string(b))
		return
	}
	d, err := contacts.detail(c.id)
	if err != .None {
		web.respond_store_error(web.ctx().req, res, err)
		return
	}
	strings.write_string(&b, contacts_views.detail_frag(d.contact, d.timeline, d.related, false))
	fmt.sbprintf(&b, `<hx-partial hx-target="#contact-%d" hx-swap="outerHTML">`, c.id)
	contacts_views.row(&b, c, false)
	strings.write_string(&b, `</hx-partial>`)
	web.respond_html(res, strings.to_string(b))
}

// From the table row: an empty body, and the outerHTML swap removes the row.
// From the drawer: the empty main body closes the overlay, and an OOB swap
// removes the stale row behind it.
delete :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	op := new_write(.Delete, id = id)
	op.from_drawer = web.query_get(req, "from") == "drawer"
	queue(req, res, op, deleted)
}

@(private)
deleted :: proc(o: ^store.Op) {
	op := (^Writing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return }
	defer web.finish(&op.deferred, res)
	if o.err != .None {
		answer_error(op, res, o.err)
		return
	}
	if op.from_drawer {
		web.respond_html(res, fmt.tprintf(`<tr id="contact-%d" hx-swap-oob="delete"></tr>`, op.id))
	} else {
		web.respond_html(res, "")
	}
}

// A failed write, answered from its continuation, as a handler would (the
// request's context is back after a successful resume).
@(private)
answer_error :: proc(op: ^Writing, res: ^web.Response, err: m.Error) {
	web.respond_store_error(web.request(&op.deferred), res, err)
}
