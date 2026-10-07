# TODO

What's left, as a checklist. Check items off as they land and add follow-ups as you find them;
`CLAUDE.md`'s standing policy works from this file.

## Make it yours

- [ ] Replace the Notes starter with your domain: `models` → `repository` (plus a migration) →
      `services` → `views` → `controllers` → `routes.odin`, with an e2e spec and a load scenario for
      every endpoint (the Recipes in `CLAUDE.md`).
- [ ] Write the site's home title: `BRAND_HOME_TITLE` in `app/src/views/brand.odin` is a stand-in,
      and it's what a search result shows for the site.
- [ ] Point `SITE_URL` at your domain (`brand.odin`, or `SITE_URL` in `fly.toml`).
- [ ] Re-render the social card `app/static/og.png` from `tools/og/og.html`, and redraw the favicon
      (`favicon.svg` + `favicon.ico`).
- [ ] If you want search-engine verification: set `BING_SITE_AUTH` / `INDEXNOW_KEY` in `brand.odin`
      and register their routes (the starter has none).
- [ ] Prune what still describes the demo: `CLAUDE.md` (architecture table, recipes),
      `app/README.md`, `app/static/app.css` (the theme library) and `app.js`, `docs/USE_CASES.md`,
      `load-tests/RESULTS.md`.
- [ ] Deploy: `infra/PLAN.md` → Operator steps (Fly), or `deploy/docker-host` (any Docker host).
- [ ] Delete `tools/init` once you're done with it.
