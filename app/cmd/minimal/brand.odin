package main

// ---- minimal's brand: its names, its nav, its copy --------------------------------------
//
// The smallest profile: home (the notes card), notes and about, a memory store,
// the lite theme, no SQLite library. Rename here, not across the features.

import "../../platform/html"
import about_web "../../features/about/web"
import home_web "../../features/home/web"

BRAND := html.Brand {
	// Rendered raw so it can carry inline markup (the accent dot is a <b> that
	// .brand-name b styles); developer-authored, never user input.
	wordmark    = "odin<b>·</b>htmx",
	suffix      = "Odin + HTMX",
	home_title  = "Odin + HTMX starter — server-rendered HTML, one binary",
	source_name = "Odin + HTMX",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
	// A placeholder origin until the profile has a domain: SITE_URL overrides it,
	// and the *.fly.dev redirect stays off for a placeholder.
	site_url    = "https://minimal.example.com",
	og_image    = "/static/og.png",
}

NAV := [?]html.Nav_Item {
	{"/", "Home", "grid"},
	{"/about", "About", "info"},
}

HOME := home_web.Copy {
	title       = "Home",
	eyebrow     = "Starter",
	heading     = "Your app",
	lede        = "A minimal Odin + HTMX page. Add a note: it is stored and appended over one request. Replace this with your own.",
	description = "A minimal Odin + HTMX starter: one page, one entity, in a single self-contained binary.",
}

ABOUT := about_web.Copy {
	subtitle    = "A minimal starter for a simple, server-rendered website: Odin + HTMX in one self-contained binary.",
	description = "About this project: a minimal starter built on an Odin backend rendering HTML with HTMX, in one self-contained binary.",
	lede        = `<p class="about-lede">Built on a <strong>starter</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a>, served as a single statically-linked binary.</p>`,
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}
