package main

// ---- full's brand: Houston's names, its nav, its copy ------------------------------------
//
// Houston, the home server's own site (PLAN §7.1, §7.3): at M4 slice 3 its main host alone,
// with accounts, on SQLite and the hyperscript client. Its lab host and the rest of the
// catalog arrive with slice 10. Rename here, not across the features.

import "../../platform/html"
import about_web "../../features/about/web"
import home_web "../../features/home/web"

BRAND := html.Brand {
	// Rendered raw so it can carry inline markup (the accent dot is a <b> that
	// .brand-name b styles); developer-authored, never user input.
	wordmark    = "houston<b>·</b>",
	suffix      = "Houston",
	home_title  = "Houston: the home server's own site",
	source_name = "odin-htmx-starter",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
	// A placeholder origin until the profile is deployed: SITE_URL overrides it, and the
	// *.fly.dev redirect stays off for a placeholder.
	site_url    = "https://houston.example.com",
	og_image    = "/static/og.png",
	overlays    = true, // #toasts: a 429's toast lands there
}

NAV := [?]html.Nav_Item {
	{"/", "Home", "grid"},
	{"/login", "Account", "users"},
	{"/about", "About", "info"},
}

HOME := home_web.Copy {
	title       = "Home",
	eyebrow     = "Houston",
	heading     = "Mission control for the house",
	lede        = "Members sign in with the account an admin gave them. The rest of Houston arrives feature by feature.",
	description = "Houston: the home server's own site, built on an Odin + HTMX starter.",
}

ABOUT := about_web.Copy {
	subtitle    = "The home server's own site, on an Odin + HTMX starter.",
	description = "About Houston: an Odin backend rendering HTML with HTMX, accounts on SQLite, in one self-contained binary.",
	lede        = `<p class="about-lede">Built on <strong>odin-htmx-starter</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a>, served as a single statically-linked binary.</p>`,
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}
