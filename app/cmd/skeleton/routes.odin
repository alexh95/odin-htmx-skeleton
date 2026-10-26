package main

// ---- skeleton's routes: one host, one line per mounted table -----------------------------
//
// The skeleton's src/routes.odin as one line per package: the URLs are its own,
// so the parity gate's k6 scenarios hit the same paths (§6.3).

import "../../platform/app"
import "../../platform/web"
import about_web "../../features/about/web"
import contacts_web "../../features/contacts/web"
import dashboard_web "../../features/dashboard/web"
import gallery_web "../../features/gallery/web"

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml /BingSiteAuth.xml /<indexnow>.txt
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"dashboard", {{.Get, "/", dashboard_web.page, .Public, {}, 0}}}, // the root: the dashboard
	{"dashboard", dashboard_web.ROUTES[:]}, // /ui/ping
	{"gallery", gallery_web.ROUTES[:]},     // /components /forms /forms/submit /validate/email /ui/*
	{"contacts", contacts_web.ROUTES[:]},   // /data /contacts… /search /api/search
	{"about", about_web.ROUTES[:]},         // /about
}

HOSTS := [?]app.Host{{"main", "SITE_URL", false, ROUTES[:], NAV[:]}}
