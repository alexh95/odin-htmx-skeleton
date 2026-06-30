# CLAUDE.md

Guidance for working in this repo. Read it before changing anything; it captures decisions
and gotchas that aren't obvious from the source and that are expensive to rediscover.

## What this is

A web app showcasing an **Odin** backend rendering HTML with **HTMX** on the front end — evolving
into a flagship internal admin console with a multi-style theme library. **Read
[`PHILOSOPHY.md`](PHILOSOPHY.md) first** — it's the why, and changes must stay in line with it.
[`docs/USE_CASES.md`](docs/USE_CASES.md) says what the stack is for (and the flagship direction);
[`docs/DATA.md`](docs/DATA.md) is the path past the in-memory POC.

```
odin-htmx-demo/
  app/          The application (Odin sources, static assets, run scripts). All real work.
  e2e/          Playwright browser tests (implemented). `cd e2e && npm ci && npm test`.
  load-tests/   k6 throughput/latency tests (implemented). `cd load-tests && ./run.sh --quick`.
  docs/         PHILOSOPHY.md (root), USE_CASES.md, DATA.md + DATA_IMPL.md — vision, fit, data.
  CLAUDE.md TODO.md CHANGELOG.md   ← you are here
```

## Standing policy (do this every session)

1. **Keep `CHANGELOG.md` current.** Every change that touches behaviour, structure, or build
   goes under `## [Unreleased]` (Keep a Changelog format: Added / Changed / Fixed / Removed).
   No silent changes.
2. **Keep `TODO.md` current.** Pick items from it; check off what you finish; add follow-ups
   you discover. It is the source of truth for what's left.
3. **Keep e2e and load-tests in sync (once implemented).** Every user-facing feature or
   endpoint must be represented in *both* suites — e2e asserts its behaviour, load-tests
   measures its cost. Adding `/foo` means adding a `/foo` e2e scenario *and* a `/foo` load
   scenario in the same change. If you add one, add the other or write a TODO and say so.
4. **Update docs you invalidate.** If you change the API, layout, or a convention here, fix
   `CLAUDE.md`, `app/README.md`, and the relevant `PLAN.md` in the same pass.
5. **Commit with Conventional Commits** (see below). One logical change per commit.

## Commits — Conventional Commits

Every commit follows the [Conventional Commits](https://www.conventionalcommits.org) spec:

```
type(scope): imperative subject
```

- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- **Scope** (encouraged): the area touched — `views`, `controllers`, `services`, `repository`,
  `routes`, `css`, `js`, `e2e`, `load`, `infra`, `deps`, `docs`.
- **Subject**: imperative mood, lower-case, no trailing period, ≤ ~72 chars.
- **Breaking changes**: `type(scope)!: …` and/or a `BREAKING CHANGE:` footer.
- Body explains *why* when it isn't obvious; wrap ~72.
- AI-authored commits end with `Co-Authored-By: Claude <…>`.

**Changelog mapping**: `feat`→Added, `fix`→Fixed, `refactor`/`perf`/`style`→Changed, removals
→Removed. Keep `CHANGELOG.md` `[Unreleased]` in step with the commits as you go.

Commits are GPG-signed (configured in git). If signing isn't available in an automated
environment, an explicit `--no-gpg-sign` on that one commit is acceptable.

## Build / run / verify

All commands run from `app/`.

```sh
prepare.bat   # once: fetch htmx + the SQLite amalgamation, compile sqlite    (./prepare.sh elsewhere)
run.bat [port]   # build + serve (default 8080)                              (./run.sh elsewhere)

odin build src -out:bin/demo.exe    # build only (entry package is src/); MUST be warning-free
./bin/demo.exe 8080                 # run the built binary on a port
```

odin-http is a **pinned git submodule** (`app/odin-http`); after a fresh clone run
`git submodule update --init` (or `git clone --recurse-submodules`). `prepare.*` fetches htmx and
the **pinned, SHA-256-verified SQLite amalgamation** and compiles it to a static lib, so a **C
toolchain is now required** (MSVC Build Tools on Windows — run from an *x64 Native Tools* prompt;
`clang` on Linux; Xcode CLT on macOS). The server binds loopback by default; set `BIND_ALL=1` (and
`PORT`) for containers — the deploy path (`Dockerfile`, `fly.toml`, `.github/workflows/ci.yml`,
`infra/PLAN.md`).

Verify with curl for contracts, and a browser (preview/headless pointed at `localhost`) for
anything HTMX actually swaps or animates. The store is SQLite, chosen by `DB_PATH`: `:memory:`
(a fresh seeded store per process — the test/CI default) or a file path that persists (`run.*`
default to a local `data.db`). A clean build is **zero warnings** — treat warnings as errors.

## Dependencies — the line we hold

The shipped app's runtime dependencies are deliberately few: **HTMX** (front end), **odin-http**
(backend HTTP, a stand-in for the core module Odin is expected to grow), and **SQLite** (the store
— bound as the amalgamation and *statically linked in*, the most-deployed database on earth, not a
framework or a server). All three are pinned and vendored/compiled into the one binary. That's it.

- No NPM, no bundler, no build system beyond `odin build` (+ `prepare` compiling sqlite once).
- No CSS/JS frameworks. CSS is hand-written; JS is vanilla and tiny.
- No template engine — HTML is generated by Odin procedures.
- **Every** static asset (htmx, `app.css`, `app.js`, `favicon.svg`) is **embedded into the
  binary** (`#load` in `controllers.odin`) and served from memory — the binary is fully
  self-contained, nothing is read from disk at runtime. Editing CSS/JS needs a rebuild.
- Before reaching for a library, ask whether ~30 lines of Odin or CSS does it. They usually
  do. New runtime dependencies in `app/` need a real justification.
- Test tooling is exempt: `e2e/` and `load-tests/` may use external tools (Playwright, k6)
  because they're dev-time and never shipped. Prefer single-binary tools. The product itself
  stays JS-free; `e2e/` uses npm (it runs in Playwright's Docker image on CI, which ships
  node/npm, so there's nothing extra to install).

## Architecture — strict layering

Each layer is its own Odin **package** under `app/src/` (a directory = a package), so the
boundaries are enforced by the compiler, not just convention. Dependencies point one direction
only; an illegal shortcut won't compile (or would create an import cycle).

```
src/ (main: main.odin, routes.odin) → controllers → services → repository → models
                                                  ↘ views ↗
```

| Package (dir) | Layer | Rule |
|------|-------|------|
| `src/models/` | model | Types + enum label tables. No logic, no imports beyond `core`. |
| `src/sqlite/` | binding | ~15 `foreign` decls for the SQLite amalgamation. The only C-ABI crossing. |
| `src/repository/` | repository | Owns the SQLite store: `repo.odin` (connection/lock/migrations + helpers) + per-table files (`contacts.odin`, `events.odin`). Imports `models`, `sqlite`. |
| `src/services/` | service | Search/sort/paginate/validate. Plain values + errors, never HTTP. Imports `models`, `repository`. |
| `src/views/` | view | HTML builders (a component is a proc writing into a `^strings.Builder`). Imports `models`, `services`/`repository`. |
| `src/controllers/` | controller | **The only layer that imports `http`.** Parse → call service → render via `views.*` → respond. Embeds htmx via `#load`. |
| `src/` (`package main`) | entry + wiring | `main.odin` seeds + serves; `routes.odin` is the route table. Imports `controllers` (+ `repository` for the seed). |

Cross-package calls are qualified: `repository.repo_list()`, `services.service_page()`,
`views.view_dashboard()`, `models.Contact`. Sibling packages import each other relatively
(`import "../models"`); `odin-http` lives at `app/odin-http`, so it's `"../odin-http"` from
`src/` and `"../../odin-http"` from `src/controllers/`.

The server runs **N nbio event-loop threads** (one per core by default; `THREADS` env
overrides), so handlers run concurrently. The store is one SQLite connection guarded by an
`sync.RW_Mutex`. **v1 takes the lock *exclusively* for every op, reads included** — a single
connection's prepared statements are shared mutable state, so concurrent shared-lock reads would
corrupt each other (parallel reads return with per-thread WAL connections — `docs/DATA_IMPL.md` §4,
and the note in `repository/repo.odin`). Because callers read a returned contact *after* the lock
drops, the repository hands out **temp-arena snapshots** (columns cloned into the request arena via
`clone_col`), never pointers into a statement buffer. If you touch the store, go through a `repo_*`
proc.

## Code aesthetics (Odin)

Write it the way Casey Muratori or Jonathan Blow would write C — but in Odin. Compression-
oriented: solve the problem simply, once, and let small reusable procs do the work.

- **Comments say *why*, not *what*.** If the code is obvious, no comment. When there is a
  comment, it explains a decision, a constraint, or a non-obvious mechanism. No narration, no
  AI slop, no restating the line below it.
- **Section dividers**: `// ---- name ----------------------------------------------------`.
- **One definition per concept.** Enum→label is one table (`ROLE_NAMES`); a sort comparator is
  one proc per key, reversed for `_desc` rather than duplicated per direction. Find the seam
  that collapses N cases into one.
- **Naming**: `snake_case` procs/vars, `Pascal_Case`... actually `Ada_Case` types (`Contact`,
  `Field_Error`), `SCREAMING_CASE` constants. Match the surrounding file.
- **Visibility**: `@(private="file")` for true file-locals only. A proc used across files must
  be package-scoped — don't mark it file-private (it won't compile).
- Match the existing density and idiom. The reference for taste is the existing code.

## Views / HTML conventions

- **Raw string literals** (backticks) for all HTML so attribute quotes stand as-is. Reserve
  `fmt.sbprintf` for interpolation: Odin uses `%` verbs (`%d`, `%s`; `%%` is a literal percent).
  **`fmt` also treats `{` and `}` as directive characters** — a format string containing literal
  braces (JSON in `htmx-config`, `hx-vals`, an inline `<script>{…}`) emits `%!(MISSING …)` into
  the output. So never route brace-bearing HTML through `sbprintf`: write it with `w()` and
  splice the dynamic bits around it. (This silently broke the page `<head>` once — see CHANGELOG.)
- **`w(b, s)`** writes a string; **`esc(b, s)`** HTML-escapes. Every dynamic value that lands
  in text passes through `esc`; every value in an `href`/query passes through `url_encode`.
  This is the injection boundary — no exceptions.
- **Semantic HTML**: `<header><nav><main><section><article><aside><footer>`, `<form>/<label>/
  <fieldset>`, `<dialog>`-style modals, `<details>/<summary>` accordions, real `<table>`,
  real `<button>`. No div soup.
- A page handler builds a content string and wraps it with `layout(title, active, content)`.
  Fragments return bare HTML (no layout).

## Allocator model (the #1 gotcha — get this right)

odin-http gives each connection a growing arena as **`context.temp_allocator`**, freed *after*
the response is flushed.

- **Build all response HTML in the temp allocator** (`strings.builder_make(context.temp_allocator)`,
  `fmt.tprintf`, etc.). It lives exactly long enough and costs nothing to free.
- **`context.allocator` stays the heap.** Anything that must outlive the request — i.e.
  everything stored in the repository — is `strings.clone`d into it. `repo_create`/`repo_update`
  clone; `repo_delete` frees. **Never put a temp-allocated string into the store.**
- Body reads are async: `http.body(req, ...)` may defer. The `user_data` you pass must outlive
  the call → allocate it with `new(T, context.temp_allocator)`, not on the stack.

## odin-http cheat sheet (verified against the cloned source)

```odin
import http "../../odin-http"   // relative; submodule at app/odin-http ("../odin-http" from src/)

// server (main.odin)
s: http.Server
http.server_shutdown_on_interrupt(&s)
opts := http.Default_Server_Opts; opts.thread_count = os.get_processor_core_count() // THREADS env overrides
http.listen_and_serve(&s, http.router_handler(&router),
    net.Endpoint{address = net.IP4_Loopback, port = port}, opts)

// router (routes.odin) — Lua patterns, captures via req.url_params[i]
http.router_init(&router); defer http.router_destroy(&router)
http.route_get/route_post/route_put/route_patch/route_delete/route_options(
    &router, "/contacts/(%d+)", http.handler(some_handler))
// register specific routes before catch-alls; first match in registration order wins.

// handler
some_handler :: proc(req: ^http.Request, res: ^http.Response) { ... }

// request
req.url.path      // "/static/app.css"   (full path)
req.url.query     // "q=foo&sort=name"   (raw, after '?'; see query_get helper)
req.url_params    // []string  capture groups

// body (async, form-encoded)
http.body(req, -1, user_ptr, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
    if err != nil { ... }                 // Body_Error is a #shared_nil union → != nil works
    form, ok := http.body_url_encoded(body)   // map[string]string, percent-decoded
})

// responses
http.respond_html(res, html, status = .OK)
http.respond_plain(res, text)
http.respond_json(res, value)                              // marshals any
http.respond_file_content(res, "htmx.min.js", HTMX_JS)     // content-type from extension
http.respond_dir(res, "/static/", "static", req.url.path)  // pass the FULL path; it strips base + blocks traversal
http.respond(res, http.Status.Not_Found)
```

## HTMX conventions / gotchas

- **htmx 4 events** are colon-namespaced (`htmx:after:request`, `htmx:after:swap`,
  `htmx:after:process`) and carry `event.detail.ctx` (`sourceElement`, `target`, `response`, …).
  Form auto-reset lives in `app.js` (not `hx-on`): a document listener resets
  `form[data-reset-on-success]` after a 2xx, **scoped by `ctx.sourceElement`** so a child field's
  validation request can't reset the form (the email field on /forms validates as you type — an
  unscoped reset wiped what the user typed; this bit us once).
- **Out-of-band toasts**: return `<div class="toast" hx-swap-oob="beforeend:#toasts">…</div>`
  from any handler; `view_toast(kind, msg, oob=true)` does this.
- **OOB a *table row* with `<hx-partial>`, not `hx-swap-oob`.** htmx 4 collects OOB via
  `querySelectorAll("[hx-swap-oob]")`, which doesn't descend into `<template>`; and a response that
  *starts* with a non-table element is body-parsed, which drops a trailing bare `<tr>`. So to
  refresh `#contact-<id>` alongside a drawer swap, wrap the row in
  `<hx-partial hx-target="#contact-N" hx-swap="outerHTML">…</hx-partial>` (htmx turns it into a
  `<template>` it processes). See `contacts_update`. (A row-only response that *starts* with `<tr>`,
  like delete-from-drawer, is fine bare.)
- **Form bodies arrive `+`-encoded.** htmx 4 sends spaces as `+` (the form-encoding standard);
  odin-http's `body_url_encoded` only percent-decodes, so parse POST bodies with the controllers'
  `body_form` helper (it `+`→space-decodes like `query_decode`), never `http.body_url_encoded`.
- **Exit animations**: `hx-swap="outerHTML swap:220ms"` keeps the node around long enough for
  the `.htmx-swapping` CSS to play.
- **Overlays** (modal/drawer) load into `#overlay` and close via `GET /ui/clear` (empty body).
  The modal backdrop intentionally has **no** close handler — an outside click must not
  discard a half-typed field. The drawer backdrop may close (no field to lose).
- View Transitions are on globally via `htmx-config` (`{"transitions":true}`) in `layout`.
- **Boosted navigation**: the brand + primary-nav links carry `hx-boost="true"` (on **each link** —
  htmx 4 doesn't inherit it from a parent `<nav>` the way htmx 2 did). Clicking swaps the `<body>`
  and pushes history instead of a full document load — SPA-like, no asset re-parse, no theme flash,
  and the `<title>` updates from the response. Boost only internal HTML links; leave the JSON-API
  tile and the no-action search/filter forms alone. Server work and bytes are unchanged (whole pages
  are still rendered) — it's a client-side win. A body swap re-creates `#toasts` / `#overlay` / the
  picker, so keep per-node JS state swap-safe (see the JS conventions).

## CSS conventions (`app/static/app.css`)

- **Token-driven, two orthogonal axes.** `data-style` × `data-scheme` on `<html>` (6 styles, 23
  schemes; SSR default `modern`/`midnight`, restored pre-paint from localStorage to avoid a flash).
  Structural tokens live on `:root`; each `[data-style=x][data-scheme=y]` block sets the palette;
  `--on-accent` flips button text dark on light-accent schemes. Components read tokens
  (`var(--accent)`, `var(--surface)`), never raw colours — so a new scheme is one palette block and
  a new style is one `[data-style]` block over untouched component HTML.
- One `.btn` + modifiers (`.btn-primary`, `.btn-outline`, …). Same pattern for badges/chips.
  Don't fork a new base class when a modifier will do.
- **Vibrant but disciplined**: violet→indigo→cyan gradient accents, `color-mix()` for tints.
- **Snappy**: transitions 120–220ms, ease-out / spring curves (`--ease`, `--spring`).
  Always honour `prefers-reduced-motion` (there's a global override at the bottom).
- Dynamic values driven by CSS custom properties set from JS (e.g. slider `--fill`, ring
  `--p`, avatar `--h`), not by rewriting styles in JS.

## JS conventions (`app/static/app.js`)

- Vanilla, no dependencies, small. HTMX drives interactions; JS only does what the server
  can't: theme persistence, toast lifecycle, tab selection state, slider fill, count-up.
- **Delegated listeners** on `document` so dynamically swapped content is covered; re-init
  swapped content on `htmx:after:process` (htmx 4's "content wired up" event). The file runs
  `defer` (DOM is ready).
- **Keep per-node state swap-safe** — a boosted nav swaps the whole `<body>`. Observe a stable
  ancestor (the toast retire-observer watches `document.body`, not the swapped `#toasts`), and make
  on-load init idempotent so `htmx:after:process` can re-run it after a swap (the count-up flags
  `data-counted`; `markPicker` just re-sets aria state).

## Odin gotchas (discovered here)

- `strconv.atoi` is deprecated → `strconv.parse_int(s, 10)`.
- `len(EnumType)` is valid (member count). Iterate enumerated arrays as `for value, key in ARR`.
- `make([dynamic]T, context.temp_allocator)` is valid (allocator as the 2nd arg).
- Ternary `cond ? a : b` exists; use it for small attribute choices.
- `strings.split_by_byte_iterator(&s, '&')` mutates `s` (pass a local copy of `req.url.query`).

## Recipes

- **New page**: add `view_x()` in `src/views/` → `page_x` controller calling
  `render_page(res, "Title", "/x", desc, views.view_x())` → `route_get` in `routes.odin` → a nav
  entry in `NAV` (`src/views/views.odin`) if it's top-level. Add e2e + load scenarios. Changelog.
- **New fragment/endpoint**: `view_*` returning bare HTML → controller → route. If it mutates,
  go through a service → repository proc; never touch the store from a controller. Escape all
  input. Add e2e + load scenarios. Changelog.
- **New component**: a proc writing into `^strings.Builder` + a token-driven CSS block. Reuse
  `icon`, `esc`, `w`. Add it to the `/components` gallery.
```
