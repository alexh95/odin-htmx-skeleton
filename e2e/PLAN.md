# End-to-end tests — plan

> Status: **implemented.** The Playwright suite lives alongside this plan (31 tests across the
> six spec files below); see [`README.md`](README.md) to run it. This document stays as the
> design rationale. One deviation: a `webServer` launcher (`serve.mjs`) builds + runs the
> binary, in place of the `fixtures/server.ts` sketched below.

## Goal

Prove the app behaves correctly *through a real browser* — the HTMX swaps, the
animations settling, the bits that curl can't see. The existing curl checks already cover
the request/response contracts; e2e covers what happens after the fragment lands in the DOM.

The three bugs fixed in this round become permanent regression tests:
- the invite dialog does **not** close on an outside click and keeps its field,
- validating the email on `/forms` does **not** wipe the name/email fields,
- range sliders paint their fill to match the thumb.

## Tooling

**Playwright** (recommended). It auto-waits for elements and network to settle, which suits
HTMX's async swaps, runs headless in CI, and drives Chromium/Firefox/WebKit. The trade-off:
it's a JS-ecosystem dev dependency, which cuts against the app's zero-dependency stance — but
it is a *test-time* tool, never shipped, and lives entirely inside `e2e/`. The app itself
stays dependency-free. Managed with npm; on CI it runs in Playwright's official Docker image
(browsers + OS deps + node/npm preinstalled).

Considered and rejected for now: a pure-Odin HTTP harness. It's great for contract tests
(and we may add one later) but it can't execute HTMX or assert on rendered DOM, so it
doesn't replace browser e2e.

## Layout

```
e2e/
  package.json            # playwright only (npm; package-lock.json)
  playwright.config.ts    # 3 engines, fullyParallel, trace on retry
  global-setup.ts         # builds app/bin once with -warnings-as-errors
  fixtures.ts             # worker-scoped server per port + baseURL override
  tests/
    navigation.spec.ts
    search.spec.ts
    components.spec.ts    # tabs, accordion, modal (regression), drawer, toasts
    forms.spec.ts         # validation, field-persist (regression), slider fill (regression)
    crud.spec.ts          # create / cycle / delete / sort / paginate / filter
    assets.spec.ts        # embedded htmx, disk css, path-traversal 404
  README.md
```

## Server under test

The store is in-memory and resets every time the process starts, so a freshly spawned binary
is a clean, deterministic fixture. As implemented:
1. `global-setup.ts` builds the binary once (`-warnings-as-errors`).
2. A **worker-scoped fixture** (`fixtures.ts`) spawns one server per Playwright worker on its
   own port (`8200 + parallelIndex`), waits on `GET /healthz`, and kills it at worker end.
3. It overrides `baseURL` so each worker's `page`/`request` hit that worker's server.

Because every worker has its **own process and its own store**, the suite runs **fully in
parallel** (`fullyParallel: true`) across workers and the three engines — no shared-state
collisions, no need for `workers: 1`. (The first cut did run serially against a single shared
server; per-worker isolation replaced it. See the parallelisation commit.)

## Scenarios

**navigation** — dashboard renders; each nav link routes and sets `aria-current`; theme
toggle flips `data-theme` and survives a reload (localStorage).

**search** — typing debounces then shows the dropdown; the query is highlighted with
`<mark>`; an empty query collapses it; clicking a result lands on `/data?q=…`; outside-click
and Escape dismiss it.

**components** — tabs swap the panel and move `aria-selected`; accordion expands; **modal**:
opens, an outside (backdrop) click leaves it open with its field intact, × and Cancel close
it; **drawer**: opens and the backdrop click *does* close it (it has no field to lose);
**toast**: appears and auto-dismisses after its timeout.

**forms** — bad email shows an error message, good email shows "Looks good."; **name + email
persist after validation fires** (regression); **slider `--fill` tracks the value**
(regression); submit creates a contact → success card + toast; the form resets only on its
own submit, not on field validation.

**crud** — create appends a row and raises a toast; cycle advances the status badge; delete
removes the row (and a missing id returns 404 with the row untouched); sort headers reorder
and flip asc/desc; pagination and filter swap the table region without a full reload.

**assets** — `/static/htmx.min.js` is the embedded copy (200, JS content-type, ~51 KB);
`/static/app.css` is 200 from disk; `/static/../main.odin` is blocked (404).

## Selectors

Prefer role/text queries and the stable ids the app already exposes (`#overlay`, `#toasts`,
`#contact-region`, `#contact-tbody`, `.field-msg`, `.backdrop`, `.modal`). Add `data-testid`
only where a query would otherwise be brittle — don't blanket the markup with them.

## CI

GitHub Actions: install Odin → `odin build` the app → `npx playwright install --with-deps`
→ run. Upload traces/screenshots on failure. Gate merges on green. Where this runs and how it
fits the deploy pipeline: see [`infra/PLAN.md`](../infra/PLAN.md).

## Parity with load-tests

Per the policy in `CLAUDE.md`: every endpoint covered here must also have a scenario in
`load-tests/`. When you add an e2e scenario for a new endpoint, add its load scenario in the
same change (or file a TODO). e2e proves it's *correct*; load-tests prove it's *fast*.

## Out of scope (for later)

Visual-regression snapshots (Playwright `toHaveScreenshot`), and an accessibility audit pass
(axe). Note them so they're not forgotten, but they're not part of the first cut.
