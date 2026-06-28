# Use cases — where this stack wins, and the flagship it's evolving into

Companion to [`../PHILOSOPHY.md`](../PHILOSOPHY.md). The philosophy says *use the right tool*; this
says **which jobs are the right job** for server-rendered HTML + HTMX + a fast single-binary
backend, and commits the demo to becoming the canonical exemplar of one of them.

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

## The flagship (the app's direction)

The demo today is a *sampler* — a dashboard, a component gallery, a forms page, a CRUD table —
good for proving the stack, but it reads as several disconnected demos. The decision (see
`CHANGELOG`/`TODO`) is to **evolve it into one cohesive flagship: an internal admin console** built
on the domain it already has (people/contacts with roles, status, and a score). This is the dead-
center sweet-spot application, and making it *one believable tool* rather than a grab-bag is the
most honest possible showcase.

What "flagship" means in practice (tracked in `TODO.md`):

- **A coherent product frame** — a named internal console, consistent nav, a real information
  architecture, not four unrelated pages.
- **Depth on the core entity** — a record **detail** view, richer fields, related data, an activity
  trail; CRUD that feels like a tool you'd actually use.
- **Real workflows** — bulk actions, saved filters, inline edit, validation that mirrors the server.
- **The component gallery becomes the style/scheme showroom** (see the theming work) rather than a
  standalone page — components shown *in situ* in the console.

It stays strictly CRUD-centric and within the sweet spot — we are deepening the exemplar, not
chasing a use case the stack is wrong for.

## The standing rule: app / e2e / load-tests at par

Every user-facing feature or endpoint lands in **all three** suites in the same change — `app/`
builds it, [`../e2e/`](../e2e) asserts its behavior, [`../load-tests/`](../load-tests) measures its
cost. Adding `/foo` means an e2e scenario *and* a load scenario for `/foo`, or an explicit TODO
saying why not. This is non-negotiable; it's what keeps the flagship trustworthy as it grows.
