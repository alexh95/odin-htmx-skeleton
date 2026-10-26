package dashboard_web

// ---- dashboard: routes and handlers ----------------------------------------------------------
//
// Its page is `skeleton`'s root, a row the profile writes in routes.odin (the
// skeleton's `/`, on which the /  budget rests); on full's lab host the same
// page sits at /dashboard (§6.3). Its one row of its own is the ping fragment.

import "core:time"

import "../../../platform/web"
import dashboard ".."
import dashboard_views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/ui/ping", ui_ping, .Public, {.Fragment}, 0},
}

page :: proc(req: ^web.Request, res: ^web.Response) {
	st, err := dashboard.stats()
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Dashboard", "/",
		"A server-rendered web stack in one binary: an Odin backend renders the HTML, HTMX handles the interaction, SQLite holds the data. Click through the worked example.",
		dashboard_views.page(st))
}

// A fresh reading from the process: a synthetic one, cheap by design (it's the
// budget's fragment, /ui/ping, 0.06 ms in the skeleton).
ui_ping :: proc(req: ^web.Request, res: ^web.Response) {
	token := time.now()._nsec / 1_000_000
	web.respond_html(res, dashboard_views.ping(token, 40 + int(token % 60)))
}
