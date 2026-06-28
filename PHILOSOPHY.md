# Philosophy

Why this project is built the way it is, and the line it intends to hold. Read this before adding
anything; if a change argues with what's here, the change needs a very good reason — or this
document needs updating on purpose.

## The thesis

**Render HTML on the server in a fast, simple language. Send it over the wire. Let the browser do
what browsers already do well. Reach for JavaScript only where the browser genuinely can't.**

That's the whole idea. An **Odin** backend generates HTML from plain procedures; **HTMX** lets
those server-rendered fragments swap into the page without a full reload; the browser remains the
runtime. No bundler, no framework, no build step beyond `odin build`. The deployed artifact is a
**single self-contained binary** that answers a request in sub-millisecond compute and ships every
asset embedded in itself.

## On JavaScript — the honest version

The claim is **not** "all JavaScript is evil." It's that JavaScript has a job it was designed for —
nudging the DOM, changing the state of a button — and a job it was *conscripted* into: being the
engine of an entire application, a second runtime bolted on top of the one the browser already
provides. That second runtime is not free. A modern SPA framework ships a non-trivial amount of
code whose primary purpose is to re-implement, in userland, things the platform already does:
routing, history, templating, diffing the DOM the browser already owns.

This project uses JavaScript the first way. `app.js` is small and vanilla: it persists the theme,
runs the toast lifecycle, paints a slider fill, animates a count-up — the handful of things that
are genuinely client-only. HTMX (the one front-end dependency) drives everything else by asking the
server for the next chunk of HTML. The button changes state. We did not build an engine to do it.

## The shared vision: Odin and HTMX

These two tools were chosen because they point the same direction — *against accidental complexity,
toward doing the obvious thing directly.*

- **Odin** is a language for people who want to know what their program does: explicit allocations,
  no hidden control flow, no runtime surprises, compiles fast, stays out of your way. It treats
  simplicity and the joy of a comprehensible system as features, not nostalgia.
- **HTMX** is the same instinct applied to the web: hypermedia as it was meant to be, the server as
  the source of truth, behavior kept local to the markup that triggers it, and the browser — not a
  framework — as the application runtime.

Put together you get a stack with *almost no moving parts between a request and the bytes on the
screen*, and you can hold the entire thing in your head. That legibility is the point.

## The line we hold

The **shipped app depends on exactly two things: HTMX and odin-http.** (See `CLAUDE.md` →
"Dependencies — the line we hold" for the operational rules.)

- No npm, no bundler, no CSS/JS framework, no template engine. HTML comes from Odin procedures; CSS
  is hand-written and token-driven; JS is vanilla and tiny.
- Before reaching for a library, ask whether ~30 lines of Odin or CSS does it. They usually do.
- Test tooling (Playwright, k6) is exempt — it's dev-time and never shipped.

## The 90%, honestly

This project is roughly **90% faithful** to the philosophy, and says so out loud rather than
pretending purity:

- **A little JavaScript.** `app.js` exists. It's small, vanilla, and does only what the server
  can't. That's the philosophy working as intended, not a violation — but it's not *zero*, so we
  count it.
- **A data layer.** There's an in-memory store. It's a proof-of-concept stand-in, deliberately the
  simplest thing that works; a real datasource is future work (see `docs/DATA.md`). Until then it's
  honest to call it what it is.

Naming the 10% is the point. A philosophy you can't measure yourself against is just a vibe.

## What it buys

- **One binary.** Nothing to orchestrate at runtime; copy it and run it. Assets are `#load`ed in.
- **Speed that isn't a feature you added later.** Sub-millisecond server render; the load tests
  (`load-tests/RESULTS.md`) put a modest box in the tens-of-thousands of requests/second. When the
  app feels slow, it's the network — measure the wire, not the server.
- **No build to rot.** There's no `node_modules`, no transpile step, no lockfile drift. `odin build`
  today, `odin build` in five years.
- **Legibility.** You can read the request path end to end: route → controller → service →
  repository → view. No magic in between.

## Scope honesty — the right tool, not the only tool

This started as a thing to find out whether the stack is viable — a toy built in a couple of weeks
to change the state of a button. It succeeded at that. It is **not** a claim that hypermedia
replaces every front end. Highly stateful, offline-first, canvas/realtime-collaborative, or
latency-hostile-to-round-trips UIs may legitimately want more client code. The discipline here is
to know *which* applications this approach serves best and lean into those — see
[`docs/USE_CASES.md`](docs/USE_CASES.md) — rather than to evangelize it into places it doesn't fit.

Use the right tool. For a large and useful class of applications, this *is* the right tool, and the
industry reaches past it out of habit, not necessity.
