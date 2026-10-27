package w_web

// No EXTS line (exts), a family outside w's and declared by x too, mounted on a
// host whose hub.mount doesn't name it (topics), and a '-' Lua reads as a
// quantifier beside three it doesn't (routes).

ROUTES := [?]web.Route {
	{.Get, "/shared", page, .Public, {}, 0},
	{.Get, "/w/csp-report", page, .Public, {}, 0},    // '-' after a literal: a lazy quantifier
	{.Get, "/w/(.-)/end", page, .Public, {}, 0},      // after '.': meant
	{.Get, "/w/x%-y", page, .Public, {}, 0},          // escaped
	{.Get, "/w/([a-z-]+)", page, .Public, {}, 0},     // a range inside a set
}

TOPICS := [?]hub.Topic {
	{family = "x.feed"},
}

page :: proc() {}
