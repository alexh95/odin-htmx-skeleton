# odin-htmx-demo

A proof-of-concept web app — an **Odin** backend with **HTMX** on the front end — with browser
and load test suites.

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

## Tests

Both suites are implemented and gate CI, kept at par with the app — every endpoint has a
behaviour test *and* a load scenario.

- **`e2e/`** — Playwright browser tests (Chromium/Firefox/WebKit). `cd e2e && npm ci && npm test`.
- **`load-tests/`** — k6 throughput/latency suite. `cd load-tests && ./run.sh --quick`.

Each directory's `README.md` is the operating manual; its `PLAN.md` is the design rationale.
