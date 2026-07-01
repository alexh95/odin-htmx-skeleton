package views
import "../models"
import "../services"

import "core:fmt"
import "core:strings"

// ---- views --------------------------------------------------------------
//
// HTML is assembled by writing into a strings.Builder — no template engine, a
// "component" is a proc that appends markup. Raw string literals (backticks) let
// attribute quotes stand as-is. Everything builds in the request arena (temp
// allocator) and is freed once the response is flushed. Every dynamic string
// passes through esc() — the one defence against injected markup.

w :: proc(b: ^strings.Builder, s: string) {
	strings.write_string(b, s)
}

// HTML-escape text content. Not optional anywhere user input is echoed.
esc :: proc(b: ^strings.Builder, s: string) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&': w(b, "&amp;")
		case '<': w(b, "&lt;")
		case '>': w(b, "&gt;")
		case '"': w(b, "&#34;")
		case '\'': w(b, "&#39;")
		case: strings.write_byte(b, s[i])
		}
	}
}

// ---- icons --------------------------------------------------------------
//
// A closed set of inline SVGs, 24x24, stroked with currentColor. One proc, one
// switch — adding an icon is a single case.
icon :: proc(b: ^strings.Builder, name: string) {
	w(b, `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">`)
	switch name {
	case "grid":    w(b, `<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>`)
	case "info":    w(b, `<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>`)
	case "bolt":    w(b, `<path d="M13 2 3 14h7l-1 8 10-12h-7l1-8Z"/>`)
	case "palette": w(b, `<path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.9 0 1.6-.7 1.6-1.6 0-.4-.2-.8-.4-1.1-.3-.3-.4-.6-.4-1.1a1.6 1.6 0 0 1 1.6-1.6h2c3 0 5.6-2.5 5.6-5.5C22 6 17.5 2 12 2Z"/><circle cx="6.5" cy="11.5" r="1" fill="currentColor" stroke="none"/><circle cx="9.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="14.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="17.5" cy="11.5" r="1" fill="currentColor" stroke="none"/>`)
	case "github":  w(b, `<path fill="currentColor" stroke="none" d="M12 2A10 10 0 0 0 8.84 21.5c.5.08.66-.22.66-.48l-.01-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.26-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.38.2 2.39.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85l-.01 2.74c0 .27.16.57.67.48A10 10 0 0 0 12 2Z"/>`)
	}
	w(b, `</svg>`)
}

// ---- theme picker -------------------------------------------------------
//
// Two orthogonal axes carried as data-attributes on <html>: `data-style` (the
// treatment) and `data-scheme` (the palette). Pure presentation: the picker is
// static HTML, app.js applies + persists the choice (localStorage), and the head
// pre-paint script restores it before first paint. No server endpoint.

@(private = "file")
Style_Opt :: struct {
	id, label: string,
}

@(private = "file")
Scheme_Opt :: struct {
	style, id, label, swatch: string,
}

@(private = "file")
STYLES := []Style_Opt {
	{"modern", "Modern"},
	{"skeuo", "Skeuo"},
	{"terminal", "Terminal"},
	{"brutal", "Brutalist"},
	{"editorial", "Editorial"},
	{"arcade", "Arcade"},
}

@(private = "file")
SCHEMES := []Scheme_Opt {
	{"modern", "midnight", "Midnight", "#7c5cff"},
	{"modern", "daylight", "Daylight", "#5b8cff"},
	{"modern", "nebula", "Nebula", "#f472d0"},
	{"modern", "aurora", "Aurora", "#34d399"},
	{"modern", "ember", "Ember", "#fb923c"},
	{"modern", "sandstone", "Sandstone", "#d2622f"},
	{"modern", "ocean", "Ocean", "#38bdf8"},
	{"skeuo", "aqua", "Aqua", "#3b82f6"},
	{"skeuo", "graphite", "Graphite", "#8b95a3"},
	{"skeuo", "brass", "Brass", "#d8a64a"},
	{"terminal", "green", "Green", "#2bff66"},
	{"terminal", "amber", "Amber", "#ffb000"},
	{"terminal", "ibm", "IBM", "#8ab4ff"},
	{"terminal", "paper", "Paper", "#1f7a3d"},
	{"brutal", "paper", "Paper", "#2b46ff"},
	{"brutal", "ink", "Ink", "#111111"},
	{"brutal", "acid", "Acid", "#e6ff36"},
	{"editorial", "manuscript", "Manuscript", "#8a2f3a"},
	{"editorial", "sepia", "Sepia", "#9a5a2e"},
	{"editorial", "night", "Night", "#d99a5a"},
	{"arcade", "arcade", "Arcade", "#ff3df0"},
	{"arcade", "synthwave", "Synthwave", "#ff2d95"},
	{"arcade", "pop", "Pop", "#ff3b6b"},
}

// Fingerprinted asset URLs, set once at startup by controllers.init_etags from
// the embedded bytes. Bare defaults until init runs.
HTMX_HREF := "/static/htmx.min.js"
CSS_HREF := "/static/app.css"
JS_HREF := "/static/app.js"

theme_picker :: proc(b: ^strings.Builder) {
	w(b, `<details class="picker"><summary class="icon-btn" aria-label="Theme and style" title="Theme & style">`)
	icon(b, "palette")
	w(b, `</summary><div class="picker-panel"><p class="picker-head">Style</p><div class="picker-styles">`)
	for s in STYLES {
		fmt.sbprintf(b, `<button class="chip" type="button" data-pick-style="%s" aria-pressed="false" onclick="pickStyle('%s')">%s</button>`, s.id, s.id, s.label)
	}
	w(b, `</div><p class="picker-head">Scheme</p>`)
	for s in STYLES {
		fmt.sbprintf(b, `<div class="picker-schemes" data-for="%s">`, s.id)
		for sc in SCHEMES {
			if sc.style != s.id {continue}
			fmt.sbprintf(b, `<button class="swatch" type="button" data-pick-scheme="%s" aria-pressed="false" title="%s" style="--sw:%s" onclick="pickScheme('%s')"></button>`, sc.id, sc.label, sc.swatch, sc.id)
		}
		w(b, `</div>`)
	}
	w(b, `</div></details>`)
}

// ---- layout -------------------------------------------------------------

NAV := [?]struct {
	href, label, icon: string,
} {
	{"/", "Home", "grid"},
	{"/about", "About", "info"},
}

// The one page shell. `active` is the href of the current page so the nav can
// mark it. The inline head script sets the theme before first paint to avoid a
// flash of the wrong palette.
layout :: proc(title, active, description, content: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	// The head carries literal { } (htmx-config JSON, the theme script), and
	// Odin's fmt treats braces as directives — so write it raw with w() and splice
	// the only dynamic values (title/description) in between.
	w(&b, `<!doctype html>
<html lang="en" data-style="modern" data-scheme="midnight">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="htmx-config" content='{"transitions":true,"defaultSwap":"innerHTML"}'>
<title>`)
	esc(&b, title)
	w(&b, " · ")
	esc(&b, BRAND_SUFFIX)
	w(&b, `</title>
<meta name="description" content="`)
	esc(&b, description)
	w(&b, `">
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="`)
	w(&b, CSS_HREF)
	w(&b, `">
<script>try{var d=document.documentElement,s=localStorage.getItem('style'),c=localStorage.getItem('scheme');if(s)d.dataset.style=s;if(c)d.dataset.scheme=c;}catch(e){}</script>
<script src="`)
	w(&b, HTMX_HREF)
	w(&b, `" defer></script>
<script src="`)
	w(&b, JS_HREF)
	w(&b, `" defer></script>
</head>
<body>
<header class="topbar">
  <a class="brand" href="/" hx-boost="true"><span class="brand-mark">`)
	icon(&b, "bolt")
	w(&b, `</span><span class="brand-name">`)
	w(&b, BRAND_WORDMARK)
	w(&b, `</span></a>
  <nav class="nav" aria-label="Primary">`)
	for item in NAV {
		cur := item.href == active ? ` aria-current="page"` : ""
		fmt.sbprintf(&b, `<a class="nav-link" href="%s"%s hx-boost="true">`, item.href, cur)
		icon(&b, item.icon)
		fmt.sbprintf(&b, `<span>%s</span></a>`, item.label)
	}
	w(&b, `</nav>
  `)
	theme_picker(&b)
	w(&b, `
</header>
<main class="container">`)
	w(&b, content)
	w(&b, `</main>
</body>
</html>`)
	return strings.to_string(b)
}

// Section header used at the top of every page body.
page_head :: proc(b: ^strings.Builder, eyebrow, title, subtitle: string) {
	fmt.sbprintf(b, `<header class="page-head"><p class="eyebrow">%s</p><h1>%s</h1><p class="lede">%s</p></header>`, eyebrow, title, subtitle)
}

// ---- home ---------------------------------------------------------------

view_home :: proc(notes: []models.Note) -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(&b, "Starter", "Your app", "A minimal Odin + HTMX + SQLite page. Add a note — it's stored in SQLite and appended over one request. Replace this with your own.")

	w(&b, `<section class="block"><article class="card">`)
	// data-reset-on-success: app.js clears the form after its own 2xx submit.
	w(&b, `<form class="add-note" hx-post="/notes" hx-target="#note-list" hx-swap="afterbegin" data-reset-on-success>`)
	w(&b, `<input name="body" placeholder="Write a note…" required autocomplete="off" aria-label="Note">`)
	w(&b, `<button class="btn btn-primary" type="submit">Add</button></form>`)
	w(&b, `<ul class="note-list" id="note-list">`)
	for n in notes {
		view_note_li(&b, n)
	}
	w(&b, `</ul></article></section>`)
	return strings.to_string(b)
}

view_note_li :: proc(b: ^strings.Builder, n: models.Note) {
	w(b, `<li class="note"><span class="note-body">`)
	esc(b, n.body)
	w(b, `</span><small class="note-time">`)
	esc(b, services.time_ago(n.at))
	w(b, `</small></li>`)
}

// ---- about --------------------------------------------------------------

view_about :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(&b, "About", "About this project", "A minimal starter for a simple, server-rendered website — Odin + HTMX + SQLite in one self-contained binary.")

	w(&b, `<section class="block"><article class="card about">`)
	w(&b, `<p class="about-lede">Built on a <strong>starter skeleton</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a> over a <a href="https://sqlite.org" target="_blank" rel="noopener">SQLite</a> store, served as a single statically-linked binary.</p>`)
	w(&b, `<div class="about-stack"><span class="tag">Odin</span><span class="tag">HTMX 4</span><span class="tag">SQLite</span><span class="tag">single binary</span><span class="tag">no build step</span></div>`)
	// BRAND_REPO is a developer-set constant (see brand.odin), not user input.
	fmt.sbprintf(&b, `<a class="btn btn-primary about-cta" href="%s" target="_blank" rel="noopener">`, BRAND_REPO)
	icon(&b, "github")
	w(&b, `<span>View on GitHub</span></a>`)
	w(&b, `</article></section>`)
	return strings.to_string(b)
}
