package main

// ---- skeleton's brand: its names, its nav, its copy -------------------------------------
//
// The odin-htmx skeleton, as the starter's witness profile (S18): dashboard,
// gallery, contacts and about, on SQLite, at the skeleton's exact URLs. Rename
// here, not across the features.

import "../../platform/html"
import about_web "../../features/about/web"

BRAND := html.Brand {
	// Rendered raw so it can carry inline markup (the accent dot is a <b> that
	// .brand-name b styles); developer-authored, never user input.
	wordmark       = "odin<b>·</b>htmx",
	suffix         = "Odin + HTMX",
	// The root page's <title> stands alone: search engines show it as the result
	// for the site as a whole. Near 60 characters, past which it is truncated.
	home_title     = "Odin + HTMX skeleton — server-rendered HTML, one binary",
	source_name    = "Odin + HTMX skeleton",
	repo           = "https://github.com/alexh95/odin-htmx-starter",
	// The canonical origin: canonical and og:url, the sitemap, the *.fly.dev
	// redirect. SITE_URL overrides it; no trailing slash.
	site_url       = "https://odin-htmx.alexh95.com",
	// Unfingerprinted on purpose: social platforms cache a preview against its URL.
	og_image       = "/static/og.png",
	// Bing's and IndexNow's ownership proofs: public by design, per deployment.
	bing_site_auth = "66E45151A5C32201FC3C8F86B6E094FF",
	indexnow_key   = "e826b40f813548d2bd2e94885e506dfa",
	search         = {href = "/search", placeholder = "Search contacts…", label = "Search contacts"},
	overlays       = true,
}

NAV := [?]html.Nav_Item {
	{"/", "Dashboard", "grid"},
	{"/components", "Components", "layers"},
	{"/forms", "Forms", "edit"},
	{"/data", "Data & CRUD", "table"},
	{"/about", "About", "info"},
}

ABOUT := about_web.Copy {
	subtitle    = "A starter skeleton for simple, server-rendered websites — Odin + HTMX + SQLite in one self-contained binary.",
	description = "About this project — a starter skeleton for simple, server-rendered websites: an Odin backend rendering HTML with HTMX over a SQLite store, in one self-contained binary. Links to the source on GitHub.",
	lede        = `<p class="about-lede">This is a <strong>starter skeleton</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a> over a <a href="https://sqlite.org" target="_blank" rel="noopener">SQLite</a> store, served as a single statically-linked binary.</p>`,
	body        = `<p class="muted">The contacts &amp; events console you have been clicking through is the <em>worked example</em> that proves the patterns — not the product. Clone the repository, strip the demo, and build your own thing on the same scaffolding: the layered architecture, the data layer, the theme system, and the build / CI / deploy / test harness.</p>`,
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}
