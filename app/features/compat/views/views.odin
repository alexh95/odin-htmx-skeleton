package compat_views

// ---- compat: the two compatibility extensions, each on its own bundle (§12.3) -------------
//
// htmx-2-compat and hx-alpine-compat change what htmx means on the page that
// loads them, so each lives on a page of its own with its own bundle, under the
// hash CSP. The rest of the starter uses neither, and these pages say why.

import "core:strings"

import "../../../platform/html"

index_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Compat", "Compatibility layers", "Two of htmx 4's extensions exist to make old code run: each gets a page and a bundle of its own, and the starter uses neither.")
	html.w(&b, `<section class="block"><div class="compat-cards">`)
	card(&b, "/compat/htmx2", "htmx-2-compat", "htmx 2's semantics on htmx 4: implicit inheritance, error responses left unswapped, and the old event names.")
	card(&b, "/compat/alpine", "hx-alpine-compat", "Loaded with no Alpine: it registers, does nothing, and breaks nothing.")
	html.w(&b, `</div></section>`)
	return strings.to_string(b)
}

@(private = "file")
card :: proc(b: ^strings.Builder, href, title, text: string) {
	html.w(b, `<a class="card compat-card" href="`)
	html.w(b, href)
	html.w(b, `"><h2>`)
	html.esc(b, title)
	html.w(b, `</h2><p class="muted">`)
	html.esc(b, text)
	html.w(b, `</p></a>`)
}

@(private = "file")
back :: proc(b: ^strings.Builder) {
	html.w(b, `<p class="block"><a href="/compat">Back to the compatibility layers</a></p>`)
}

// /compat/htmx2: markup written the htmx 2 way, as the skeleton's views were
// before its move to htmx 4 (78a31ca, ea5ae91), on a page whose bundle adds
// htmx-2-compat. A refused submit answers 422, which htmx 2 never swapped and
// htmx 4 does; a child inherits its parent's hx-target, as in htmx 2; the old
// event names fire (compat.js counts htmx:afterSwap).
htmx2_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Compat", "htmx-2-compat", "htmx 2's semantics on htmx 4, on this page only.")
	html.w(&b, `<section class="block compat-prose"><p>The starter's forms answer a refused submit with 422 and the reason, and htmx 4 swaps it where the form says (<code>hx-status:422</code>). htmx-2-compat puts 4xx and 5xx back on htmx's no-swap list, so here the reason never shows: the form below keeps its old result. It also turns implicit inheritance back on, which htmx 4 dropped so that an attribute on a container stops reaching every element inside it, and fires htmx 2's event names beside htmx 4's.</p></section>`)

	html.w(&b, `<section class="block"><div class="compat-grid">`)
	html.w(&b, `<div class="card"><h2>A form from the htmx 2 era</h2>`)
	html.w(&b, `<form id="h2-form" hx-post="/compat/htmx2/save" hx-target="#h2-result"><label class="field"><span>Name</span><input name="name" id="h2-name" maxlength="40"></label>`)
	html.w(&b, `<button class="btn btn-primary" id="h2-save">Save</button></form>`)
	html.w(&b, `<div id="h2-result" class="compat-out" aria-live="polite"><p class="muted">Nothing saved yet.</p></div></div>`)

	html.w(&b, `<div class="card"><h2>Implicit inheritance</h2><div id="h2-parent" hx-target="#h2-inherited">`)
	html.w(&b, `<button class="btn" type="button" id="h2-child" hx-get="/compat/htmx2/ping">Ping</button></div>`)
	html.w(&b, `<p class="muted">The button names no target; it inherits its parent's.</p><div id="h2-inherited" class="compat-out" aria-live="polite"></div></div>`)

	html.w(&b, `<div class="card"><h2>htmx 2's event names</h2><p>htmx:afterSwap fired <output id="h2-swaps">0</output> times.</p></div>`)
	html.w(&b, `</div></section>`)
	back(&b)
	return strings.to_string(b)
}

saved :: proc(name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p id="h2-saved">Saved `)
	html.esc(&b, name)
	html.w(&b, `.</p>`)
	return strings.to_string(b)
}

refused :: proc(msg: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p class="field-msg form-error" id="h2-refused">`)
	html.esc(&b, msg)
	html.w(&b, `</p>`)
	return strings.to_string(b)
}

pong :: proc() -> string { return `<p id="h2-pong">pong, into the parent's target</p>` }

// /compat/alpine: the extension alone, with no Alpine on the page (D3: Alpine is
// a client framework, and stays out unless Alex asks). An ordinary swap shows
// htmx behaving as it does everywhere else.
alpine_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Compat", "hx-alpine-compat", "The Alpine bridge, loaded with no Alpine: it registers and changes nothing.")
	html.w(&b, `<section class="block compat-prose"><p>hx-alpine-compat defers Alpine's mutation observer around swaps and carries Alpine's state through morphs. It needs Alpine.js, a client framework, which the starter never ships, so this page loads the extension alone: it registers, every hook finds no Alpine and returns, and htmx works as it does on every other page.</p></section>`)
	html.w(&b, `<section class="block"><div class="card"><h2>An ordinary swap</h2><button class="btn" type="button" id="alpine-ping" hx-get="/compat/alpine/ping" hx-target="#alpine-out">Ping</button>`)
	html.w(&b, `<div id="alpine-out" class="compat-out" aria-live="polite"></div></div></section>`)
	back(&b)
	return strings.to_string(b)
}

alpine_pong :: proc() -> string { return `<p id="alpine-pong">pong, unchanged</p>` }
