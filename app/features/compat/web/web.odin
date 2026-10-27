package compat_web

// ---- compat: the compatibility layers' routes (PLAN §12.3, §15.5) --------------------------
//
// /compat/htmx2 and /compat/alpine load their own bundles (htmx plus one
// extension each) under the hash CSP; .Lab_Host keeps them off an origin with
// sessions, since htmx-2-compat changes what every hx-* attribute on the page
// means (D20). The index is on Main.

import "core:strings"
import "core:unicode/utf8"

import "../../../platform/web"
import compat_views "../views"

EXTS :: web.Exts{}
BUNDLES :: bit_set[web.Bundle]{.Compat_Htmx2, .Compat_Alpine}

ROUTES := [?]web.Route {
	{.Get, "/compat", index, .Public, {.Lab_Host}, 0},
	{.Get, "/compat/htmx2", htmx2, .Public, {.Lab_Host}, 0},
	{.Post, "/compat/htmx2/save", htmx2_save, .Public, {.Lab_Host, .Fragment}, 0},
	{.Get, "/compat/htmx2/ping", htmx2_ping, .Public, {.Lab_Host, .Fragment}, 0},
	{.Get, "/compat/alpine", alpine, .Public, {.Lab_Host}, 0},
	{.Get, "/compat/alpine/ping", alpine_ping, .Public, {.Lab_Host, .Fragment}, 0},
}

index :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "Compat", "/compat", "htmx 4's two compatibility extensions, each on a page and a bundle of its own.", compat_views.index_page())
}

htmx2 :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "htmx-2-compat", "/compat", "htmx 2's semantics on htmx 4: error responses left unswapped, implicit inheritance and the old event names.",
		compat_views.htmx2_page(), bundle = .Compat_Htmx2)
}

// POST /compat/htmx2/save: a name of 1-40 characters, or 422 with the reason,
// which this page's htmx never swaps.
htmx2_save :: proc(req: ^web.Request, res: ^web.Response) {
	name := strings.trim_space(web.form(req)["name"])
	if name == "" || utf8.rune_count(name) > 40 {
		web.respond_html(res, compat_views.refused("A name of 1 to 40 characters, please."), .Unprocessable_Content)
		return
	}
	web.respond_html(res, compat_views.saved(name))
}

htmx2_ping :: proc(req: ^web.Request, res: ^web.Response) {
	web.respond_html(res, compat_views.pong())
}

alpine :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "hx-alpine-compat", "/compat", "The Alpine bridge loaded with no Alpine: it registers and changes nothing.",
		compat_views.alpine_page(), bundle = .Compat_Alpine)
}

alpine_ping :: proc(req: ^web.Request, res: ^web.Response) {
	web.respond_html(res, compat_views.alpine_pong())
}
