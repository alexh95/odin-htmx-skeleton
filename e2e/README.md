# End-to-end tests

Playwright browser tests for the starter's profiles. They drive real browsers against a freshly
built profile binary and assert on what happens *after* HTMX swaps land in the DOM — the bits curl
can't see. See [`PLAN.md`](PLAN.md) for the design rationale, and the repo's `docs/PLAN.md`
§19.1.2 for the matrix.

## Run

From this directory (npm — isolated test-only tooling, never shipped):

```sh
npm ci
npx playwright install --with-deps chromium firefox webkit   # one-time: fetch browsers
npm test                            # skeleton: three engines + the api project; -- --project=chromium narrows
```

`E2E_PROFILE` picks the profile under test: `skeleton` by default, in the three engines (Firefox
only in CI: it can't start on the dev PC) plus the `api` project; any other profile in chromium plus
`api` (`E2E_PROFILE=minimal npm test`).

Specs that never open a page (each talks HTTP, to the worker's server or its own) form the `api`
project in `playwright.config.ts`, so they run once rather than once per engine.

`global-setup.ts` builds the profile once through `../build.sh <profile>` (`build.bat` on Windows),
which holds every flag (`-vet -strict-style -warnings-as-errors` and the further vet flags). It runs `prepare` first only
when prepare's outputs are missing or don't match its pins, so a run needs `odin` (and its
linker), plus **a C toolchain** whenever prepare has work to do (it compiles SQLite; on Windows,
that means an x64 Native Tools prompt). A prepare failure stops the run. It then asks the binary
what it mounts (`--features --json`). Each Playwright **worker spawns its own server** on a port
the OS picks, with an **isolated `:memory:` store** — which is what lets the suite run **fully in
parallel** across workers and engines. The server's env is pinned (`helpers/server.ts`), so a
`PORT` or `DB_PATH` exported in your shell can't redirect the suite to another server or your
`data.db`.

- `npm run test:ui` — interactive runner.
- `npm run test:headed` — watch it drive a real browser.
- `npm run report` — open the last HTML report.

On CI the engines are sharded across runners inside Playwright's official Docker image (browsers
+ OS deps + node/npm preinstalled), so there's no browser-install step there. The chromium shard
also runs the `api` project.

## Tags: which specs run on which profile

Specs live by feature, `tests/<f>/`, and carry a tag for every feature they touch: `@<f>`, or
`@<f>-<member>` when they need one member of a build family (`@contacts-sqlite`, `@platform-full`).
A spec in `tests/<f>/` always carries `@<f>`. `fixtures.ts` runs a spec only when the build has
every feature (and member) its tags name, and skips it otherwise, naming what's missing; an
untagged spec fails. `has('<tag>')` from `fixtures.ts` lets a shared spec branch on the build (the
cross-site guard forges a contact where there are contacts, a note where there are notes).
`--grep @contacts` narrows a run the usual way.

## Route coverage

Every server the suite starts gets a `/metrics` bearer, and `stopServer` keeps its per-route request
counters (`app_http_requests_total`) in `../app/build/coverage/e2e/<profile>/`. `tools/check parity`
holds them, and the load suite's, against the profile's routes (`bin --routes --json`): every route
needs a non-zero count from both suites, or a waiver with a reason in `../tests/parity-waivers.txt`
(PLAN §19.1.11). A route reached only by a click counts too.

## Layout

```
global-setup.ts        prepare if needed, build the profile through build.{sh,bat}, read --features --json
fixtures.ts            per-worker server (own port + isolated store) → parallel; the tag selection; has()
helpers/server.ts      starts a server (free port, pinned env, fails fast with its output) + get/post/del;
                       stopServer keeps the route counters
tests/
  platform/            what every profile serves: assets, routing, security headers + CSP, the cross-site
                       write guard, input limits, operations (probes, /metrics, /licenses, the access log),
                       SEO contract, canonical redirect, style defaults, responsive, navigation + theme
                       picker, backup (@platform-sqlite)
  dashboard/           the dashboard's figures come from the store
  gallery/             components (tabs, accordion, toasts, modal, drawer) and forms (validation, sliders)
  contacts/            CRUD, paging, search, ids, escaping, writes, 422s, events (FK), persistence
  home/ notes/ about/  the minimal profile's pages: the notes card, adding and refusing a note, about
```

The regression tests pin bugs fixed earlier: the modal keeps its field on a
backdrop click, `/forms` doesn't wipe name/email on validation, range sliders
paint `--fill` to match the thumb, a crafted `sort` param can't inject markup,
and a click isn't swallowed by a swap's view transition. That last one presses
with `mouse.down()` / `mouse.up()`: `locator.click()` waits a transition out,
which hides the race.

## Parity with load-tests

Per `CLAUDE.md`: every endpoint covered here also has a `load-tests/` scenario, and vice versa,
which the route counters now check rather than state. When you add a spec for a new endpoint, add
its load scenario in the same change (or a waiver with its reason). e2e proves *correct*;
load-tests prove *fast*.
