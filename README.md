# odin-htmx-skeleton

A **starter skeleton** for a simple, server-rendered website: an **Odin** backend rendering HTML
with **HTMX**, a **SQLite** store, and browser + load test suites — all in one self-contained
binary. Clone it, rename it, strip the demo, build your thing.

**Live demo: [odin-htmx.alexh95.com](https://odin-htmx.alexh95.com/)** — the whole thing, served by
one ~3 MB binary on a shared-cpu-1x machine.

The bundled app (a contacts/events admin console with a multi-style theme library) is the
**worked example** that proves the patterns — not the product. You keep the scaffolding
(architecture, data layer, theming, build / CI / deploy / test harness) and swap the demo domain
for your own.

```
odin-htmx-skeleton/
  app/          The application: Odin server, views, static assets, run scripts.
  e2e/          Playwright browser tests — see e2e/README.md.
  load-tests/   k6 throughput/latency tests — see load-tests/README.md.
  docs/         PHILOSOPHY.md (root), USE_CASES.md, DATA.md, DATA_IMPL.md, STRIP.md.
  infra/        PLAN.md: hosting, CI/CD, and the Fly operator steps.
  deploy/       docker-host/: deploy to any Linux box with Docker, over SSH.
  tools/        init/ (rename + strip, run once), og/ (the social card's source).
```

## Quick start

Needs the Odin compiler **and a C toolchain** (MSVC Build Tools on Windows, `clang` on Linux,
Xcode CLT on macOS) — `prepare` compiles the SQLite amalgamation. See
[app/README.md](app/README.md) → *Run it* for the per-OS setup.

```sh
cd app
prepare.bat        # once: odin-http submodule, htmx, SQLite          (./prepare.sh on Linux/macOS)
run.bat            # builds and serves http://localhost:8080          (./run.sh elsewhere)
```

See [app/README.md](app/README.md) for the full tour — pages, architecture, endpoints, and
design notes.

## Using this as a starter

1. **Use this template.** Click **“Use this template”** on GitHub to create your own repo (or just
   clone this one).
2. **Rename it.** From the repo root:
   ```sh
   odin run tools/init -- your-name --repo https://github.com/you/your-name --site https://your.domain
   ```
   One pass rewrites the binary, the Fly app, the Docker image, the Docker-host deploy, the startup
   banner and the test-package names; the brand constants in
   [`app/src/views/brand.odin`](app/src/views/brand.odin) (wordmark, title suffix, home title, repo,
   site URL); and the favicon's label and the social card's source. It blanks the two search-engine
   ownership tokens (a fork verifies its own site) and removes the template-only `minimal` CI job.
   It applies every edit or none, and ends with what's left to do by hand. Run `odin run tools/init`
   with no args to see the options (`--wordmark`, `--suffix`, `--repo`, `--site`, `--minimal`);
   delete `tools/init` once you're happy.
3. **Replace the demo with your domain.** What you **keep** vs. **strip**:
   - **Keep — the scaffolding:** the layered packages (`models` / `repository` / `services` /
     `views` / `controllers`), the SQLite layer + migrations, the theme system, the view/component
     helpers, and the build / CI / Docker / deploy / e2e / load harness.
   - **Strip — the demo:** the contacts + events domain and the demo pages' content. The strict
     layering keeps this nearly mechanical.

To extend it, follow the **Recipes** in [CLAUDE.md](CLAUDE.md) (new page, new endpoint, new
component) and the architecture tour in [app/README.md](app/README.md).

Prefer to start from a blank slate? `odin run tools/init -- your-name --minimal` also strips the
contacts/events demo down to a one-page **Notes** starter (the full stack over one entity), keeping
the shell, theme, data layer, and test/deploy harness. It starts a fresh `CHANGELOG.md` and `TODO.md`,
and deletes the Quick start's `app/data.db`, whose schema is the demo's. To strip it by hand instead — or just to see
exactly what's demo vs. scaffold — follow [docs/STRIP.md](docs/STRIP.md).

## Deploy

The deployable is one binary in a slim container. [infra/PLAN.md](infra/PLAN.md) covers Fly.io (the
`fly.toml` and the CI deploy job here) and its operator steps; [deploy/docker-host](deploy/docker-host)
runs it on any Linux box with Docker, with the SQLite database on a persistent volume. Linux deploys
need io_uring, which Docker's default seccomp profile blocks: run containers under
`docker/seccomp-io-uring.json`, as `compose.yaml` does. See [infra/PLAN.md](infra/PLAN.md) →
*io_uring platform requirement*.

## Tests

Two suites, meant to stay at par with the app: every endpoint gets a behaviour test *and* a load
scenario. `load-tests/parity.sh` lists the routes either suite doesn't mention yet.

- **`e2e/`** — Playwright browser tests (Chromium/Firefox/WebKit). CI runs them on every push and
  PR. `cd e2e && npm ci && npx playwright install && npm test`.
- **`load-tests/`** — k6 throughput/latency suite. It runs locally, not in CI: shared runners make
  noisy benchmarks. `cd load-tests && ./run.sh --quick`; add `--strict` to exit non-zero on a
  breached threshold.

Each directory's `README.md` is the operating manual; its `PLAN.md` is the design rationale.

## License

[zlib](LICENSE) — use it for anything, including commercially, with or without changes. The only
conditions are that you don't claim you wrote the original, that you mark altered versions as
altered, and that you leave the notice in the source. Attribution is appreciated, not required.
