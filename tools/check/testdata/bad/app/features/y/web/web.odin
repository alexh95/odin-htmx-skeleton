package y_web

ROUTES := [?]web.Route {
	{.Get, "/shared/thing", page, .Public, {}, 0},
}

// Named by bad's BUNDLE_EXTS and hub.mount: the inline root's handler mounts it.
EXTS :: web.Exts{}

TOPICS := [?]hub.Topic {
	{family = "y.thing"},
}

init :: proc() {}

page :: proc() {}
