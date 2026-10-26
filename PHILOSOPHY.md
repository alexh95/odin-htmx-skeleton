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
are genuinely client-only. A profile may name those behaviours in _hyperscript instead
(`_="install Toast"`), and counts it as a dependency. HTMX drives everything else by asking the
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

The shipped app depends on htmx (plus the extensions a profile loads, from the same tarball under
the same 0BSD licence), odin-http (our fork), optionally SQLite, and optionally _hyperscript. An
optional client runtime is still a dependency, and is counted as one. (See `CLAUDE.md` →
"Dependencies — the line we hold" for the operational rules, and `docs/PLAN.md` §3.3 for why each
entry below is there.)

- No npm, no CSS/JS framework, no template engine. HTML comes from Odin procedures; CSS is
  hand-written and token-driven; JS is vanilla and tiny, or a behaviour the markup names.
- Before reaching for a library, ask whether ~30 lines of Odin or CSS does it. They usually do.
- Test tooling (Playwright, k6) is exempt: it's dev-time and never shipped.

## The 90%, honestly

This project is not purely faithful to the philosophy, and says so out loud rather than pretending
purity. The ledger counts everything that bends it:

| # | What bends | What it costs | Why it's worth it |
|---|---|---|---|
| 1 | **`app.js`** | vanilla JavaScript in every profile | it does only what the server can't: the theme pre-paint and its persistence, count-up, the hyperscript gate, the vanilla twins of the behaviours |
| 2 | **SQLite**, optional per profile | a C library statically linked when present, and a C compile step in prepare | persistence with no server and no network hop (`docs/DATA.md`); a profile without it builds with no SQLite at all |
| 3 | **_hyperscript 0.9.94**, optional per profile, core only | 39.7 KB brotli, a second, interpreted runtime, pre-1.0 with a bus factor of about one; it runs any `_` that reaches the page, so the CSP no longer backstops an escaping mistake | the element names its behaviour (`_="install Name"`) and the definition lives with the feature that owns the markup; the CSP stays free of `unsafe-eval`; an install-only gate and the vanilla twins keep it contained and replaceable |
| 4 | **the odin-http fork** | a small diff we maintain in-tree (`app/vendor/odin-http/UPSTREAM.md`), re-applied on each upstream bump | streams on the HTTP port, shutdown deadlines, the crash guard, timeouts and limits need code inside odin-http |
| 5 | **`tools/bundle`**, a prepare-time Odin tool | a prepare step that reruns whenever CSS, `_hs` or extension files change; it calls the `brotli` and `gzip` CLIs | it concatenates pinned, SHA-verified files in a fixed order and precompresses them: no module graph, no transpile step, nothing at runtime, so a bundler only in the sense of `cat` |
| 6 | **`platform/guard`**, non-local control flow | `setjmp`/`longjmp`, formally undefined behaviour, against "no hidden control flow"; confined to one package and the fork's callback entry points | Odin has no recover, so without it one trap kills every stream on every loop; every trap is logged, and one that touched shared state exits 70 |

The plan's ledger has two more rows that enter with the change that lands them: ffmpeg as an
offline transcoding tool (video), and the device feed's plain-text stream (M14).

Naming what bends is the point. A philosophy you can't measure yourself against is just a vibe.

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
