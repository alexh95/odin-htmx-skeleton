# End-to-end tests — design

The operating manual is [`README.md`](README.md); the test plan for the whole starter is
`docs/PLAN.md` §19.1 (D37). This is the why behind the harness.

## Goal

Prove each profile behaves correctly *through a real browser* — the HTMX swaps, the animations
settling, the bits curl can't see — and pin every bug fixed once as a regression test (the modal
keeps its field on a backdrop click; `/forms` validation doesn't wipe the fields; range sliders paint
their fill; a click isn't lost to a swap's view transition). The `api` project covers the HTTP
contracts that need no browser (headers, limits, routing, the crawler contract, operations).

## Tooling

**Playwright.** It auto-waits for elements and the network to settle, which suits HTMX's async
swaps, runs headless in CI, and drives Chromium, Firefox and WebKit. It's a JS dev dependency, which
cuts against the app's no-dependency stance, but it is test-time only, never shipped, and lives
entirely in `e2e/`; on CI it runs in Playwright's own image. A pure-Odin HTTP harness could cover the
contracts but can't execute HTMX or assert on the DOM, so it doesn't replace this.

## The server under test

`global-setup.ts` builds the profile once through `build.sh` and asks the binary what it mounts
(`--features --json`). Each Playwright **worker spawns its own server** on a port the OS picks, with
a pinned environment (`DB_PATH=:memory:` whatever the shell exports) and its own store, so the suite
runs **fully in parallel** across workers and engines with no shared-state collisions. A spec that
needs its own server (a file DB, a crash, a custom `SITE_URL`) starts one with `startServer`.

## One suite, many profiles

Specs live with the feature they test (`tests/<f>/`) and carry a tag for every feature they touch;
the fixture skips a spec whose features the build lacks, naming them, and fails an untagged one. So a
profile, or a fork's generated selection, carries exactly its own tests, and a spec written against
the full skeleton still runs where its features are. A shared spec branches on the build with
`has()` rather than probing URLs.

## Selectors

Prefer role and text queries and the stable ids the app exposes (`#overlay`, `#toasts`,
`#contact-region`, `#contact-tbody`, `.field-msg`, `.backdrop`, `.modal`). Add `data-testid` only
where a query would otherwise be brittle.

## Route coverage

Every server the suite starts is scraped for its per-route request counters as it stops; with the
load suite's, `tools/check parity` proves every route of the profile was reached by both (PLAN
§19.1.11). A route reached only by a click counts.

## Out of scope for now

Visual-regression snapshots; the accessibility pass (`@axe-core/playwright`) and the CSP specs arrive
with the client-stack milestone (PLAN §19.1.2).
