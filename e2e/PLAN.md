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
stays dependency-free. The package manager / runtime is **Bun**, not npm — see
[ADR 0001](../docs/adr/0001-bun-for-javascript-tooling.md).

Considered and rejected for now: a pure-Odin HTTP harness. It's great for contract tests
(and we may add one later) but it can't execute HTMX or assert on rendered DOM, so it
doesn't replace browser e2e.

## Layout

```
e2e/
  package.json            # playwright only
  playwright.config.ts    # baseURL, one worker (in-memory store is shared), trace on fail
  fixtures/server.ts      # build + spawn app/bin/demo.exe on a test port, await "listening"
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

The store is in-memory and resets every time the process starts, so a fresh `bin/demo.exe`
per run is a clean, deterministic fixture. `fixtures/server.ts`:
1. `odin build ..\app -out:...` (or assume a prebuilt binary in CI),
2. spawn it on a dedicated port (e.g. 8099), parse stdout for the `listening` line,
3. hand `baseURL` to Playwright, tear the process down in global teardown.

Run serially (`workers: 1`): every test shares one in-memory store, so parallel writes would
collide. Tests that mutate (CRUD) should create rows with unique names and clean up, or rely
on a fresh server per file (`fullyParallel: false`, project-level server fixture).

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
