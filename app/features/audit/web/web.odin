package audit_web

// ---- audit: /admin/audit (PLAN §17.7) ------------------------------------------------------
//
// The log, newest first, filtered by actor and action prefix; the rows below the first page
// come one page at a time as the last row scrolls into view (keyset on the id), and the
// filter's whole result, up to EXPORT_MAX rows, comes as CSV through hx-download. Admins only,
// from the LAN (§17.2, D41).

import "core:strings"

import "../../../platform/html"
import "../../../platform/web"
import audit ".."
import m "../models"
import audit_views "../views"

EXTS :: web.Exts{.Download}

ROUTES := [?]web.Route {
	{.Get, "/admin/audit", page, .Admin_Audit, {.Private, .Lan_Only}, 0},
	{.Get, "/admin/audit/rows", rows, .Admin_Audit, {.Fragment, .Lan_Only}, 0},
	{.Get, "/admin/audit/export", export, .Admin_Audit, {.Fragment, .Lan_Only}, 0},
}

@(private)
filter_of :: proc(req: ^web.Request, limit: int) -> m.Filter {
	before, _ := web.parse_id(web.query_get(req, "before"))
	return audit.filter(web.query_get(req, "actor"), web.query_get(req, "action"), before, limit)
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	f := filter_of(req, audit.PAGE)
	f.before = 0
	entries := make([dynamic]m.Entry, context.temp_allocator)
	if err := audit.list(f, &entries); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Audit log", "Who did what, newest first. Nothing here can be changed, and an entry is kept for 400 days.")
	audit_views.page(&b, f, entries[:], audit.kept())
	web.render_page(req, res, "Audit log", "/admin/audit", "The audit log.", strings.to_string(b))
}

@(private)
rows :: proc(req: ^web.Request, res: ^web.Response) {
	f := filter_of(req, audit.PAGE)
	entries := make([dynamic]m.Entry, context.temp_allocator)
	if err := audit.list(f, &entries); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	audit_views.rows(&b, f, entries[:])
	web.respond_html(res, strings.to_string(b))
}

@(private)
export :: proc(req: ^web.Request, res: ^web.Response) {
	f := filter_of(req, audit.EXPORT_MAX)
	f.before = 0
	entries := make([dynamic]m.Entry, context.temp_allocator)
	if err := audit.list(f, &entries); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	audit.write_csv(&b, entries[:])
	web.respond_csv(res, "audit.csv", strings.to_string(b))
}
