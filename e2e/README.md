# End-to-end tests

Playwright browser tests for the Odin + HTMX showcase. They drive a real
Chromium against a freshly built server binary and assert on what happens
*after* HTMX swaps land in the DOM — the bits curl can't see. See
[`PLAN.md`](PLAN.md) for the design and scenario rationale.

## Run

From this directory:

```sh
npm install
npx playwright install --with-deps chromium   # one-time: fetch the browser
npm test
```

`serve.mjs` (Playwright's `webServer`) prepares deps, builds `../app` with
`-warnings-as-errors`, and runs the binary on port 8137 — so a run needs `odin`
on `PATH`. A fresh process per run means a clean in-memory store; tests run
serially (`workers: 1`) because that store is shared.

- `npm run test:ui` — interactive runner.
- `npm run test:headed` — watch it drive a real browser.
- `npm run report` — open the last HTML report.

## Layout

```
tests/
  navigation.spec.ts   dashboard, routing + aria-current, ping, theme persistence
  search.spec.ts       active search: highlight, navigate, collapse, Escape/outside-click
  components.spec.ts    tabs, accordion, toasts, modal (regression), drawer
  forms.spec.ts        email validation, field-persist (regression), slider --fill (regression), submit+reset
  crud.spec.ts         create / cycle / delete, 404, sort, pagination, filter
  assets.spec.ts       embedded htmx, on-disk css, path-traversal 404, health, JSON API
```

The three regression tests pin the bugs fixed earlier: the modal keeps its
field on a backdrop click, `/forms` doesn't wipe name/email on validation, and
range sliders paint `--fill` to match the thumb.

## Parity with load-tests

Per `CLAUDE.md`: every endpoint covered here should also have a `load-tests/`
scenario, and vice versa. When you add a spec for a new endpoint, add its load
scenario in the same change (or file a TODO). e2e proves *correct*; load-tests
prove *fast*.
