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
