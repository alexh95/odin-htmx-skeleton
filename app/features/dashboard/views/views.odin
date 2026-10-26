package dashboard_views

// ---- dashboard: the views ------------------------------------------------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import dashboard ".."

w :: html.w
esc :: html.esc
page_head :: html.page_head

page :: proc(st: dashboard.Stats) -> string {
	b := strings.builder_make(context.temp_allocator)
	// The heading names the project, not the nav item. This is the one page a
	// search engine shows for the site as a whole, and it reads the <h1> together
	// with <title>, og:title and the JSON-LD name — "Dashboard" answers a
	// different question than the other three do. The overview keeps its own
	// heading below, where it describes the section rather than the site.
	page_head(
		&b,
		"Odin + HTMX",
		"A server-rendered web stack in one binary",
		"An Odin backend renders every page as HTML, HTMX supplies the interaction and SQLite holds the data — no framework, no bundler, no build step.",
	)

	w(
		&b,
		`<div class="block-head"><h2>Overview</h2><p class="muted">Live figures from the demo store, counted by SQLite. Each line is a spread, not a trend: contacts per role, then engagement scores from low to high.</p></div>`,
	)
	w(&b, `<section class="stat-grid">`)
	stat_card(&b, "users", "Total contacts", st.total, fmt.tprintf("%d roles", len(st.by_role)), st.by_role, "/data")
	stat_card(&b, "check", "Active", st.active, fmt.tprintf("%d%% of all", st.active_pct), st.spread_active, "/data?status=Active")
	stat_card(&b, "bell", "Invited", st.invited, fmt.tprintf("%d%% of all", st.invited_pct), st.spread_invited, "/data?status=Invited")
	stat_card(&b, "bolt", "Avg. engagement", st.avg_score, "score / 100", st.spread, "/data?sort=score_desc")
	w(&b, `</section>`)

	// `block` only adds the section spacing `.split` has none of — the new prose
	// section below would otherwise sit flush against this one.
	w(&b, `<section class="block split">
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
	html.icon(&b, "bolt")
	w(&b, `<span>Ping server</span></button>
  </aside>
</section>`)

	// A page of widgets says nothing about itself to a reader who arrived from a
	// search result — the stats and tiles above are captions, not an explanation.
	// Deliberately not the About page's wording: two pages restating each other
	// are two thin pages, so this one covers the mechanism and About covers the
	// project.
	w(&b, `<section class="block"><div class="block-head"><h2>What you are looking at</h2><p class="muted">The stack behind these pages.</p></div>
  <article class="card about">
    <p class="about-lede">Every page here was assembled as a string by an Odin procedure and sent as HTML. No client-side framework renders it, no bundler packs it, and nothing is read from disk while it runs: htmx, the stylesheet, the icons and the social card are compiled into the binary and served from memory.</p>
    <p class="muted">HTMX covers what a plain page cannot. The table sorts, pages and edits in place, fields validate as you type, overlays open and toasts arrive — each one a small fragment of HTML swapped into the page over a single request, rendered by the same server that rendered the page. The store is SQLite, linked in as the amalgamation, so a deploy is one file you copy.</p>
    <p class="muted">The contacts console is a demonstration rather than the point of it. What a fork inherits is underneath: strictly layered packages the compiler keeps honest, the data layer, the token-driven theme system, and the build, test and deploy harness that comes with them. <a href="/about">More about the project</a>.</p>
    <div class="about-stack"><span class="tag">Odin</span><span class="tag">HTMX 4</span><span class="tag">SQLite</span><span class="tag">single binary</span><span class="tag">no build step</span></div>
  </article>
</section>`)
	return strings.to_string(b)
}

@(private = "file")
// `href` (optional) makes the card a link into the data view — the overview
// drills into the working tool, tying the console's pages together.
stat_card :: proc(b: ^strings.Builder, ic, label: string, value: int, delta: string, spark: []int, href := "") {
	if href != "" {
		w(b, `<a class="stat stat-link" href="`)
		esc(b, href)
		w(b, `">`)
	} else {
		w(b, `<article class="stat">`)
	}
	w(b, `<div class="stat-top"><span class="stat-icon">`)
	html.icon(b, ic)
	w(b, `</span><span class="stat-label">`)
	esc(b, label)
	w(b, `</span></div>`)
	fmt.sbprintf(b, `<div class="stat-value" data-count="%d">%d</div>`, value, value)
	w(b, `<div class="stat-foot"><span class="stat-delta">`)
	esc(b, delta)
	w(b, `</span>`)
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
	w(b, `<a class="tile" href="`)
	esc(b, href)
	w(b, `"><span class="tile-icon">`)
	html.icon(b, ic)
	w(b, `</span><div><strong>`)
	esc(b, title)
	w(b, `</strong><p>`)
	esc(b, desc)
	w(b, `</p></div></a>`)
}

ping :: proc(now_ms: i64, rps: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="ping-ok">`)
	html.icon(&b, "check")
	fmt.sbprintf(
		&b,
		`<div><strong>200 OK</strong><small>uptime token %d · %d req/s synthetic</small></div></div>`,
		now_ms,
		rps,
	)
	return strings.to_string(b)
}
