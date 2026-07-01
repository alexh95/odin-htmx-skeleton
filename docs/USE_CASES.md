# Use cases — where this stack wins, and the example it ships

> **Read first:** this project is a **starter skeleton** (see [`../TODO.md`](../TODO.md)). The
> contacts/events console is the **worked example** that proves the stack's patterns — *not* a
> product to finish. The sweet-spot analysis below is what still matters: it tells you whether the
> skeleton is the right thing to fork for *your* site.

Companion to [`../PHILOSOPHY.md`](../PHILOSOPHY.md). The philosophy says *use the right tool*; this
says **which jobs are the right job** for server-rendered HTML + HTMX + a fast single-binary
backend — i.e. when this skeleton is the right thing to fork.

## The sweet spot

The approach wins when **the server owns the truth, a round trip is acceptable, and the client
holds little durable state.** Concretely:

| Class | Why it fits | Examples |
|---|---|---|
| **Internal tools / admin consoles** | Trusted networks, data-on-server, CRUD + tables + forms — the browser's native strengths | user/role admin, back-office, ops dashboards |
| **Line-of-business CRUD** | Records, validation, workflow; correctness matters more than 60fps client state | CRM, inventory, ticketing, billing |
| **Forms-heavy workflows** | Validation belongs on the server anyway; HTMX gives live feedback without a client model | applications, onboarding wizards, approvals |
| **Read-heavy browse/search** | Filter/sort/paginate are cheap on the server; results stream as HTML | catalogs, directories, reporting |
| **Content + light interactivity** | Mostly static, a few live bits | docs, marketing with search/forms |

The common thread: **the page is a view of server state, not an application that happens to render.**
When that's true, shipping a client framework to re-implement routing/templating/state is pure
overhead — you pay download, parse, hydrate, and a build pipeline to do what the server already did.

## Where it's the wrong tool (say so)

Per the philosophy's scope humility — reach for more client code when the job genuinely needs it:

- **Offline-first / PWA** — the client must own state and work without the server.
- **Realtime collaborative canvas** (Figma-like), **games**, **rich-text/WYSIWYG editors** — high-
  frequency local interaction where a round trip per change is fatal.
- **Spreadsheet-grade local computation** — thousands of interdependent cells recalculating live.
- **Latency-hostile UX** where even one network hop per interaction is unacceptable.

HTMX handles *debounced* live search, inline validation, optimistic-ish swaps, and progressive
disclosure comfortably. It does **not** want to be a 60fps physics loop. Know the difference.

## The worked example

The bundled app is a **contacts/events admin console** — the dead-center sweet-spot application
(internal tool, data-on-server, CRUD + tables + forms). It's here to *prove the patterns*, not to be
a product you finish, so it's built as one believable tool rather than a grab-bag:

- a **dashboard** whose stat cards drill into the filtered data view;
- a **sortable / filterable / paginated table** with create · update · delete;
- a record **detail drawer** with inline edit, an activity trail from real `events` joined back to
  contacts, and related records — CRUD that feels like a tool you'd use;
- a **forms** page with live inline validation that mirrors the server;
- a component gallery that doubles as the **style/scheme showroom** — every theme, shown *in situ*.

That's the exemplar. Product-depth features a real console would grow — **bulk actions**, saved
filters, a **named console identity** — are **out of scope as goals**: they'd be cruft a copier
deletes, and they teach nothing new about the stack. When you fork this, the example is what you
*strip* — by hand ([`STRIP.md`](STRIP.md)) or with `init --minimal` — keeping the scaffolding beneath
it. It stays strictly CRUD-centric and inside the sweet spot; that's the honest showcase.

## The standing rule: app / e2e / load-tests at par

Every user-facing feature or endpoint lands in **all three** suites in the same change — `app/`
builds it, [`../e2e/`](../e2e) asserts its behavior, [`../load-tests/`](../load-tests) measures its
cost. Adding `/foo` means an e2e scenario *and* a load scenario for `/foo`, or an explicit TODO
saying why not. This is non-negotiable; it's what keeps the example — and your fork — trustworthy.
