# End-to-end tests

Playwright browser tests for the Odin + HTMX showcase. They drive a real
Chromium against a freshly built server binary and assert on what happens
*after* HTMX swaps land in the DOM — the bits curl can't see. See
[`PLAN.md`](PLAN.md) for the design and scenario rationale.

## Run

From this directory (npm — isolated test-only tooling, never shipped):

```sh
npm ci
npx playwright install --with-deps chromium firefox webkit   # one-time: fetch browsers
npm test                            # all three engines; add -- --project=chromium to narrow
```

`global-setup.ts` runs `prepare` + builds `../app` once (with `-warnings-as-errors`), so a run
needs `odin` **and a C toolchain** on `PATH` (prepare compiles SQLite). Then each Playwright
**worker spawns its own server** on its own port (`8200 + parallelIndex`, see `fixtures.ts`) with
an **isolated `:memory:` SQLite store** — which is what lets the suite run **fully in parallel**
across workers and the three browser engines.

- `npm run test:ui` — interactive runner.
- `npm run test:headed` — watch it drive a real browser.
- `npm run report` — open the last HTML report.

On CI the engines are sharded across runners inside Playwright's official Docker image (browsers
+ OS deps + node/npm preinstalled), so there's no browser-install step there.

## Layout

```
global-setup.ts        runs prepare + builds the app binary once (-warnings-as-errors)
fixtures.ts            per-worker server (own port + isolated :memory: store) → parallel
helpers/server.ts      spawn/get/post/del/health for specs that manage their own server
tests/
  navigation.spec.ts   dashboard + stat-card drill-through, routing + aria-current, ping, theme + showroom
  search.spec.ts       active search: highlight, navigate, collapse, Escape/outside-click
  components.spec.ts    tabs, accordion, toasts, modal (regression), drawer
  forms.spec.ts        email validation, field-persist (regression), slider --fill (regression), submit+reset
  crud.spec.ts         create/cycle/delete, 404, sort (+ injection regression), pagination, filters, detail drawer
  assets.spec.ts       embedded htmx, on-disk css, path-traversal 404, health, JSON API
  events.spec.ts       events between contacts: deleting a contact cascades its interactions (FK)
  persistence.spec.ts  data survives a process restart (a file-backed DB)
```

The regression tests pin bugs fixed earlier: the modal keeps its field on a
backdrop click, `/forms` doesn't wipe name/email on validation, range sliders
paint `--fill` to match the thumb, and a crafted `sort` param can't inject markup.

## Parity with load-tests

Per `CLAUDE.md`: every endpoint covered here should also have a `load-tests/`
scenario, and vice versa. When you add a spec for a new endpoint, add its load
scenario in the same change (or file a TODO). e2e proves *correct*; load-tests
prove *fast*.
