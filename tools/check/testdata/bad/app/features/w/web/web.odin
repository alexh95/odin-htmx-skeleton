package w_web

ROUTES := [?]web.Route {
	{.Get, "/shared", page, .Public, {}, 0},
}

page :: proc() {}
