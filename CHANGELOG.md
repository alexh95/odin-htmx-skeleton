# Changelog

All notable changes to this project are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is pre-1.0 and dates are used in
place of releases. **Every behaviour/structure/build change gets an entry under
`[Unreleased]`** — see `CLAUDE.md`. Entries track [Conventional Commits](https://www.conventionalcommits.org):
`feat`→Added, `fix`→Fixed, `refactor`/`perf`/`style`→Changed, removals→Removed.

## [Unreleased]

### Added
- **Events — a second table, related to contacts.** `events(actor_id, target_id → contacts,
  ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`) records interactions *between*
  two contacts. The detail drawer's activity feed is now **real data**: `event_timeline` JOINs the
  events back to contacts to resolve the other party, rendered as a one-click jump (replacing the
  deterministic-fake `service_activity`). Deleting a contact cascades its interactions. New domain
  types (`models.Event`/`Event_Kind`/`Interaction`), seeded deterministically. End-to-end at par:
  model + repository + service + view + e2e + load. New e2e: the FK cascade (delete a contact → its
  interactions vanish); the detail `load` scenario now exercises the JOIN. **42 e2e total.**

### Changed
- **Docs accuracy pass.** Brought the prose docs up to date with the SQLite store + events: the
  top `README.md` no longer calls the e2e/load suites "plans only" (both are implemented and gate
  CI); `CLAUDE.md`, `PHILOSOPHY.md`, `app/README.md`, the e2e/load READMEs+PLANs, and the
  apollo-11/infra docs now reflect three dependencies (HTMX + odin-http + SQLite), the C-toolchain
  requirement, `DB_PATH`, the exclusive-lock concurrency model, the `data-style`×`data-scheme` theme
  system, the repository split, and the events JOIN.
- **Repository split into common + per-entity files.** `repo_sqlite.odin` → `repo.odin` (the shared
  connection/lock, migration runner, and `exec`/`prep`/`bind_text`/`clone_col`/`scalar_int` helpers)
  + `contacts.odin` (the seven `repo_*`) + `events.odin` (`event_timeline`). Adding a table is now a
  new file + a migration, no churn to the plumbing. Added `repo_close` (finalises statements,
  checkpoints the WAL) wired via `defer` in main.
- **Load tests re-measured for SQLite** ([`load-tests/RESULTS.md`](load-tests/RESULTS.md)). Reads
  still scale with threads but ~3–4× (vs the in-memory store's ~5×) — the v1 single shared connection
  forces an *exclusive* lock on reads too; the new `detail` events-JOIN scales worst (1.9×), the
  measured trigger for per-thread WAL connections. A file DB costs ~2.7× on writes (WAL + fsync) and
  nothing on reads. 0% errors throughout.
- **Persistent SQLite data layer** — replaces the in-memory POC store. The seven `repo_*`
  procedures are reimplemented over SQLite (`src/repository/repo_sqlite.odin`) behind a ~15-decl
  amalgamation binding (`src/sqlite/`); **services, views, controllers, e2e and load suites are
  unchanged** (the whole point of the repository seam). Backend selected by **`DB_PATH`**:
  `:memory:` (default — a real in-RAM SQLite, seeded fresh per boot, gone on exit; what the e2e/load
  suites get, identical isolation to before) or a file path that **persists**. WAL +
  `busy_timeout`/`foreign_keys`/`synchronous=NORMAL`; plain-SQL migrations (`migrations/0001_init.sql`,
  `#load`ed) behind a `schema_version` table; `repo_seed` seeds only an empty store; statements
  prepared once. Concurrency v1: one shared connection under the existing `sync.RW_Mutex` taken
  **exclusively** for every op (a single connection's prepared statements can't be shared across
  concurrent readers — parallel reads return with per-thread WAL connections, deferred to load-test
  evidence). One new e2e test: **data survives a process restart** (41 e2e total). See
  [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md).
- **`prepare.*` fetches + compiles the SQLite amalgamation** (the htmx precedent, not a submodule):
  a pinned, **SHA-256-verified** `sqlite-amalgamation-3530300.zip` (SQLite 3.53.3) → unzipped into a
  gitignored `app/vendor/sqlite/` → compiled to a static lib (`sqlite3.lib` via `cl /MT` on Windows,
  `sqlite3.a` via `clang`+`ar` on unix), idempotently. A **C toolchain is now a hard requirement**;
  `prepare` checks for it and prints a per-OS install hint. The Dockerfile and CI gain
  `clang binutils unzip`. apollo-11 mounts a named volume at `/data` (`DB_PATH=/data/data.db`) for a
  durable live demo; Fly stays `:memory:` until a volume is provisioned (documented in `fly.toml`).
- **Data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md), docs only) — a
  concrete "how" for replacing the in-memory POC with **SQLite** in Odin: the binding choice
  (vendor vs amalgamation), schema + boot-time migrations, the seven `repo_*` as prepared SQL, the
  allocator discipline (clone column text into the temp arena — the same guarantee `snapshot()`
  gives today), how WAL maps onto the server's reader/writer model, build/deploy/ops, and the
  rollout. Complements `DATA.md` (the why/when).
- **`list` load scenario** (`GET /contacts?status=&sort=`) — the filtered/sorted table-region
  fragment, closing the last load-parity gap from Phase D; wired into the run driver (~38k req/s).
- **Overview → tool wiring** (Phase D increment 4, product cohesion). The dashboard stat cards are
  now links into the data view: *Active*/*Invited* → the table filtered to that status, *Avg.
  engagement* → sorted by score, *Total* → the full table. `page_data` now honours a `sort` query.
  Ties the four pages into one console (the overview drives the working tool) rather than four
  separate demos. e2e covers the drill-through.
- **Status quick-filters on the data table** (Phase D increment 3). A row of filter chips (All /
  Active / Invited / Disabled) above the table; the active one is marked, and the filter threads
  through the request like search/sort/page (`service_page` gains a `status` arg; every region link
  carries `&status=`), so filtering composes with text search and survives sort/paginate. e2e covers
  it; no new endpoint (a query param on the existing `/contacts` region).
- **Contact detail drilldown** (Phase D, flagship app — first increment). Clicking a row's name
  (`GET /contacts/:id`) opens a drawer with the full record (role, status, an engagement meter,
  id), a **derived activity trail** (a plausible, deterministic timeline — there's no persisted
  event log yet, see `docs/DATA.md`), and **related** contacts (others in the same role, each a
  one-click jump to its own detail). Re-skins under every style via tokens. The service layer gains
  `service_activity`/`service_related`; new `GET /contacts/(%d+)` route. e2e covers
  open/content/related/close; `load-tests/scenarios/detail.js` keeps it at par (~42k req/s locally).
- **Actionable detail drawer** (Phase D increment 2). The drawer is no longer read-only: **inline
  edit** (name/email/role/status/engagement, swapped in place — the slide doesn't re-animate),
  **cycle status**, and **delete** — all from the drawer. Edits/cycles re-render the drawer *and*
  refresh the table row behind it via an OOB swap (the `<tr>` wrapped in a `<template>` to survive
  the non-table swap context); drawer-delete closes the overlay and OOB-removes the row.
  `repo_update` now persists `score`. e2e covers edit+OOB-row, cycle, delete; the `write` load
  scenario becomes create→edit→delete so `POST /contacts/:id` is at par.
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
- **CI builds on all three platforms now**, not just Linux. The `build` job is a matrix over
  `ubuntu-latest`, `macos-latest` (Apple Silicon / arm64-darwin — exercises odin-http's **kqueue**
  path under `core:nbio`) and `windows-latest` (the primary dev platform — **IOCP** path). The
  ubuntu leg is unchanged; e2e and deploy are untouched. Each leg downloads its own **verified**
  Odin release asset (the names are irregular: the macOS-arm64 asset is tagged `…-dev-06`, the
  Windows asset carries no arch and unpacks to `dist/`), with `runner.os` in the cache key. C
  toolchain per OS so Odin can link — apt `clang` (Linux), Xcode CLT (macOS),
  `ilammy/msvc-dev-cmd` before the build (Windows); the build `-out` carries a per-OS extension
  (`.exe` on Windows). One shared bash smoke script boots the binary and hits the same endpoints on
  every OS, with `DB_PATH=:memory:` set for forward-compat with the planned SQLite layer.
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
- **Reflected HTML-injection via the `sort` query param** (security). The data table reflected
  `sort` into its `hx-get="…"` attributes (filter chips + pager) **without** the `url_encode` its
  sibling params (`q`, `status`) already used, so a crafted value — e.g.
  `/data?sort="><img src=x onerror=…>` — could break out of the attribute on a directly-navigable,
  `text/html` GET endpoint. `sort` is now `url_encode`d at every reflection site (legit values like
  `score_desc` are unreserved and round-trip unchanged; `sort_th` was already safe, emitting only
  derived column literals). Pinned by an e2e regression test.
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
