package main

import http "../odin-http"
import "controllers"

// The whole route table in one place. Specific patterns are registered before
// catch-alls (the /static handler is last).
build_router :: proc(r: ^http.Router) {
	http.route_get(r, "/healthz", http.handler(controllers.health)) // platform liveness probe

	// Crawler contract. Both are generated from views.NAV + views.SITE_URL.
	http.route_get(r, "/robots.txt", http.handler(controllers.robots_txt))
	http.route_get(r, "/sitemap.xml", http.handler(controllers.sitemap_xml))

	// pages
	http.route_get(r, "/", http.handler(controllers.page_home))
	http.route_get(r, "/about", http.handler(controllers.page_about))

	// the one write path: add a note (returns the new <li> to append)
	http.route_post(r, "/notes", http.handler(controllers.notes_create))

	// assets: all embedded into the binary, served from memory
	http.route_get(r, "/static/(.+)", http.handler(controllers.serve_static))
}
