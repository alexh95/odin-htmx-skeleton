# Brief — odin-htmx-starter (Alex, 2026-10-25)

The request that started this workspace, kept so every later session plans against the same ask.

## The ask

Promote the **odin-htmx-skeleton** (github.com/alexh95/odin-htmx-skeleton, pinned reference clone in
`_ref/odin-htmx-skeleton` at 709bc94) to a **starter**: a more versatile **superset** of the skeleton.

- More features: **WS/SSE etc. — every htmx 4 extension** (https://four.htmx.org/extensions).
- The new starter must be able to produce something with the **performance characteristics of the
  skeleton (or better)** and the **same feature set**, while keeping the grand philosophy
  (`_ref/odin-htmx-skeleton/PHILOSOPHY.md`).
- The plan must include the decision: **promote the skeleton, or start a new repo and retire the skeleton.**

Must cover:

- all the htmx extensions
- **_hyperscript** (https://hyperscript.org/)
- the same Odin tooling, plus an **audit of the resulting Odin code** for performance and stability
- the same **optional SQLite** back end
- everything else deemed important (**e2e, load test, pipeline**)

## Granularity — the core idea

The skeleton was a *minimal implementation of the maximal set of features*. The starter should do that and
more: it should offer **granularity over the covered features** and provide **multiple full implementations
of the relevant options**. E.g. it can minimally initialise a project as a simple "hello world" for the
selected feature set. Ideally one app, kept modular; if several instances are needed to prove things work,
use routes like `htmx-odin-starter.alexh95.com/minimal` and `/full` (served by the same server, or separate
to be more representative).

## The showcase app

Plan a **full app that makes good use of all the features**. Huge scope is welcome: it's a test of whether
these tools can manage huge complexity while maintaining code quality (see the philosophy). Alex's seed
features:

- **Instant messaging** (capped by a rolling buffer and/or truncated after a while).
- **AI chatbot** — not part of the starter itself. Leave a TODO: Alex may put a simple **llama.cpp** model
  on the local network later. Only the chat FE/BE interfaces and bindings matter now; mock a bot that
  answers with random "todo" / "under construction" messages. Assume llama.cpp somewhere on the LAN.
- **A terminal console** — Alex will set up a **Raspberry Pi** later; plan how to connect to it.
- **Serving video content.**
- **Serving game content** — see https://games.alexh95.com/ (spark, code in `<SPARK_DIR>`). How
  to integrate it, and does the game portal need adaptation?
- **User accounts, roles and permissions.**
- Many other things worth adding.

## Hosting

Include a hosting section in case fly.io isn't cutting it — but the **local network setup on apollo**
comes first, before anything goes on the public web.
