package demo

import http "odin-http"

// HTMX is embedded into the binary at compile time, so the backend ships its
// own copy and serves it from memory (see serve_htmx). prepare.* fetches this
// one file before the first build.
HTMX_JS :: #load("static/htmx.min.js")

// The whole route table in one place. Specific patterns are registered before
// catch-alls (e.g. the embedded htmx route before the on-disk /static handler)
// because the router takes the first match in registration order.
build_router :: proc(r: ^http.Router) {
	// pages
	http.route_get(r, "/", http.handler(page_dashboard))
	http.route_get(r, "/components", http.handler(page_components))
	http.route_get(r, "/forms", http.handler(page_forms))
	http.route_get(r, "/data", http.handler(page_data))

	// search: HTMX fragment + plain JSON
	http.route_get(r, "/search", http.handler(frag_search))
	http.route_get(r, "/api/search", http.handler(api_search))

	// contacts: list fragment + CRUD over POST / DELETE
	http.route_get(r, "/contacts", http.handler(frag_contacts))
	http.route_post(r, "/contacts", http.handler(contacts_create))
	http.route_post(r, "/contacts/(%d+)", http.handler(contacts_update))
	http.route_delete(r, "/contacts/(%d+)", http.handler(contacts_delete))

	// component fragments
	http.route_get(r, "/ui/modal", http.handler(ui_modal))
	http.route_get(r, "/ui/drawer", http.handler(ui_drawer))
	http.route_get(r, "/ui/clear", http.handler(ui_clear))
	http.route_get(r, "/ui/tab/(%w+)", http.handler(ui_tab))
	http.route_get(r, "/ui/toast", http.handler(ui_toast))
	http.route_get(r, "/ui/ping", http.handler(ui_ping))

	// form validation + submit
	http.route_post(r, "/validate/email", http.handler(validate_email_field))
	http.route_post(r, "/forms/submit", http.handler(forms_submit))

	// assets: embedded htmx first, then anything else from disk
	http.route_get(r, "/static/htmx.min.js", http.handler(serve_htmx))
	http.route_get(r, "/static/(.+)", http.handler(serve_static))
}
