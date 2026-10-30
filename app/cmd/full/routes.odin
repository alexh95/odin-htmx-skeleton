package main

// ---- full's routes: Houston's main host (its lab host is slice 10) ------------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import audit_web "../../features/audit/web"
import modules_web "../../features/modules/web"
import home_web "../../features/home/web"
import identity "identity:."

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"platform", hub.ROUTES[:]},        // /events: the topics below
	{"home", {{.Get, "/", home_web.page, .Public, {}, 0}}}, // the root: a card per feature
	{"accounts", identity.ROUTES[:]},   // /login /logout /accounts/sessions
	{"audit", audit_web.ROUTES[:]},     // /admin/audit: the log, LAN only
	{"modules", modules_web.ROUTES[:]}, // /admin/modules: what this build is
	{"about", about_web.ROUTES[:]},     // /about
}

// Mounted by main with hub.mount("main", ..TOPICS[:]).
TOPICS := [?][]hub.Topic {
	identity.TOPICS[:], // the identity's member topics: what a revoke ends
}

HOSTS := [?]app.Host{{"main", "SITE_URL", true, ROUTES[:], NAV[:]}}
