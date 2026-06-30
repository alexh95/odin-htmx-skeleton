package main

import http "../odin-http"
import "controllers"

// The whole route table in one place. Specific patterns are registered before
// catch-alls (e.g. the embedded htmx route before the on-disk /static handler)
// because the router takes the first match in registration order.
build_router :: proc(r: ^http.Router) {
	// controllers.health (platform liveness probe)
	http.route_get(r, "/healthz", http.handler(controllers.health))

	// pages
	http.route_get(r, "/", http.handler(controllers.page_dashboard))
	http.route_get(r, "/components", http.handler(controllers.page_components))
	http.route_get(r, "/forms", http.handler(controllers.page_forms))
	http.route_get(r, "/data", http.handler(controllers.page_data))
	http.route_get(r, "/about", http.handler(controllers.page_about))

	// search: HTMX fragment + plain JSON
	http.route_get(r, "/search", http.handler(controllers.frag_search))
	http.route_get(r, "/api/search", http.handler(controllers.api_search))

	// contacts: list fragment, detail drilldown, + CRUD over POST / DELETE
	http.route_get(r, "/contacts", http.handler(controllers.frag_contacts))
	http.route_get(r, "/contacts/(%d+)", http.handler(controllers.contact_detail))
	http.route_post(r, "/contacts", http.handler(controllers.contacts_create))
	http.route_post(r, "/contacts/(%d+)", http.handler(controllers.contacts_update))
	http.route_delete(r, "/contacts/(%d+)", http.handler(controllers.contacts_delete))

	// component fragments
	http.route_get(r, "/ui/modal", http.handler(controllers.ui_modal))
	http.route_get(r, "/ui/drawer", http.handler(controllers.ui_drawer))
	http.route_get(r, "/ui/clear", http.handler(controllers.ui_clear))
	http.route_get(r, "/ui/tab/(%w+)", http.handler(controllers.ui_tab))
	http.route_get(r, "/ui/toast", http.handler(controllers.ui_toast))
	http.route_get(r, "/ui/ping", http.handler(controllers.ui_ping))

	// form validation + submit
	http.route_post(r, "/validate/email", http.handler(controllers.validate_email_field))
	http.route_post(r, "/forms/submit", http.handler(controllers.forms_submit))

	// assets: all embedded into the binary, served from memory
	http.route_get(r, "/static/(.+)", http.handler(controllers.serve_static))
}
