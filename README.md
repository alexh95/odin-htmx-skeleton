# odin-htmx-demo

A **starter skeleton** for a simple, server-rendered website: an **Odin** backend rendering HTML
with **HTMX**, a **SQLite** store, and browser + load test suites — all in one self-contained
binary. Clone it, rename it, strip the demo, build your thing.

The bundled app (a contacts/events admin console with a multi-style theme library) is the
**worked example** that proves the patterns — not the product. You keep the scaffolding
(architecture, data layer, theming, build / CI / deploy / test harness) and swap the demo domain
for your own.

```
odin-htmx-demo/
  app/          The application: Odin server, views, static assets, run scripts.
  e2e/          Playwright browser tests — see e2e/README.md.
  load-tests/   k6 throughput/latency tests — see load-tests/README.md.
  docs/         PHILOSOPHY.md (root), USE_CASES.md, DATA.md, DATA_IMPL.md.
```

## Quick start

Needs the Odin compiler **and a C toolchain** (MSVC Build Tools on Windows, `clang` on Linux,
Xcode CLT on macOS) — `prepare` compiles the SQLite amalgamation. See
[app/README.md](app/README.md) → *Run it* for the per-OS setup.

```sh
cd app
prepare.bat        # once: clones odin-http, fetches htmx + SQLite    (./prepare.sh on Linux/macOS)
run.bat            # builds and serves http://localhost:8080          (./run.sh elsewhere)
```

See [app/README.md](app/README.md) for the full tour — pages, architecture, endpoints, and
design notes.

## Using this as a starter

Clone it and replace the demo with your domain. What you **keep** vs. **strip**:

- **Keep — the scaffolding:** the layered packages (`models` / `repository` / `services` / `views` /
  `controllers`), the SQLite layer + migrations, the theme system, the view/component helpers, and
  the build / CI / Docker / deploy / e2e / load harness.
- **Strip — the demo:** the contacts + events domain and the demo pages' content. The strict
  layering keeps this nearly mechanical.

To extend it, follow the **Recipes** in [CLAUDE.md](CLAUDE.md) (new page, new endpoint, new
component) and the architecture tour in [app/README.md](app/README.md).

> Smoother onboarding — a “Use this template” button, an `init` rename script, and a `docs/STRIP.md`
> — is on the [roadmap](TODO.md) (Phase F → 1.0).

## Tests

Both suites are implemented and gate CI, kept at par with the app — every endpoint has a
behaviour test *and* a load scenario.

- **`e2e/`** — Playwright browser tests (Chromium/Firefox/WebKit). `cd e2e && npm ci && npm test`.
- **`load-tests/`** — k6 throughput/latency suite. `cd load-tests && ./run.sh --quick`.

Each directory's `README.md` is the operating manual; its `PLAN.md` is the design rationale.
