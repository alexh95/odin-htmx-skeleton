# odin-htmx-demo

A proof-of-concept web app — an **Odin** backend with **HTMX** on the front end — alongside
its test plans.

```
odin-htmx-demo/
  app/          The application: Odin server, views, static assets, run scripts.
  e2e/          End-to-end (browser) test plan — see e2e/PLAN.md.
  load-tests/   Load/throughput test plan — see load-tests/PLAN.md.
```

## Quick start

```sh
cd app
prepare.bat        # once: clones odin-http, downloads htmx.min.js   (./prepare.sh on Linux/macOS)
run.bat            # builds and serves http://localhost:8080         (./run.sh elsewhere)
```

See [app/README.md](app/README.md) for the full tour — pages, architecture, endpoints, and
design notes.

## Tests

`e2e/` and `load-tests/` currently hold **plans only** (`PLAN.md` in each). They describe how
those suites will be built; the implementations land when explicitly requested.
