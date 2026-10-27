# odin-htmx-starter

A **starter** for server-rendered web apps: an **Odin** backend rendering HTML with **HTMX**, a
**SQLite** or in-memory store, and browser, load and crash-drill suites, all in one self-contained
binary. A site is a **profile**, a selection of features on a shared platform; pick one, rename it,
replace the example features with yours.

**Live demo: [odin-htmx.alexh95.com](https://odin-htmx.alexh95.com/)** — the whole thing, served by
one ~3 MB binary on a shared-cpu-1x machine.

The `skeleton` profile (a contacts/events console with a multi-style theme library) is the **worked
example** that proves the patterns, and the performance witness the platform is held to; the
`minimal` profile is the one-page starter. You keep the platform (request path, crash guard, store,
observability, theming, build / CI / deploy / test harness) and write features.

```
odin-htmx-starter/
  app/          the platform, the features, their stores and the profiles: see app/README.md
  e2e/          Playwright specs per feature, chosen by the profile: see e2e/README.md
  load-tests/   k6 scenarios per feature, and the parity gate: see load-tests/README.md
  tools/        check (what the compiler can't see), bundle (the assets), drills (crash and
                shutdown drills), baseline (old releases for the parity gate), init (rename), og
  tests/        parity-waivers.txt: the waivers of the parity rules, each with its reason
  docs/         PLAN.md (the plan), design/ (decisions), spikes/, PHILOSOPHY.md (root), DATA.md
  infra/        PLAN.md: hosting, CI/CD, and the Fly operator steps
  deploy/       docker-host/: deploy to any Linux box with Docker, over SSH
  build.sh      build.bat: the one place a profile's build flags live
```

## Quick start

Needs the Odin compiler and, for a SQLite profile, **a C toolchain** (MSVC Build Tools on Windows,
`clang` on Linux, Xcode CLT on macOS): `prepare` compiles the SQLite amalgamation. See
[app/README.md](app/README.md) → *Run it* for the per-OS setup.

```sh
app/prepare.sh              # once: htmx, SQLite, the profiles' bundled assets   (app\prepare.bat)
app/run.sh                  # builds skeleton and serves http://127.0.0.1:8080  (app\run.bat)
PROFILE=minimal app/run.sh  # the minimal profile
./build.sh skeleton -o:speed   # just build: app/bin/skeleton                   (build.bat)
```

## Using this as a starter

1. **Use this template.** Click **“Use this template”** on GitHub to create your own repo (or just
   clone this one).
2. **Compose it.** From the repo root, see what there is, then pick:
   ```sh
   odin run tools/init -- --list
   odin run tools/init -- your-name --features notes,about --repo https://github.com/you/your-name --site https://your.domain
   ```
   With a selection (`--features a,b`, or `--profile minimal|skeleton|lab`, and the families
   `--store`, `--identity`, `--client`, `--theme`), init writes one profile, `app`, from the features
   you picked (their dependencies and a root page join them), deletes the rest, points the scripts
   and CI at `app`, and renames: the Fly app, the Docker-host deploy and the test-package names, the
   brand in `app/cmd/app/brand.odin` (wordmark, title suffix, home title, repo, site URL), the
   favicon's label and the social card's source, and it blanks the two search-engine ownership
   tokens (a fork verifies its own site). It first builds and tests the result in a scratch copy
   (`--no-verify` skips that), applies every edit or none, and ends with what's left to do by hand.
   `--explain` and `--dry-run` print the plan and write nothing. Without a selection it only renames,
   keeping every profile.
3. **Grow it.** `odin run tools/init -- --add <feature>` and `--without <feature>` edit the profile
   in place; `--store sqlite --profile app` swaps a family. A feature is a folder,
   `app/features/<f>/`, with its store in each family under `app/stores/`, mounted by one line in a
   profile's `routes.odin`; `odin run tools/check -- all` says when a profile and its features
   disagree.

To extend it, follow the **Recipes** in [CLAUDE.md](CLAUDE.md) (new feature, page, endpoint, store,
profile) and the tour in [app/README.md](app/README.md).

## Deploy

The deployable is one binary in a slim container (`docker build --build-arg PROFILE=…`, `skeleton`
by default; the binary is `/app/server`). [infra/PLAN.md](infra/PLAN.md) covers Fly.io (the
`fly.toml` and the CI deploy job here) and its operator steps; [deploy/docker-host](deploy/docker-host)
runs it on any Linux box with Docker, with the SQLite database on a persistent volume. Linux deploys
need io_uring, which Docker's default seccomp profile blocks: run containers under
`docker/seccomp-io-uring.json`, as `compose.yaml` does. See [infra/PLAN.md](infra/PLAN.md) →
*io_uring platform requirement*.

## Tests

Every endpoint gets a behaviour test *and* a load scenario, and the servers' request counters check
it: `tools/check parity` fails a route either suite never reached (or waives it with a reason in
`tests/parity-waivers.txt`).

- **`e2e/`**: Playwright specs per feature (Chromium, Firefox, WebKit, and a browser-less `api`
  project), tagged with the features they touch and run against whichever profile is built.
  `cd e2e && npm ci && npx playwright install && npm test` (`E2E_PROFILE=minimal` for minimal).
- **`load-tests/`**: k6 scenarios per feature. `cd load-tests && ./run.sh --quick`; `--parity`
  runs the parity gate against the 1.2.0 and 1.1.1 releases (`docs/perf/PARITY.md`).
- **`tools/drills/drills.mjs <profile>`**: crashes of every class (pure ones answer 500 and serving
  goes on; dirty ones exit 70), the watchdog, 10k malformed requests, the shutdown bound, restart
  and the fd ceiling, and the size, memory and boot budgets.
- **Unit tests**: `sh .github/scripts/unit-tests.sh` (every package with tests, leaks fatal);
  `CMD=test ./build.sh <profile>` for a profile's boot checks.

Each test directory's `README.md` is the operating manual.

## License

[zlib](LICENSE) — use it for anything, including commercially, with or without changes. The only
conditions are that you don't claim you wrote the original, that you mark altered versions as
altered, and that you leave the notice in the source. Attribution is appreciated, not required.
