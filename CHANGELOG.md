# Changelog

All notable changes to this project are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is pre-1.0 and dates are used in
place of releases. **Every behaviour/structure/build change gets an entry under
`[Unreleased]`** — see `CLAUDE.md`. Entries track [Conventional Commits](https://www.conventionalcommits.org):
`feat`→Added, `fix`→Fixed, `refactor`/`perf`/`style`→Changed, removals→Removed.

## [Unreleased]

### Added
- **Contact detail drilldown** (Phase D, flagship app — first increment). Clicking a row's name
  (`GET /contacts/:id`) opens a drawer with the full record (role, status, an engagement meter,
  id), a **derived activity trail** (a plausible, deterministic timeline — there's no persisted
  event log yet, see `docs/DATA.md`), and **related** contacts (others in the same role, each a
  one-click jump to its own detail). Read-only for now; re-skins under every style via tokens. The
  service layer gains `service_activity`/`service_related`; new `GET /contacts/(%d+)` route. e2e
  covers the open/content/related/close; `load-tests/scenarios/detail.js` keeps it at par
  (~42k req/s locally).
- **`/components` style showroom.** The components page opens with a catalog of all **6 styles ×
  23 schemes** — each style labelled with its scheme swatches; click any swatch to jump straight to
  that exact `style + scheme` (`setTheme` applies + persists) and the whole page re-skins live, the
  components below acting as the live preview. The active swatch is marked. No new server surface
  (client-side, like the picker), so load-tests stay at par; e2e covers the jump + persistence.
- **Arcade (video-game) style** (Phase C, 5/5 — the style library is complete). A chunky neon HUD:
  glowing panels and buttons, heavy uppercase type, vibrant gradients. Three schemes — **Arcade**
  (dark magenta/cyan), **Synthwave** (dark pink→orange sunset), and **Pop** (a clean candy-bright
  light variant). Final library: **6 styles, 23 schemes** (Modern 7, Skeuomorphic 3, Terminal 4,
  Brutalist 3, Editorial 3, Arcade 3), each with at least one light scheme, every one a pure
  `[data-style]` block over untouched component HTML.
- **Editorial / Paper style** (Phase C, 4/5). Serif throughout, warm and print-like: hairline
  rules, a single restrained accent, small-caps eyebrows, a ruled page header, title-case buttons
  (not shouty). Three schemes — **Manuscript** (light, ink on warm white, claret accent), **Sepia**
  (aged warm paper), and **Night** (a dark reading mode, cream on warm brown with gold).
- **Brutalist style** (Phase C, 3/5). Raw and loud: zero radius, thick borders, flat fills, and
  hard offset shadows that shift on press; heavy uppercase type; inverted nav block. Ships **dark
  *and* light** — **Paper** (light, cobalt/red), **Ink** (dark, white-on-black), and **Acid** (a
  loud acid-yellow with black + magenta).
- **Terminal / CRT style** (Phase C, 2/5). Monospace throughout, phosphor text with a soft glow,
  boxy thin-bordered panels, solid-fill uppercase buttons, and faint CRT scanlines (a single fixed
  gradient — cheap). Four schemes: **Green** (classic phosphor), **Amber**, **IBM** (cool
  blue/white), and **Paper** (a light teletype printout — every style now ships a light scheme).
- **Skeuomorphic style** (Phase C, first of five). A tactile treatment built entirely from layered
  gradients + bevel shadows — **no image assets**: raised panels with an inset top highlight,
  recessed (inset-shadow) form fields, glossy buttons that physically press on `:active`, a domed
  range thumb in a recessed groove. A per-style **bevel kit** (`--hi`/`--lo`/`--gloss`) drives it,
  tuned by three schemes: **Aqua** (light, lickable blue), **Graphite** (dark brushed metal), and
  **Brass** (warm wood + brass). Adding it took only a `[data-style="skeuo"]` block + scheme
  palettes + the picker entries — the component HTML is untouched. e2e now also covers switching the
  *style* axis and revealing that style's schemes. Remaining: Terminal, Brutalist, Editorial, Video-game.
- **Theme picker — two axes, `data-style` × `data-scheme`** (Phase B of the style library). The
  page shell carries `data-style` (the treatment) and `data-scheme` (the palette) on `<html>`,
  rendered server-side as `modern`/`midnight` (works with no JS) and restored from `localStorage`
  by the pre-paint script (no flash). A stateless topbar picker (a `<details>` popover) applies and
  persists the choice via tiny vanilla JS — no server endpoint, so load-tests stay at par. The CSS
  splits the old single dark/light theme into the `[data-style][data-scheme]` token contract;
  **Modern** ships **seven schemes** — Midnight, Daylight, Nebula, Aurora, plus warm **Ember**
  (dusk) and **Sandstone** (warm light) and cool **Ocean**. A new `--on-accent` token keeps text
  readable on light-accent gradients (so buttons aren't white-on-bright). e2e covers switch +
  persist. Phase C layers in the additional styles (Skeuomorphic, Terminal, Brutalist, Editorial,
  Video-game).
- **Vision + direction docs.** [`PHILOSOPHY.md`](PHILOSOPHY.md) (server-rendered HTML, browser as
  runtime, JS only where the browser can't, the Odin↔HTMX shared worldview, the honest 90/10),
  [`docs/USE_CASES.md`](docs/USE_CASES.md) (the sweet spot + the decision to evolve the sampler into
  one flagship internal admin console), and [`docs/DATA.md`](docs/DATA.md) (the repository seam, and
  SQLite→Postgres as the path past the in-memory POC). Wired into `CLAUDE.md`; phased plan in `TODO.md`.
- Initialized the repository as git and made the first commit.
- Adopted Conventional Commits; documented the spec and changelog mapping in `CLAUDE.md`.
- Infrastructure plan ([`infra/PLAN.md`](infra/PLAN.md)): remote hosting, CI/CD, deployment,
  and where to run e2e / load-tests — free / low-cost.
- Deployment: `Dockerfile` (two-stage, pinned Odin `dev-2026-06`, single-binary + static
  runtime), `fly.toml` (Fly.io, always-on `shared-cpu-1x`), and `.dockerignore`.
- CI/CD: `.github/workflows/ci.yml` — build with `-warnings-as-errors`, smoke-test the binary
  (pages, static, JSON API, CRUD), and deploy to Fly.io on green `master`.
- `app/main.odin` reads `PORT` from the environment and binds `0.0.0.0` when `BIND_ALL` is
  set, so the binary is container-deployable (local default stays loopback).
- `GET /healthz` liveness probe (200 `ok`); wired as the Fly.io health check in `fly.toml`.
- End-to-end test suite ([`e2e/`](e2e/)): Playwright over a freshly built binary — navigation,
  search, components, forms, CRUD and assets, including the three regression bugs. Runs across
  all three engines (Chromium, Firefox, WebKit). Wired into CI as a gating job; deploy now needs
  both `build` and `e2e`.
- `compose.yaml` for an optional local prod-parity run (`docker compose up --build`) — builds
  the same image Fly deploys. Not required for dev; handy for load-tests against a prod-like
  container.
- Favicon (`app/static/favicon.svg`, linked from the page head): a fusion mark — htmx's `</>`
  brackets on the project's violet→cyan gradient tile with the app's bolt accent.
- SEO: a **page-specific `<meta name="description">`** (the item Lighthouse flagged) plus Open
  Graph `og:type`/`og:title`/`og:description` on every page, threaded through `render_page`.
- Two-host deploy ([`deploy/apollo-11/`](deploy/apollo-11/)): a sudo-free `deploy.sh` (+ compose,
  README) that builds the self-contained image **on** a home Docker box from source tarred over
  SSH, joins it to the existing nginx-proxy-manager `npm` network for a subdomain, and publishes a
  host port for proxy-free load testing. IP/hostname/domain are parameterized. Required
  `seccomp=unconfined` so odin-http's io_uring isn't blocked by Docker's default profile (Fly
  dodged this via Firecracker). Yielded the two-host numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md): byte-heavy endpoints saturate the 1 GbE wire
  (~912 Mbit vs 2.4 GB/s loopback), and NPM+TLS on the shared box costs ~12×.
- Load tests ([`load-tests/`](load-tests/)): **k6** scenarios for every endpoint class —
  `static`, `pages`, `search`, `api`, `write` (create→delete), and a `mixed` 90/10 read/write
  blend — sharing one warmup→measured-window shape with per-phase thresholds and a
  dependency-free JSON/CSV summary. A `run.sh`/`run.bat` driver builds the app `-o:speed`,
  launches a fresh server per scenario × VU level (clean store), sweeps the VU curve, and
  stitches `results/summary.md`. `bombardier` baselines run if present. Numbers and the
  single-thread-ceiling reading land in [`load-tests/RESULTS.md`](load-tests/RESULTS.md).

### Changed
- Refactored the backend into one Odin **package per layer** under `app/src/`
  (`models`, `repository`, `services`, `views`, `controllers`, and `src/` = entry `main`+routes),
  so the layering is compiler-enforced rather than convention. Cross-layer calls are now
  qualified (`repository.repo_list`, `views.view_dashboard`, …). Build entry is `odin build src`;
  `htmx.min.js` is `#load`ed from `controllers`. Behaviour unchanged (93/93 e2e green).
- Vendored odin-http as a pinned git submodule (`app/odin-http`, commit `112c49b`) for
  reproducible CI/CD builds; `prepare.*` stays the local-dev convenience path.
- e2e now runs **fully in parallel**: each Playwright worker spawns its own server on its own
  port with an isolated in-memory store (`global-setup.ts` builds once, `fixtures.ts` spawns
  per worker), replacing the single shared server + `workers: 1`. ~2.5× faster locally. On CI
  the engines are **sharded across concurrent runners** (a browser matrix) instead of piling
  workers onto one CPU-bound runner, and each shard runs in **Playwright's official Docker
  image** (which also ships node/npm) so the browsers + OS deps are preinstalled (no per-run
  install — that was the biggest, most variable cost). `workers` tracks the runner's cores.

### Performance
- **Cache-busting for CSS/JS.** Asset URLs in the page `<head>` now carry a `?v=<content-hash>`
  (computed once at startup, exposed as `views.ASSET_VERSION`). Since the HTML is dynamic and never
  cached, a changed stylesheet yields a new URL clients fetch immediately — no more serving the old
  `app.css` until `max-age` expires (the cause of needing a hard refresh after deploys). Verified on
  both deployments.
- **Moved the Fly deployment from `iad` (US-East) to `fra` (Frankfurt)** so it serves the
  primary (European) audience from nearby. Latency is RTT-bound, not compute-bound (the server
  answers `/healthz` in sub-ms), so over IPv4 a full page load dropped from ~850 ms to **~160 ms**.
  Fly's *IPv6* anycast additionally mis-routed some EU ISPs to a far edge (~785 ms over v6);
  fronting the origin with a **proxied Cloudflare record** (Full-strict, cert validated via DNS-01)
  fixed it — page TTFB is now **~105 ms on both v4 and v6** from a nearby Cloudflare edge, with
  `/static` edge-cached.
- **Multithreaded server.** The event loop now runs one nbio thread **per core** (was pinned to
  one); `THREADS` env overrides. The in-memory store, previously lock-free *because* it was
  single-threaded, is now guarded by an `sync.RW_Mutex` — reads share, writes are exclusive — and
  the repository hands callers **temp-arena snapshots** (structs copied, strings cloned under the
  lock) so nothing aliases store memory across a concurrent delete/realloc. Load-tests sweep
  `THREADS=1` vs `N` against the same binary for the before/after; numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md).
- Static assets now send `Cache-Control: public, max-age=3600` and a strong **ETag** (a content
  hash computed once at startup), with conditional `304 Not Modified` handling — repeat page
  loads reuse cached htmx/CSS/JS instead of re-downloading, and a redeploy changes the hash so
  clients never serve stale assets.
- All static assets (`app.css`, `app.js`, `favicon.svg`, htmx) are now **embedded into the
  binary** and served from memory, replacing the disk-served `respond_dir` path. The deployed
  artifact is a single self-contained file (the Dockerfile no longer ships `static/`), there
  are no per-request disk reads, and path traversal is structurally impossible.
- First page load: `defer` the embedded htmx script so it no longer blocks rendering (the
  pre-paint theme script stays synchronous to avoid a flash). htmx still initialises before
  `DOMContentLoaded`; the full e2e suite passes unchanged across all three engines.

### Fixed
- Range slider fill was missing under Terminal, Brutalist, Editorial and Arcade — each style's
  `input` rule tied the range track on specificity and (being later) clobbered the fill layer (the
  same issue the skeuo style hit). Each now restores the fill on its
  `[data-style] input[type="range"]` rule, matched to the style (phosphor glow, flat accent, a
  refined gradient, neon). Completes the style library.
- Range slider fill lagged behind the thumb: the shared `input` rule transitioned `background`,
  which animated the `background-size` that paints the fill. The range track now opts out
  (`transition: none`), so the fill tracks the thumb instantly while the thumb keeps its own
  transform transition.
- Low-contrast schemes: the green scheme (Aurora) was washed out and white button text was hard to
  read on bright accents. Aurora is rebuilt around a vivid emerald with lifted muted text, and the
  new `--on-accent` token flips button/badge text dark on light-accent schemes.
- Linux/CI build: `prepare.*` now creates `bin/` (odin's `-out:` won't), the shell scripts
  carry the exec bit, and the Dockerfile/CI invoke `prepare` via `sh` — so the build no
  longer depends on a pre-existing `bin/` or the exec bit surviving a Windows-origin context.
- Page `<head>` was emitting `%!(MISSING)`: Odin's `fmt` treats `{`/`}` as directives, so the
  `htmx-config` JSON and the theme pre-paint script were mangled (htmx ran on defaults and
  threw on `JSON.parse`). The cycle button's `hx-vals` JSON had the same break. Brace-bearing
  literals now bypass `fmt` (written with `w()`). Caught by the new e2e suite.
- Out-of-band toasts (form submit, contact create) now keep their `.toast` wrapper — htmx's
  positional OOB swap appends an element's children, so the toast is wrapped in a carrier.

## [0.2.0] — 2026-06-26

### Added
- Project docs for efficient single-prompt sessions: `CLAUDE.md` (architecture, code/CSS/JS
  aesthetics, odin-http API cheat sheet, allocator model, Odin/HTMX gotchas, recipes), this
  `CHANGELOG.md`, and `TODO.md`.
- Test plans: `e2e/PLAN.md` (Playwright browser tests) and `load-tests/PLAN.md` (k6/bombardier
  throughput tests). Plans only — not yet implemented.
- Top-level `README.md` describing the `app/` + `e2e/` + `load-tests/` layout.

### Changed
- Restructured the repo: the entire application moved into `app/`, with `e2e/` and
  `load-tests/` as siblings. Run/prepare scripts are location-independent (`%~dp0` /
  `dirname`), so they work unchanged from `app/`.

### Fixed
- Invite dialog no longer closes on an outside (backdrop) click, so a half-typed field can't
  be lost by accident. Dismissal is explicit (× / Cancel).
- `/forms` no longer clears the name and email fields when the email validates. The email
  field's `htmx:afterRequest` was bubbling to the form and triggering `reset()`; the handler
  is now guarded with `event.target === this`.
- Range sliders now paint their fill to match the thumb as it moves (was a static 60%). The
  fill is driven by a `--fill` custom property updated from `app.js`.

## [0.1.0] — 2026-06-26

### Added
- Initial Odin + HTMX showcase.
  - Pure-Odin backend on `odin-http` (server, router, request/response over `core:nbio`);
    HTMX embedded into the binary via `#load` and served from memory; CSS/JS from disk.
  - Layered backend: models → repository → services → controllers → views.
  - Pages: Dashboard, Components gallery, Forms (with live inline validation), Data & CRUD.
  - Global debounced HTMX active-search plus a plain JSON API (`/api/search`).
  - In-memory CRUD over POST/DELETE; single-threaded lock-free store.
  - Hand-written, token-driven CSS with a dark/light theme toggle and snappy animations.
  - Cross-platform `prepare`/`run` scripts (Windows / Linux / macOS).
