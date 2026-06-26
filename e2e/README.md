# End-to-end tests

Playwright browser tests for the Odin + HTMX showcase. They drive a real
Chromium against a freshly built server binary and assert on what happens
*after* HTMX swaps land in the DOM — the bits curl can't see. See
[`PLAN.md`](PLAN.md) for the design and scenario rationale.

## Run

Tooling is **Bun** (not npm) — see [ADR 0001](../docs/adr/0001-bun-for-javascript-tooling.md).
From this directory:

```sh
bun install
bunx playwright install --with-deps chromium firefox webkit   # one-time: fetch browsers
bun run test                       # all three engines; add --project=chromium to narrow
```

`global-setup.ts` builds `../app` once (with `-warnings-as-errors`), so a run needs `odin` on
`PATH`. Then each Playwright **worker spawns its own server** on its own port (`8200 +
parallelIndex`, see `fixtures.ts`) with an **isolated in-memory store** — which is what lets
the suite run **fully in parallel** across workers and the three browser engines.

- `bun run test:ui` — interactive runner.
- `bun run test:headed` — watch it drive a real browser.
- `bun run report` — open the last HTML report.

> Use `bun run test`, **not** `bun test` — the latter is Bun's own test runner; ours shells out
> to the Playwright CLI.

## Layout

```
global-setup.ts        builds the app binary once (-warnings-as-errors)
fixtures.ts            per-worker server (own port + isolated store) → parallel
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
