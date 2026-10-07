# Changelog

All notable changes to this project are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/); releases are tagged from **1.0.0** on. **Every
behaviour/structure/build change gets an entry under `[Unreleased]`** — see `CLAUDE.md`. Entries
track [Conventional Commits](https://www.conventionalcommits.org): `feat`→Added, `fix`→Fixed,
`refactor`/`perf`/`style`→Changed, removals→Removed.

## [Unreleased]

### Added
- **CI builds and runs the Docker image on every PR** ([#37](https://github.com/alexh95/odin-htmx-skeleton/issues/37)).
  Until now only Fly's builder built it, after the merge. The new `docker` job (host runner) starts
  it through `compose.yaml` under the io_uring seccomp profile and waits for its `HEALTHCHECK`. It
  then curls `/healthz` and `/`, checks it runs as UID 10001, and requires `docker stop` to exit 0 in
  under 3 s. Last, it creates a DB on a fresh `/data` volume as that user.
- **CI checks that the version pins agree** (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). `.github/scripts/check-pins.sh`,
  run first in the build job's Linux leg, fails if the `Dockerfile`'s `ODIN_VERSION`/`ODIN_SHA256`,
  `ci.yml`'s env, the three matrix asset names and the linux digest disagree. It also fails if a
  Playwright image tag differs from `@playwright/test` in `e2e/package-lock.json`. Sweeps used to
  check these by hand.

### Changed
- **CI's apt step switches to HTTPS mirrors when the runner's mirror won't answer** (part of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). The 1.1.1 retry loop wasn't enough:
  both master runs after it timed out in the same step. Two attempts against
  `azure.archive.ubuntu.com` used up the 10-minute budget, so neither run deployed.
  - **Why another mirror:** every failure that day was a plain-HTTP (port 80) fetch from a
    Playwright container. HTTPS downloads in the same jobs (npm, the Odin tarball) worked, and the
    azure mirror has no HTTPS.
  - **What the script does now:** `apt-install.sh` tries the configured mirror once, then rewrites
    every Ubuntu source (both the one-line and the deb822 format) to HTTPS. Canonical's own
    `archive`/`security.ubuntu.com` comes first, then `mirrors.edge.kernel.org`.
  - **Faster attempts:** in-apt timeouts are 15 s with one retry, so a dead mirror fails an attempt
    quickly.
  - **Timeouts:** apt steps now get 15 min and jobs 25.
  - **Tested** locally against stub `apt-get`s that accept only one of the two fallback mirrors,
    through the `APT_SOURCES` override.
- **CI runs with a read-only token, and a new push to a PR cancels the old run** (rest of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). `permissions: contents: read` is set
  for the whole workflow; no job needs more, the deploy included (it uses `FLY_API_TOKEN`). Branch
  pushes get a concurrency group per run, so they are never cancelled or queued.
- **CI runs on `main` as well as `master`, and deploys from the repo's default branch** (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). A fork that renamed its default
  branch used to lose CI and its deploy without a word.
- **The Odin download is checked against its SHA-256** in CI and the `Dockerfile` (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)), like htmx and SQLite already were.
  The release's published digests sit next to `ODIN_VERSION`: `ODIN_SHA256` in `ci.yml`'s env and
  the `Dockerfile`, and one `odin_sha256` per build-matrix asset. The build job's Odin cache key now
  includes the digest.
- **Browser-less e2e specs run once, not once per engine** (part of
  [#42](https://github.com/alexh95/odin-htmx-skeleton/issues/42)). `events` and `persistence` never
  open a page, so they're now the `api` project in `playwright.config.ts`, which CI runs on the
  chromium shard. A full local run is 215 tests (71 per engine + 2), down from 219.
- **e2e shards no longer compile SQLite on every run** (part of
  [#43](https://github.com/alexh95/odin-htmx-skeleton/issues/43)). They cache `prepare`'s outputs
  (`htmx.min.js`, `app/vendor/sqlite`), keyed on `prepare.sh` (the pins and compile flags) and the
  image's distro, and `global-setup` skips `prepare` on a hit. That saves about a minute per shard.
  The build job still runs `prepare` from scratch on all three OSes. The Odin cache keys stay as
  they are: the containers write gzip archives and the host zstd, so one entry can't serve both.
  `ci.yml` also notes how a private fork can drop the macOS (10×) or Windows (2×) leg.

### Fixed
- **`docker compose up` can start the server** ([#38](https://github.com/alexh95/odin-htmx-skeleton/issues/38)).
  odin-http's event loop needs io_uring, which Docker's default seccomp profile has blocked since 25.0,
  so the root `compose.yaml` aborted at startup. New `docker/seccomp-io-uring.json` is Docker's default
  profile plus `io_uring_setup`/`_enter`/`_register`, and `compose.yaml` runs under it. The requirement
  is noted in the `Dockerfile` and `compose.yaml`.
- **The container stops cleanly, runs as non-root and reports its health**
  ([#39](https://github.com/alexh95/odin-htmx-skeleton/issues/39)).
  - **`STOPSIGNAL SIGINT`:** the server only handles SIGINT, so `docker stop`'s SIGTERM was ignored
    by PID 1 and every stop waited 10 s for a SIGKILL, skipping `repo_close`.
  - **`USER 10001`:** `/data` is created owned by it, so a fresh volume there is writable.
    **Upgrading:** a volume that already holds root-owned files (apollo-11's `odin-htmx-data`), or a
    Fly volume, needs a one-time `chown -R 10001:10001` on it before the new image can open the DB.
  - **`HEALTHCHECK`** on `/healthz`, through bash's `/dev/tcp`, so it adds no package.
- **e2e servers can't pick up the wrong port or your `data.db`**
  ([#41](https://github.com/alexh95/odin-htmx-skeleton/issues/41)). Every server the suite starts
  now goes through `helpers/server.ts`. It takes a port the OS picks, not a fixed base, which two
  runs at once could share; on Windows the second server binds a taken port silently, so a stale
  build got tested. It also pins the env (`PORT`, `DB_PATH=:memory:`, an empty `BIND_ALL` and
  `SITE_URL`), and fails fast with the server's own output if it exits. `persistence.spec.ts`
  restarts on a fresh port. Checked by running the suite with `PORT`, `DB_PATH`, `SITE_URL` and
  `BIND_ALL` exported: it passed, and the exported `DB_PATH` was never created.
- **e2e's `global-setup` no longer hides a failed `prepare`** (part of
  [#42](https://github.com/alexh95/odin-htmx-skeleton/issues/42)). It used to warn and carry on, so
  the build could link a stale SQLite or fail later with a less useful error. It now skips `prepare`
  when htmx, the SQLite stamp and a newer library already match `prepare.sh`'s pins, so a re-run on
  Windows needs no MSVC prompt. When `prepare` does run, its failure stops the suite.
- **Stale notes in the e2e docs, `ci.yml` and the `Dockerfile`** (part of
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). `e2e/PLAN.md` described 31 tests in
  six files run by a `serve.mjs` launcher, and its CI section described a browser install the CI
  doesn't do. `e2e/README.md` left out `seo` and `responsive`. Both said CSS is served from disk.
  The `Dockerfile` header spoke of on-disk static assets, and `ci.yml` of "the planned SQLite layer".
- **The minimal starter covers every endpoint in both suites**
- **The minimal starter's write path and `/about` are in both suites**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). `init --minimal` now also installs
  a `POST /notes` load scenario (`notes.js`) and an `/about` e2e spec. The spec checks that the page
  renders as the current nav item, that the nav reaches it with a boosted swap, and that its repository
  link matches the JSON-LD. The starter's `pages.js` now loads `/about` as well as `/`.
- **The social card has a source: `tools/og/og.html`**
  ([#28](https://github.com/alexh95/odin-htmx-skeleton/issues/28)). `og.png` was a bare image showing
  the upstream's name and domain, with no way to redraw it. The 1200×630 HTML recreates it, and its
  header has the one-line re-render through the Playwright the e2e suite already installs
  (`npx playwright screenshot`), so there's no new dependency. `init` writes the fork's wordmark,
  name and domain into it.
- **`init --minimal` starts the fork's own CHANGELOG and TODO**
  ([#29](https://github.com/alexh95/odin-htmx-skeleton/issues/29)). The 700-line upstream changelog
  and 260-line backlog were left in place, and `CLAUDE.md` tells an agent to work from that backlog.
  They're replaced with short starters (`tools/init/minimal/`). The changelog records the template
  release the fork started from, read from the upstream changelog. The TODO lists the remaining
  make-it-yours steps.
- **`load-tests/run.sh --strict`**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)). Without it the driver still records
  a breached threshold and carries on (a sweep exists to find the knee). With it, the run lists the
  failed `scenario@VUs` and exits 1, so it can gate. Checked: `P95=0.001 ./run.sh --quick --strict
  static` exits 1, and exits 0 without `--strict`.
- **`load-tests/parity.sh`** ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)) lists
  every route in `routes.odin` and whether `e2e/tests/` and `load-tests/scenarios/` mention its path,
  so the "both suites" rule can be checked rather than just stated. It's a text search, not coverage.
  It reports and exits 0; `--strict` exits 1 on a gap, for when it can gate. Today it finds 26
  literal routes: 6 with no e2e mention (the `/ui/*` fragments, reached by clicks), 14 with no load
  scenario. On the minimal starter, 0 and 2 (`/healthz`, `/favicon.ico`).

### Changed
- **The README says what the test suites enforce**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)). It claimed both suites "gate CI".
  CI runs e2e only; the load suite is local, so it says that now and points at `--strict`. The e2e
  line gains `npx playwright install`.
- **README and `docs/STRIP.md` match the code**
  ([#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). The README listed "three brand
  constants" for `init` (it's five, plus two blanked tokens, the favicon and the card). It now shows
  `--site` in the example and lists every option. It gains a **Deploy** section linking
  `infra/PLAN.md` and `deploy/docker-host`, with the io_uring requirement, and the layout block lists
  `infra/`, `deploy/` and `tools/`. `init`'s usage text now lists `--site`. `docs/STRIP.md`'s
  keep-lists cover the 1.1.0 crawler contract: the SEO handlers and routes, `robots_txt`'s
  demo-specific `Disallow` list, `og.png` and its source, `BRAND_HOME_TITLE`, and the generic
  `seo.spec.ts`/`seo.js`. It also covers the CI `minimal` job and the stale `data.db`.
- **Per-id load-test URLs are tagged with a route `name`**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)): `POST`/`DELETE /contacts/:id` in
  `write.js` and `mixed.js`, and `GET /contacts/:id` in `detail.js`. Untagged, each id was its own k6
  time series (100k–200k over a full run), and k6's memory grew on the machine the server shares.
- **`deploy/apollo-11` is now `deploy/docker-host`, a generic self-host example**
  ([#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). It was the only deploy with
  persistence, and it was wired to one home server: an ssh alias, `/mnt/fast-storage`, and an
  external `npm` network. `deploy.sh` now takes `HOST` (required), plus `NAME`, `REMOTE_DIR`,
  `HOST_PORT`, `VOLUME` and `PROXY_NET`, and writes them to an `.env` beside `compose.yaml`. The
  reverse-proxy network is an opt-in overlay (`compose.proxy.yaml`). The container now stops on
  SIGINT, the only signal the server shuts down cleanly on; as PID 1 it ignored Docker's SIGTERM
  until the SIGKILL, skipping the WAL checkpoint. The README covers backups. `init` renames the
  defaults. To keep an existing deployment's container and data, set `NAME`, `REMOTE_DIR`,
  `PROXY_NET` and `VOLUME`. Compose named the old volume `<project>_<volume>`, so check
  `docker volume ls`.
- **Deploy docs cover the io_uring seccomp profile and a non-root image**
  ([#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44),
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). `deploy/docker-host` ships
  `docker/seccomp-io-uring.json` (Docker's default profile plus io_uring) when the repo has it and runs
  the container under it, falling back to `seccomp=unconfined`. The README and `infra/PLAN.md` name
  the profile. For an image that runs as UID 10001, `fly.toml`, `infra/PLAN.md` and the docker-host
  README give the one-time `chown -R 10001:10001 /data` for a root-owned volume. On Fly, that's a
  first deploy with the mount but no `DB_PATH`, then `fly ssh console`.
- **`infra/PLAN.md` describes the repo as it is**
  ([#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). Gone: the on-disk `static/`, the
  bookworm Dockerfile sketch, "prepare clones odin-http at latest", the stale odin-http/Odin pins,
  and "CI smoke stands in for e2e". The operator steps use the name `init` sets and the current
  repo instead of the upstream's. The deploy token gets a 90-day expiry (`-x 2160h`) and a rotation
  note, instead of `-x 999999h`. New sections: the **io_uring platform requirement**, **Persistence
  on Fly** (a volume is one machine's, so `fly scale count 2` means two databases; a deploy restarts
  the machine), and rollback. `fly.toml` gains a commented `SITE_URL` and points at the volume
  caveats.

### Fixed
- **A fork's e2e no longer fails on the blanked ownership tokens**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The `BingSiteAuth.xml` and
  IndexNow tests decided whether to run by looking for `/data` in the sitemap, so after `init` blanked
  both tokens they still ran and got 404. They now read `BING_SITE_AUTH` / `INDEXNOW_KEY` from
  `brand.odin` and skip only when the token is empty; when one is set they also check the served
  value against it. The `*.fly.dev` redirect test skips while `SITE_URL` is still an
  `*.example.com` placeholder, the case #25 changes.
- **`init` leaves almost nothing of the upstream's identity behind**
  ([#28](https://github.com/alexh95/odin-htmx-skeleton/issues/28)). It now also rewrites
  `BRAND_HOME_TITLE` (a "<name> — built with Odin + HTMX" stand-in), the JSON-LD code name, the
  favicon's label, the social card source, the README's live-demo line (removed), the upstream's
  canonical URL wherever the docs quote it, `app.css`'s header, `infra/PLAN.md`,
  `load-tests/README.md` and the docker-host deploy. It rejects a backslash in the brand values (they
  land in Odin string literals). The "Next" list names what only the fork can do: the home title, a
  real `SITE_URL`, re-rendering `og.png`, the favicon artwork, the ownership tokens, the first deploy,
  and the LICENSE notice. A closing read-only scan lists every file that still names the upstream.
  `grep -rE 'odin-htmx|alexh95|apollo-11'` outside CHANGELOG/TODO/LICENSE/`tools/` after
  `init acme-site` went from 39 lines in 12 files to 3 in 3; after `--minimal`, from 38 in 11 to 2
  in 2. What's left is one measurement record in `RESULTS.md` and two lines in files this change
  doesn't touch.
- **`init` removes the template-only `minimal` CI job from the fork**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The job runs `tools/init` on the
  checkout to keep the `--minimal` templates honest, so in a fork it failed as soon as `tools/init`
  was deleted (as the README says to), or overwrote a minimal fork's own code. `deploy` needs every
  job, so the deploy was blocked too. Both variants now delete the job and its comment block and drop
  it from `deploy`'s `needs`. `init` fails, changing nothing, if it can't find the job or if
  `ci.yml` still runs `tools/init` afterwards.
- **A minimal fork's CI build job passes its smoke test**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The step curls `/api/search` and
  `POST /contacts`, which the starter doesn't have, so every leg failed with "api/search returned
  404". `init --minimal` swaps those lines for the starter's `/about` and `POST /notes`.
- **The README's order of steps no longer crashes a minimal fork**
  ([#26](https://github.com/alexh95/odin-htmx-skeleton/issues/26)). The Quick start's `run` creates
  `app/data.db` with the demo's schema; after `init --minimal` the starter's migration runner counted
  it as up to date and the app exited with `no such table: notes`. `init --minimal` now deletes
  `app/data.db` and its `-wal`/`-shm` files (a dev store, reseeded on the next run) and says so before
  asking to proceed. A database elsewhere (`DB_PATH`) is named in the "Next" list. The migration
  check that would catch this at boot is #21.
- **`./run.sh --quick` works in a minimal fork again**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). The load driver kept a hard-coded
  scenario list that `init --minimal` was meant to trim, but the line it matched had changed in 1.1.0,
  so the trim silently missed and the run died at the first deleted scenario. `run.sh` now runs every
  `scenarios/*.js` by default, so there is no list to keep in step.
- **`init` fails loudly instead of skipping an edit that no longer applies**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). It now plans every change in
  memory (`tools/init/plan.odin`) and writes only if all of them apply; otherwise it lists each miss
  and changes nothing. A targeted replacement must match. In the name-token pass, every listed file
  must exist and every token must hit somewhere; a file left with nothing to rename is only noted. A
  second run says the checkout is already renamed. An audit of every existing replacement found two misses: the `run.sh` scenario list
  (above) and `app/README.md`, which was in the rename list with nothing to rename.
### Changed
- **The repository's SQLite plumbing is one shared file.** `repository/db.odin` holds the
  connection, lock, migration runner and bind/scan helpers, unchanged between the demo and the
  `--minimal` starter; `repo.odin` keeps only the app's wiring (migrations, statements, seed). A fix
  to the plumbing now lands in both variants at once.

### Fixed
- **Request bodies and text fields are size-limited**
  ([#13](https://github.com/alexh95/odin-htmx-skeleton/issues/13)). A 50 MB `name` used to be
  stored and then re-sent by every page that listed it. A new `controllers.front` middleware
  (`middleware.odin`, shared with `--minimal`) reads every body before routing, capped at 64 KiB:
  past that it answers 413 without reading it. Handlers get the parsed form from `request_form()`,
  so they are plain synchronous code. `validate_contact` caps names at 100 characters and emails at
  254, the minimal starter caps a note at 500, and each input carries the same `maxlength`. e2e:
  `limits.spec.ts`.
- **The `--minimal` starter passes `odin check -vet`** (part of
  [#29](https://github.com/alexh95/odin-htmx-skeleton/issues/29)): `notes.odin` dropped an unused
  `import "core:c"`.

## [1.1.1] - 2026-10-07

A patch release with two changes:
- **Search highlighting** now marks exactly what the search matched, including text whose lowercase
  form has a different byte length (`İ`, `ẞ`, invalid UTF-8).
- **CI** retries flaky Ubuntu mirror fetches and puts a timeout on every job.

Nothing else changed since 1.1.0. A fork started from 1.1.0 or earlier should take the new
`write_highlighted` in `app/src/views/views.odin` (it replaces the old one, with its file-private
`match_ci` helper). The CI change is optional: `.github/scripts/apt-install.sh` plus the matching
`ci.yml` edits.

### Changed
- **CI survives Ubuntu mirror outages, and no job can run for hours** (part of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). The three `apt-get install clang …`
  steps failed CI three times on 2026-10-07, each before a single test ran. One hung for 4 min until it
  was cancelled by hand; twice `azure.archive.ubuntu.com` (and once `security.ubuntu.com`) timed out
  from the runner. They now go through one script, `.github/scripts/apt-install.sh`. It retries the
  whole update+install up to 5 times with 20–100 s backoff, because `Acquire::Retries` alone only
  retries one fetch within seconds. It uses `sudo` only when not root, so the host runner and the
  Playwright containers share it. Every job also gets a `timeout-minutes` (20; 30 for the Fly deploy,
  whose remote builder has stalled for about 10 min before), and each apt step gets 10. A hang now
  fails in minutes instead of running to GitHub's 6 h default. Tested locally with stub
  `apt-get`/`sudo`: an install that fails once is retried and succeeds, both as root and through sudo.

### Fixed
- **Search highlighting could mark the wrong characters.** `write_highlighted` found matches in a
  lowercased copy of the text, then cut the original with that copy's offsets. Lowercasing can change
  a string's byte length: `İ` lowers to `i`, `ẞ` to `ß`, and an invalid UTF-8 byte to the 3-byte
  U+FFFD. So searching `İ` marked `in`, and a stored `Straẞe` found by `straße` was marked as
  `Straẞ`. It now walks the original text rune by rune, applying the same per-rune
  `unicode.to_lower` that `services.contains_ci` matches with, so the marks cover exactly what the
  search matched. e2e: two request-level cases in `search.spec.ts` cover a query and stored text whose
  lowercase changes length; both failed before the fix. No load-test change: the endpoint and its cost
  are the same.

## [1.1.0] - 2026-10-07

The skeleton now ships the **crawler contract** every new site needs, so a fork can be found:
one canonical origin (`SITE_URL`, set by `init --site`), `robots.txt`, a `sitemap.xml` derived from
the nav, canonical and social-card tags, JSON-LD, a root `favicon.ico`, and opt-in Bing/IndexNow
verification. All of it is ported into the `--minimal` starter and covered by both the e2e and the
load suites. The project is now licensed **zlib**. Two fixes: clicks are no longer lost while an
htmx swap runs ([#8](https://github.com/alexh95/odin-htmx-skeleton/issues/8)), and the home page's
`<title>` and `og:title` now agree. Every pin is current: Odin `dev-2026-10`, htmx `4.0.0` final,
Debian 13 `trixie`, SQLite `3.53.4`, Playwright `1.63.0`, and the GitHub Actions on their Node 24
majors. Nothing breaking for a fork: the additions are opt-in or derived from what's already there.

### Changed
- **Dependency sweep — every pin checked against upstream; one moved.**
  - **Odin `dev-2026-09` → `dev-2026-10`** (`ci.yml`'s `ODIN_VERSION` and all three matrix asset
    names, the `Dockerfile`). The assets were downloaded before landing: every name resolves, every
    SHA-256 matches the release's published digest, and the layouts are unchanged (the Windows zip
    still unpacks to `dist/`; each tarball still has one top-level dir for `--strip-components=1`).
    The release drops macOS *Intel* builds, which doesn't touch the matrix — its macOS leg is arm64.
    No source change was needed. On Windows it does change the linker: Odin now links with its own
    bundled `radlink` instead of MSVC's `link.exe`. It links the `/MT` `sqlite3.lib` cleanly, and the
    three comments that named `link.exe` (`ci.yml`, `app/README.md`, `run.bat`) were corrected. The
    MSVC Build Tools are still required, for `cl` and for the CRT/SDK libraries Odin links against.
    The release's compiler work also shows up here: a debug build of `app/src` went from 0.48 s to
    0.27 s on the same machine, and the `-o:speed` binary shrank by ~10 KB.
  - **Checked and already current:** odin-http `fac113f` (upstream `main`), htmx `4.0.0` (the newest
    4.x), SQLite `3.53.4`, Playwright `1.63.0` (and its `v1.63.0-jammy` image), `actions/checkout@v7`
    (7.0.1), `actions/cache@v6` (6.1.0), `actions/upload-artifact@v7` (7.0.2 came out today; the
    major tag already picks it up), `ilammy/msvc-dev-cmd@v1.13.0`, and `setup-flyctl` at SHA
    `ed8efb33` (still tag 1.6 and upstream `master`). The Debian base floats on `trixie-slim`.
  - Verified on Windows 11 (MSVC 14.51) with the `dev-2026-10` release: a fresh `prepare.bat` (the
    pinned htmx and SQLite downloads still match their SHA-256s), clean `-warnings-as-errors` builds
    (debug and `-o:speed`), all 213 e2e tests (71 each on chromium, firefox and webkit), and the
    `tools/init --minimal` starter built and run through its own e2e (19 passed; the 3 skips are by
    design: the two per-deployment verification files `init` blanks, and a demo-copy check). Linux
    and macOS are CI's.

### Changed
- **Dependency sweep — every pin checked against upstream; one moved.**
  - **Playwright `1.62.1` → `1.63.0`** (`e2e/package.json` + lockfile, and both CI container image
    tags — `mcr.microsoft.com/playwright:v1.63.0-jammy` is published, so the npm package and the
    image move together as they must). The lockfile also loses its `fsevents` entry: `playwright`
    1.63.0 no longer declares that optional dependency, so the drop is upstream's, not npm pruning a
    macOS-only package on a Windows install. Nothing in the release affects this suite — its new APIs
    (test locks, `locator.visible()`, frame-agnostic `frameLocator()`) are additive, and its one
    removal, Ubuntu 20.04 support, doesn't touch the `jammy` image.
  - **Checked and already current:** Odin `dev-2026-09` (still the latest release), odin-http
    `fac113f` (upstream `main`), htmx `4.0.0` (the newest 4.x; npm's `latest` tag is the 2.x line),
    SQLite `3.53.4` (no newer release), `actions/checkout@v7` (7.0.1), `actions/cache@v6` (6.1.0),
    `actions/upload-artifact@v7` (7.0.1), `ilammy/msvc-dev-cmd@v1.13.0`, and `setup-flyctl` at SHA
    `ed8efb33` (still tag 1.6 and upstream `master`). The Debian base floats on `trixie-slim`.
  - **The CI containers stay on `jammy` deliberately.** Playwright now also ships `noble` (24.04) and
    `resolute` (26.04) images, but moving would change the e2e jobs' OS and their apt `clang`
    (14 → 18) along with the browsers — the same rule the Debian base follows: leave a release when
    its standard support ends, in a change of its own. Logged in `TODO.md`.
  - Verified on Windows 11 (MSVC 14.51): a fresh `prepare.bat` (the pinned htmx and SQLite downloads
    still match their SHA-256s), a clean `-warnings-as-errors` build on the `dev-2026-09` release, and
    all 213 e2e tests — 71 each on chromium, firefox and webkit — on Playwright 1.63.0.

### Fixed
- **Clicks were lost while an htmx swap ran** ([#8](https://github.com/alexh95/odin-htmx-skeleton/issues/8)).
  `htmx-config` turned `transitions` on globally, so *every* swap — a validation message, a search
  result, a toast — ran inside `document.startViewTransition()`, and for as long as a view transition
  runs, Chromium hit-tests the whole page to `<html>`. A click whose mouse-up landed in that
  window (~250 ms of default crossfade) never reached its target. The easy way to hit it: type in
  the `/forms` email field, then click the theme picker — the mouse-down blurs the field, its
  `change` trigger validates, and that swap's transition took the mouse-up; the picker needed a
  second click. Now only the boosted brand + nav links run a view transition, opting in with
  `hx-swap="innerHTML transition:true"`: a page that is being replaced can afford the dead window,
  a fragment swap that leaves the rest of the page live cannot. Fragments lose nothing visible —
  each already has its own CSS entrance animation. The alternative the issue floated,
  `::view-transition { pointer-events: none }`, was tried first and does not help: Chromium still
  routes the hit to `<html>`. One side effect: back/forward no longer crossfade, since htmx 4 takes a
  history restore's transition from the global flag alone. Ported to the `--minimal` templates.
  e2e: a real press on the picker (`mouse.down()`, ~100 ms, `mouse.up()`) that blurs the email field
  must open it — `locator.click()` waits a transition out, which is how the suite missed this; a
  `startViewTransition` counter pins a fragment swap at zero transitions and a boosted navigation at
  one, so the cause is caught in every engine, including those that don't drop the click; and the
  minimal starter's spec presses the picker right after adding a note. No load-test change: no
  endpoint changed, and the pages differ only in a few bytes of htmx attributes.
- **`<title>` and `og:title` disagreed on the home page.** The previous pass gave `/` a title that
  names the project, but left `og:title` on the `"<page> · <brand>"` shape — so the page offered
  "Dashboard · Odin + HTMX" as its other name, and a crawler weighing two names for one page may
  print either. Both now resolve through a single `head_title` proc in `layout`, so they cannot drift
  apart again, and `seo.spec.ts` asserts they agree on every page in the sitemap. Ported to the
  `--minimal` templates, which carried the same mismatch.

### Added
- **The home page now says what the site is.** Its `<h1>` read "Dashboard" — the nav item, not the
  product — while `<title>`, `og:title` and the JSON-LD `name` all named the project; and the whole
  page carried ~120 words, every one of them a caption on a stat card or a link tile. Bing had
  crawled it and declined to index it ("known to Bing but has some issues"), which is the same thing
  a reader arriving from a search result experiences: a wall of widgets and no answer to "what is
  this". So:
  - the heading names the stack (**"A server-rendered web stack in one binary"**), agreeing with the
    title rather than competing with it;
  - the overview keeps its own `<h2>`, where "Overview" describes the *section* — which is what it
    was always describing;
  - a closing prose block explains the mechanism (rendered by Odin procedures, embedded assets, HTMX
    fragments, SQLite linked in). Deliberately **not** the About page's wording: two pages restating
    each other are two thin pages, so this one covers the mechanism and About covers the project.
  - the meta description was realigned with the title for the same reason.
  Reuses the About card's classes (`.card.about`, `.about-lede`, `.about-stack`) — no new CSS. e2e:
  the home `<h1>` is cross-checked against the app's own rendered nav label rather than a hardcoded
  string, so it holds for the `--minimal` starter too, and the prose block is asserted to carry real
  text. Load scenarios already cover `/` (`pages.js`, `mixed.js`); the page only got bigger.

### Added
- **How the site presents itself in search results.** It reached page one, and the result showed a
  placeholder icon, the site name "alexh95" and the title "Dashboard · Odin + HTMX" — three separate
  defaults, each with its own documented lever:
  - **`GET /favicon.ico`** — a real 16/32/48 multi-size `.ico`, rendered from the existing
    `favicon.svg` and embedded via `#load`. Crawlers look for it at the *site root* (not `/static`)
    and are far more reliable with a raster icon than an SVG; the SVG link stays for browsers, so
    each client takes what it prefers.
  - **`WebSite` JSON-LD on the home page**, with `name` matching `og:site_name`. Absent it, the site
    name is derived from the hostname — which on a subdomain is the bare registrable name, hence
    "alexh95" rather than the project. Emitted **only** on the home page: that is where Google reads
    it, and repeating it elsewhere is a conflicting signal at best.
  - **`BRAND_HOME_TITLE`** — the home page's `<title>` now stands alone instead of taking the
    `<page> · <brand>` shape, because that page is the result shown for the site as a whole and
    "Dashboard" describes a nav item, not the product. Interior pages keep the suffix.
- All three are **skeleton functionality, not deployment config**, so unlike the verification tokens
  they are ported into the `--minimal` templates too: every site wants a favicon a crawler can use
  and its own name in results.
- Four e2e cases cover them, including that `WebSite` appears on the home page *only*, that the ICO
  magic bytes are real, and that `WebSite.name` and `og:site_name` agree — they are trusted over the
  hostname fallback precisely because they agree, so a drift between them is a regression.

### Added
- **IndexNow — `GET /<key>.txt`.** One key push-notifies Bing, Yandex, Seznam and Naver that a URL
  changed instead of waiting to be re-crawled. Ownership is proved by serving the key back as plain
  text at its own path, so `views.INDEXNOW_KEY` (brand.odin) is public by design — the same
  per-deployment identity as `BING_SITE_AUTH`, blanked by `init` for the same reason, and an unset
  key means **the route is never registered at all**.
  The path *is* the key, so the route pattern is built at startup rather than written literally, and
  the dot is escaped (`%%.`): unescaped, a Lua pattern reads `.` as *any character* and would hand
  the key out from near-miss paths. Both the exact path and that near-miss are asserted in
  `seo.spec.ts`, along with byte-exact equality of the body — the engines compare it verbatim, so a
  trailing newline would fail the ownership check.

### Added
- **`LICENSE` — zlib.** There was none, so the default was *all rights reserved*, which flatly
  contradicted a repo whose pitch is "clone it, rename it, build your thing". zlib is the most
  permissive of the common licences that still asks altered versions to say they are altered —
  exactly the ask of a skeleton meant to be cloned and rewritten. Deliberately **not** mirrored into
  the JSON-LD `license` field: `views.odin` is shared with the `--minimal` templates every fork
  starts from, and a hardcoded licence URL there would have each fork asserting a licence its author
  never chose. GitHub's own licence detection is the signal that matters anyway.
- **`GET /BingSiteAuth.xml`** — Bing Webmaster ownership proof, served from the binary. DNS
  verification had cost two wrong record values and a resolver-cache stall; a file the app serves is
  deterministic the moment it deploys, with no propagation or caches in the way.
  `views.BING_SITE_AUTH` (brand.odin) holds the token — per-deployment identity, so it sits beside
  `SITE_URL` rather than in the view. **An empty token 404s the route**, and `init` blanks it, so a
  fork can never advertise someone else's ownership proof. The minimal templates deliberately do not
  carry the route at all: it is deployment config, not skeleton functionality.
  Covered in `seo.spec.ts` (XML shape + a 32-hex token), skipped in variants without a token.
  Not added to the load suite on purpose — a one-shot verification endpoint that search engines hit
  a handful of times ever is not a traffic path, and measuring it would be noise.

### Added
- **Crawler contract — the site can now be indexed.** It previously shipped `<title>`, a meta
  description and `og:title`/`og:description`, but nothing that told a search engine *which* URL a
  page is or where the pages are, and nothing linking the site to its repository:
  - **`views.SITE_URL`** (`brand.odin`, overridable by a `SITE_URL` env var) is the one canonical
    origin. Everything absolute derives from it, so the origin is stated once.
  - **`<link rel="canonical">` + `og:url`** on every page, self-referential and absolute
    (`SITE_URL + active`, the same href the nav marks). Plus `og:site_name`, `og:image` and
    `twitter:card`, and a JSON-LD `SoftwareSourceCode` block tying the site to `BRAND_REPO` so a
    crawler reads one project rather than two unrelated URLs.
  - **`GET /robots.txt`** — allows the pages, disallows the fragment routes (`/ui/`, `/api/`,
    `/search`, `/contacts`, `/validate/`, `/forms/submit`). Those answer with bare HTML built to be
    swapped into a page; indexed alone they are thin near-duplicates competing with the real pages.
  - **`GET /sitemap.xml`** — generated by walking `views.NAV`, so a page cannot be added to the nav
    and silently left out. Both endpoints emit absolute URLs on `SITE_URL`; a sitemap advertising a
    different host than the canonical tag is discarded.
  - **`og.png`** (1200×630, drawn in the project's own palette) embedded via `#load` like every
    other asset and served at a deliberately *unfingerprinted* `/static/og.png` — social platforms
    cache a preview against its URL, so that path has to survive redeploys.
- **`canonical_host` middleware** (`main.odin`): the app answers on both the custom domain and its
  `*.fly.dev` hostname, so a crawler that found both would index the site twice and split its
  ranking signals. A 301 collapses them onto `SITE_URL`, carrying the accumulated authority — a
  canonical tag alone only hints, and only to search engines. Scoped to `*.fly.dev` rather than
  "any non-canonical host" so localhost and LAN development keep working, and **`/healthz` is
  exempt**: Fly's own probe calls it, and a probe that follows a redirect off-host fails the
  deploy rather than the request.
- **`init --site <url>`** — the scaffolding tool now rewrites `SITE_URL` alongside the other brand
  constants, defaulting to `https://<name>.example.com`. Without it every fork would serve
  canonical tags and a sitemap pointing at *this* project's domain, telling Google the fork is a
  copy of someone else's page.
- **The `--minimal` starter ships the same crawler contract.** `init --minimal` replaces
  `routes.odin`, `controllers.odin` and `views.odin` wholesale, so the SEO work had to be ported
  into those templates too — otherwise the variant that exists *to be built on* would be the one
  shipping without canonical tags, robots or a sitemap. `OG_IMAGE_HREF` moved to `brand.odin`
  (which survives the strip) so both variants share one definition. Its sitemap lists whatever its
  smaller `NAV` holds, which is exactly the point of deriving it.
- **e2e `seo.spec.ts` (11 cases) and the `seo` load scenario**, per the both-suites rule: the
  crawler contract is invisible in the UI, so it can rot silently. Covers robots/sitemap content
  and content types, canonical↔og:url agreement per page, absolute `og:image`, JSON-LD *parsing*
  (invalid JSON there is invisible but fatal to crawlers), the PNG magic bytes, and all three
  redirect behaviours including the `/healthz` exemption.

### Changed
- **Named the project consistently `odin-htmx-skeleton`.** The repo, the Fly app and the domain
  said "skeleton" while `README.md`'s H1, the repo tree in `CLAUDE.md`, the `app.css` header and
  the startup banner still said `odin-htmx-demo` — the word a search engine weights most for a
  repo page was the one word that disagreed with itself. `tools/init` loses its now-dead
  `odin-htmx-demo` rename token (nothing matches it any more; `odin-htmx-skeleton` already covers
  every occurrence).
- `README.md` links the live demo, and `CLAUDE.md` gains a **Crawlers / SEO** section recording the
  rules that are easy to break silently: one canonical origin, sitemap/canonical *derived* from
  `NAV` rather than hand-maintained, new fragment routes belong in the `robots.txt` disallow list,
  `og.png` stays unfingerprinted, and JSON-LD is all literal braces so it must use `w()`.

### Changed
- **Dependency sweep — every pin checked against upstream.** Three moved, the rest were already
  current:
  - **Odin toolchain `dev-2026-07a` → `dev-2026-09`** (`Dockerfile` ARG + the CI `ODIN_VERSION` env).
    Two releases in one step. Per the standing warning above the CI matrix, all three hardcoded
    asset names were verified to resolve *before* landing — `dev-2026-09` is regular
    (`odin-linux-amd64-`, `odin-macos-arm64-`, `odin-windows-amd64-`), so the version-only bump is
    safe here; `dev-2026-08` was checked too and is likewise regular.
  - **odin-http `112c49b` → `fac113f`** (8 commits). Six are vendored-OpenSSL churn that cannot
    reach this binary — it never takes odin-http's TLS client path, and `ldd`/`nm` on the built
    binary confirm it links only libc/libm with zero OpenSSL symbols (Fly terminates TLS at the
    edge). The remaining two are small fixes (a client-cookie delete allocator, #114/#117).
  - **Playwright `1.61.1` → `1.62.1`** (`e2e/package.json` + lockfile, and both CI container image
    tags). This unblocks the previous sweep's deliberate hold: it stayed at 1.61.1 only because
    `mcr.microsoft.com/playwright:v1.62.0-jammy` was unpublished. `v1.62.1-jammy` now exists, so the
    npm package and the image move together as they must.
  - **Checked and already current:** SQLite `3.53.4` (the mirror's `master` reads 3.54.0, but no
    `version-3.54.0` release tag exists yet), htmx `4.0.0`, `actions/checkout@v7`,
    `actions/cache@v6`, `actions/upload-artifact@v7`, `superfly/setup-flyctl` at SHA `ed8efb33`
    (tag 1.6). **`ilammy/msvc-dev-cmd@v1.13.0` is no longer a deliberate hold** — upstream has
    published nothing newer, so the pin is simply current; the standing deprecation warning remains.
    The Debian base is the floating `trixie-slim` tag and tracks Debian 13 point releases on rebuild.
  - Verified: clean `-warnings-as-errors` build on `dev-2026-09`, and 51/52 e2e on chromium (the one
    failure is `persistence.spec.ts`, the known sandbox port-reuse race — `Address_In_Use` on
    restart — which passes on CI).
- **htmx `4.0.0-beta6` → `4.0.0`** (the 4.0 final, released 2026-08-28; + new SHA-256 in
  `prepare.sh`/`prepare.bat`). One behaviour change upstream bit us, and it is subtle: an OOB swap
  now **suppresses an empty main swap** by default. htmx computes
  `hasPartials = partialTasks.length || (oobTasks.length && !config.allowEmptySwapAfterOOB)` and
  skips the main swap when it is set — in beta6 only `hx-partial` counted, so an empty body still
  swapped. Delete-from-drawer depends on exactly that shape: `contacts_delete` answers `?from=drawer`
  with an empty body plus one OOB `<tr hx-swap-oob="delete">`, and *closing the drawer is that empty
  swap into `#overlay`*. Under 4.0.0 the drawer stayed open. Fixed with the new `swapEmpty:true` swap
  modifier on that one button (`views_fragments.odin`) rather than the global
  `allowEmptySwapAfterOOB` config — the safer new default holds everywhere else, and the one site
  that relies on the old semantics now says so. The other OOB sites were audited and are unaffected:
  the create form's validation-error toast swaps `beforeend` (an empty fragment appends nothing) and
  `/ui/clear` sends no OOB at all. Every other htmx-4 behaviour the app relies on is unchanged
  (`htmx:after:*` events and `detail.ctx`, `hx-partial`, `hx-boost`, `hx-preserve`, `hx-vals`,
  OOB toasts, `htmx-config`). Note `config.defaultSwapEmpty` was also dropped from the empty-swap
  chain upstream; this repo never set it. Caught by the existing `crud.spec.ts` drawer-delete
  scenario — 51/52 e2e green on chromium (the lone failure, `persistence.spec.ts`, is a local
  harness port-reuse race — the restarted server hits `Address_In_Use` — and fails identically on
  beta6, so it is unrelated to this bump).
- **Odin toolchain `dev-2026-06` → `dev-2026-07a`** (`Dockerfile` ARG + the CI `ODIN_VERSION` env).
  Note the CI matrix's three hardcoded asset names had to change too, and two changed *shape*, not
  just the version substring: upstream's `dev-2026-06` shipped a truncated `odin-macos-arm64-dev-06`
  and an arch-less `odin-windows-dev-2026-06`, while `dev-2026-07a` is regular
  (`odin-macos-arm64-dev-2026-07a`, `odin-windows-amd64-dev-2026-07a`). A version-only bump would
  have 404'd the macOS and Windows legs — all three URLs were verified to resolve before landing.
  Upstream's notable changes here: Linux now defaults to **PIE + full RELRO** and C-vararg handling
  tightened; neither affected this codebase (clean `-warnings-as-errors` build, 156/156 e2e).
- **Dependency sweep — low-risk pass.** Every pin checked against upstream and bumped where safe:
  - **Debian base `bookworm-slim` → `trixie-slim`** (Debian 13.6, both Dockerfile stages — they must
    match for glibc). Bookworm's *regular* security support ended 2026-07-12 (LTS-only from there),
    which made this the time-sensitive one. Brings clang 19 (was 14) and glibc 2.41 (was 2.36).
  - **htmx `4.0.0-beta5` → `4.0.0-beta6`** (+ new SHA-256 in `prepare.sh`/`prepare.bat`). One
    breaking change upstream — `htmx:swap:finally` renamed to `htmx:finally:swap` — which this repo
    never referenced; all seven htmx-4 behaviours the app relies on are unchanged.
  - **SQLite `3.53.3` → `3.53.4`** (amalgamation + new SHA-256; same 3.53 branch, patch only).
  - **GitHub Actions onto their Node 24 majors**: `checkout@v4→v7`, `cache@v4→v6`,
    `upload-artifact@v4→v7`. Note `upload-artifact@v5` is a trap — it advertises Node 24 but still
    declares `using: node20`; v6 is the true minimum. `msvc-dev-cmd` is deliberately **held** at
    v1.13.0 (upstream stale since 2024-03, still Node 20), so one deprecation warning remains by
    design. `setup-flyctl` is no longer floating on `@master` — pinned to SHA `ed8efb33` (tag 1.6).
  - **Checked and already current:** `odin-http` (submodule `112c49b` = upstream HEAD).
  - **Deliberately held: Playwright.** npm has 1.62.0, but the matching CI container image is not
    published yet — `mcr.microsoft.com/playwright:v1.62.0-jammy` 404s (verified against the full
    registry tag list; playwright.dev's docs page claims otherwise but just templates the version
    number in). The npm package and the image tag must move together, so both stay at 1.61.1.
- **Load tests re-run for 1.0** — [`load-tests/RESULTS.md`](load-tests/RESULTS.md) refreshed on the
  current SQLite build (2026-07-01, Ryzen 5800X, `THREADS=1` vs `16`, `:memory:`). Reads scale **~4×**
  (search 4.6×, pages 4.2×, list/mixed 4.0–4.1×, api 3.8×); the `detail` events-JOIN is the worst
  read at **1.9×** and flat past 50 VUs — the single shared connection's exclusive lock, the concrete
  case for per-thread WAL connections. Writes ~2×, `static` ~2.3× (peaks **~2.3 GB/s** over
  loopback), **0% errors through 200 VUs**; a file DB costs **~3×** on writes. The doc now leads with
  SQLite (the current store) and demotes the pre-SQLite in-memory numbers to a historical note.
- **Simpler toast observer.** `watchToasts` (`app.js`) watches `#toasts` directly again instead of the
  whole `document.body` subtree — a workaround that's unnecessary now that `#toasts` is `hx-preserve`'d
  (so it's the same node across boosted navigations). Same behaviour, narrower scope; the toast e2e
  still passes.

## [1.0.0] - 2026-07-01

First tagged release: the project is now a **template-ized starter skeleton** (Phase F). It's a
GitHub *template repository* with a `tools/init` rename script (`--minimal` also strips the demo to a
one-page Notes starter, guarded in CI), a centralized brand, and starter docs
([`README`](README.md) "Using this as a starter", [`docs/STRIP.md`](docs/STRIP.md)). The bundled
contacts/events console — Odin + HTMX + SQLite in one self-contained binary, with a multi-style theme
library, boosted SPA-like navigation, and browser + load suites gating CI — is the **worked example**
you clone and strip, not a product to finish. Everything below shipped continuously to the live demo
pre-1.0; **1.0.0 marks the point it became clone-and-go.**

### Fixed
- **A toast no longer vanishes when you navigate.** A boosted nav swaps the `<body>`, which was
  wiping any live toast along with `#toasts`. `hx-preserve` on `#toasts` keeps the node (and its
  toasts) across the swap, so a toast rides through a page change and retires on its own schedule.
  Pinned by e2e.

### Added
- **`tools/init` — a rename script for starting a new project** (Phase F → 1.0). An Odin program
  (`odin run tools/init -- <new-name>`) that renames the skeleton in one pass across a fixed, audited
  file set: the binary (`demo`), the Fly app + Docker image, the apollo-11 service + volume, the
  `main.odin` banner, the e2e package names, and the three `brand.odin` constants (`--wordmark` /
  `--suffix` / `--repo` override the derived defaults). Name validation + a confirm prompt guard it.
  The tool is itself Odin — the skeleton's tooling stays on the stack it teaches. The repo is also a
  GitHub *template repository* now, and the README's "Using this as a starter" walks the
  use-template → `init` → keep-vs-strip path.
  - `--minimal` additionally **strips the demo to a one-page Notes starter** — the full
    model→repo→service→view→controller stack over a single entity, keeping the shell, theme, data
    layer, and test/deploy harness. It deletes the contacts/events domain, the demo pages, and their
    specs/scenarios, then drops in minimal templates (`tools/init/minimal/`, embedded via `#load`).
    Validated end-to-end: renamed + stripped app builds `-warnings-as-errors`, runs, and passes a
    fresh 4-test e2e suite across all three engines.
  - CI **`minimal` job** guards the templates from rotting: it strips a fresh checkout to the Notes
    starter and runs its e2e (global-setup builds `-warnings-as-errors`, so one job covers compile-
    and runtime-rot, and the rename path too). Chromium only; gates deploy alongside build + e2e.
- **About page** (`/about`) — a content page describing the skeleton (Odin + HTMX + SQLite in one
  binary, the demo as the worked example) with a button linking to the source on GitHub. Added to the
  primary nav (boosted like the rest). The repo URL is a `BRAND_REPO` constant in `brand.odin` —
  point it at your fork — alongside the brand wordmark/suffix; new `info` + `github` icons. e2e: the
  page opens from the nav and the GitHub link is present and safe (`target=_blank`, `rel=noopener`);
  the 390px responsive sweep now covers it too. **51 e2e total.**
- **SPA-like navigation via `hx-boost`.** The brand and primary-nav links are boosted: htmx fetches
  the page, swaps the `<body>`, and pushes history instead of a full document load. Navigating
  between pages no longer re-parses the document, re-evaluates CSS/JS, or re-runs the theme pre-paint
  script (so no flash), and with `transitions` on it crossfades. Server work and bytes are unchanged
  (whole pages are still rendered) — this is a client-side / perceived-speed win, not a throughput
  one. `hx-boost` sits on each link (htmx 4 doesn't inherit it from `<nav>` the way htmx 2 did) and
  is scoped to internal HTML links, so the JSON-API tile and the no-action search/filter forms keep
  their normal behaviour. To stay correct under a body swap, `app.js` hardens its per-node state: the
  toast-retire `MutationObserver` watches `document.body` (stable) instead of the swapped `#toasts`,
  and the dashboard count-up + theme-picker pressed-state re-init on `htmx:after:process` (both made
  idempotent). New e2e: nav swaps in place without a reload and updates the `<title>`; toasts still
  auto-retire after a boosted nav. **49 e2e total.**
- **Events — a second table, related to contacts.** `events(actor_id, target_id → contacts,
  ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`) records interactions *between*
  two contacts. The detail drawer's activity feed is now **real data**: `event_timeline` JOINs the
  events back to contacts to resolve the other party, rendered as a one-click jump (replacing the
  deterministic-fake `service_activity`). Deleting a contact cascades its interactions. New domain
  types (`models.Event`/`Event_Kind`/`Interaction`), seeded deterministically. End-to-end at par:
  model + repository + service + view + e2e + load. New e2e: the FK cascade (delete a contact → its
  interactions vanish); the detail `load` scenario now exercises the JOIN. **42 e2e total.**

### Changed
- **Phase F docs — `docs/STRIP.md` + `USE_CASES.md` re-skin** (Phase F → 1.0). New
  [`docs/STRIP.md`](docs/STRIP.md): a demo-vs-scaffold map and file-by-file walkthrough for removing
  the contacts/events demo by hand, cross-linked to `init --minimal` (the automated version) and the
  CLAUDE recipes. `docs/USE_CASES.md`'s old "flagship (the app's direction)" section is rewritten as
  "the worked example" (built, not a direction to chase), the retired product-depth items (bulk
  actions, a named console) are named as out-of-scope, and the "read first" banner is tightened. With
  these + the template repo, `init`, and `init --minimal`, **Phase F (template-ize) is complete.**
- **Brand/app name centralized for renaming** (Phase F → 1.0). `app/src/views/brand.odin` now holds
  `BRAND_WORDMARK` (the topbar wordmark) and `BRAND_SUFFIX` (the `<title>` / og:title suffix), read
  only by `layout`. Renaming the skeleton's display name is now a two-constant edit instead of
  literals scattered through the views. Output is byte-identical; the remaining name touch-points
  (binary/`fly.toml`/`Dockerfile` names, the `main.odin` banner) are the `init` script's job.
- **Quality pass: dropped a needless indirection, fixed stale copy.** The body-reading handlers that
  need only the response (`contacts_create`, `validate_email_field`, `forms_submit`) now pass `res`
  directly through `http.body`'s user pointer (odin-http's own idiom) instead of each allocating a
  `Form_Ctx` whose `id` they never set; `Form_Ctx` remains only for `contacts_update`, which needs
  the row id. Four user-facing strings that still called the store "in-memory" now say SQLite
  (in-memory is just the default `:memory:` mode; a real deploy persists to a file).
- **Reframed the project as a starter skeleton** (docs only). It's a template you clone, rename,
  strip, and build on — the contacts/events admin app + theme library are the *worked example*, not
  a product to finish. `TODO.md` rewritten around it: a **Phase F → 1.0** "template-ize" roadmap
  (GitHub template, an `init` rename script, brand parameterization, a starter README, a
  `docs/STRIP.md`), a **1.x** of what every new site needs (**auth/sessions/CSRF**, per-thread WAL
  connections, a second entity as an "add your own resource" example), and **stretch** goals
  (a `--minimal` variant, common-need recipes, export/a11y). Product-depth items (bulk actions, a
  named console identity) retired as goals. README + `docs/USE_CASES.md` reframed to match.
- **htmx 2 → 4 (pinned to 4.0.0-beta5).** `prepare.*` now pin htmx exactly — a specific version
  **and a SHA-256 check** (replacing the floating `htmx.org@2`) — same reproducibility discipline as
  `ODIN_VERSION` and the SQLite amalgamation; the embedded copy drops ~51 KB → ~36 KB. Migration
  fixes for htmx 4's breaking changes, all caught by the e2e suite:
  - **Config keys renamed** in the `htmx-config` meta: `defaultSwapStyle` → `defaultSwap`,
    `globalViewTransitions` → `transitions`.
  - **`htmx:load` → `htmx:after:process`** for re-initialising swapped content (range-slider fill).
  - **Form auto-reset moved from `hx-on` to `app.js`.** htmx 4's `htmx:after:request` carries
    `event.detail.ctx` (no `.successful`) and the reset is scoped by `ctx.sourceElement` on
    `form[data-reset-on-success]` — robust whether the form's target is inside it (`#form-result`)
    or elsewhere (`#contact-tbody`), and a child field's validation can't trip it.
  - **Form bodies decode `+` as space.** htmx 4 sends spaces as `+` (the standard); odin-http's
    `body_url_encoded` only percent-decodes, so controllers parse POST bodies with a new `body_form`
    helper (`+`-aware, like `query_decode`). This was the latent bug behind broken creates/edits.
  - **OOB table-row refresh via `<hx-partial>`.** htmx 4's OOB `querySelectorAll` doesn't descend
    into `<template>`, and a response starting with the non-table `<aside>` drops a trailing bare
    `<tr>`; the drawer-edit now wraps the row in `<hx-partial hx-target="#contact-N" hx-swap=…>`.
    Removed the now-dead `oob` arg from `view_contact_row`.
  - **Fingerprinted asset URLs (cache-bust without a query).** The page now links content-addressed
    paths — `/static/app.<hash>.css`, `/static/htmx.<hash>.min.js`, `/static/app.<hash>.js` — instead
    of a `?v=<hash>` query (cleaner, and `htmx.min.js` previously had *no* buster, so Cloudflare
    served a stale htmx after the 2→4 bump until its URL changed). `serve_static` accepts both the
    hashed and bare names; hashed URLs are served `Cache-Control: immutable` (the bytes for that URL
    can't change), bare names keep ETag + revalidation.
- **Docs accuracy pass.** Brought the prose docs up to date with the SQLite store + events: the
  top `README.md` no longer calls the e2e/load suites "plans only" (both are implemented and gate
  CI); `CLAUDE.md`, `PHILOSOPHY.md`, `app/README.md`, the e2e/load READMEs+PLANs, and the
  apollo-11/infra docs now reflect three dependencies (HTMX + odin-http + SQLite), the C-toolchain
  requirement, `DB_PATH`, the exclusive-lock concurrency model, the `data-style`×`data-scheme` theme
  system, the repository split, and the events JOIN.
- **Repository split into common + per-entity files.** `repo_sqlite.odin` → `repo.odin` (the shared
  connection/lock, migration runner, and `exec`/`prep`/`bind_text`/`clone_col`/`scalar_int` helpers)
  + `contacts.odin` (the seven `repo_*`) + `events.odin` (`event_timeline`). Adding a table is now a
  new file + a migration, no churn to the plumbing. Added `repo_close` (finalises statements,
  checkpoints the WAL) wired via `defer` in main.
- **Load tests re-measured for SQLite** ([`load-tests/RESULTS.md`](load-tests/RESULTS.md)). Reads
  still scale with threads but ~3–4× (vs the in-memory store's ~5×) — the v1 single shared connection
  forces an *exclusive* lock on reads too; the new `detail` events-JOIN scales worst (1.9×), the
  measured trigger for per-thread WAL connections. A file DB costs ~2.7× on writes (WAL + fsync) and
  nothing on reads. 0% errors throughout.
- **Persistent SQLite data layer** — replaces the in-memory POC store. The seven `repo_*`
  procedures are reimplemented over SQLite (`src/repository/repo_sqlite.odin`) behind a ~15-decl
  amalgamation binding (`src/sqlite/`); **services, views, controllers, e2e and load suites are
  unchanged** (the whole point of the repository seam). Backend selected by **`DB_PATH`**:
  `:memory:` (default — a real in-RAM SQLite, seeded fresh per boot, gone on exit; what the e2e/load
  suites get, identical isolation to before) or a file path that **persists**. WAL +
  `busy_timeout`/`foreign_keys`/`synchronous=NORMAL`; plain-SQL migrations (`migrations/0001_init.sql`,
  `#load`ed) behind a `schema_version` table; `repo_seed` seeds only an empty store; statements
  prepared once. Concurrency v1: one shared connection under the existing `sync.RW_Mutex` taken
  **exclusively** for every op (a single connection's prepared statements can't be shared across
  concurrent readers — parallel reads return with per-thread WAL connections, deferred to load-test
  evidence). One new e2e test: **data survives a process restart** (41 e2e total). See
  [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md).
- **`prepare.*` fetches + compiles the SQLite amalgamation** (the htmx precedent, not a submodule):
  a pinned, **SHA-256-verified** `sqlite-amalgamation-3530300.zip` (SQLite 3.53.3) → unzipped into a
  gitignored `app/vendor/sqlite/` → compiled to a static lib (`sqlite3.lib` via `cl /MT` on Windows,
  `sqlite3.a` via `clang`+`ar` on unix), idempotently. A **C toolchain is now a hard requirement**;
  `prepare` checks for it and prints a per-OS install hint. The Dockerfile and CI gain
  `clang binutils unzip`. apollo-11 mounts a named volume at `/data` (`DB_PATH=/data/data.db`) for a
  durable live demo; Fly stays `:memory:` until a volume is provisioned (documented in `fly.toml`).
- **Data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md), docs only) — a
  concrete "how" for replacing the in-memory POC with **SQLite** in Odin: the binding choice
  (vendor vs amalgamation), schema + boot-time migrations, the seven `repo_*` as prepared SQL, the
  allocator discipline (clone column text into the temp arena — the same guarantee `snapshot()`
  gives today), how WAL maps onto the server's reader/writer model, build/deploy/ops, and the
  rollout. Complements `DATA.md` (the why/when).
- **`list` load scenario** (`GET /contacts?status=&sort=`) — the filtered/sorted table-region
  fragment, closing the last load-parity gap from Phase D; wired into the run driver (~38k req/s).
- **Overview → tool wiring** (Phase D increment 4, product cohesion). The dashboard stat cards are
  now links into the data view: *Active*/*Invited* → the table filtered to that status, *Avg.
  engagement* → sorted by score, *Total* → the full table. `page_data` now honours a `sort` query.
  Ties the four pages into one console (the overview drives the working tool) rather than four
  separate demos. e2e covers the drill-through.
- **Status quick-filters on the data table** (Phase D increment 3). A row of filter chips (All /
  Active / Invited / Disabled) above the table; the active one is marked, and the filter threads
  through the request like search/sort/page (`service_page` gains a `status` arg; every region link
  carries `&status=`), so filtering composes with text search and survives sort/paginate. e2e covers
  it; no new endpoint (a query param on the existing `/contacts` region).
- **Contact detail drilldown** (Phase D, flagship app — first increment). Clicking a row's name
  (`GET /contacts/:id`) opens a drawer with the full record (role, status, an engagement meter,
  id), a **derived activity trail** (a plausible, deterministic timeline — there's no persisted
  event log yet, see `docs/DATA.md`), and **related** contacts (others in the same role, each a
  one-click jump to its own detail). Re-skins under every style via tokens. The service layer gains
  `service_activity`/`service_related`; new `GET /contacts/(%d+)` route. e2e covers
  open/content/related/close; `load-tests/scenarios/detail.js` keeps it at par (~42k req/s locally).
- **Actionable detail drawer** (Phase D increment 2). The drawer is no longer read-only: **inline
  edit** (name/email/role/status/engagement, swapped in place — the slide doesn't re-animate),
  **cycle status**, and **delete** — all from the drawer. Edits/cycles re-render the drawer *and*
  refresh the table row behind it via an OOB swap (the `<tr>` wrapped in a `<template>` to survive
  the non-table swap context); drawer-delete closes the overlay and OOB-removes the row.
  `repo_update` now persists `score`. e2e covers edit+OOB-row, cycle, delete; the `write` load
  scenario becomes create→edit→delete so `POST /contacts/:id` is at par.
- **`/components` style showroom.** The components page opens with a catalog of all **6 styles ×
  23 schemes** — each style labelled with its scheme swatches; click any swatch to jump straight to
  that exact `style + scheme` (`setTheme` applies + persists) and the whole page re-skins live, the
  components below acting as the live preview. The active swatch is marked. No new server surface
  (client-side, like the picker), so load-tests stay at par; e2e covers the jump + persistence.
- **Arcade (video-game) style** (Phase C, 5/5 — the style library is complete). A chunky neon HUD:
  glowing panels and buttons, heavy uppercase type, vibrant gradients. Three schemes — **Arcade**
  (dark magenta/cyan), **Synthwave** (dark pink→orange sunset), and **Pop** (a clean candy-bright
  light variant). Final library: **6 styles, 23 schemes** (Modern 7, Skeuomorphic 3, Terminal 4,
  Brutalist 3, Editorial 3, Arcade 3), each with at least one light scheme, every one a pure
  `[data-style]` block over untouched component HTML.
- **Editorial / Paper style** (Phase C, 4/5). Serif throughout, warm and print-like: hairline
  rules, a single restrained accent, small-caps eyebrows, a ruled page header, title-case buttons
  (not shouty). Three schemes — **Manuscript** (light, ink on warm white, claret accent), **Sepia**
  (aged warm paper), and **Night** (a dark reading mode, cream on warm brown with gold).
- **Brutalist style** (Phase C, 3/5). Raw and loud: zero radius, thick borders, flat fills, and
  hard offset shadows that shift on press; heavy uppercase type; inverted nav block. Ships **dark
  *and* light** — **Paper** (light, cobalt/red), **Ink** (dark, white-on-black), and **Acid** (a
  loud acid-yellow with black + magenta).
- **Terminal / CRT style** (Phase C, 2/5). Monospace throughout, phosphor text with a soft glow,
  boxy thin-bordered panels, solid-fill uppercase buttons, and faint CRT scanlines (a single fixed
  gradient — cheap). Four schemes: **Green** (classic phosphor), **Amber**, **IBM** (cool
  blue/white), and **Paper** (a light teletype printout — every style now ships a light scheme).
- **Skeuomorphic style** (Phase C, first of five). A tactile treatment built entirely from layered
  gradients + bevel shadows — **no image assets**: raised panels with an inset top highlight,
  recessed (inset-shadow) form fields, glossy buttons that physically press on `:active`, a domed
  range thumb in a recessed groove. A per-style **bevel kit** (`--hi`/`--lo`/`--gloss`) drives it,
  tuned by three schemes: **Aqua** (light, lickable blue), **Graphite** (dark brushed metal), and
  **Brass** (warm wood + brass). Adding it took only a `[data-style="skeuo"]` block + scheme
  palettes + the picker entries — the component HTML is untouched. e2e now also covers switching the
  *style* axis and revealing that style's schemes. Remaining: Terminal, Brutalist, Editorial, Video-game.
- **Theme picker — two axes, `data-style` × `data-scheme`** (Phase B of the style library). The
  page shell carries `data-style` (the treatment) and `data-scheme` (the palette) on `<html>`,
  rendered server-side as `modern`/`midnight` (works with no JS) and restored from `localStorage`
  by the pre-paint script (no flash). A stateless topbar picker (a `<details>` popover) applies and
  persists the choice via tiny vanilla JS — no server endpoint, so load-tests stay at par. The CSS
  splits the old single dark/light theme into the `[data-style][data-scheme]` token contract;
  **Modern** ships **seven schemes** — Midnight, Daylight, Nebula, Aurora, plus warm **Ember**
  (dusk) and **Sandstone** (warm light) and cool **Ocean**. A new `--on-accent` token keeps text
  readable on light-accent gradients (so buttons aren't white-on-bright). e2e covers switch +
  persist. Phase C layers in the additional styles (Skeuomorphic, Terminal, Brutalist, Editorial,
  Video-game).
- **Vision + direction docs.** [`PHILOSOPHY.md`](PHILOSOPHY.md) (server-rendered HTML, browser as
  runtime, JS only where the browser can't, the Odin↔HTMX shared worldview, the honest 90/10),
  [`docs/USE_CASES.md`](docs/USE_CASES.md) (the sweet spot + the decision to evolve the sampler into
  one flagship internal admin console), and [`docs/DATA.md`](docs/DATA.md) (the repository seam, and
  SQLite→Postgres as the path past the in-memory POC). Wired into `CLAUDE.md`; phased plan in `TODO.md`.
- Initialized the repository as git and made the first commit.
- Adopted Conventional Commits; documented the spec and changelog mapping in `CLAUDE.md`.
- Infrastructure plan ([`infra/PLAN.md`](infra/PLAN.md)): remote hosting, CI/CD, deployment,
  and where to run e2e / load-tests — free / low-cost.
- Deployment: `Dockerfile` (two-stage, pinned Odin `dev-2026-06`, single-binary + static
  runtime), `fly.toml` (Fly.io, always-on `shared-cpu-1x`), and `.dockerignore`.
- CI/CD: `.github/workflows/ci.yml` — build with `-warnings-as-errors`, smoke-test the binary
  (pages, static, JSON API, CRUD), and deploy to Fly.io on green `master`.
- `app/main.odin` reads `PORT` from the environment and binds `0.0.0.0` when `BIND_ALL` is
  set, so the binary is container-deployable (local default stays loopback).
- `GET /healthz` liveness probe (200 `ok`); wired as the Fly.io health check in `fly.toml`.
- End-to-end test suite ([`e2e/`](e2e/)): Playwright over a freshly built binary — navigation,
  search, components, forms, CRUD and assets, including the three regression bugs. Runs across
  all three engines (Chromium, Firefox, WebKit). Wired into CI as a gating job; deploy now needs
  both `build` and `e2e`.
- `compose.yaml` for an optional local prod-parity run (`docker compose up --build`) — builds
  the same image Fly deploys. Not required for dev; handy for load-tests against a prod-like
  container.
- Favicon (`app/static/favicon.svg`, linked from the page head): a fusion mark — htmx's `</>`
  brackets on the project's violet→cyan gradient tile with the app's bolt accent.
- SEO: a **page-specific `<meta name="description">`** (the item Lighthouse flagged) plus Open
  Graph `og:type`/`og:title`/`og:description` on every page, threaded through `render_page`.
- Two-host deploy ([`deploy/apollo-11/`](deploy/apollo-11/)): a sudo-free `deploy.sh` (+ compose,
  README) that builds the self-contained image **on** a home Docker box from source tarred over
  SSH, joins it to the existing nginx-proxy-manager `npm` network for a subdomain, and publishes a
  host port for proxy-free load testing. IP/hostname/domain are parameterized. Required
  `seccomp=unconfined` so odin-http's io_uring isn't blocked by Docker's default profile (Fly
  dodged this via Firecracker). Yielded the two-host numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md): byte-heavy endpoints saturate the 1 GbE wire
  (~912 Mbit vs 2.4 GB/s loopback), and NPM+TLS on the shared box costs ~12×.
- Load tests ([`load-tests/`](load-tests/)): **k6** scenarios for every endpoint class —
  `static`, `pages`, `search`, `api`, `write` (create→delete), and a `mixed` 90/10 read/write
  blend — sharing one warmup→measured-window shape with per-phase thresholds and a
  dependency-free JSON/CSV summary. A `run.sh`/`run.bat` driver builds the app `-o:speed`,
  launches a fresh server per scenario × VU level (clean store), sweeps the VU curve, and
  stitches `results/summary.md`. `bombardier` baselines run if present. Numbers and the
  single-thread-ceiling reading land in [`load-tests/RESULTS.md`](load-tests/RESULTS.md).

### Changed
- **CI builds on all three platforms now**, not just Linux. The `build` job is a matrix over
  `ubuntu-latest`, `macos-latest` (Apple Silicon / arm64-darwin — exercises odin-http's **kqueue**
  path under `core:nbio`) and `windows-latest` (the primary dev platform — **IOCP** path). The
  ubuntu leg is unchanged; e2e and deploy are untouched. Each leg downloads its own **verified**
  Odin release asset (the names are irregular: the macOS-arm64 asset is tagged `…-dev-06`, the
  Windows asset carries no arch and unpacks to `dist/`), with `runner.os` in the cache key. C
  toolchain per OS so Odin can link — apt `clang` (Linux), Xcode CLT (macOS),
  `ilammy/msvc-dev-cmd` before the build (Windows); the build `-out` carries a per-OS extension
  (`.exe` on Windows). One shared bash smoke script boots the binary and hits the same endpoints on
  every OS, with `DB_PATH=:memory:` set for forward-compat with the planned SQLite layer.
- Refactored the backend into one Odin **package per layer** under `app/src/`
  (`models`, `repository`, `services`, `views`, `controllers`, and `src/` = entry `main`+routes),
  so the layering is compiler-enforced rather than convention. Cross-layer calls are now
  qualified (`repository.repo_list`, `views.view_dashboard`, …). Build entry is `odin build src`;
  `htmx.min.js` is `#load`ed from `controllers`. Behaviour unchanged (93/93 e2e green).
- Vendored odin-http as a pinned git submodule (`app/odin-http`, commit `112c49b`) for
  reproducible CI/CD builds; `prepare.*` stays the local-dev convenience path.
- e2e now runs **fully in parallel**: each Playwright worker spawns its own server on its own
  port with an isolated in-memory store (`global-setup.ts` builds once, `fixtures.ts` spawns
  per worker), replacing the single shared server + `workers: 1`. ~2.5× faster locally. On CI
  the engines are **sharded across concurrent runners** (a browser matrix) instead of piling
  workers onto one CPU-bound runner, and each shard runs in **Playwright's official Docker
  image** (which also ships node/npm) so the browsers + OS deps are preinstalled (no per-run
  install — that was the biggest, most variable cost). `workers` tracks the runner's cores.

### Performance
- **Cache-busting for CSS/JS.** Asset URLs in the page `<head>` now carry a `?v=<content-hash>`
  (computed once at startup, exposed as `views.ASSET_VERSION`). Since the HTML is dynamic and never
  cached, a changed stylesheet yields a new URL clients fetch immediately — no more serving the old
  `app.css` until `max-age` expires (the cause of needing a hard refresh after deploys). Verified on
  both deployments.
- **Moved the Fly deployment from `iad` (US-East) to `fra` (Frankfurt)** so it serves the
  primary (European) audience from nearby. Latency is RTT-bound, not compute-bound (the server
  answers `/healthz` in sub-ms), so over IPv4 a full page load dropped from ~850 ms to **~160 ms**.
  Fly's *IPv6* anycast additionally mis-routed some EU ISPs to a far edge (~785 ms over v6);
  fronting the origin with a **proxied Cloudflare record** (Full-strict, cert validated via DNS-01)
  fixed it — page TTFB is now **~105 ms on both v4 and v6** from a nearby Cloudflare edge, with
  `/static` edge-cached.
- **Multithreaded server.** The event loop now runs one nbio thread **per core** (was pinned to
  one); `THREADS` env overrides. The in-memory store, previously lock-free *because* it was
  single-threaded, is now guarded by an `sync.RW_Mutex` — reads share, writes are exclusive — and
  the repository hands callers **temp-arena snapshots** (structs copied, strings cloned under the
  lock) so nothing aliases store memory across a concurrent delete/realloc. Load-tests sweep
  `THREADS=1` vs `N` against the same binary for the before/after; numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md).
- Static assets now send `Cache-Control: public, max-age=3600` and a strong **ETag** (a content
  hash computed once at startup), with conditional `304 Not Modified` handling — repeat page
  loads reuse cached htmx/CSS/JS instead of re-downloading, and a redeploy changes the hash so
  clients never serve stale assets.
- All static assets (`app.css`, `app.js`, `favicon.svg`, htmx) are now **embedded into the
  binary** and served from memory, replacing the disk-served `respond_dir` path. The deployed
  artifact is a single self-contained file (the Dockerfile no longer ships `static/`), there
  are no per-request disk reads, and path traversal is structurally impossible.
- First page load: `defer` the embedded htmx script so it no longer blocks rendering (the
  pre-paint theme script stays synchronous to avoid a flash). htmx still initialises before
  `DOMContentLoaded`; the full e2e suite passes unchanged across all three engines.

### Fixed
- **Broken mobile layout.** The topbar (brand · nav · search · picker) was a rigid single row that
  forced a **page-wide horizontal scroll on phones** (~184px past a 390px viewport), with the search
  box clipped; the data table also clipped its right-hand columns. Now: below **720px** the search
  drops to a full-width second row (brand mark only, icon-only nav, picker right-aligned); the nav
  labels hide until they genuinely fit (**≤940px**, was 880 — which closed an 881–939px overflow
  band on small laptops); and below **560px** the data table folds email/role/engagement into the
  detail drawer (name · status · actions remain), with `.table-scroll` still catching anything
  wider. **Zero horizontal overflow from 320–1280px**, desktop unchanged; pinned by 4 e2e tests.
- **Reflected HTML-injection via the `sort` query param** (security). The data table reflected
  `sort` into its `hx-get="…"` attributes (filter chips + pager) **without** the `url_encode` its
  sibling params (`q`, `status`) already used, so a crafted value — e.g.
  `/data?sort="><img src=x onerror=…>` — could break out of the attribute on a directly-navigable,
  `text/html` GET endpoint. `sort` is now `url_encode`d at every reflection site (legit values like
  `score_desc` are unreserved and round-trip unchanged; `sort_th` was already safe, emitting only
  derived column literals). Pinned by an e2e regression test.
- Range slider fill was missing under Terminal, Brutalist, Editorial and Arcade — each style's
  `input` rule tied the range track on specificity and (being later) clobbered the fill layer (the
  same issue the skeuo style hit). Each now restores the fill on its
  `[data-style] input[type="range"]` rule, matched to the style (phosphor glow, flat accent, a
  refined gradient, neon). Completes the style library.
- Range slider fill lagged behind the thumb: the shared `input` rule transitioned `background`,
  which animated the `background-size` that paints the fill. The range track now opts out
  (`transition: none`), so the fill tracks the thumb instantly while the thumb keeps its own
  transform transition.
- Low-contrast schemes: the green scheme (Aurora) was washed out and white button text was hard to
  read on bright accents. Aurora is rebuilt around a vivid emerald with lifted muted text, and the
  new `--on-accent` token flips button/badge text dark on light-accent schemes.
- Linux/CI build: `prepare.*` now creates `bin/` (odin's `-out:` won't), the shell scripts
  carry the exec bit, and the Dockerfile/CI invoke `prepare` via `sh` — so the build no
  longer depends on a pre-existing `bin/` or the exec bit surviving a Windows-origin context.
- Page `<head>` was emitting `%!(MISSING)`: Odin's `fmt` treats `{`/`}` as directives, so the
  `htmx-config` JSON and the theme pre-paint script were mangled (htmx ran on defaults and
  threw on `JSON.parse`). The cycle button's `hx-vals` JSON had the same break. Brace-bearing
  literals now bypass `fmt` (written with `w()`). Caught by the new e2e suite.
- Out-of-band toasts (form submit, contact create) now keep their `.toast` wrapper — htmx's
  positional OOB swap appends an element's children, so the toast is wrapped in a carrier.

## [0.2.0] — 2026-06-26

### Added
- Project docs for efficient single-prompt sessions: `CLAUDE.md` (architecture, code/CSS/JS
  aesthetics, odin-http API cheat sheet, allocator model, Odin/HTMX gotchas, recipes), this
  `CHANGELOG.md`, and `TODO.md`.
- Test plans: `e2e/PLAN.md` (Playwright browser tests) and `load-tests/PLAN.md` (k6/bombardier
  throughput tests). Plans only — not yet implemented.
- Top-level `README.md` describing the `app/` + `e2e/` + `load-tests/` layout.

### Changed
- Restructured the repo: the entire application moved into `app/`, with `e2e/` and
  `load-tests/` as siblings. Run/prepare scripts are location-independent (`%~dp0` /
  `dirname`), so they work unchanged from `app/`.

### Fixed
- Invite dialog no longer closes on an outside (backdrop) click, so a half-typed field can't
  be lost by accident. Dismissal is explicit (× / Cancel).
- `/forms` no longer clears the name and email fields when the email validates. The email
  field's `htmx:afterRequest` was bubbling to the form and triggering `reset()`; the handler
  is now guarded with `event.target === this`.
- Range sliders now paint their fill to match the thumb as it moves (was a static 60%). The
  fill is driven by a `--fill` custom property updated from `app.js`.

## [0.1.0] — 2026-06-26

### Added
- Initial Odin + HTMX showcase.
  - Pure-Odin backend on `odin-http` (server, router, request/response over `core:nbio`);
    HTMX embedded into the binary via `#load` and served from memory; CSS/JS from disk.
  - Layered backend: models → repository → services → controllers → views.
  - Pages: Dashboard, Components gallery, Forms (with live inline validation), Data & CRUD.
  - Global debounced HTMX active-search plus a plain JSON API (`/api/search`).
  - In-memory CRUD over POST/DELETE; single-threaded lock-free store.
  - Hand-written, token-driven CSS with a dark/light theme toggle and snappy animations.
  - Cross-platform `prepare`/`run` scripts (Windows / Linux / macOS).
