package main

// ---- full's routes: Houston's main host (its lab host is slice 10) ------------------------

import "../../platform/app"
import "../../platform/web"
import about_web "../../features/about/web"
import home_web "../../features/home/web"
import identity "identity:."

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"home", {{.Get, "/", home_web.page, .Public, {}, 0}}}, // the root: a card per feature
	{"accounts", identity.ROUTES[:]},   // /login /logout /accounts/sessions
	{"about", about_web.ROUTES[:]},     // /about
}

HOSTS := [?]app.Host{{"main", "SITE_URL", true, ROUTES[:], NAV[:]}}
