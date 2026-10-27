package main

// ---- minimal's routes: one host, one line per mounted table -----------------------------

import "../../platform/app"
import "../../platform/web"
import about_web "../../features/about/web"
import home_web "../../features/home/web"
import notes_web "../../features/notes/web"

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"home", {{.Get, "/", home_web.page, .Public, {}, 0}}}, // the root: a card per feature
	{"notes", notes_web.ROUTES[:]},     // POST /notes
	{"about", about_web.ROUTES[:]},     // /about
}

HOSTS := [?]app.Host{{"main", "SITE_URL", false, ROUTES[:], NAV[:]}}
