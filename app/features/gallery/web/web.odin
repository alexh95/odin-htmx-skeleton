package gallery_web

// ---- gallery: routes and handlers ---------------------------------------------------------------
//
// The skeleton's component gallery and forms (§6.3 lists its exact URLs):
// /components, /forms and its submit, the /ui fragments (overlays, tabs,
// toasts) and the email check. The forms page creates a contact, through the
// contacts domain (a hard dependency, D6).

import "core:strings"

import "../../../platform/html"
import "../../../platform/store"
import "../../../platform/web"
import "../../contacts"
import gallery_views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/components", page_components, .Public, {}, 0},
	{.Get, "/forms", page_forms, .Public, {}, 0},
	{.Post, "/forms/submit", forms_submit, .Public, {.Fragment}, 0},
	{.Post, "/validate/email", validate_email, .Public, {.Fragment}, 0},
	{.Get, "/ui/modal", ui_modal, .Public, {.Fragment}, 0},
	{.Get, "/ui/drawer", ui_drawer, .Public, {.Fragment}, 0},
	{.Get, "/ui/clear", ui_clear, .Public, {.Fragment}, 0},
	{.Get, "/ui/tab/(%w+)", ui_tab, .Public, {.Fragment}, 0},
	{.Get, "/ui/toast", ui_toast, .Public, {.Fragment}, 0},
}

page_components :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Components", "/components",
		"A gallery of UI components built with Odin + HTMX — buttons, badges, avatars, progress, tabs, accordions, dialogs, drawers and toasts, each swapped in over a single request.",
		gallery_views.components_page())
}

page_forms :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Forms", "/forms",
		"Forms with live inline validation powered by HTMX over an Odin backend: email checks as you type, selects, switches, a range slider, and a real submit that creates a contact.",
		gallery_views.forms_page({contacts.role_labels(), contacts.MAX_NAME, contacts.MAX_EMAIL, contacts.MAX_NOTES}))
}

validate_email :: proc(req: ^web.Request, res: ^web.Response) {
	email := strings.trim_space(web.form(req)["email"])
	switch {
	case email == "":                 web.respond_html(res, "")
	case contacts.valid_email(email): web.respond_html(res, html.field_msg(true, "Looks good."))
	case:                             web.respond_html(res, html.field_msg(false, "That doesn't look like an email."))
	}
}

@(private)
Submitting :: struct {
	using write: contacts.Write,
	deferred:    web.Deferred,
}

// A refused submit is a 422 that lands in #form-result like a success would,
// and keeps the form unreset; a stored one answers its result card and a toast.
forms_submit :: proc(req: ^web.Request, res: ^web.Response) {
	form := web.form(req)
	role, _ := contacts.role_from(form["role"])
	status, _ := contacts.status_from(form["status"])
	// An unticked checkbox isn't posted at all; a ticked one posts "on".
	c, errs := contacts.check_create(form["name"], form["email"], role, status, web.to_int(form["score"]), form["notes"], form["notify"] == "on")
	if len(errs) > 0 {
		msgs := make([]string, len(errs), context.temp_allocator)
		for e, i in errs { msgs[i] = e.msg }
		web.respond_html(res, gallery_views.form_errors(msgs), .Unprocessable_Content)
		return
	}
	op := store.new_op(Submitting, contacts.op_bytes(c))
	a := store.op_allocator(op)
	op.kind, op.input = .Create, c
	op.input.name = strings.clone(c.name, a)
	op.input.email = strings.clone(c.email, a)
	op.input.notes = strings.clone(c.notes, a)
	op.done = submitted
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
submitted :: proc(o: ^store.Op) {
	op := (^Submitting)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred)
	if res == nil { return }
	defer web.finish(&op.deferred, res)
	if o.err != .None {
		web.respond_store_error(web.request(&op.deferred), res, o.err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, gallery_views.form_result(op.result.id, op.result.name, op.result.email))
	strings.write_string(&b, html.toast("success", "Saved to the SQLite store.", true))
	web.respond_html(res, strings.to_string(b))
}

ui_modal :: proc(req: ^web.Request, res: ^web.Response) { web.respond_html(res, gallery_views.modal()) }
ui_drawer :: proc(req: ^web.Request, res: ^web.Response) { web.respond_html(res, gallery_views.drawer()) }
ui_clear :: proc(req: ^web.Request, res: ^web.Response) { web.respond_html(res, "") }
ui_tab :: proc(req: ^web.Request, res: ^web.Response) { web.respond_html(res, gallery_views.tab_panel(req.url_params[0])) }

ui_toast :: proc(req: ^web.Request, res: ^web.Response) {
	kind := web.query_get(req, "kind")
	web.respond_html(res, html.toast(kind, "Something went sideways." if kind == "error" else "That worked nicely.", false))
}
