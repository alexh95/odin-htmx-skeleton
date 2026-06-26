package demo

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
	}
	w(b, `</svg>`)
}

// ---- small components ---------------------------------------------------

status_badge :: proc(b: ^strings.Builder, s: Status) {
	names := STATUS_NAMES
	cls: string
	switch s {
	case .Active:   cls = "ok"
	case .Invited:  cls = "warn"
	case .Disabled: cls = "mute"
	}
	fmt.sbprintf(b, `<span class="badge badge-%s"><i class="dot"></i>%s</span>`, cls, names[s])
}

role_chip :: proc(b: ^strings.Builder, r: Role) {
	names := ROLE_NAMES
	fmt.sbprintf(b, `<span class="chip chip-r%d">%s</span>`, int(r), names[r])
}

// Avatar from initials, hue derived from the id so each contact keeps a stable
// colour across re-renders.
avatar :: proc(b: ^strings.Builder, c: Contact) {
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
}

// The one page shell. `active` is the href of the current page so the nav can
// mark it. The inline head script sets the theme before first paint to avoid a
// flash of the wrong palette.
layout :: proc(title, active, content: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	// The head carries literal { } (htmx-config JSON, the theme script), and
	// Odin's fmt treats braces as directives — so write it raw with w() and
	// splice the only dynamic value, the title, in between. (sbprintf here would
	// emit %!(MISSING) for every brace.)
	w(&b, `<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="htmx-config" content='{"globalViewTransitions":true,"defaultSwapStyle":"innerHTML"}'>
<title>`)
	esc(&b, title)
	w(&b, ` · Odin + HTMX</title>
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="/static/app.css">
<script>try{var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t;}catch(e){}</script>
<script src="/static/htmx.min.js"></script>
<script src="/static/app.js" defer></script>
</head>
<body>
<header class="topbar">
  <a class="brand" href="/"><span class="brand-mark">`)
	icon(&b, "bolt")
	w(&b, `</span><span class="brand-name">odin<b>·</b>htmx</span></a>
  <nav class="nav" aria-label="Primary">`)
	for item in NAV {
		cur := item.href == active ? ` aria-current="page"` : ""
		fmt.sbprintf(&b, `<a class="nav-link" href="%s"%s>`, item.href, cur)
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
  <button class="icon-btn theme-toggle" type="button" aria-label="Toggle colour theme" onclick="toggleTheme()">`)
	icon(&b, "sun")
	icon(&b, "moon")
	w(&b, `</button>
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
	contacts := repo_list()
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
	stat_card(&b, "users", "Total contacts", total, "+4 this week", []int{6, 9, 7, 11, 10, 14, 13, 18})
	stat_card(&b, "check", "Active", active, "82% of base", []int{10, 11, 9, 12, 13, 12, 15, 16})
	stat_card(&b, "bell", "Invited", invited, "pending", []int{3, 4, 2, 5, 4, 6, 5, 4})
	stat_card(&b, "bolt", "Avg. engagement", avg, "score / 100", []int{40, 52, 48, 60, 58, 66, 70, 74})
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
stat_card :: proc(b: ^strings.Builder, ic, label: string, value: int, delta: string, spark: []int) {
	w(b, `<article class="stat">`)
	w(b, `<div class="stat-top"><span class="stat-icon">`)
	icon(b, ic)
	fmt.sbprintf(b, `</span><span class="stat-label">%s</span></div>`, label)
	fmt.sbprintf(b, `<div class="stat-value" data-count="%d">%d</div>`, value, value)
	w(b, `<div class="stat-foot"><span class="stat-delta">`)
	icon(b, "arrow")
	fmt.sbprintf(b, `%s</span>`, delta)
	sparkline(b, spark)
	w(b, `</div></article>`)
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
