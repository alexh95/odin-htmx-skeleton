package views
import "../repository"
import "../models"

import "core:fmt"
import "core:net"
import "core:strings"

// ---- views --------------------------------------------------------------
//
// HTML is assembled by writing into a strings.Builder. There is no template
// engine: a "component" is a proc that appends markup. Raw string literals
// (backticks) let attribute quotes stand as-is, so the markup reads like the
// HTML it produces. Everything builds in the request arena (temp allocator)
// and is freed once the response is flushed.
//
// Two rules keep this honest:
//   - every dynamic string passes through esc() (or url_encode for hrefs),
//   - structural chrome (nav, badges, avatars, icons) lives in one proc each.

w :: proc(b: ^strings.Builder, s: string) {
	strings.write_string(b, s)
}

// HTML-escape text content. The only defence against an injected '<' from a
// search box or a contact name, so it is not optional anywhere user input is
// echoed.
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

url_encode :: proc(s: string) -> string {
	return net.percent_encode(s, context.temp_allocator)
}

// Escape text while wrapping each case-insensitive occurrence of q in <mark>.
// Used by the search dropdown so the matched span lights up.
write_highlighted :: proc(b: ^strings.Builder, text, q: string) {
	if q == "" {
		esc(b, text)
		return
	}
	lt := strings.to_lower(text, context.temp_allocator)
	lq := strings.to_lower(q, context.temp_allocator)
	start := 0
	for start < len(text) {
		idx := strings.index(lt[start:], lq)
		if idx < 0 {
			esc(b, text[start:])
			return
		}
		at := start + idx
		esc(b, text[start:at])
		w(b, "<mark>")
		esc(b, text[at:at + len(q)])
		w(b, "</mark>")
		start = at + len(q)
	}
}

// ---- icons --------------------------------------------------------------
//
// A closed set of inline SVGs, 24x24, stroked with currentColor so they take
// the colour of whatever they sit in. One proc, one switch — adding an icon is
// a single case.

icon :: proc(b: ^strings.Builder, name: string) {
	w(b, `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">`)
	switch name {
	case "grid":    w(b, `<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>`)
	case "layers":  w(b, `<path d="M12 3 2 8l10 5 10-5-10-5Z"/><path d="m2 16 10 5 10-5"/><path d="m2 12 10 5 10-5"/>`)
	case "edit":    w(b, `<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>`)
	case "table":   w(b, `<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18"/>`)
	case "search":  w(b, `<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>`)
	case "sun":     w(b, `<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>`)
	case "moon":    w(b, `<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/>`)
	case "plus":    w(b, `<path d="M12 5v14M5 12h14"/>`)
	case "trash":   w(b, `<path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m2 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/>`)
	case "cycle":   w(b, `<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>`)
	case "bolt":    w(b, `<path d="M13 2 3 14h7l-1 8 10-12h-7l1-8Z"/>`)
	case "bell":    w(b, `<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>`)
	case "check":   w(b, `<path d="M20 6 9 17l-5-5"/>`)
	case "arrow":   w(b, `<path d="M12 19V5M5 12l7-7 7 7"/>`)
	case "users":   w(b, `<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9"/>`)
	case "palette": w(b, `<path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.9 0 1.6-.7 1.6-1.6 0-.4-.2-.8-.4-1.1-.3-.3-.4-.6-.4-1.1a1.6 1.6 0 0 1 1.6-1.6h2c3 0 5.6-2.5 5.6-5.5C22 6 17.5 2 12 2Z"/><circle cx="6.5" cy="11.5" r="1" fill="currentColor" stroke="none"/><circle cx="9.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="14.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="17.5" cy="11.5" r="1" fill="currentColor" stroke="none"/>`)
	case "info":    w(b, `<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>`)
	// The GitHub mark is a solid glyph; fill it with currentColor and drop the
	// stroke just for this path (overriding the SVG's stroked-line default).
	case "github":  w(b, `<path fill="currentColor" stroke="none" d="M12 2A10 10 0 0 0 8.84 21.5c.5.08.66-.22.66-.48l-.01-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.26-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.38.2 2.39.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85l-.01 2.74c0 .27.16.57.67.48A10 10 0 0 0 12 2Z"/>`)
	}
	w(b, `</svg>`)
}

// ---- theme picker -------------------------------------------------------
//
// Two orthogonal axes carried as data-attributes on <html>: `data-style` (the
// treatment — Modern, …) and `data-scheme` (the palette within a style). Pure
// presentation: the picker is static HTML, app.js applies + persists the choice
// (localStorage), and the head pre-paint script restores it before first paint.
// No server endpoint, so it adds no surface to load-test. Phase C appends styles
// and schemes to these tables and one CSS line per style to reveal its swatches.

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

// Fingerprinted asset URLs ("/static/app.<hash>.css"), set once at startup by
// controllers.init_etags from the embedded bytes. Content-addressed: a changed
// asset gets a new URL (so a redeploy is picked up immediately, no waiting out
// max-age) and the URL can be cached immutably — and it's cleaner than a ?v=
// query. Bare defaults until init runs.
HTMX_HREF := "/static/htmx.min.js"
CSS_HREF := "/static/app.css"
JS_HREF := "/static/app.js"

theme_picker :: proc(b: ^strings.Builder) {
	w(
		b,
		`<details class="picker"><summary class="icon-btn" aria-label="Theme and style" title="Theme & style">`,
	)
	icon(b, "palette")
	w(b, `</summary><div class="picker-panel"><p class="picker-head">Style</p><div class="picker-styles">`)
	for s in STYLES {
		fmt.sbprintf(
			b,
			`<button class="chip" type="button" data-pick-style="%s" aria-pressed="false" onclick="pickStyle('%s')">%s</button>`,
			s.id,
			s.id,
			s.label,
		)
	}
	w(b, `</div><p class="picker-head">Scheme</p>`)
	for s in STYLES {
		fmt.sbprintf(b, `<div class="picker-schemes" data-for="%s">`, s.id)
		for sc in SCHEMES {
			if sc.style != s.id {continue}
			fmt.sbprintf(
				b,
				`<button class="swatch" type="button" data-pick-scheme="%s" aria-pressed="false" title="%s" style="--sw:%s" onclick="pickScheme('%s')"></button>`,
				sc.id,
				sc.label,
				sc.swatch,
				sc.id,
			)
		}
		w(b, `</div>`)
	}
	w(b, `</div></details>`)
}

// The /components showroom: every style and scheme laid out at once, each swatch
// a one-click jump to that exact style + scheme. The components below it re-skin
// live (same data-style/data-scheme on <html>; setTheme applies + persists).
view_showroom :: proc(b: ^strings.Builder) {
	fmt.sbprintf(
		b,
		`<section class="block"><div class="block-head"><h2>Style showroom</h2><p class="muted">Flip the whole interface — every component below re-skins live. %d styles, %d schemes; click any swatch.</p></div><div class="showroom-grid">`,
		len(STYLES),
		len(SCHEMES),
	)
	for s in STYLES {
		fmt.sbprintf(b, `<div class="showroom-row"><span class="showroom-name">%s</span><div class="showroom-swatches">`, s.label)
		for sc in SCHEMES {
			if sc.style != s.id {continue}
			fmt.sbprintf(
				b,
				`<button class="swatch" type="button" style="--sw:%s" title="%s · %s" aria-label="%s %s" data-sw-style="%s" data-sw-scheme="%s" onclick="setTheme('%s','%s')"></button>`,
				sc.swatch,
				s.label,
				sc.label,
				s.label,
				sc.label,
				s.id,
				sc.id,
				s.id,
				sc.id,
			)
		}
		w(b, `</div></div>`)
	}
	w(b, `</div></section>`)
}

// ---- small components ---------------------------------------------------

status_badge :: proc(b: ^strings.Builder, s: models.Status) {
	names := models.STATUS_NAMES
	cls: string
	switch s {
	case .Active:   cls = "ok"
	case .Invited:  cls = "warn"
	case .Disabled: cls = "mute"
	}
	fmt.sbprintf(b, `<span class="badge badge-%s"><i class="dot"></i>%s</span>`, cls, names[s])
}

role_chip :: proc(b: ^strings.Builder, r: models.Role) {
	names := models.ROLE_NAMES
	fmt.sbprintf(b, `<span class="chip chip-r%d">%s</span>`, int(r), names[r])
}

// Avatar from initials, hue derived from the id so each contact keeps a stable
// colour across re-renders.
avatar :: proc(b: ^strings.Builder, c: models.Contact) {
	hue := (c.id * 47) % 360
	init: [2]u8
	n := 0
	for i in 0 ..< len(c.name) {
		ch := c.name[i]
		if (i == 0 || c.name[i - 1] == ' ') && ch != ' ' && n < 2 {
			init[n] = ch
			n += 1
		}
	}
	fmt.sbprintf(b, `<span class="avatar" style="--h:%d">%s</span>`, hue, string(init[:n]))
}

// ---- layout -------------------------------------------------------------

NAV := [?]struct {
	href, label, icon: string,
} {
	{"/", "Dashboard", "grid"},
	{"/components", "Components", "layers"},
	{"/forms", "Forms", "edit"},
	{"/data", "Data & CRUD", "table"},
	{"/about", "About", "info"},
}

// The one page shell. `active` is the href of the current page so the nav can
// mark it. The inline head script sets the theme before first paint to avoid a
// flash of the wrong palette.
layout :: proc(title, active, description, content: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	// The head carries literal { } (htmx-config JSON, the theme script), and
	// Odin's fmt treats braces as directives — so write it raw with w() and
	// splice the only dynamic value, the title, in between. (sbprintf here would
	// emit %!(MISSING) for every brace.)
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
<meta property="og:type" content="website">
<meta property="og:title" content="`)
	esc(&b, title)
	w(&b, " · ")
	esc(&b, BRAND_SUFFIX)
	w(&b, `">
<meta property="og:description" content="`)
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
<header class="topbar">`)
	// hx-boost turns the brand + primary-nav links into AJAX swaps: htmx fetches the
	// page, swaps the <body>, and pushes history instead of a full document load —
	// SPA-like navigation with no asset re-parse, no theme re-flash, and (with
	// transitions on) a crossfade. The server still renders whole pages; only the
	// client work changes. Scoped to these links so the JSON-API tile and the
	// no-action search/filter forms keep their normal behaviour. app.js keeps its
	// per-node state swap-safe (see watchToasts / the htmx:after:process re-init).
	w(&b, `
  <a class="brand" href="/" hx-boost="true"><span class="brand-mark">`)
	icon(&b, "bolt")
	w(&b, `</span><span class="brand-name">`)
	w(&b, BRAND_WORDMARK)
	w(&b, `</span></a>
  <nav class="nav" aria-label="Primary">`)
	for item in NAV {
		cur := item.href == active ? ` aria-current="page"` : ""
		// hx-boost sits on each link, not the <nav>: htmx 4 doesn't inherit it to
		// descendants the way htmx 2 did.
		fmt.sbprintf(&b, `<a class="nav-link" href="%s"%s hx-boost="true">`, item.href, cur)
		icon(&b, item.icon)
		fmt.sbprintf(&b, `<span>%s</span></a>`, item.label)
	}
	w(&b, `</nav>
  <form class="search" role="search" onsubmit="return false">`)
	icon(&b, "search")
	w(&b, `<input type="search" name="q" placeholder="Search contacts…" autocomplete="off" aria-label="Search contacts"
       hx-get="/search" hx-trigger="keyup changed delay:250ms, search, focus" hx-target="#search-results" hx-swap="innerHTML">
    <div id="search-results" class="search-results" tabindex="-1"></div>
  </form>
  `)
	theme_picker(&b)
	w(&b, `
</header>
<main class="container">`)
	w(&b, content)
	w(&b, `</main>
<div id="overlay"></div>
<div id="toasts" class="toasts" aria-live="polite" aria-atomic="false"></div>
</body>
</html>`)
	return strings.to_string(b)
}

// Section header used at the top of every page body.
page_head :: proc(b: ^strings.Builder, eyebrow, title, subtitle: string) {
	fmt.sbprintf(
		b,
		`<header class="page-head"><p class="eyebrow">%s</p><h1>%s</h1><p class="lede">%s</p></header>`,
		eyebrow,
		title,
		subtitle,
	)
}

// ---- dashboard ----------------------------------------------------------

view_dashboard :: proc() -> string {
	contacts := repository.repo_list()
	total := len(contacts)
	active, invited, score_sum := 0, 0, 0
	for c in contacts {
		if c.status == .Active {active += 1}
		if c.status == .Invited {invited += 1}
		score_sum += c.score
	}
	avg := total > 0 ? score_sum / total : 0

	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Overview",
		"Dashboard",
		"A proof-of-concept component kit served from an Odin backend, wired up with HTMX.",
	)

	w(&b, `<section class="stat-grid">`)
	stat_card(&b, "users", "Total contacts", total, "+4 this week", []int{6, 9, 7, 11, 10, 14, 13, 18}, "/data")
	stat_card(&b, "check", "Active", active, "82% of base", []int{10, 11, 9, 12, 13, 12, 15, 16}, "/data?status=Active")
	stat_card(&b, "bell", "Invited", invited, "pending", []int{3, 4, 2, 5, 4, 6, 5, 4}, "/data?status=Invited")
	stat_card(&b, "bolt", "Avg. engagement", avg, "score / 100", []int{40, 52, 48, 60, 58, 66, 70, 74}, "/data?sort=score_desc")
	w(&b, `</section>`)

	w(&b, `<section class="split">
  <article class="card">
    <div class="card-head"><h2>Explore the kit</h2><span class="muted">four pages</span></div>
    <div class="link-grid">`)
	link_tile(&b, "/components", "layers", "Components", "Buttons, badges, tabs, accordions, overlays and toasts.")
	link_tile(&b, "/forms", "edit", "Forms", "Inputs, selects, switches and live inline validation.")
	link_tile(&b, "/data", "table", "Data & CRUD", "A sortable, paginated table with create / update / delete.")
	link_tile(&b, "/api/search?q=grace", "search", "JSON API", "The same data, served as plain JSON — no HTMX involved.")
	w(&b, `</div>
  </article>
  <aside class="card">
    <div class="card-head"><h2>Server</h2><span class="badge badge-ok"><i class="dot"></i>live</span></div>
    <p class="muted">Ask the Odin process for a fresh reading. The button swaps in a fragment and raises a toast — all over one request.</p>
    <div id="ping-slot" class="ping-slot"><span class="muted">No reading yet.</span></div>
    <button class="btn btn-primary" hx-get="/ui/ping" hx-target="#ping-slot" hx-swap="innerHTML">`)
	icon(&b, "bolt")
	w(&b, `<span>Ping server</span></button>
  </aside>
</section>`)
	return strings.to_string(b)
}

@(private = "file")
// `href` (optional) makes the card a link into the data view — the overview
// drills into the working tool, tying the console's pages together.
stat_card :: proc(b: ^strings.Builder, ic, label: string, value: int, delta: string, spark: []int, href := "") {
	if href != "" {
		fmt.sbprintf(b, `<a class="stat stat-link" href="%s">`, href)
	} else {
		w(b, `<article class="stat">`)
	}
	w(b, `<div class="stat-top"><span class="stat-icon">`)
	icon(b, ic)
	fmt.sbprintf(b, `</span><span class="stat-label">%s</span></div>`, label)
	fmt.sbprintf(b, `<div class="stat-value" data-count="%d">%d</div>`, value, value)
	w(b, `<div class="stat-foot"><span class="stat-delta">`)
	icon(b, "arrow")
	fmt.sbprintf(b, `%s</span>`, delta)
	sparkline(b, spark)
	w(b, href != "" ? `</div></a>` : `</div></article>`)
}

// Inline sparkline. Points are scaled into a fixed 100x32 viewBox; the area
// under the line is filled with a fading gradient defined in the CSS.
@(private = "file")
sparkline :: proc(b: ^strings.Builder, pts: []int) {
	if len(pts) < 2 {
		return
	}
	lo, hi := pts[0], pts[0]
	for p in pts {
		lo = min(lo, p)
		hi = max(hi, p)
	}
	span := max(1, hi - lo)
	w(b, `<svg class="spark" viewBox="0 0 100 32" preserveAspectRatio="none" aria-hidden="true"><polyline points="`)
	for p, i in pts {
		x := f32(i) / f32(len(pts) - 1) * 100
		y := 30 - f32(p - lo) / f32(span) * 26
		fmt.sbprintf(b, "%.1f,%.1f ", x, y)
	}
	w(b, `"/></svg>`)
}

@(private = "file")
link_tile :: proc(b: ^strings.Builder, href, ic, title, desc: string) {
	fmt.sbprintf(b, `<a class="tile" href="%s"><span class="tile-icon">`, href)
	icon(b, ic)
	fmt.sbprintf(b, `</span><div><strong>%s</strong><p>%s</p></div></a>`, title, desc)
}
