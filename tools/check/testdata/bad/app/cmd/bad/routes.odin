package main

import "../../platform/app"
import "../../platform/hub"
import u_web "../../features/u/web"
import w_web "../../features/w/web"
import x_web "../../features/x/web"
import y_web "../../features/y/web"

ROUTES := [?]app.Mount {
	{"y", x_web.ROUTES[:]},                              // x's table, mounted as y's
	{"x", {{.Get, "/", y_web.page, .Public, {}, 0}}},    // a profile row of x whose handler is y's
	{"w", w_web.ROUTES[:]},                              // /shared, which x claims too
}

// x's and y's TOPICS (y's page is the inline root's handler), and u's, whose
// package no host mounts; w's are missing (topics).
TOPICS := [?][]hub.Topic {
	x_web.TOPICS[:],
	y_web.TOPICS[:],
	u_web.TOPICS[:],
}

NAV := [?]int{}

HOSTS := [?]app.Host{{"main", "SITE_URL", false, ROUTES[:], NAV[:]}}
