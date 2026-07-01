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
| `app/src/controllers/controllers.odin` | demo handlers **+ generic asset/health plumbing** | **keep the plumbing**, drop the demo handlers |
| `app/src/routes.odin` | the route table | **rewrite** to your routes |
| `app/src/main.odin` | seed + serve | **keep** (entity-agnostic) |
| `app/src/sqlite/`, `app/src/views/brand.odin` | binding, brand constants | **keep** |
| `app/static/app.css`, `app.js` | theme + component CSS, tiny JS | **keep** (prune unused rules at leisure) |
| `e2e/tests/*.spec.ts` | demo behaviour tests | **delete**, write your own (keep `fixtures.ts`, `global-setup.ts`, `helpers/`) |
| `load-tests/scenarios/*.js` | demo load scenarios | **delete** the demo ones, keep `static.js`, repoint `pages.js` + `run.sh` |
| everything else (`prepare.*`, `run.*`, `Dockerfile`, `fly.toml`, `.github/`, `deploy/`) | the harness | **keep** |

## Step by step

### 1. The domain (`models` + `repository`)

Delete `repository/contacts.odin`, `repository/events.odin`, and `migrations/0002_events.sql`.
Replace `models/models.odin` with your type, and `migrations/0001_init.sql` with your table(s). Add
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

In `controllers.odin`, **keep** `render_page`, `body_form`, `health`, and the whole static block
(`init_etags` + `serve_static` + the `#load`ed assets) — all generic. **Remove** the demo handlers
(`page_dashboard`/`components`/`forms`/`data`, `frag_*`, `api_search`, `contacts_*`, `validate_*`,
`forms_submit`, `ui_*`). Add a handler per page/action.

Rewrite `routes.odin` to register only your routes (keep `/healthz` and `/static/(.+)`).
`main.odin` needs no change — it only speaks to `repository.repo_*` and `controllers.init_etags` +
`build_router`.

### 4. Tests + load

Delete the demo specs under `e2e/tests/` and write your own against your pages (keep `fixtures.ts`,
`global-setup.ts`, `helpers/`). Under `load-tests/scenarios/`, delete the contacts-specific ones
(`api`, `detail`, `list`, `search`, `write`, `mixed`), point `pages.js` at your pages, and update
`run.sh`'s default `SCENARIOS` list and its readiness-probe paths. Keep app / e2e / load **at par**
as you build — see [`../CLAUDE.md`](../CLAUDE.md).

### 5. Rename + docs

Run `tools/init` (without `--minimal`) to rename the binary / Fly app / Docker image / brand, or do
it by hand. Then prune the docs that describe the example — `CHANGELOG.md`, `TODO.md`,
[`USE_CASES.md`](USE_CASES.md), `load-tests/RESULTS.md` — and rewrite `README.md` / `app/README.md`
for your app.

## Then build up

Adding your first page, endpoint, and entity follows the **Recipes** in
[`../CLAUDE.md`](../CLAUDE.md). The minimal Notes starter (`tools/init/minimal/`) is a complete,
compiling example of one entity wired through every layer — the smallest thing that still exercises
the whole stack.
