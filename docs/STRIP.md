# Stripping the demo — from the worked example to your own app

The bundled contacts/events console is the **worked example**, not the product. This is the map for
removing it, leaving the scaffolding you actually keep: the page shell, the theme system, the SQLite
data layer, and the build / CI / deploy / test harness.

The strict layering (see [`../CLAUDE.md`](../CLAUDE.md) → *Architecture*) makes this nearly
mechanical — a package is a directory, and only one package touches storage, one renders HTML, one
speaks HTTP. Delete the demo's *contents* and the seams are obvious.

## The fast path: let the tool do it

```sh
odin run tools/init -- your-name --minimal --repo https://github.com/you/your-name
```

`--minimal` performs exactly the strip below and drops in a one-page **Notes** starter (the same
full model→repository→service→view→controller stack, over a single trivial entity). If you'd rather
keep the demo as a reference and carve your own path, read on — everything `--minimal` automates is
spelled out here, and the templates it installs live in [`../tools/init/minimal/`](../tools/init/)
as a worked target.

## What's demo vs. scaffold

| Path | Role | Do |
|---|---|---|
| `app/src/models/models.odin` | demo domain (`Contact`, `Event`, enums) | **replace** with your type(s) |
| `app/src/repository/contacts.odin`, `events.odin` | demo entities' storage | **delete** |
| `app/src/repository/migrations/0002_events.sql` | demo schema | **delete** |
| `app/src/repository/migrations/0001_init.sql` | demo schema | **replace** with your tables |
| `app/src/repository/repo.odin` | connection / lock / migrations / helpers | **keep**, retarget (below) |
| `app/src/services/services.odin` | demo search/sort/paginate/validate | **replace** with your logic |
| `app/src/views/views_pages.odin`, `views_fragments.odin` | demo pages + fragments | **delete** |
| `app/src/views/views.odin` | layout, brand, theme picker, icons **+ demo dashboard** | **keep the shell**, drop the demo procs |
| `app/src/controllers/controllers.odin` | demo handlers **+ generic plumbing** (assets, health, crawler contract) | **keep the plumbing**, drop the demo handlers |
| `app/src/routes.odin` | the route table | **rewrite** to your routes, keeping the generic ones (below) |
| `app/src/main.odin` | seed + serve + the canonical-host redirect | **keep** (entity-agnostic) |
| `app/src/sqlite/`, `app/src/views/brand.odin` | binding, site identity (brand, home title, `SITE_URL`, ownership tokens) | **keep** (`tools/init` rewrites brand.odin) |
| `app/static/app.css`, `app.js` | theme + component CSS, tiny JS | **keep** (prune unused rules at leisure) |
| `app/static/og.png`, `favicon.svg`, `favicon.ico` | the social card + icons, still the upstream's | **keep**, then redraw: `og.png` re-renders from [`../tools/og/og.html`](../tools/og/og.html) |
| `e2e/tests/seo.spec.ts` | the crawler contract, derived from what the app serves | **keep**: it's generic (demo-only checks skip themselves) |
| `e2e/tests/*.spec.ts` (the rest), `e2e/helpers/server.ts` | demo behaviour tests, and the helper only the persistence + events specs use | **delete**, write your own (keep `fixtures.ts`, `global-setup.ts`) |
| `load-tests/scenarios/*.js` | load scenarios | **keep** `static.js` + `seo.js` (generic), repoint `pages.js`, **delete** the rest |
| `.github/workflows/ci.yml` → the `minimal` job | guards the `--minimal` templates by running `tools/init` | **delete** it and drop it from `deploy`'s `needs` (a fork deletes `tools/init`) |
| `app/data.db` (+ `-wal`, `-shm`) | the local dev database, at the demo's schema | **delete** once your migrations replace the demo's |
| everything else (`prepare.*`, `run.*`, `Dockerfile`, `fly.toml`, the rest of `.github/`, `deploy/`, `infra/`) | the harness | **keep** |

## Step by step

### 1. The domain (`models` + `repository`)

Delete `repository/contacts.odin`, `repository/events.odin`, and `migrations/0002_events.sql`.
Replace `models/models.odin` with your type, and `migrations/0001_init.sql` with your table(s), then
delete `app/data.db*`: the migration runner counts applied migrations, so a database already at the
demo's version would skip yours and fail with "no such table". Add
a `repository/<entity>.odin` that prepares its statements and exposes the ops your app needs — copy
the shape of the old `contacts.odin` (it's the reference for statements + the lock + `clone_col`).

Retarget the three entity-specific hooks in `repository/repo.odin`:

- `MIGRATIONS` — list your migration files (`#load`ed, applied in order at boot).
- `repo_open` / `repo_close` — call your `prepare_<entity>` / `finalize_<entity>`.
- `repo_seed` — seed your table(s) when empty.

Everything else in `repo.odin` (connection, `RW_Mutex`, `exec`/`prep`/`bind_text`/`clone_col`/
`scalar_int`, the migration runner, `fatal`) is entity-agnostic — **keep it as is**.

### 2. The views (`views`)

Delete `views_pages.odin` and `views_fragments.odin`. In `views.odin`, **keep** `w` / `esc`, `icon`,
the theme picker (`STYLES` / `SCHEMES` / `theme_picker`), `HTMX_HREF` / `CSS_HREF` / `JS_HREF`, `NAV`,
`layout`, and `page_head` — that's the reusable shell. **Remove** the demo body procs
(`view_dashboard`, `view_showroom`, `stat_card`, `sparkline`, `link_tile`, and the contact-specific
`status_badge` / `role_chip` / `avatar` / `write_highlighted`). Trim `NAV` to your pages and add a
`view_<page>` proc per page.

### 3. The seams (`controllers` + `routes`)

In `controllers.odin`, **keep** `render_page`, `body_form`, `health`, the crawler contract
(`robots_txt`, `sitemap_xml`, `favicon_ico`, `bing_site_auth`, `indexnow_key`), and the whole static
block (`init_etags` + `serve_static` + the `#load`ed assets) — all generic. Only `robots_txt`'s
`Disallow:` list is demo-specific: replace it with your own fragment routes. **Remove** the demo
handlers (`page_dashboard`/`components`/`forms`/`data`, `frag_*`, `api_search`, `contacts_*`,
`validate_*`, `forms_submit`, `ui_*`). Add a handler per page/action.

Rewrite `routes.odin` to register only your routes, keeping the generic ones: `/healthz`,
`/robots.txt`, `/sitemap.xml`, `/favicon%.ico`, `/BingSiteAuth.xml`, the IndexNow key route, and
`/static/(.+)` last. `main.odin` needs no change — it only speaks to `repository.repo_*` and
`controllers.init_etags` + `build_router`.

### 4. Tests + load

Delete the demo specs under `e2e/tests/` and `e2e/helpers/server.ts`, and write your own specs
against your pages (keep `fixtures.ts`, `global-setup.ts`). Keep `seo.spec.ts`: it derives the page
set, origin and tokens from the app itself, so it holds for any site, and its demo-only checks skip
themselves. Under `load-tests/scenarios/`, keep `static.js` and `seo.js` (generic), delete the
contacts-specific ones (`api`, `detail`, `list`, `search`, `write`, `mixed`), point `pages.js` at your
pages, and drop `/api/search` from `run.sh`'s optional bombardier baseline. `run.sh` runs every file
in `scenarios/`, so there's no list to update. Keep app / e2e / load **at par** as you build — see
[`../CLAUDE.md`](../CLAUDE.md); `load-tests/parity.sh` lists the routes either suite misses.

### 5. Rename + docs

Run `tools/init` (without `--minimal`) to rename the binary / Fly app / Docker image / brand, or do
it by hand. It also removes the CI `minimal` job and lists what still names the upstream. Then write
`BRAND_HOME_TITLE`, re-render `og.png`, prune the docs that describe the example — `CHANGELOG.md`,
`TODO.md`, [`USE_CASES.md`](USE_CASES.md), `load-tests/RESULTS.md` — and rewrite `README.md` /
`app/README.md` for your app.

## Then build up

Adding your first page, endpoint, and entity follows the **Recipes** in
[`../CLAUDE.md`](../CLAUDE.md). The minimal Notes starter (`tools/init/minimal/`) is a complete,
compiling example of one entity wired through every layer — the smallest thing that still exercises
the whole stack.
