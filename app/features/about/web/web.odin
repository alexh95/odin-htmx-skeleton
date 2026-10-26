package about_web

// ---- about: the project page ---------------------------------------------------------------
//
// Every profile's /about: what the site is built with and where its source is.
// The words are the profile's (brand.odin); the shape is shared.

import "core:strings"

import "../../../platform/html"
import "../../../platform/web"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/about", page, .Public, {}, 0},
}

// The profile's words. `lede` and `body` are developer-authored markup, rendered
// raw like the brand's wordmark; everything else is text.
Copy :: struct {
	subtitle, description: string,
	lede, body:            string,
	repo:                  string,
}

@(private) copy: Copy

init :: proc(c: Copy) {
	copy = c
}

page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "About", "About this project", copy.subtitle)
	html.w(&b, `<section class="block"><article class="card about">`)
	html.w(&b, copy.lede)
	html.w(&b, copy.body)
	html.w(&b, `<div class="about-stack"><span class="tag">Odin</span><span class="tag">HTMX 4</span><span class="tag">SQLite</span><span class="tag">single binary</span><span class="tag">no build step</span></div>`)
	// The repo is a developer-set constant (brand.odin), not user input.
	html.w(&b, `<a class="btn btn-primary about-cta" href="`)
	html.w(&b, copy.repo)
	html.w(&b, `" target="_blank" rel="noopener">`)
	html.icon(&b, "github")
	html.w(&b, `<span>View on GitHub</span></a>`)
	html.w(&b, `</article></section>`)
	web.render_page(req, res, "About", "/about", copy.description, strings.to_string(b))
}
