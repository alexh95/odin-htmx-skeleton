# TODO

Source of truth for outstanding work. Check items off as you finish them; add follow-ups you
discover. See `CLAUDE.md` for the standing policy. Keep this and `CHANGELOG.md` current.

## The project, in one line

This is a **starter skeleton** for a simple, server-rendered website on Odin + HTMX + SQLite —
clone it, rename it, strip the demo, build your thing. The bundled app (contacts/events admin
console + the theme library + the test/deploy harness) is the **worked example** that proves the
patterns, *not* the product. So "done" means *a great starting point*, not *a finished app*:
copy-and-start ergonomics and good defaults matter more than feature depth.

> Reframe: earlier docs ([`docs/USE_CASES.md`](docs/USE_CASES.md)) framed this as evolving into a
> "flagship admin console." That app is now explicitly the **example**, not the goal. Product-depth
> items (**bulk actions**, a **named console identity**) are **out of scope as goals** — they'd just
> be cruft a copier deletes — and survive only as "example extensions you might add."

## Roadmap to 1.0 — template-ize (Phase F) — ✅ shipped as v1.0.0 (2026-07-01)

Make it trivial to start a new project from. Bounded: mostly docs + one script. **All items below are
done** — the repo is a GitHub template with `tools/init` (+ `--minimal`), a centralized brand, and
the starter docs. Next up is **1.x** (below), headlined by auth.

- [x] **GitHub *template repository*.** Repo set as a Template Repository (the "Use this template"
      button is live); README has the use-template → `init` steps.
- [x] **An `init` / scaffold script** — `tools/init` (an Odin program: the skeleton's own tooling on
      the stack it teaches). Renames the app everywhere it's hardcoded in one pass — the binary
      (`demo`), the `fly.toml` app, the docker image, the apollo-11 service + volume, the `main.odin`
      banner, the test-package names, and the three `brand.odin` constants — across a fixed, audited
      file set. `--wordmark`/`--suffix`/`--repo` override the brand defaults; a confirm prompt +
      name validation guard it. Tested (run → build → revert).
  - [x] `--minimal`: strips the contacts/events demo to a one-page **Notes** starter (the full
        model→repo→service→view→controller stack over one entity), keeping the shell + theme +
        data-layer + harness. Deletes the demo domain/pages/specs/scenarios and drops in minimal
        templates (`tools/init/minimal/`, embedded via `#load`). Tested end-to-end: run → build
        (`-warnings-as-errors`) → curl smoke → **12/12 e2e** → revert.
- [x] **Parameterize the brand / app name** to one place — `app/src/views/brand.odin` holds
      `BRAND_WORDMARK` (the topbar wordmark, inline markup allowed) and `BRAND_SUFFIX` (the
      `<title>` / og:title suffix); `layout` is the only reader. The display name is now a
      two-constant edit instead of literals scattered through the views. The remaining name
      touch-points are outside the views (binary/app name in run/build scripts + `fly.toml` +
      `Dockerfile`, and the `main.odin` startup banner) — the `init` script will tie them together.
- [x] **README as a starter guide**, not a demo tour: use-template → run `init` → keep-vs-strip →
      the `CLAUDE.md` **Recipes** for adding a page / entity / endpoint. (Live in the README's
      "Using this as a starter".)
- [x] **`docs/STRIP.md` — "remove the demo."** Written: the demo-vs-scaffold map + the file-by-file
      seams to delete the contacts/events domain and demo pages, leaving the shell + data layer +
      theming + harness. Cross-links `init --minimal` (the automated version) and the CLAUDE recipes.
- [x] **Re-skin the docs to the skeleton framing** — `USE_CASES.md`'s "flagship (the app's
      direction)" section is now "the worked example" (built, past tense), the retired product-depth
      items (bulk actions, named console) are called out as out-of-scope, and the "read first" banner
      is tightened.

## 1.x — what *every new site* needs (so the skeleton should ship it)

- [ ] **Auth: sessions + CSRF.** The highest-leverage addition for a *starter* — every new site
      reinvents login/sessions/CSRF and it's easy to get wrong. A minimal, in-philosophy
      session-cookie pattern (login page, a protected-route guard, a CSRF token on POST/DELETE),
      held to the "few dependencies" line. Also closes the current CSRF gap on the mutating surface.
- [ ] **Per-thread WAL connections** — already **load-justified** (reads scale ~3–4× not ~5× under
      the v1 single shared connection; the `detail` JOIN worst at 1.9×). Ship the right concurrency
      default and re-measure in `load-tests/RESULTS.md`.
- [ ] **A second entity as a worked "add your own resource" example** (e.g. teams/companies a
      contact belongs to) — doubles as the multi-resource nav pattern *and* the literal tutorial for
      extending the skeleton. App / e2e / load at par, as always.

## Stretch goals

- [x] **A `--minimal` scaffold variant** — delivered as `init --minimal` (see Phase F above): a
      fully-wired one-page **Notes** starter you generate on demand (blank-but-wired), instead of a
      second variant to maintain beside the showcase.
- [ ] **Common-need recipes** as documented patterns (file upload, an env/config story, a background
      task) — kept as *recipes*, not framework features, to stay true to the philosophy.
- [ ] **Reporting/export** (CSV of the filtered table) and a focused **a11y pass** (drawer/modal
      focus management, keyboard nav) — cheap reinforcement of the "exemplar" claim.

## Shipped — the foundation the skeleton provides

The patterns + harness a fork inherits. (Was "Now / next"; the initiative below is built.)

- [~] **Vision + flagship + style library** (this initiative). Anchored by
      [`PHILOSOPHY.md`](PHILOSOPHY.md), [`docs/USE_CASES.md`](docs/USE_CASES.md),
      [`docs/DATA.md`](docs/DATA.md). Keep app/e2e/load-tests **at par** at every phase.
  - [x] **Phase A — direction docs.** PHILOSOPHY (vision), USE_CASES (sweet spot + flagship
        direction), DATA (datasource future-proofing). Wired into README/CLAUDE.
  - [x] **Phase B — theming foundation.** `data-style` × `data-scheme` on `<html>` (SSR default
        `modern`/`midnight`, restored pre-paint from localStorage); token contract; stateless
        `<details>` picker in the topbar (vanilla JS apply/persist, no endpoint → load par).
        **Modern** is the reference style with four schemes (Midnight/Daylight/Nebula/Aurora).
        e2e: picker switch + persist. Build clean, 32/32 e2e.
  - [x] **Phase C — the styles.** All five shipped — Skeuomorphic, Terminal/CRT, Brutalist,
        Editorial/Paper, Arcade (video-game) — each a pure `[data-style]` block with multiple
        schemes, every style incl. a light option. Plus cache-busting (`?v=hash`) so style edits
        show without a hard refresh. Library: 6 styles, 23 schemes.
    - [x] Turned `/components` into a live style/scheme **showroom**: a catalog of all 6 styles ×
          23 schemes at the top of the page; click any swatch to jump to that exact style+scheme and
          the whole page (components below) re-skins live. e2e covers it; no new server surface.
  - [~] **Phase D — flagship app.** Evolve the sampler into one cohesive internal admin console.
        Each new endpoint gets e2e **and** load scenarios in the same change.
    - [x] **Contact detail drilldown** — click a row's name → `GET /contacts/:id` opens a drawer
          with the full record, a derived **activity trail**, and **related** contacts (same role,
          each a one-click jump). Read-only for now. e2e + `detail.js` load scenario added.
    - [x] Inline edit + actions in the detail drawer (edit fields, cycle, delete — all swapped in
          place; edits OOB-refresh the table row; `repo_update` persists score). e2e + load at par.
          Phase-D review fix: an invalid drawer edit now surfaces an OOB error toast instead of
          silently reverting.
      - Known limitation: an in-drawer edit/cycle OOB-refreshes the row *in place*, so a
        filtered/sorted table can briefly show a row that no longer matches until the next
        interaction. A deeper fix would thread the table's q/status/sort into the drawer and
        re-render the whole region; acceptable for the POC.
    - [~] Richer table.
      - [x] Saved/quick **status filters** (chips: All/Active/Invited/Disabled; compose with search +
            sort + paginate via a threaded `status` arg).
      - [-] Bulk actions (select rows → set status / delete) — **out of scope as a goal** (skeleton:
            app-specific; a copier would strip it). Keep only as an example extension if ever wanted.
    - [x] Coherent product frame — the dashboard stat cards drill into the filtered/sorted data view
          (overview → tool). A *named* console identity + deeper nav IA is **out of scope** for a
          skeleton: the fork names and structures its own console.
  - [x] **Phase E — parity + polish sweep.** Parity closed: Phase D endpoints all have e2e + load
        (detail.js, the create→edit→delete write path, the new **list.js** for `GET /contacts`
        filter/sort); CHANGELOG/docs current; the Phase D review fix landed. Also wrote the
        **Odin data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md)).
        Phase E review pass swept the whole Phase D+E surface and caught a reflected
        HTML-injection via the `sort` query param (unescaped reflection into the table's `hx-get`
        attributes) — fixed by `url_encode`ing `sort` everywhere, pinned by an e2e regression test.
- [x] **Data layer — persistent SQLite** (replaces the in-memory POC).
  - [x] Implemented per [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md): amalgamation binding
        (`src/sqlite/`), the seven `repo_*` over SQLite, `prepare.*` fetch+compile (pinned + SHA-256),
        `DB_PATH` (`:memory:` default / file persists), WAL + migrations + `schema_version`. Contract
        unchanged; e2e + load pass untouched. apollo-11 persists to a named volume; Fly stays
        `:memory:` pending a volume (documented in `fly.toml`).
  - [x] **Repository cleanup + split.** Split into a **common** part (`repo.odin` — connection
        lifecycle incl. `repo_close`, the migration runner, the shared `exec`/`prep`/`bind`/`clone`/
        `scalar` helpers + the lock) and **per-entity** files (`contacts.odin`, `events.odin`), each
        owning its statements + procs. Helpers grouped, error handling documented (fatal at boot,
        best-effort per request), `repo_close` wired via `defer` in main.
  - [x] **Multi-table case — events between contacts.** `events(actor_id, target_id → contacts,
        ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`). The detail drawer's
        activity feed is now **real**: `event_timeline` JOINs back to contacts to resolve the other
        party, each a one-click jump (replaces the faked `service_activity`). Deleting a contact
        cascades its interactions. End-to-end at par: model + repo + service + view + e2e (incl. a
        cascade test; **42 e2e**) + load (`detail.js` now exercises the JOIN). Load re-measured:
        reads scale ~3–4× under the single-connection exclusive lock (`detail` JOIN worst at 1.9×) —
        see `load-tests/RESULTS.md`.
  - [ ] **Per-thread WAL connections** — moved to the **1.x roadmap** above (load-justified).
- [~] **Set up infrastructure** per [`infra/PLAN.md`](infra/PLAN.md). Code + config landed;
      what's left are operator actions on Fly/GitHub/Cloudflare (no repo changes).
  - [x] Prereq code change: `app/main.odin` reads `PORT` and binds `0.0.0.0` on `BIND_ALL`
        (loopback stays the local default).
  - [x] Pin odin-http as a submodule (`app/odin-http` @ `112c49b`) for reproducible builds.
  - [x] `Dockerfile` + `.dockerignore` + `fly.toml`; `.github/workflows/ci.yml` (build,
        smoke, deploy-on-`master`).
  - [x] Operator: created the Fly app + `FLY_API_TOKEN` secret; CI deploys on green push and the app
        is live (Fly `fra`, Cloudflare-fronted at `odin-htmx.alexh95.com`).
  - [x] Operator: front the Fly app with a **proxied Cloudflare record** (`fly certs add` + the
        `_fly-ownership` TXT and `_acme-challenge` CNAME for DNS-01 validation, CF SSL Full-strict).
        This was also a latency fix: Fly's IPv6 anycast mis-routed an EU ISP to the `jnb`
        (Johannesburg) edge (~785 ms TTFB) while IPv4 hit `ams` (~160 ms); routing through
        Cloudflare's edge bypasses Fly's anycast and serves both v4/v6 in **~105 ms** with
        `/static` edge-cached. The Fly region was also moved `iad`→`fra` so the origin is nearby.
  - [ ] Stand up the dedicated load-test environment when load-tests are implemented.
- [x] Implement the e2e suite per [`e2e/PLAN.md`](e2e/PLAN.md) — Playwright, 31 tests incl. the
      three regressions; wired into CI as a gating job. It surfaced (and we fixed) the `fmt`
      brace bug in the page `<head>` and the OOB-toast wrapper.
- [x] Implement the load-tests per [`load-tests/PLAN.md`](load-tests/PLAN.md) — k6 scenarios
      (static/pages/search/api/write/mixed), a `run.sh`/`run.bat` sweep driver, and
      `RESULTS.md`. Single-thread baseline captured.
  - [x] Headline follow-up: guarded the store with an `sync.RW_Mutex` and set `thread_count`
        to the core count (`THREADS` env overrides). Before/after in `RESULTS.md`: reads scale
        **~5×** (1→8 threads), writes ~1.8× (exclusive-lock-bound, as predicted), and the
        500-VU overload failures (13–34%) drop to **0%**. Also ran it against prod (Fly).
  - [x] Two-host absolute numbers: deployed to the apollo-11 home server
        ([`deploy/apollo-11`](deploy/apollo-11)), k6 on the workstation over a 1 GbE LAN. Found the
        wire ceiling (static/pages saturate ~912 Mbit vs 2.4 GB/s loopback) and the reverse-proxy
        cost (~12× for NPM+TLS on the shared box). Surfaced the io_uring-vs-Docker-seccomp gotcha.
        Results in `RESULTS.md`. (Further: a generator *outside* the LAN for the true external path.)
- [~] **Sync gate:** every endpoint now has both an e2e and a load scenario for its *class*
      (static, page, search, api, write). `/healthz` is hit by the run driver's readiness
      probe rather than a dedicated scenario; add one if it ever does real work.

## Backlog

- [x] Data table: the actions column overflowed into horizontal scroll on narrow viewports. Fixed
      in the mobile pass — below 560px the table folds email/role/engagement into the detail drawer
      (name · status · actions remain); the topbar was the larger culprit (page-wide scroll), also
      fixed. No horizontal overflow 320–1280px, pinned by e2e.
- [x] Pin htmx to an exact version in `prepare.*` (was the floating `@2`) for reproducible builds —
      pinned to **4.0.0-beta5** with a SHA-256 check (same discipline as ODIN_VERSION / SQLite), and
      migrated htmx 2 → 4 (renamed config keys `defaultSwap`/`transitions`, `htmx:after:process`
      re-init, the form auto-reset moved to `app.js` over `ctx.sourceElement`).
- [ ] Optional: a build-flag-gated `/__reset` endpoint to reseed the store (useful for load
      tests; must never ship in a normal build). Tie to `load-tests/PLAN.md`.
- [ ] Optional: `-o:speed` build path for benchmarking vs. the default showcase build.
- [x] CI guard for `init --minimal` rot — a `minimal` CI job strips a fresh checkout to the Notes
      starter and runs its e2e (global-setup builds it `-warnings-as-errors`, so one job catches
      compile- **and** runtime-rot, and exercises the rename path too). Chromium only; gates deploy.
      Keeps the `tools/init/minimal/` templates honest as the skeleton evolves.

## Done

- [x] Initial showcase app (dashboard, components, forms, data + CRUD, search, JSON API).
- [x] Bug fixes: modal outside-click, `/forms` field reset, static slider fill.
- [x] Restructure into `app/` + `e2e/` + `load-tests/`; project docs (`CLAUDE.md`, this file,
      `CHANGELOG.md`).
- [x] git init + first commit; adopted Conventional Commits; infrastructure plan
      (`infra/PLAN.md`).
