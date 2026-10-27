package x_web

import "../../y/web"   // a web package never imports another web package
import "../../z"
import "../../../platform/hub"

ROUTES := [?]web.Route {
	{.Get, "/", page, .Public, {}, 0},          // a root row inside a package's table
	{.Get, "/elsewhere", page, .Public, {}, 0}, // outside x's prefixes
	{.Get, "/legacy/page", page, .Public, {}, 0},
	{.Get, "/shared", page, .Public, {}, 0},
}

// Main's BUNDLE_EXTS and PAGE_BUNDLES name neither (exts).
EXTS :: web.Exts{.Sse}
BUNDLES :: bit_set[web.Bundle]{.Scripting}

TOPICS := [?]hub.Topic {
	{family = "x.feed"},
	{"elsewhere", .Queue}, // positional, and outside x's families
}

init :: proc() {}

page :: proc() {
	hub.publish("x.feed:1", "")  // declared
	hub.publish("x.ghost:1", "") // declared by no package
}
