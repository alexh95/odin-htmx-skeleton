package landing_web

// ---- landing: the starter's own page (PLAN §15.5) -------------------------------------------
//
// The lab host's `/` (the profile mounts it): the catalog explorer and the init-command
// builder, rendered once at boot from the embedded catalog; the builder's answer is a fragment.

import "core:fmt"
import "core:os"
import "core:strings"

import "../../../platform/web"
import landing ".."
import landing_views "../views"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/landing/command", command, .Public, {.Fragment}, 0},
}

// The builder's first selection: the minimal profile's features.
@(private)
FIRST :: landing.Choice{name = "my-app", features = {"home", "notes", "about"}}

@(private)
rendered: string

init :: proc() {
	if !landing.init() {
		fmt.eprintln("landing: the embedded docs/catalog.json doesn't read")
		os.exit(1)
	}
	rendered = landing_views.page(&landing.catalog, FIRST)
}

page :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Starter", "/", DESCRIPTION, rendered)
}

@(private)
DESCRIPTION :: "odin-htmx-starter: server-rendered web apps in Odin and htmx 4, in one binary. Browse its features and profiles, and make the init command for yours."

// GET /landing/command?name=…&f-<feature>=1…&store=…: the command and its plan. Only names the
// catalog has get through: a feature's box is read by its catalog name, a family by its members.
command :: proc(req: ^web.Request, res: ^web.Response) {
	c := &landing.catalog
	features := make([dynamic]string, context.temp_allocator)
	for f in c.features {
		if web.query_get(req, strings.concatenate({"f-", f.name}, context.temp_allocator)) != "" { append(&features, f.name) }
	}
	name := web.query_get(req, "name")
	if len(name) > landing.MAX_NAME { name = name[:landing.MAX_NAME] }
	choice := landing.Choice {
		name     = name,
		features = features[:],
		store    = landing.member(c.families.store, web.query_get(req, "store")),
		identity = landing.member(c.families.identity, web.query_get(req, "identity")),
		client   = landing.member(c.families.client, web.query_get(req, "client")),
		theme    = landing.member(c.families.theme, web.query_get(req, "theme")),
	}
	web.respond_html(res, landing_views.command_html(landing.plan(choice)))
}
