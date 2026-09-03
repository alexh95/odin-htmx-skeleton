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

// The home page's <title> stands alone rather than taking the "<page> · <brand>"
// shape. Search engines show it as the result title for the site as a whole, and
// "Dashboard · Odin + HTMX" describes a nav item, not the project. Keep it near
// 60 characters — past that it is truncated in results.
BRAND_HOME_TITLE :: "Odin + HTMX skeleton — server-rendered HTML, one binary"

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

// The og:image card. Deliberately *not* fingerprinted: social platforms cache a
// preview against its URL, so a stable path keeps already-shared links showing
// the right card. It only changes when the card is redrawn. Lives here rather
// than in views.odin because `init --minimal` replaces that file wholesale and
// both variants serve the same card.
OG_IMAGE_HREF :: "/static/og.png"

// Bing Webmaster Tools site verification. Bing looks for this token at
// /BingSiteAuth.xml; it is public by design, not a secret. Per-deployment
// identity rather than skeleton functionality, so it lives here beside SITE_URL
// and `init` blanks it — a fork must never serve someone else's token. Empty
// disables the route (404), which is the right answer for an unverified site.
BING_SITE_AUTH :: "66E45151A5C32201FC3C8F86B6E094FF"

// IndexNow: one key push-notifies Bing, Yandex, Seznam and Naver that a URL
// changed, instead of waiting to be re-crawled. Ownership is proved by serving
// the key as plain text at /<key>.txt, so the key is public by design — the same
// per-deployment identity as BING_SITE_AUTH, blanked by `init` for the same
// reason, and an empty key means the route is never registered.
INDEXNOW_KEY :: "e826b40f813548d2bd2e94885e506dfa"
