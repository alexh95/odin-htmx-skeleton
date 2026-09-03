package views

// ---- brand --------------------------------------------------------------
//
// The skeleton's identity, in one place — rename here, not across the views.
// `layout` is the only reader; nothing else should hardcode the product name.
// The remaining name touch-points live outside the views (the binary/app name in
// the run/build scripts + fly.toml + Dockerfile, and the startup banner in
// main.odin); the `init` script on the roadmap ties all of them together.
//
// BRAND_WORDMARK is rendered raw (not escaped) so it can carry inline markup —
// the accent dot here is a <b> styled by `.brand-name b` in app.css. Keep it to
// inline tags; it is developer-authored, never user input.
BRAND_WORDMARK :: "odin<b>·</b>htmx"

// Appended after every page title: "<page> · <BRAND_SUFFIX>" in both <title>
// and og:title. Plain text — escaped on output.
BRAND_SUFFIX :: "Odin + HTMX"

// The project's source repository, linked from the About page. Point this at
// your fork.
BRAND_REPO :: "https://github.com/alexh95/odin-htmx-skeleton"

// The canonical origin: <link rel="canonical">, og:url, the absolute URLs in
// /sitemap.xml, and the target of the *.fly.dev redirect in main.odin. The app
// answers on both the custom domain and its fly.dev hostname, so a crawler that
// finds it twice would split the ranking signals between them — this names the
// winner instead of leaving the choice to Google. No trailing slash: paths are
// appended verbatim. SITE_URL in the environment overrides it (main reads it),
// so a fork points at its own domain without touching the source.
SITE_URL := "https://odin-htmx.alexh95.com"
