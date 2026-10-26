package y_web

ROUTES := [?]web.Route {
	{.Get, "/shared/thing", page, .Public, {}, 0},
}

init :: proc() {}

page :: proc() {}
