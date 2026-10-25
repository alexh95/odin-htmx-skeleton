# Lean composition: direct calls, no injection

**Date** 2026-10-25, revised 2026-10-26 · **Status** revised to ANSWERS round 3 ("the simpler set") and folded
into DECISIONS.md and PLAN.md on 2026-10-26 (ANSWERS #1, F1, round 3); §15's SETTLED and RESOLUTIONS rows are
recorded in DECISIONS §0.2 and §0.3, not yet in those files · **Replaces** the composition mechanism of D5–D8: the
per-feature `Feature` struct and its `register()` calls, the proc-field vtables handed in from `cmd`,
`platform/ports`, and X33's vtable `exts` path · **Supersedes** this document's first version, whose `sel:` alias
layer, generated profile files and null seam packages ANSWERS round 3 set aside (§13).

**Evidence.** Two prototype rounds on the local Odin (dev-2026-10-nightly:84bc3fc, Windows, rad-link), in the design
round's scratchpad, which is not kept:
- **research note 14**, filed from the first round's results, cited by its section numbers: "14 (1)" collection
  remapping, "(1c)" the alias layer, "(2)" the switch and its cost, "(3)" route tables and the static checker, "(4)"
  `when` + `#config`, "(5)" cross-feature calls, "14 critic" the re-runs;
- **`$L2`**, this revision's two experiments: `$L2 a`, the store family layout with all four families on the build
  line, and `$L2 b`, per-host route tables with one package's page at `/` in one profile and at `/dashboard` in
  another, the boot check and a static profile check. §16 records their commands and outputs.

Claims neither round covered are marked **NEW**. `§n` is this document, `PLAN §n` is `docs/PLAN.md`, `09 §n` is a
research note, and `SK/` is the skeleton at 709bc94.

## 1. What Alex asked, and the rule

> "Let's keep the packages in separate files for more flexibility, let's also keep the layering done explicit (one
> calling the other directly) and as simple and lean, not using injection or DI or stuff like heavy frameworks such
> as spring likes to do."

The skeleton already works this way: `src/routes.odin` is the route table, and `controllers → services → repository`
are qualified direct calls (`SK/CLAUDE.md` "Architecture"). The current plan doesn't. It builds a `Feature` struct per
feature, hands each feature its implementations as proc-field structs from `cmd/<p>/main.odin`, and routes
cross-feature calls through a struct of installed callbacks (`platform/ports`). That is dependency injection, and it
goes. ANSWERS round 3 chose the simpler of the two shapes this document first proposed: nothing is generated per
profile, imports land straight on the real code, and each profile's entry files are hand-written, as the skeleton's
are.

**The rule.** Which implementation runs is never a value passed around at run time. It is one of three things:
- **a family collection on the build line** (§3), when the choice keeps a C library off the linker or swaps a whole
  platform layer: the store, the identity, the client and the theme;
- **a hand-written `switch` over an enum, with a direct call in each case** (§4), when it varies per request: the chat
  transport and the bot backend;
- **an env value read at boot, then the same kind of switch** (§4), when both members are pure Odin and one serves
  the whole process: the games catalog.

A proc value is stored in only two kinds of place:
- **dispatch tables**: route rows (URL → handler), topic rows (topic family → subscriber), job rows (job id → run),
  and the profile's home-card and find-source tables (§6, §9), as in the skeleton's router;
- **continuations** that name the caller's own next step: nbio completions, the writer task's commit, timers, jobs,
  the bot's token sink.

Both say *when* code runs, never *which* implementation runs.

## 2. The reading test

A reader starts in `app/cmd/<p>/routes.odin` and follows a request to its SQL with go-to-definition alone. Once the
router has matched the row, every hop is a qualified name, and nothing is looked up at run time:

```
app/cmd/full/routes.odin              chat_web.ROUTES[:]                        (in MAIN_ROUTES)
 → app/features/chat/web/routes.odin  {.Get, "/chat/r/([%w-]+)", room_page, …}
 → chat_web.room_page                 chat.room_view(v, slug, &msgs)
 → chat.room_view                     chat_store.recent(room.id, …)              import chat_store "store:chat"
 → app/stores/sqlite/chat/store.odin  chat_store_sqlite.recent → SQL_RECENT
```

These are the skeleton's hops (route → controller → service → repository → SQL), with none added: the domain's import
lands straight on the store package, with no alias in between. `ols.json` pins the `store` collection to
`app/stores/sqlite`, so the last hop opens the SQLite store. A memory profile's last hop is the same path with
`memory` in it, `app/stores/memory/chat/store.odin`, and the compiler's own dependency list for that build names only
that family (`$L2 a`).

## 3. The four families on the build line

| Family | Flag | Members | Imported by | Contract |
|---|---|---|---|---|
| store | `-collection:store=app/stores/<sqlite\|memory>` | one directory per family, holding one package per feature: `app/stores/sqlite/chat/` is `chat_store_sqlite` | the feature's domain, as `store:<f>`; `store:audit` from any domain, web or identity package (§9); a SQLite profile's `main`, for `MIGRATIONS` | proc types in `features/<f>/models`, one typed constant per proc in each store's `contract.odin` |
| identity | `-collection:identity=<dir>` | `app/features/accounts/identity_{accounts,envadmin,nick}/`, `app/platform/authz/anonymous/` | `platform/app` (front) as `identity:.`; the profile's `routes.odin` for `identity.ROUTES`; `main` for `identity.cli` | `authz.Load_Viewer` |
| client | `-collection:client=<dir>` | `app/platform/client/{hyperscript,vanilla}/` | `platform/html` (`behave`) | none: CI builds both members (`full` and `full-vanilla`) at every call site |
| theme | `-collection:theme=<dir>` | `app/platform/theme/{full,lite}/` | `platform/html` | none: hosted profiles build both members |

`import x "name:."` names the one package a collection points at (14 (1)). `anonymous` moves from `platform/authz`
into its own package, `platform/authz/anonymous` (`authz_anonymous`), so the identity collection always names one
identity package.

**The build line** is spelled in one place, `build.{sh,bat} <profile>` at the repo root, and every path on it is
relative to the repo root:

```sh
# build.sh <profile> [odin flags…]: the only place the family flags live. CMD=check|test|run (default build).
case "$p" in
  minimal)      store=memory id=platform/authz/anonymous            client=vanilla     theme=lite ;;
  skeleton)     store=sqlite id=platform/authz/anonymous            client=vanilla     theme=full ;;
  streams)      store=memory id=features/accounts/identity_nick     client=vanilla     theme=lite ;;
  full)         store=sqlite id=features/accounts/identity_accounts client=hyperscript theme=full ;;
  full-vanilla) store=sqlite id=features/accounts/identity_accounts client=vanilla     theme=full  src=full ;;
  lab)          store=memory id=platform/authz/anonymous            client=hyperscript theme=full ;;
esac
exec odin "${CMD:-build}" "app/cmd/${src:-$p}" \
  -collection:store=app/stores/$store -collection:identity=app/$id \
  -collection:client=app/platform/client/$client -collection:theme=app/platform/theme/$theme \
  -vet -strict-style -warnings-as-errors "$@"
```

`run.*`, `prepare.*`, CI, the Dockerfile, the e2e global setup, `load-tests/run.sh`, `tools/watch` and `tools/init
--verify` all call it. Without the flags the compiler names each missing collection, "Syntax Error: Unknown library
collection: 'store'" (and `'client'`, `'identity'`, `'theme'`; `$L2 a`). **`full-vanilla` has no directory of its
own**: it is `app/cmd/full` built with the vanilla client, so the two can't drift apart (PLAN §7.1 changes; §6).

**The store layout:**

```
app/stores/
  sqlite/<f>/   store.odin  contract.odin  migrations/NNNN_name.sql     package <f>_store_sqlite
  memory/<f>/   store.odin  contract.odin                                package <f>_store_memory
```

- **Package names are unique** per program (14 (1): "A package name must be unique"), so a feature's conformance suite,
  `features/<f>/storetest/`, imports both stores into one test binary (`$L2 a`: 2 tests pass).
- **A store imports** its feature's `models`, `platform/store` and, in the SQLite family, `platform/sqlite`,
  `platform/store/sqlite` and `platform/workers`. It never imports its domain (an import cycle, 14 (1)) or another
  store.
- **Contracts are typed constants**, `_ : m.Store_Insert : insert`, pure type checking with no code. A drifted store
  fails in its own package, built or not: "Cannot assign 'insert' of type 'proc(^Message, u64) -> Error' to
  'Store_Insert'" (`$L2 a`). `#assert(type_of(insert) == T)` can't do this job: it is false even for an exact match
  (14 (1), 14 critic).
- **`MIGRATIONS` is a package variable**, and a SQLite profile's `main` names it directly:
  `store_sqlite.migrate("chat", chat_store.MIGRATIONS[:])`. With no alias in between, the proc wrapper the first
  version needed is gone (aliases can't name a variable, 14 (1c)).
- **A feature with no member in a family has no directory there**, so a build that reaches it fails to compile:
  "Syntax Error: Path does not exist: store:contacts" (`$L2 a`). That is D18's refusal, made by the compiler; the
  generator refuses first, with advice (§10). SQLite only: accounts (so `identity_accounts`), contacts and term.
- **The memory family never hands SQLite to the linker.** `streams`' linker line ends at `"kernel32.lib"` and
  `full`'s with `…/clib/fakesql.lib`; the library's marker string is in `full`'s executable and not in `streams`'
  (`$L2 a`, with a real static library standing in for SQLite, as in 14 (1)).
- **What follows the store family**: search (FTS5 in `sqlite`, a `contains_ci` scan in `memory`), the wiki (`memory`
  is `source_files`, the read-only embedded docs; `sqlite` is editable) and the video catalog (`memory` is
  `catalog_file`, the manifest scan; `sqlite` holds the metadata). PLAN §2.8's member names survive as each store's
  `IMPL` constant.
- **One family per build.** Every feature in a profile uses the same store family, so D8's per-feature store choice
  goes. Every hosted profile is all-SQLite or all-memory already (PLAN §7.1).

**The editor** sees one member per family. `ols.json` at the repo root pins the four collections to `full`'s
members, `app/stores/sqlite`, `identity_accounts`, `client/hyperscript` and `theme/full` (OLS's `collections` are
top-level, so a profile can't remap one; 14 (1)). Other members are still standalone packages, and switching is one
line. Not tried in an editor: OLS isn't installed here.

## 4. Everything else, per axis

| Axis | Members | Chosen | How |
|---|---|---|---|
| **Chat transport** | `features/chat/transport_{ws,sse,poll,multipart}` | **per request**: the user's preference (`accounts_prefs`, X9; elsewhere a cookie), `?transport=` in tests, default `CHAT_TRANSPORT` | one hand-written `switch` in `chat_web`; every chat profile links and ships all four |
| **Bot backend** | `features/bot/backend_{mock,llama}` | **per request**: guests get mock; members choose among the healthy ones; the default is `BOT_BACKEND`, which an admin changes at run time on `/admin/bot` (in memory, audited, reset on restart) | one `switch` in `bot_web`; both linked (llama's client is `platform/stream/client`, pure Odin) |
| Bot delivery | SSE, multipart, room | per request (a form choice) | a local `switch` in `bot_web`; room mode over hub topics (§9) |
| Ops refresh | SSE, ptag, multipart | per request (`?mode=`) | a local `switch` in `ops_web` |
| Games catalog | `features/games/catalog_{static,api}` | per process: `api` when `GAMES_API_URL` is set, `static` otherwise (`GAMES_CATALOG` still overrides the static JSON) | `games_web` reads it at `init`, then a `switch`; both pure Odin, so nothing is kept off the linker |
| Search, wiki source, video catalog | the store's | the store family | §3 |
| Terminal mode | line, PTY | per device row | a column of the row, switched in `term_web` |

**The switching rule** (D8) is unchanged: per-request switching exists only on transport axes and the bot backend,
and every response from such a feature carries `x-impl` (`chat.transport=sse`, `bot.backend=mock`) and its access-log
line `impl=`.

**The chat switch** sits next to the routes in `chat_web`, which imports all four transports:

```odin
package chat_web                 // transports.odin

import "core:strings"
import chat_transport_multipart "../transport_multipart"
import chat_transport_poll      "../transport_poll"
import chat_transport_sse       "../transport_sse"
import chat_transport_ws        "../transport_ws"

Transport :: enum u8 {Ws, Sse, Poll, Multipart}

pane :: proc(t: Transport, b: ^strings.Builder, slug: string) {
	switch t {
	case .Ws:        chat_transport_ws.pane(b, slug)
	case .Sse:       chat_transport_sse.pane(b, slug)
	case .Poll:      chat_transport_poll.pane(b, slug)
	case .Multipart: chat_transport_multipart.pane(b, slug)
	}
}
// from_name(s) and name(t) the same way, over each package's NAME.
```

The bot's is the same shape: `Backend :: enum u8 {Mock, Llama}`, with `health`, `start` and `cancel` switches, and
the token sink stays a continuation.

**Cost of the switch** (14 (2)). Over 200M calls at `-o:speed`, in ns per call:

| Dispatch | Same transport each call | Random mix of four |
|---|---|---|
| direct call | 1.09–1.11 | — |
| enum + switch | 1.53–1.56 | 6.31–6.62 |
| proc-field table (the old plan) | 1.33–1.38 | 5.20–5.39 |

So the switch costs 0.2–1.2 ns more than a table, against 0.5–15 µs for a store call or a socket write, and the IR
holds four direct calls and no indirect one (14 (2)).

## 5. Package shape and layering

The per-feature split stays, with one package added, **`f_models`**: the domain calls its store directly, so a store
that imported the domain would be an import cycle (14 (1)). The shared types and the contract types sit below both,
as the skeleton's `models` does. The stores move out of the feature directory into their family's (§3).

```
app/cmd/<p>/   brand.odin main.odin routes.odin routes_test.odin   (all hand-written)                ─► everything
   │
   ├─► f_web            features/f/web/          ─► f, f_models, f_views, f's switched impls, notify_web, store:audit, platform L1–L3
   │     ├─► f_<axis>_<impl>  (switched)         ─► f, f_models, f_views, platform L1–L3       transport_ws, backend_llama, catalog_api …
   │     └─► f_views    features/f/views/        ─► f_models, f, platform/html
   ├─► f                features/f/  (services)  ─► f_models, store:f, store:audit, other features' domains, platform L1–L2
   ├─► f_store_<family> app/stores/<family>/f/   ─► f_models, platform/store*, platform/sqlite (SQLite family), platform/workers
   └─► f_models         features/f/models/       ─► core, platform L1–L2 types

platform  L4 app      ─► identity:., L1–L3                       (only cmd/* imports it; it holds front)
          L3 web html hub stream stream/client client/* theme/*   (html ─► client:., theme:.)
          L2 store store/sqlite store/memory env authz authz/anonymous obs guard workers markdown
          L1 sys sqlite ext
```

| Package | Directory | Holds | May import | Never imports |
|---|---|---|---|---|
| models `f_models` | `features/f/models/` | types, enum label tables, contract proc types | core, platform L1–L2 | anything of `f` |
| store `f_store_<family>` | `app/stores/<family>/f/` | one store, its `contract.odin`; `migrations/` in the SQLite family | `f_models`, `platform/store*`, `platform/sqlite`, `platform/workers` | `f`, `f_views`, `f_web`, other stores, any collection |
| domain `f` | `features/f/` | services: validation, rules, ownership; plain values and errors, never HTTP | `f_models`, `store:f`, `store:audit`, other features' domains (hard dependencies), platform L1–L2 | `platform/web`, `html`, `hub`, another feature's store |
| views `f_views` | `features/f/views/` | HTML builders over `^strings.Builder` | `f_models`, `f`, `platform/html` | stores, `f_web` |
| switched impl `f_<axis>_<impl>` | `features/chat/transport_ws/`, `bot/backend_llama/`, `games/catalog_api/` … | one transport, backend or catalog, chosen per request or per process by `f_web`'s switch (§4): `NAME`, `EXTS`, its handlers | `f`, `f_models`, `f_views`, platform L1–L3 | `f_web`, other impls |
| web `f_web` | `features/f/web/` | handlers, `ROUTES` (its impls' rows too), `TOPICS`, `JOBS`, `EXTS`, `init`/`start`/`drain`, `home_card`, the axis switch, hub publishes | `f`, `f_models`, `f_views`, its own impls, `notify_web` (producers, §9), `store:audit`, platform L1–L3 | any other web package, `platform/app`, the vendored odin-http |
| identity `accounts_identity_<x>`, `authz_anonymous` | `features/accounts/identity_*/`, `platform/authz/anonymous/` | `NAME`, `SETS_COOKIE`, `load_viewer`, `cli`, its `ROUTES` (`/login`, `/logout` …) | `accounts_models`, `store:audit`, platform L1–L3 (`anonymous`, in L2, L1–L2); `identity_accounts` also `accounts` and `accounts_views` | `accounts_web`, other identities, `platform/app`, any store but audit; `nick` and `envadmin` never reach SQLite (D18) |
| entry | `app/cmd/<p>/` | the profile (§6) | everything | — |

The rules that change:
- **Only the domain imports its store**, as "controllers never import repository" in the skeleton. Two importers are
  allowed besides: any domain, web or identity package for `store:audit` (§9), and a SQLite profile's `main` for
  `MIGRATIONS`.
- **A web package reaches another feature four ways only**: a domain import for a hard dependency (dashboard →
  contacts, video → uploads; D6), `notify_web` (the one web-to-web edge, §9), a hub topic named by string (§9), or a
  plain link (D6).
- **Below L4, platform never imports a feature except through a family.** `platform/app` imports `identity:`, whose
  members include feature packages; `platform/html` imports `client:` and `theme:`, which are platform packages and
  never import `platform/html` (that would be a cycle).
- **`front` moves from `platform/web` to `platform/app`** (PLAN §8.4). The identity packages import `platform/web` for
  their routes and cookies, so `platform/web` can't import `identity:` without a cycle (**NEW**: not prototyped).
- **Features never import `platform/app`**, so the typed env table moves to `platform/env` (L2) and each feature reads
  its own rows from there; `Search_Hit` moves to `platform/store` (L2), because domains return it.
- **Preferences travel on the `Viewer`** that the identity loads (theme, chat transport, mutes from `accounts_prefs`,
  X9), so chat, notify and `platform/html` read them without importing accounts (**NEW**).

**Platform work that touches an optional package, without a callback** (**NEW**). The old plan left these to
`Module_Ops`, the store vtable or `platform/app`; each is now a direct call in one direction:
- **The pure-trap reset** of the loop's reader statements (D15 rule 3) is pulled, not installed: `platform/guard`
  counts recoveries per thread, and `platform/store/sqlite` compares that count before each use of the loop's reader
  and resets every statement when it has moved. `guard` never calls into SQLite, so a memory profile still links no
  SQLite (D18).
- **SQLite numbers for ops** (`sqlite3_db_status`, writer queue, pool depth) are pushed to `platform/obs` by
  `platform/store/sqlite` on its own timer. `ops` reads obs and never imports the store, so `streams` keeps ops
  without SQLite.
- **CLI flags owned by an optional package** are answered by that package, called from `main`: `--backup` and
  `--adopt-profile` by `store_sqlite.open`, `--hash-password` by `identity.cli` in the identities that check an
  argon2id hash (`accounts`, `envadmin`; `nick`'s and `anonymous`'s `cli` answer nothing). `platform/app` answers
  only the platform's own (`--features --routes --limits --healthcheck --worker`), so a profile without SQLite or a
  hashing identity links neither for a flag.
- **Feature health and limits** are pushed to `platform/obs` as data. `status`, `modules` and `/readyz` read obs and
  `platform/env`, plus the tables `platform/app` holds after `app.serve`; none of them imports a feature.

## 6. A profile: four hand-written files

`app/cmd/<p>/` holds `brand.odin` (`BRAND`, the nav per host, copy), `routes.odin`, `main.odin` and
`routes_test.odin`, all hand-written, as `SK/app/src/main.odin` and `SK/app/src/routes.odin` are. The generator writes
them for a new project and edits them when a feature is added or removed (§10); CI checks that they agree (§11).

**`routes.odin`** mounts one line per package in each host's table, and writes the profile's own rows: the root, and
any page the profile places outside its package's table. From `streams`, which has one host:

```odin
package main

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import "../../platform/workers"
import identity "identity:."
import chat_web "../../features/chat/web"
import home_web "../../features/home/web"
// … the other web packages

// The skeleton's src/routes.odin, as one line per mounted package plus the profile's own rows.
ROUTES := [?][]web.Route{
	web.ROUTES[:],                                       // the main host's platform rows: /healthz /livez /readyz /metrics /sitemap.xml …
	web.PUBLIC_ROUTES[:],                                // every host's: /static /events /robots.txt /favicon.ico /licenses /csp-report
	{{.Get, "/", home_web.page_today, .Public, {}, 0}},  // the root: Today
	identity.ROUTES[:],                                  // /login /logout: the nickname form
	notes_web.ROUTES[:],                                 // /notes
	chat_web.ROUTES[:],                                  // /chat, the room page, post, the transports' rows, /admin/chat
	notify_web.ROUTES[:],                                // /notify
	bot_web.ROUTES[:],                                   // /bot, /admin/bot
	ops_web.ROUTES[:],                                   // /admin/ops
	status_web.ROUTES[:],                                // /status
	about_web.ROUTES[:],                                 // /about
}

// Subscribable topics, mounted the same way: a subscription to chat.room:12 runs that row's subscribe
// (perm, then the keyset replay by rowid, D13), as a GET runs a route's handler.
TOPICS := [?][]hub.Topic{
	home_web.TOPICS[:],     // home.presence
	chat_web.TOPICS[:],     // chat.room, chat.presence, chat.typing, chat.reply
	notify_web.TOPICS[:],   // notify.user
	bot_web.TOPICS[:],      // bot.health, bot.ask
	ops_web.TOPICS[:],      // ops.panel
}

// One host. The third field says front runs the identity here (nick, which sets a cookie).
HOSTS := [?]app.Host{{"main", "SITE_URL", true, ROUTES[:], TOPICS[:], NAV[:]}}

// Scheduled jobs: platform/workers runs each row on its schedule; the jobs feature's "run now" looks a row up
// by its id, as the router looks up a route.
JOBS := [?][]workers.Job{
	notify_web.JOBS[:],     // notify.prune: read notifications after 30 days (D36)
	chat_web.JOBS[:],       // chat.retention
}
```

- **Tables are package-level**, because a slice literal inside a proc points into its frame (09 §4.4). Mounting
  another package's table, `chat_web.ROUTES[:]`, and writing the profile's own rows inline, `{{.Get, "/", …}}`, both
  compile under `-vet -strict-style` and run (14 (3) variant B; `$L2 b`).
- **`app.Host`** is `{name, site_env, identity, routes, topics, nav}`: the host's log and metrics label, the env var
  that names its origin, whether `front` runs the identity there, and its three tables. `$L2 b`'s `web.Host` holds
  the routes only; topics and nav per host are **NEW**.
- **Boot keys every row by prefix** (D9), per host, so order here matters only inside a prefix. `bin --routes` prints
  the flat table of each host.

**`main.odin`** is the boot sequence as plain calls, as `SK/app/src/main.odin` is. From `full`:

```odin
package main

import "../../platform/app"
import "../../platform/html"
import "../../platform/store"
import store_sqlite "../../platform/store/sqlite"
import identity "identity:."
import accounts_store "store:accounts"
import audit_store "store:audit"
import chat_store "store:chat"
import notify_store "store:notify"
// … one store import per SQLite-backed feature, for its MIGRATIONS
import "../../features/chat"
import "../../features/wiki"
import bot_web "../../features/bot/web"
import chat_web "../../features/chat/web"
// … the other web packages

// The Today page's cards in order, and find's sources: dispatch tables, the same kind as ROUTES.
HOME_CARDS := [?]html.Home_Card{chat_web.home_card, bot_web.home_card, video_web.home_card, lists_web.home_card, status_web.home_card}
FIND_SOURCES := [?]store.Find_Source{{"chat", chat.search}, {"wiki", wiki.search}, {"lists", lists.search}, {"calendar", calendar.search}}

// Every extension the main bundle needs (D19). Boot refuses a bundle whose /* exts: */ header differs.
BUNDLE_EXTS :: chat_web.EXTS + notify_web.EXTS + bot_web.EXTS + ops_web.EXTS + lists_web.EXTS + video_web.EXTS // + …

main :: proc() {
	app.boot("full")                       // PLAN §8.6 steps 1–3: --healthcheck and --worker, NOFILE, logger, the platform env
	identity.cli()                         // --hash-password: accounts checks an argon2id hash

	// Each reads its own env rows and declares its limits to obs. Nothing starts yet. notify before its producers.
	notify_web.init()
	chat_web.init()
	bot_web.init()
	// …
	home_web.init(HOME_CARDS[:])
	find_web.init(FIND_SOURCES[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)   // step 4: the boot checks (§11); --features, --routes, --limits answer here

	store_sqlite.open()                    // step 5: --backup and --adopt-profile, then DB_PATH and MEMMODE (PLAN §11)
	store_sqlite.migrate("accounts", accounts_store.MIGRATIONS[:])   // dependency order (PLAN §11.7)
	store_sqlite.migrate("audit",    audit_store.MIGRATIONS[:])
	store_sqlite.migrate("notify",   notify_store.MIGRATIONS[:])
	store_sqlite.migrate("chat",     chat_store.MIGRATIONS[:])
	// … one line per SQLite-backed store this build reaches; rows of features not migrated here stay, dormant

	app.serve(HOSTS[:], JOBS[:], BRAND)    // steps 6–10: seed, assets, bind, loops, banner; returns once the loops run
	ops_web.start()                        // the 1 Hz panel publisher
	bot_web.start()                        // the llama health probe

	app.wait()                             // PLAN §8.7 steps 1–2: the signal; /readyz answers 503, the accept op goes
	chat_web.drain()                       // step 3: each closes its own streams (WS 1012, SSE retry:, multipart's last boundary)
	bot_web.drain()                        // cancel generations
	term_web.drain()                       // tell terminal sessions
	app.shutdown()                         // steps 3–8 under their deadlines: grace, idle peers, active requests, timers, flush, exit 0 or 70
}
```

- **Migrations** are one call per store in dependency order, not one slice literal of pairs: the runner never holds a
  literal that points into `main`'s frame (09 §4.4), and `--adopt-profile` is read inside `migrate`. A memory
  profile's `main` has no `store_sqlite` import at all, and a `migrate` line left in one doesn't compile, since memory
  stores declare no `MIGRATIONS`.
- **The lifecycle is in `main`.** `start` runs once `app.serve` has the loops running (PLAN §8.6 step 9), and the
  `drain` calls sit between the signal and the platform's deadlines (PLAN §8.7 step 3), in the order written. The
  platform keeps the deadlines; `main` shows who drains what.
- **`HOME_CARDS` and `FIND_SOURCES`** are handed to the one feature that reads each, as `ROUTES` is handed to the
  router. The Today page shows the cards in the table's order, which no longer has to follow `NAV`. A source is a
  domain's `search`, which fills `store.Search_Hit` rows.
- **`brand.odin`** keeps `BRAND`, `NAV` (and `LAB_NAV` in `full`, §7) and the copy. Boot checks that every nav href
  is a GET route on its host.
- **`routes_test.odin`** runs the boot checks under `CMD=test ./build.sh <p>` (`$L2 b`: `odin test` passes for
  `skeleton` and `full`, and fails with 7 problems for `bad`).

**`full-vanilla`** is `full`'s four files built with `client=vanilla` (§3). It runs the core and twinned-behaviour
specs (D22) on the main host. Its lab host's `/scripting/live` builds one widget in hyperscript, which is inert under
the vanilla client; `lab` and `full` cover it (**NEW**; PLAN §7.1 left `scripting` and `compat` out of `full-vanilla`
for this reason).

## 7. Two hosts in one binary: Houston and houston-lab

`full` carries every catalog feature (ANSWERS round 3) on two hosts, from one binary and one container
(`starter-full`):

| Host | Origin env | Identity | Root | Mounts |
|---|---|---|---|---|
| `houston.alexh95.com` | `SITE_URL` | `accounts`: sessions, cookies | `home` at `/` (Today) | Houston's features (D29) |
| `houston-lab.alexh95.com` | `SITE_URL_LAB` | none: every viewer is the Guest, and nothing sets a cookie | `landing` at `/` (the catalog explorer) | every starter demo and lab page: `notes`; the skeleton's `contacts` (its contacts/events console), `gallery`, `about` (**NEW**: round 3 names no page for it) and `dashboard` at `/dashboard`; `lab` (the stream contract pages); `scripting`; `compat` |

From `full`'s `routes.odin`:

```odin
// Houston proper.
MAIN_ROUTES := [?][]web.Route{
	web.ROUTES[:],
	web.PUBLIC_ROUTES[:],
	{{.Get, "/", home_web.page_today, .Public, {}, 0}},          // the root: Today
	identity.ROUTES[:],                                          // /login /logout /register /invite /account
	accounts_web.ROUTES[:],                                      // /admin/accounts
	chat_web.ROUTES[:],                                          // /chat …
	// … one line per Houston package
}

// houston-lab: no identity runs here; every starter demo and lab page.
LAB_ROUTES := [?][]web.Route{
	web.PUBLIC_ROUTES[:],
	{
		{.Get, "/",          landing_web.page,   .Public, {}, 0},   // the root: the catalog explorer
		{.Get, "/dashboard", dashboard_web.page, .Public, {}, 0},   // the page `skeleton` mounts at /
	},
	dashboard_web.ROUTES[:],                                     // /ui/ping
	gallery_web.ROUTES[:],                                       // /components /forms /ui /validate
	contacts_web.ROUTES[:],                                      // /data /contacts /search /api/search
	about_web.ROUTES[:],                                         // /about
	notes_web.ROUTES[:],                                         // /notes
	lab_web.ROUTES[:],                                           // /lab/streams
	scripting_web.ROUTES[:],                                     // /scripting/*: .Lab_Host, .Nonce_Csp
	compat_web.ROUTES[:],                                        // /compat/*: .Lab_Host
}

// MAIN_TOPICS and LAB_TOPICS are mounted the same way; LAB_TOPICS holds lab_web.TOPICS only.
HOSTS := [?]app.Host{
	{"main", "SITE_URL",     true,  MAIN_ROUTES[:], MAIN_TOPICS[:], NAV[:]},
	{"lab",  "SITE_URL_LAB", false, LAB_ROUTES[:],  LAB_TOPICS[:],  LAB_NAV[:]},
}

JOBS := [?][]workers.Job{
	notify_web.JOBS[:],
	chat_web.JOBS[:],
	// … one line per package with jobs
	{
		{"notes.reset",    .Daily, notes_web.reset},             // houston-lab's demo data, reset nightly
		{"contacts.reset", .Daily, contacts_web.reset},
	},
}
```

**How the hosts work:**
- **A row answers on the host whose table mounts it.** `front` picks the host by `Host` (the origin's host without
  the port, as D10 matched `SITE_URL_LAB`) and routes only within that host's prefix map. A request whose `Host`
  matches no origin goes to the main host, where the canonical-host 301 still applies (PLAN §8.4). In `$L2 b`,
  `/dashboard` answers 200 on the lab host and 404 on the main one, `/chat` the reverse, `/scripting/live` only on
  the lab host and `/healthz` only on the main one.
- **The platform's rows** come in two tables: `web.ROUTES` (the probes, `/metrics`, the sitemap and the ownership
  proofs) for a site's main host, and `web.PUBLIC_ROUTES` (static assets, `/events`, `robots.txt`, `favicon.ico`,
  `/licenses`, `/csp-report`) for every host.
- **Topics are per host too** (**NEW**): `/events` on houston-lab subscribes only to the families in `LAB_TOPICS`
  (the lab's stream demos), so a page there can't subscribe to Houston's topics even as a Guest.
- **Prefix uniqueness is per host.** Each host has its own prefix map, and on one host a router key belongs to one
  feature. The prefix rule itself (D9) is per feature, so it reads the same on every host: `/chat` is chat's wherever
  it is mounted, and one package may be mounted on both hosts (the platform's public rows are). `tools/check routes`
  checks ownership per host (`$L2 b`: `prefix "/chat" claimed by dashboard (app/cmd/bad/routes.odin(23)) and chat`),
  and boot refuses a router key fed by two mounted tables on one host (**NEW**).
- **One root per host.** Each host's table has exactly one `GET /` row, written in `routes.odin`, never in a package's
  `ROUTES`. So one package's page can sit at `/` in one profile and elsewhere in another: the skeleton's dashboard is
  the root in `skeleton` and `/dashboard` on houston-lab, inside dashboard's own `/dashboard` prefix (`$L2 b`). Boot
  counts the roots per host, and `tools/check` refuses a root row inside a package table (`$L2 b`). D9's "home,
  dashboard and landing are mutually exclusive" becomes "one root per host": `full` has `home` on one host and
  `landing` on the other.
- **The lab rules.** `.Lab_Host` keeps its name (PLAN §2.11) and now means "mount only on a host where no
  cookie-setting identity runs": scripting and compat, whose pages need `eval` or change htmx's semantics, can sit on
  houston-lab or on `lab`'s one origin (identity `anonymous`), never on Houston's. A host whose `identity` field is
  false runs no identity, so each of its rows must declare `.Public`. A second host's env var must be set and name a
  different host than `SITE_URL`. All three are boot checks (`$L2 b`).
- **The demo data** lives in Houston's SQLite file, in the demo features' own tables (contacts keeps the skeleton's
  table names, PLAN §11.5). Each is capped, by `NOTES_CAP` and `CONTACTS_CAP` (**NEW**), and reset nightly by a job
  row that `full`'s `routes.odin` writes, as it writes the root: whether a feature's data is a capped demo is a fact
  about the profile, not the package. A feature's `reset` drops its rows and reseeds them as `SEED=1` does.
- **The lab host's pages** use the bare lab layout (no bell, no account menu) and its own nav, `LAB_NAV`, send
  `X-Robots-Tag: noindex` (the `lab` profile's origin holds the indexed copy), and link to Houston by absolute URL, so
  every crossing is a full navigation. Houston links to them from its footer (PLAN §13.2).
- **`lab` stays an independent witness** at `odin-htmx-starter.alexh95.com`, from its own binary and container
  (ANSWERS F2).

## 8. A feature end to end: chat

**Models** sit below the service, the views and both stores:

```odin
package chat_models

import "../../../platform/store"

Message :: struct {id, room, author, mention: u64, author_name, body, body_html: string, at: i64}
Room    :: struct {id: u64, slug, title: string, kind: Room_Kind}
Error   :: store.Error   // .None .Not_Found .Constraint .Failed

// The store contract; each store, in either family, checks its procs against these in contract.odin.
Store_Recent :: proc(room, before: u64, limit: int, out: ^[dynamic]Message) -> Error
Store_Insert :: proc(m: ^Message) -> Error
Store_Search :: proc(rooms: []u64, q: string, limit: int, out: ^[dynamic]Message) -> Error
```

**The store**, the SQLite member:

```odin
package chat_store_sqlite        // app/stores/sqlite/chat/store.odin

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/chat/models"

IMPL :: "sqlite"

SQL_RECENT :: `SELECT id, author, author_name, body_html, at FROM chat_messages
	WHERE room = ?1 AND id < ?2 ORDER BY id DESC LIMIT ?3`

recent :: proc(room, before: u64, limit: int, out: ^[dynamic]m.Message) -> m.Error {
	q := db.reader(SQL_RECENT)          // this loop's read-only connection (D16)
	defer db.reset(q)
	db.bind_id(q, 1, room); db.bind_id(q, 2, before); db.bind_int(q, 3, limit)
	// … the skeleton's next_row loop: log SQLite's message, return an Error, clone columns into the request arena
	return .None
}

MIGRATIONS := [?]store.Migration{{1, "0001_messages", #load("migrations/0001_messages.sql", string)} /* … */}
```

```odin
package chat_store_sqlite        // contract.odin: a drifted signature fails here, built or not

import m "../../../features/chat/models"

_ : m.Store_Recent : recent
_ : m.Store_Insert : insert
_ : m.Store_Search : search
```

**The domain** holds plain services, as the skeleton's `services` does:

```odin
package chat

import "core:strings"
import "../../platform/authz"
import m "models"
import chat_store "store:chat"

room_view :: proc(v: ^authz.Viewer, slug: string, out: ^[dynamic]m.Message) -> (room: m.Room, err: m.Error) {
	room, err = find_room(slug)
	if err != .None || !can_read(v, room) {
		return room, .Not_Found               // a private room is never revealed
	}
	return room, chat_store.recent(room.id, max(u64), 50, out)
}

check_post :: proc(v: ^authz.Viewer, room: m.Room, body: string) -> (msg: m.Message, problem: string) {
	text := strings.trim_space(body)
	if text == "" { return {}, "Say something first." }
	if len(text) > MAX_BODY { return {}, "That message is too long." }
	return {room = room.id, author = v.id, author_name = v.name, body = text,
		body_html = render(text), mention = mentioned(text)}, ""
}

post :: proc(msg: ^m.Message) -> m.Error {return chat_store.insert(msg)}
```

**Web** keeps its rows, topics and extensions in one file, next to its handlers. Its table lists the transports' rows
as well, because `chat_web` imports all four for the switch (§4):

```odin
package chat_web                 // routes.odin

EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS + chat_transport_multipart.EXTS + bit_set[web.Ext]{.Pending, .Upsert, .Prompt, .Targets, .Download}
ROOM :: "chat.room"

ROUTES := [?]web.Route{
	{.Get,  "/chat",                  index,                          .Chat_Read,     {.Private},           0},
	{.Get,  "/chat/r/([%w-]+)",       room_page,                      .Chat_Read,     {.Private},           0},
	{.Post, "/chat/r/([%w-]+)",       post_message,                   .Chat_Post,     {},                   4096},
	{.Get,  "/chat/r/([%w-]+)/ws",    chat_transport_ws.stream,       .Chat_Read,     {.Stream},            0},
	{.Get,  "/chat/r/([%w-]+)/since", chat_transport_poll.since,      .Chat_Read,     {.Fragment},          0},
	{.Get,  "/chat/r/([%w-]+)/parts", chat_transport_multipart.parts, .Chat_Read,     {.Stream},            0},
	{.Get,  "/chat/m/(%d+)/menu",     message_menu,                   .Chat_Read,     {.Fragment},          0},
	{.Get,  "/admin/chat",            moderation,                     .Chat_Moderate, {.Private, .Step_Up}, 0},
}   // sse has no row: it rides /events

TOPICS := [?]hub.Topic{
	{ROOM,            .Queue,  256, true,  subscribe_room,   nil},           // perm, then keyset replay by rowid (D13)
	{"chat.presence", .Latest, 256, false, subscribe_member, nil},
	{"chat.typing",   .Latest, 64,  false, subscribe_member, nil},
	{"chat.reply",    .Queue,  64,  false, nil,              store_reply},   // the bot's room answers (§9)
}
```

The handlers:

```odin
package chat_web                 // room.odin

import "core:strings"
import "../../../platform/hub"
import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"
import notify_web "../../notify/web"
import audit_store "store:audit"

room_page :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	msgs := make([dynamic]m.Message, context.temp_allocator)
	room, err := chat.room_view(v, req.url_params[0], &msgs)
	if err != .None { web.respond_store_error(req, res, err); return }

	t := transport_for(req, v)                       // preference, ?transport=, CHAT_TRANSPORT (PLAN §14.1)
	b := strings.builder_make(context.temp_allocator)
	chat_views.room(&b, room, msgs[:], v)
	pane(t, &b, room.slug)                           // §4's switch: a direct call per case
	web.impl(res, "chat.transport", name(t))         // x-impl: chat.transport=ws (D8)
	web.render_page(req, res, room.title, "/chat", strings.to_string(b))
}

post_message :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	room, err := chat.room_for_post(v, req.url_params[0])
	if err != .None { web.respond_store_error(req, res, err); return }
	msg, problem := chat.check_post(v, room, web.form(req)["body"])
	if problem != "" { web.respond_422(res, chat_views.form_error(problem)); return }
	if err = chat.post(&msg); err != .None { web.respond_store_error(req, res, err); return }

	// After the service returns, so services stay pure (D4). Rendered once for every viewer (PLAN §14.1).
	html := chat_views.bubble(msg)
	hub.publish(ROOM, msg.room, msg.id, html)
	if msg.mention != 0 { notify_web.send(msg.mention, "chat.mention", room_url(room), html) }   // a hard dependency (§9)
	if mentions_bot(msg) { hub.publish("bot.ask", msg.room, msg.id, msg.body) }                 // bot's row, if mounted (§9)
	web.respond_html(res, html)
}

hide_message :: proc(req: ^web.Request, res: ^web.Response) {
	// … moderation: hide, then publish the tombstone
	audit_store.append(web.viewer(req).id, "chat.hide", target, web.form(req)["reason"], "")   // a row, or a mod=audit line (§9)
}
```

**Writes are asynchronous under store v3.** The sketch is synchronous so it reads straight through. Under store v3 a
write commits on the writer task (D16), so `Store_Insert` carries the continuation the handler wants run on commit,
and the tail of `post_message` (publish, notify, respond) becomes that named proc in the same file. `store_memory`
calls it at once. A continuation names the caller's own next step, which is the "when" case of the rule in §1, so the
reading test still holds.

## 9. Cross-feature calls

- **Notify is a direct import.** `chat_web` imports `notify_web` and calls `notify_web.send(user, kind, ref, html)`,
  which stores the item through notify's domain and publishes the bell on `notify.user:<uid>` (D4 keeps publishes in
  web). Every producer does the same (chat, lists, calendar, polls, guestbook, bot, jobs; PLAN §14.2), so notify is a
  hard dependency of each, and the generator closes a selection over it. This is the one web-to-web import, and
  `tools/check imports` allows no other. `kind` is a namespaced string (`"chat.mention"`), so notify never names a
  producer's kinds; mutes per kind keep the same strings.
- **Audit is a store.** A package that audits does `import audit_store "store:audit"` and calls
  `audit_store.append(actor, action, target, reason, meta)`. The SQLite family writes an `audit_log` row; the memory
  family writes one `mod=audit` log line (`$L2 a`: `mod=audit actor=3 action=chat.post target=chat_messages:1` from
  `streams`, `audit: row 10 …` from `full`). It is the one store any domain, web or identity package may import: an
  append-only log has no rules for a domain to add. The `audit` feature's page, `/admin/audit`, reads through
  audit's domain and is mounted only in SQLite profiles.
- **The bot's room mode runs over hub topics with static rows.** `chat_web` publishes a message that mentions the bot
  on `bot.ask:<room>`, by name. `bot_web.TOPICS` holds the static row `{"bot.ask", .Queue, 64, false, nil,
  room_ask}`, whose `deliver` proc the hub runs once per publish, as the router runs a route's handler. `room_ask`
  starts the backend and streams upserts of `#m-<id>` to `chat.room:<room>`; the finished answer goes back on
  `chat.reply:<room>`, chat's own static row, which stores it as a message from the bot and publishes the persisted
  bubble. Neither feature imports the other. Without bot, nothing mounts `bot.ask`, so the publish reaches no row and
  is dropped and counted; `tools/check topics` requires every family a package publishes to by name to be declared
  by some package, so a typo fails CI (**NEW**: the `deliver` field and the check are not prototyped). A subscription
  made in `main` at run time would be the observer pattern (14 (5) (b)); a static row is a dispatch table.
- **The admin's bot default** moves from `/admin/modules` to bot's own `/admin/bot`, which bot owns by D9's prefix
  rule. `modules` shows the value, which bot pushes to `platform/obs`, and links to the page: a plain link (D6), so
  `modules` never imports bot.
- **The Today cards and find's sources are tables in `main`** (§6): `home_web` and `find_web` call each row in order,
  and import no other feature.
- **Jobs are the third dispatch table.** A package with scheduled work keeps `JOBS := [?]workers.Job{{"notify.prune",
  .Daily, prune}}` next to that work, and `routes.odin` mounts it as it mounts `TOPICS`; a profile may write its own
  rows too (§7's demo resets). `app.serve` hands the table to `platform/workers`. The `jobs` feature's "run now" and
  cancel call `workers.run_now(id)` and `workers.cancel(run)`, a lookup by id like a route's; workers keeps each
  run's state as data, and `jobs` reads it into `jobs_runs` and publishes `jobs.runs`, so workers never calls a
  feature. Job ids carry the feature prefix, as topics do.
- **Unchanged** (D6): domain imports for hard dependencies (dashboard → contacts, video → uploads); plain links for UI
  composition; hub topics for genuine broadcasts; no foreign keys or cascades across features.

## 10. What the generator writes

`tools/init` keeps the skeleton's plan-then-commit engine and the composing behaviour of D26.

| File | When | What |
|---|---|---|
| `app/cmd/app/{main,routes,routes_test,brand}.odin` | a new project | §6's four files for the selection: imports, `init` calls in dependency order, `start` and `drain` calls, `store_sqlite.open` and one `migrate` per SQLite-backed store (SQLite family only), the host tables with the root row, `TOPICS`, `JOBS`, `HOME_CARDS`, `FIND_SOURCES`, `BUNDLE_EXTS`, `HOSTS`, the nav |
| `build.{sh,bat}` | a new project | one profile, `app`, with the selection's four families |
| `ols.json` | a new project | the four collections pinned to the project's families |
| `UPSTREAM.md`, `.github/workflows/ci.yml`, `CHANGELOG.md`, `TODO.md` | a new project | as before (10 §6): the command line and the selection; the CI matrix trimmed to `app` |
| the same four profile files, `build.*`, `ols.json` | `--add <f>`, `--without <f>`, the family commands | edits in place |

- **Edits are planned against the parsed file.** `core:odin/parser` finds each table literal and the call block, and
  each edit is a literal insertion or deletion of one line: an import, a mount line per host table, a `TOPICS` or
  `JOBS` line, an `init`, `start` or `drain` call, a `migrate` line, a home-card or find-source row. If a file doesn't
  have the shape the plan expects, the engine aborts with nothing written (`SK/tools/init/plan.odin:228-239`) and says
  which file to fix by hand. `--without` also deletes `features/<f>/`, `app/stores/*/<f>/`, `e2e/tests/<f>` and
  `load-tests/scenarios/<f>`.
- **The family commands** edit the profile's line in `build.*` and `ols.json`: `--store sqlite|memory`,
  `--identity accounts|envadmin|nick|anonymous`, `--client`, `--theme`. The per-axis `--impl` commands go: every
  transport and both bot backends are always linked, the games catalog follows `GAMES_API_URL`, and the wiki and
  video follow the store family.
- **`--verify`** applies the plan to a scratch copy, builds through `build.*`, runs `tools/check profile` and compares
  `bin --features --json` (the profile, the family members' `NAME`s and the route ids per host) with the plan before
  touching the tree.
- **Lean defaults**: the memory family, `nick` (or `anonymous` when the selection has `scripting` or `compat`), the
  vanilla client, the lite theme, `home` as the root. **Refusals come with advice**: "contacts has no memory store;
  use --store sqlite", and two roots on one host.
- **Hello world for any selection** (D27) is unchanged in substance: the leanest families plus a root feature. So
  `init myapp --features chat` writes chat, notify (its hard dependency) and home, and boots to Today with chat's card
  over all four transports, on the memory store and the nick identity.
- **In CI** the generator job runs `tools/check profile` on every committed profile instead of D7's `--emit --like`
  byte comparison, and keeps its singleton and pairwise runs (D27, D37).

## 11. Checks

**At boot**, in `app.check`, and in CI through `app/cmd/<p>/routes_test.odin`, per host. Each is fatal with a
message:
1. a duplicate route id `"<METHOD> <pattern>"` on one host, or a row with no handler;
2. a row whose prefix or flags need a perm (`/admin/*`, `.Step_Up`, `.Lan_Only`) but that declares `.Public` (X4);
3. not exactly one root row (`GET /`) on a host;
4. a `.Lab_Host` row on a host where a cookie-setting identity runs; a row with any perm but `.Public` on a host
   with no identity; a second host whose env var is unset or names `SITE_URL`'s host (D5, D25). `identity.SETS_COOKIE`
   is a constant, but the env is read at boot, so this check stays at boot;
5. a router key fed by two mounted tables on one host (**NEW**);
6. the `BUNDLE_EXTS` constant differs from the embedded bundle's `/* exts: … */` header ("run prepare"; D19);
7. a nav href with no GET route on its host;
8. a topic family mounted twice on a host, or a persisted topic with no subscribe; a job id mounted twice.

`$L2 b` prototyped 1–4: the `bad` profile trips 1, 3 and 4 (8 problems at boot, 7 under `odin test`, which sets
two distinct origins), and no row of it trips 2 or lacks a handler. An unknown env var inside a known prefix is a
warning, given after the `init` calls have recorded their rows.

**Statically**, in `tools/check`, with no build, over `core:odin/parser` (`$L2 b tools/check`, 264 lines, and
14 (3)'s 205-line route checker):
- `profile`: every feature package the profile imports is mounted (its `ROUTES` on some host, its `TOPICS` and `JOBS`
  mounted, its `init` called when it declares one); no orphan routes (no `ROUTES` table in the tree that no committed
  profile mounts); every store with `MIGRATIONS` that a SQLite build reaches has a `migrate` line in `main`. `$L2 b`
  prototyped the first: "notes_web is imported, but no host mounts notes_web.ROUTES" (imported for its `init` only).
  The rest is **NEW**;
- `routes`, per host: each row inside its feature's prefixes (`/<f>`, `/admin/<f>`, `/api/<f>`, plus the README
  exceptions of D9), no router key claimed by two features, exactly one root, and no root row inside a package's
  `ROUTES`; `ROUTES` only in web, switched impl and identity packages. `$L2 b` prototyped the first four: 0 problems
  for `skeleton` and `full`, 5 for `bad`'s routes (and the one `profile` problem above);
- `topics`: each family and each job id prefixed by its declaring feature's name and declared once; every family a
  package publishes to by literal name declared by some package (§9);
- `contracts`: every proc type in a `models` contract has a typed-constant line in that feature's store in each
  family that has one; every identity checks `authz.Load_Viewer`;
- `imports`: each package's import lines against §5's table. `store:<f>` only from `f`'s domain, `store:audit` from
  any domain, web or identity package, either from a SQLite profile's `main`; `identity:` from `platform/app` and `cmd`;
  `client:` and `theme:` from `platform/html`; a web package imports no other web package but `notify_web`;
- `exts`: every `EXTS` declaration on one line, and `BUNDLE_EXTS` naming every mounted package that declares one.

**With the compiler**, in CI:
- `CMD=check ./build.sh <p>` for every profile, because each call site is checked only against its build's family
  members;
- `odin check app/stores/<family>/<f> -no-entry-point -vet -strict-style -warnings-as-errors` for every store in both
  families. Stores import no collection, so they check alone, and one that no profile builds can't rot (`$L2 a`: all
  eight store packages exit 0, and a drifted one fails in its own `contract.odin`). A family directory itself is not
  a package ("Empty directory that contains no .odin files"), so CI loops over its subdirectories;
- **domains, views, web packages, switched implementations and identities don't check alone**: they reach a
  collection ("Unknown library collection: 'store'", `$L2 a`; 14 critic e6). CI checks them under each selecting
  profile's line, and `identity_envadmin`, which no hosted profile selects, under a generated `--identity envadmin`
  selection in the nightly matrix (**NEW**);
- `odin test features/<f>` under each profile that mounts `f`, and `features/<f>/storetest` with both stores imported
  directly (`$L2 a`).

**Bundle derivation** (D19) keeps "one definition". `tools/bundle <p>` takes the package list from the compiler,
`./build.sh <p> -export-dependencies:json`, which resolves the four collections and lists exactly the selected
members (`$L2 a`: `streams` lists `stores/memory/*`, `client/vanilla`, `identity_nick` and `theme/lite` and no
SQLite package; `full` lists `stores/sqlite/*` with their migrations), and unions the `EXTS` of those packages. Boot
compares that header with `main`'s `BUNDLE_EXTS` constant. X33's runtime union over vtable `exts` fields goes.

**Route-coverage parity** (PLAN §19.1.11) is unchanged, per host: `bin --routes --json` prints each host's route ids,
each id keys its request counter, and `tools/check parity` requires a non-zero counter after both the e2e run and the
k6 run, with waivers in `tests/parity-waivers.txt`. `rbac.spec` runs every route × both hosts in `full` (PLAN
§17.2); the robots Disallow lines (`.Fragment` rows) and the sitemap (`NAV`) are derived per host.

## 12. Costs, plainly

1. **Build-flag plumbing.** Bare `odin build app/cmd/<p>` no longer works; it needs four flags. Odin has no response
   files ("Invalid flag: @mem.rsp", 14 (1)), so the flags live in `build.{sh,bat}`, which every script, CI job, the
   Dockerfile and the generator call. spark already builds with a collection flag (`-collection:spark=/src`, 09
   §4.3). 09 §5's flag-free build is overturned.
2. **The editor sees one member per family**, `full`'s (§3). Editing another member works as a standalone package;
   following a call into it means switching one `ols.json` line. Not tried in an editor.
3. **Fewer packages check alone.** Domains, views, web packages, switched implementations, identities,
   `platform/html` and `platform/app` need a profile's flags; stores and platform L1–L2 check alone.
4. **One store family per build.** A profile can't put chat in SQLite and notes in memory, as D8 allowed. No hosted
   profile wants that.
5. **Every chat profile ships all four transports** (X29's "a poll-only chat ships no ws" goes): ws, sse,
   hx-multipart and ptag are in every chat bundle and binary. Their size isn't measured here.
6. **Both bot backends and both games catalogs are linked** wherever their feature is. Both members are pure Odin.
7. **Notify comes with every producer.** A chat selection always carries notify, so chat's hello world gains the bell.
8. **The generator edits hand-written files.** `--add` and `--without` must find each table and call block in files
   people edit; a profile reshaped beyond the expected shape makes the generator stop and name the file. CI checks
   consistency, not bytes, so a hand edit that keeps the profile consistent passes, and one that leaves a package
   unmounted fails.
9. **Ownership is static.** Boot sees duplicate ids, roots, keys fed by two tables and the lab rules per host, but
   which feature may claim a prefix is `tools/check`'s, since the binary can't tell which feature a profile row's
   handler belongs to (14 (3)). A build that skipped CI could boot with a row outside its feature's prefixes.
10. **Two hosts share one process and one SQLite file.** houston-lab's demo tables sit beside Houston's, capped and
    reset nightly; a crash in a demo page is a crash of Houston's process, which the crash model contains as it
    contains any other (D15). This is F2's one-binary, two-origins choice, unchanged.
11. **Effort is about neutral (NEW).** There is no emitter for profile files and no alias layer, but the generator
    learns parse-based edits, and `tools/check` gains `profile`, per-host `routes` and `contracts`. This is an
    estimate, not a measurement.

The four flags cost nothing measurable in time: `streams` and `full` check in 138 ms (best of 5) and build in 277 and
281 ms (best of 3), in line with 14 (1)'s 115 ms check and 259 ms build of a one-collection program (`$L2 a`).

## 13. Rejected

- **A `sel:` collection per profile with generated alias packages** (this document's first version): one uniform flag,
  but a hop per aliased call, 14–30 generated files per profile, and aliases can't name a package variable (14 (1c)).
  ANSWERS round 3 chose imports that land on the real code.
- **Generated per-profile dispatchers** (`sel:chat_transports`, `sel:bot_backends` over each profile's own set): they
  kept X29's lean chat bundles at the cost of a generated package per runtime axis; a hand-written switch over all
  four is simpler (ANSWERS round 3).
- **The `SELECTION` mini-language, generated `main.odin` and `routes.odin`, and the `--emit --like` byte check**: one
  line to read, but a second syntax and a generator that is load-bearing for every profile; the profile files are
  hand-written, and CI checks their consistency.
- **Null-object seam packages** (`platform/none/{notify,audit,bot_reply}` behind `sel:` seams): notify is a direct
  import, audit a store, and room mode a pair of topics, so no seam is left to fill.
- **Generated fan-outs** (`sel:home_cards`, `sel:find_sources`, `sel:lifecycle`): the profile's `main` lists the cards,
  the sources and the lifecycle calls itself.
- **A collection per axis per feature** (`-collection:chat_store=…`): a flag per axis on every command, with no family
  rule to keep them consistent (14 (1)).
- **`when` + `#config` with every implementation imported**: `-vet` needs markers, false branches go unchecked, a value
  typo silently takes the `else` branch, and the import-derived bundle over-includes (14 (4)).
- **One flat route literal per profile**, exactly the skeleton's shape: easy to grep, but every row is repeated in
  every profile that mounts it; per-package tables keep one definition per route.
- **Root rows inside a package's `ROUTES`**: a package couldn't sit at `/` in one profile and `/dashboard` in another.
- **The `.Lab_Host` gate as a flag filter in `front`**: per-host tables say which rows answer where, and the flag
  stays only as a mount rule.
- **A run-time `hub.subscribe` in `main` for room mode** (14 (5) (b)): the observer pattern; a static row is a dispatch
  table.
- **A build-time choice for the games catalog and the bot backend**: both members are pure Odin, so there is nothing
  to keep off the linker.
- **The bot default on `/admin/modules`**: it needs a hard import of bot or a seam; `/admin/bot` needs neither.
- **`STORE=sqlite|memory` at boot** (D8, D10): no build links both families.

## 14. What is deleted, and what survives

| Deleted | Replaced by |
|---|---|
| `Feature` struct and each feature's `register()` (D5, D7) | per-package `ROUTES`, `TOPICS`, `JOBS` and `EXTS`, mounted per host by `routes.odin`; explicit `init`, `start` and `drain` calls in `main` |
| proc-field vtables `Store`, `Transport`, `Bot_Backend`, `authz.Identity`, their `make_*` constructors and the implementation lists in `main` (D8, PLAN §7.2) | the store, identity, client and theme families on the build line; hand-written switches for the transports and the bot backend; contracts as typed constants in `models` |
| `platform/ports` and its installation at registration (D6) | notify by direct import, audit through `store:audit`, room mode over `bot.ask` and `chat.reply` |
| `Feature.nav`, `home_card`, `search`, `app.Search_Hit` | `NAV` and `LAB_NAV` in `brand.odin`; `HOME_CARDS` and `FIND_SOURCES` in `main`; `store.Search_Hit` (L2) |
| `Feature.ops` (`Module_Ops`) | health, metrics and limits pushed to `platform/obs` by direct calls; `start` and `drain` called by `main`; `zone` dropped, because the guard's counters already decide pure or dirty (PLAN §10.2 rule 3) |
| `Feature.env`, `jobs`, `migrations`, `topics` | `platform/env` reads in each `init`; `JOBS` tables; one `migrate` call per store in `main`; `TOPICS` tables |
| what the old plan left to `Module_Ops`, the store vtable or `platform/app`: the pure-trap reader reset, SQLite stats for ops, `--backup` and `--hash-password` | pulled by `store/sqlite`, pushed to obs, answered by their owners from `main` (§5) |
| the bot-default switch on `/admin/modules` (D8, D31) | bot's own `/admin/bot`, linked from `modules` |
| `Feature.requires` and `app.Capability` | a build that reaches a missing family member fails to compile, and the generator refuses first with advice |
| `Feature.extensions`, the vtable `exts` field and X33's register()-union check | `BUNDLE_EXTS` in `main` against the bundle header; `tools/bundle` over the compiler's package list |
| the per-feature store choice and `STORE` at boot (D8, D10) | one store family per build |
| X29's lean transport sets | every chat profile ships the four transports |
| D7's `--emit --like` byte check | `tools/check profile` |
| the `.Lab_Host` host filter in `front` (PLAN §8.4 step 2) | per-host tables in `HOSTS` |
| 09 §5's flag-free `odin build cmd/<p>` | `build.{sh,bat} <profile>` |

**Survives unchanged in substance**:
- the per-feature split into separate packages, and the strict layering enforced by `tools/check imports`;
- `web.Route` with perm, flags and body cap, route ids, and the prefix rule and prefix-first router (D9), now per
  host;
- hand-written profile entry files with the selection in their import lines (D7), and `brand.odin`;
- **the per-request switching rule** (D8): transport axes and the bot backend only, always announced in `x-impl` and
  `impl=`. The admin's runtime bot default stays an in-memory value, audited and reset on restart, now set on
  `/admin/bot`;
- the one-line `EXTS` and the fatal bundle-header check (D19);
- per-feature migrations and their runner (PLAN §11.7), and D18's claim and its CI proof;
- the generator's compose, lean defaults and refusals, and its singleton and pairwise CI runs;
- no foreign keys or cascades across features, domain imports for hard dependencies, and plain links (D6);
- topic names and policies (D13);
- `@(init)` rejected, `#config` only for `VERSION`, `TEST_ROUTES` and `PROFILE`, and no compiled feature disabled at
  run time (Q28);
- `full`'s one binary on two origins, with no session on the second, and `lab` as an independent witness (ANSWERS F2).

## 15. Changes to DECISIONS.md, SETTLED.md, RESOLUTIONS.md and PLAN.md

New text in brief; the full wording is in DECISIONS.md and PLAN.md, folded in on 2026-10-26.

| Id | New text |
|---|---|
| S17 | "explicit `register()` calls; proc-field vtables; runtime env selection among imported" → "hand-written `main.odin` and `routes.odin` per profile; the store, identity, client and theme families as collections on `build.{sh,bat} <profile>`'s line; hand-written switches for the transports and the bot backend" |
| S9 | "through a Store vtable" → "through `store:<f>`, the build's store family" |
| D4 | add `f_models`; stores move to `app/stores/<family>/<f>/` (`<f>_store_<family>`), importing `f_models` and platform L1–L2 only; the domain imports `store:<f>`; switched impls are web-side; `store:audit` from any domain, web or identity package; `notify_web` the one web-to-web edge; delete `platform/ports`; the env table → `platform/env` and `Search_Hit` → `platform/store`; `platform/app` (L4) imports `identity:` and holds `front`; `platform/html` imports `client:` and `theme:`; `anonymous` → `platform/authz/anonymous`; request path "store vtable" → "store family" |
| D5 | delete `Feature`; keep `Route`; per-package `ROUTES`/`TOPICS`/`JOBS`; root rows written in `routes.odin`; `app.Host` and per-host tables; boot checks per §11; prefix ownership, root rows in package tables and mount completeness move to `tools/check`; delete `requires`; README env tables from `bin --limits --json` |
| D6 | ports → notify by direct import, audit through `store:audit`, room mode over static topic rows; Feature fields → `HOME_CARDS`, `FIND_SOURCES`, obs pushes, `TOPICS`, `JOBS`; "no open registries" stays |
| D7 | stands, with four hand-written files (`brand`, `main`, `routes`, `routes_test`); the generator writes them for a new project and edits them on add or remove; CI's `tools/check profile` replaces the `--emit --like` byte check |
| D8 | vtables → the four families (build) and hand-written switches (per request), costs from 14 (2); the games catalog by `GAMES_API_URL`; the wiki and video catalogs follow the store family; one store family per build; delete `STORE`; the bot default on `/admin/bot`; the switching rule and `x-impl` unchanged |
| D9 | one prefix map per host, built at boot from that host's tables; one root per host, written in `routes.odin` (dashboard at `/dashboard` on houston-lab); "home, dashboard, landing mutually exclusive" → "one root per host"; ownership checked statically per host |
| D10 | the env table moves to `platform/env`; rows are recorded by each `init`, which starts nothing; `--features --routes --limits` answer in `app.check` after the inits (PLAN §8.6 step 1 splits); `--backup` and `--adopt-profile` by `store_sqlite.open`, `--hash-password` by `identity.cli`; `SITE_URL_LAB` names `HOSTS`' second host; add `NOTES_CAP`, `CONTACTS_CAP` (NEW); delete `STORE` |
| D13 | topics declared in per-package `TOPICS` (family, policy, ring, persisted, subscribe, deliver) and mounted per host; `deliver` runs a server-side row once per publish (room mode) |
| D15 | drop `Module_Ops.zone`; rule 3's counters decide; the pure-trap reader reset is pulled by `store/sqlite` from guard's recovery count (§5) |
| D16 | the writer task runs each write's continuation on its loop; the continuation (web side) publishes the persisted topic, so `store/sqlite` never imports `hub`; `store/sqlite` pushes `sqlite3_db_status` numbers to obs |
| D18 | "imports only `store_memory` implementations" → "built with `-collection:store=app/stores/memory`, whose `main` doesn't import `platform/store/sqlite`"; a memory build that reaches a SQLite-only store fails to compile; CI proof unchanged |
| D19 | `tools/bundle` reads the compiler's `-export-dependencies:json` of `build.sh <p>`; `BUNDLE_EXTS` in `main`; delete X33's vtable path |
| D21, D25 | `full`'s lab host carries every starter demo and lab page (ANSWERS round 3), with `landing` at its root and capped demo data reset nightly; `.Lab_Host` becomes a mount rule; per-host tables replace the host filter in `front` |
| D22, D23 | client and theme are the `client:` and `theme:` families, read by `platform/html` |
| D24 | `full` covers every catalog feature on two hosts; `full-vanilla` is `app/cmd/full` built with the vanilla client; a slice adds its feature's lines to the profiles that mount it |
| D26 | the generator writes §10's files for a new project and edits them on `--add`/`--without`; the family commands edit `build.*` and `ols.json`; the per-axis `--impl` commands go; `--verify` uses `build.*` and `tools/check profile`; `--without` deletes `app/stores/*/<f>/` |
| D27 | "every feature registers a `home_card`" → "every feature with a page exports `home_card`; `main`'s `HOME_CARDS` lists them in order" |
| D29 | Houston proper on `houston.alexh95.com`; the starter demos and lab pages on `houston-lab.alexh95.com` |
| D31 | `Bot_Backend` vtable → the `switch` in `bot_web`; room mode over `bot.ask` and `chat.reply`; the default switch on `/admin/bot` |
| D33, D34 | the video catalog follows the store family; the games catalog by `GAMES_API_URL` |
| D35 | `authz.Identity` vtable → the `identity:` family (contract `authz.Load_Viewer`), called by `platform/app`'s front; preferences ride on the `Viewer`; no identity runs on a host whose `identity` field is false |
| D36 | notify by direct import; find and home over `main`'s tables; `status` and `modules` read obs, env and the mounted tables; `jobs` over the mounted `JOBS` and workers' run state; `modules` links to `/admin/bot`; the wiki follows the store family |
| D37 | stores checked standalone in both families; switched impls and identities under a profile's line; a generated envadmin selection nightly; feature tests under each mounting profile; `storetest` imports both stores |
| D39 | `tools/check` gains `profile`, per-host `routes`, `topics`, `contracts` and the collection rules in `imports` |
| D40 | every job builds through `build.{sh,bat} <profile>`; `ols.json` pinned to `full`'s families |
| D45 | CLAUDE.md: "Ports" → "Families and switches"; recipes for a new store (a package per family + `contract.odin`), a new feature (its lines in each profile that mounts it), a new route (a row in the package's `ROUTES`, or the profile's own rows for a root); gotchas: the four flags, typed-constant contracts (not `#assert`), unique store package names, root rows only in `routes.odin` |
| X5 | one root per host |
| X29 | the lean transport sets go; implementation `EXTS` stay, unioned into `chat_web.EXTS` |
| X30 | `platform/app` stays L4, now importing `identity:` and holding `front`; features never import it |
| X33 | `platform/ext` stays; the vtable `exts` path is deleted |

PLAN.md sections to rewrite:
- §1.1 (the package-shape bullet), §1.2 (`full`'s row: every catalog feature on two hosts), §1.3 (the S17 row),
  §1.5 (#1 decided);
- §2.3 (`full-vanilla`), §2.4 (`houston-lab`'s row), §2.5 (`app/stores/`, root `build.{sh,bat}` and `ols.json`),
  §2.6 (drop `platform/ports`; `platform/app`; add `platform/env`, `platform/authz/anonymous`), §2.7 (`f_models`),
  §2.8 (stores by family; catalogs and wiki), §2.10 (`bot.ask`, `chat.reply`), §2.11 (`.Lab_Host`'s meaning; drop
  `app.Capability`, `Module_Ops.zone`, `STORE`), §2.12 (drop `STORE`; `NOTES_CAP`, `CONTACTS_CAP`), §2.13 (the
  seams table), §2.15 (root feature per host; lab host);
- §5.1–§5.3 and §5.5 (§5.2: `front`, the CLI flags and `Search_Hit` move as §5 says);
- §6.1–§6.5 (§6.3: one root per host);
- §7.1 (`full` and `full-vanilla`), §7.2, §7.3 (closes its **Open:** on "every feature"), §7.4, §7.5;
- §8.3 (a prefix map per host), §8.4 (the host gate by table), §8.6 (step 1 splits; steps 4–5 as `main`'s calls),
  §8.7 (step 3 through `main`'s `drain` calls), §9.2 (topic declaration, `deliver`, topics per host), §10.2 items 3
  and 7, §10.4 (`Module_Ops`), §11.1 (the writer task's continuations), §11.4, §11.5 (the demo tables), §11.6 (the
  demo caps and nightly reset), §11.7;
- §12.1 (bundle derivation; every chat bundle carries the four transports), §12.4, §12.5, §13.2 (the lab host's
  pages), §13.3 (the admin journey's bot default), §14.1–§14.3, §15.1 (find, lists, calendar), §15.3 (the catalog by
  env), §15.4 (status, jobs, modules), §15.5 (houston-lab's pages), §17.1, §17.2 (every route × both hosts), §17.7;
- §19.1.11 (per host), §19.1.12, §19.2.2 item 4 ("the feature's store vtable" → "the feature's store family"), §20.1;
- §22.3 (M1 gains `build.*`, `tools/check profile` and the `contracts` check; M4 gains houston-lab's demos), §22.6 (a
  risk for collection plumbing; R20 now covers per-host tables), §22.7.

## 16. Evidence notes (`$L2`)

Toolchain: the local Odin, `dev-2026-10-nightly:84bc3fc`, Windows 11, rad-link. As in 14 (1), the "SQLite" library
is a real static library built with clang 19.1.0 (`clang --target=x86_64-pc-windows-msvc -O2 -c fakesql.c -o
fakesql.obj && llvm-ar rcs fakesql.lib fakesql.obj`); it carries the string `FAKESQL_LIBRARY_LINKED`, so `grep -c`
on an executable shows whether the linker pulled it in, and both SQLite-family stores share its one counter. Each
command ran from the experiment's root, which stands for the repo root. `V` is `-vet -strict-style
-warnings-as-errors`, and absolute paths in compiler output are shortened to `…/`.

### `$L2 a`: the four families (43 files)

```
app/platform/{sqlite, store, store/sqlite, authz, app, html, client/{hyperscript,vanilla}, theme/{full,lite}}
app/features/{chat/{models,web,storetest}, chat, notify/{models,web}, notify, audit/models, contacts/models, contacts,
              accounts/{models, identity_accounts, identity_nick}}
app/stores/sqlite/{accounts, audit, chat, contacts, notify}/{store.odin, contract.odin, migrations/0001_*.sql}
app/stores/memory/{audit, chat, notify}/{store.odin, contract.odin}
app/cmd/{streams, full}/main.odin       build.sh (streams: memory, nick, vanilla, lite; full: sqlite, accounts, hyperscript, full)
```

`platform/app` imports `identity "identity:."`, `platform/html` imports `client "client:."` and `theme "theme:."`,
the domains import `store:<f>`, and `chat_web` imports `notify_web` and `audit_store "store:audit"`.

Every store package checks alone, and the domain checks under either family:
```
$ for d in app/stores/sqlite/* app/stores/memory/*; do odin check $d -no-entry-point $V; done
(accounts audit chat contacts notify; audit chat notify)   [exit 0] × 8
$ odin check app/features/chat -no-entry-point -collection:store=app/stores/memory $V    [exit 0]
$ odin check app/features/chat -no-entry-point -collection:store=app/stores/sqlite $V    [exit 0]
$ odin check app/features/chat -no-entry-point $V
…/app/features/chat/chat.odin(7:1) Syntax Error: Unknown library collection: 'store'
$ odin check app/stores/sqlite -no-entry-point $V
Syntax Error: Empty directory that contains no .odin files: …/app/stores/sqlite
$ CMD=check ./build.sh streams    [exit 0]
$ CMD=check ./build.sh full       [exit 0]
$ odin check app/cmd/streams $V                     (no flags)
…/app/features/notify/notify.odin(4:1) Syntax Error: Unknown library collection: 'store'
…/app/platform/html/html.odin(6:1) Syntax Error: Unknown library collection: 'client'
…/app/platform/app/app.odin(6:1) Syntax Error: Unknown library collection: 'identity'
…/app/platform/html/html.odin(7:1) Syntax Error: Unknown library collection: 'theme'
(and the same for store:chat and store:audit)   [exit 1]
```

The memory family never reaches the linker with the C library:
```
$ ./build.sh streams -print-linker-flags | grep -c fakesql
0
$ ./build.sh streams -print-linker-flags | grep -o '/subsystem.*'
/subsystem:CONSOLE /machine:x64    "kernel32.lib" "bcrypt.lib" "kernel32.lib"
$ ./build.sh full -print-linker-flags | grep -o '/subsystem.*'
/subsystem:CONSOLE /machine:x64    "kernel32.lib" "bcrypt.lib" "kernel32.lib" "…/clib/fakesql.lib"
$ grep -c FAKESQL_LIBRARY_LINKED bin/streams.exe; grep -c FAKESQL_LIBRARY_LINKED bin/full.exe
0
1
sizes: streams 600,064 B, full 603,136 B
```

Both run, each on its own family members:
```
$ ./bin/streams.exe
boot streams identity=nick sets_cookie=true
hub.publish notify.user:7 chat.mention /chat/r/lobby (notify.store=memory)
mod=audit actor=3 action=chat.post target=chat_messages:1
<html data-client=vanilla data-theme=lite schemes=2><title>room</title><article id=m-1 data-behave="Auto_Scroll">ana: hello @ana</article>
chat.store=memory notify.store=memory recent=1
$ ./bin/full.exe
boot full identity=accounts sets_cookie=true
store: sqlite open
store: migrate accounts 0001_users
store: migrate audit 0001_log
store: migrate contacts 0001_contacts
store: migrate notify 0001_items
store: migrate chat 0001_messages
hub.publish notify.user:7 chat.mention /chat/r/lobby (notify.store=sqlite)
audit: row 10 actor=1 action=chat.post target=chat_messages:8
<html data-client=hyperscript data-theme=full schemes=23><title>room</title><article id=m-8 _="Auto_Scroll">alex: hello @ana</article>
chat.store=sqlite notify.store=sqlite recent=11 contacts=12
```
`full`'s `main` migrates with `store_sqlite.migrate("chat", chat_store.MIGRATIONS[:])`, a package variable named
across the collection with no wrapper.

The compiler's package list holds only the selected members:
```
$ ./build.sh streams -export-dependencies:json -export-dependencies-file:deps_streams.json
app/stores/memory/{audit,chat,notify}/{contract,store}.odin; client/vanilla, identity_nick, theme/lite; no platform/sqlite
$ ./build.sh full -export-dependencies:json -export-dependencies-file:deps_full.json
app/stores/sqlite/{accounts,audit,chat,contacts,notify}/{contract,store}.odin and each migrations/0001_*.sql;
client/hyperscript, identity_accounts, theme/full, platform/sqlite, store/sqlite
```

A drifted store fails in its own package (a copy of the memory chat store with `insert` given a second parameter
and `recent` renamed):
```
$ odin check app/stores/drift/chat -no-entry-point $V
…/app/stores/drift/chat/contract.odin(5:1) Error: Cannot assign 'insert' of type 'proc(^Message, u64) -> Error' to 'Store_Insert'
	_ : m.Store_Insert : insert
…/app/stores/drift/chat/contract.odin(6:22) Error: Undeclared name: recent
	_ : m.Store_Recent : recent
[exit 1]
```

A memory build that reaches a SQLite-only store does not compile (D18's refusal):
```
$ odin check app/cmd/full -collection:store=app/stores/memory -collection:identity=app/features/accounts/identity_accounts -collection:client=app/platform/client/hyperscript -collection:theme=app/platform/theme/full $V
…/app/features/accounts/identity_accounts/identity.odin(4:1) Syntax Error: Path does not exist: store:accounts
…/app/cmd/full/main.odin(14:1) Syntax Error: Path does not exist: store:contacts
[exit 1]
```
The prototype's `identity_accounts` imports `store:accounts` itself; in the design it goes through the accounts
domain (§5), which reaches the same import and fails the same way.

The conformance suite imports both chat stores into one binary:
```
$ odin test app/features/chat/storetest $V
Finished 2 tests in 1.2846ms. All tests were successful.
```

Time (best of 5 for check, best of 3 for build): `CMD=check ./build.sh streams` 138 ms, `full` 138 ms;
`./build.sh streams` 277 ms, `full` 281 ms.

### `$L2 b`: per-host tables, the root rule and the checks

```
app/platform/web/web.odin    Route, Host{name, site_env, identity, routes}, PUBLIC_ROUTES, ROUTES, check_hosts, dispatch (147 lines)
app/features/{home, dashboard, landing, notes, chat, scripting, oops}/web/web.odin
app/cmd/skeleton/            one host: the dashboard's page as the root row, dashboard_web.ROUTES (/ui/ping), notes
app/cmd/full/                MAIN_ROUTES (root: home; chat) and LAB_ROUTES (root: landing; /dashboard → dashboard_web.page;
                             dashboard_web.ROUTES, notes, scripting with .Lab_Host); HOSTS main (identity) and lab (none)
app/cmd/bad/                 two roots on main (one inside oops_web.ROUTES), none on lab, scripting on main, chat on lab,
                             dashboard_web.ROUTES mounted twice on lab, a dashboard row under /chat, SITE_URL_LAB = SITE_URL's
                             host, notes_web imported for its init only
tools/check/check.odin       the static profile check (264 lines)
```
Each `main` builds the env map (`SITE_URL`, `SITE_URL_LAB`), runs `web.check_hosts`, exits 1 on any problem, then
dispatches probe requests by `Host`. `identity.SETS_COOKIE` is a constant in each profile's `routes.odin`.

```
$ odin check app/cmd/skeleton $V; odin check app/cmd/full $V; odin check app/cmd/bad $V     [exit 0] × 3
$ odin run app/cmd/skeleton $V
starter-skeleton.alexh95.com Get /                -> [main] 200 dashboard page
starter-skeleton.alexh95.com Get /dashboard       -> [main] 404
starter-skeleton.alexh95.com Get /ui/ping         -> [main] 200 pong
starter-skeleton.alexh95.com Get /notes           -> [main] 200 notes list
$ odin run app/cmd/full $V
houston.alexh95.com      Get /                -> [main] 200 home: Today
houston.alexh95.com      Get /dashboard       -> [main] 404
houston.alexh95.com      Get /scripting/live  -> [main] 404
houston.alexh95.com      Get /chat            -> [main] 200 chat rooms
houston-lab.alexh95.com  Get /                -> [lab] 200 landing: the catalog explorer
houston-lab.alexh95.com  Get /dashboard       -> [lab] 200 dashboard page
houston-lab.alexh95.com  Get /ui/ping         -> [lab] 200 pong
houston-lab.alexh95.com  Get /scripting/live  -> [lab] 200 scripting: hx-live (eval)
houston-lab.alexh95.com  Get /chat            -> [lab] 404
houston-lab.alexh95.com  Get /static/app.js   -> [lab] 200 asset
houston-lab.alexh95.com  Get /healthz         -> [lab] 404
$ odin run app/cmd/bad $V
boot: host main: duplicate route id "Get /"
boot: host main: "Get /scripting/live" is .Lab_Host, but this host runs a cookie-setting identity
boot: host main: 2 root rows (GET /), want exactly 1
boot: host lab: SITE_URL_LAB names the same host as main
boot: host lab: duplicate route id "Get /ui/ping"
boot: host lab: "Get /chat" declares .Chat_Read on a host with no identity (every viewer is a Guest)
boot: host lab: "Get /admin/chat" declares .Chat_Moderate on a host with no identity (every viewer is a Guest)
boot: host lab: 0 root rows (GET /), want exactly 1
[exit 1]
$ odin test app/cmd/skeleton $V      Finished 1 test … The test was successful.   [exit 0]
$ odin test app/cmd/full $V          Finished 1 test … The test was successful.   [exit 0]
$ odin test app/cmd/bad $V           (both origins set) 7 problems logged; expected len(problems) to be 0, got 7   [exit 1]
```
The same `dashboard_web.page` answers `/` in `skeleton` and `/dashboard` on `full`'s lab host, and a row answers
only on the host whose table mounts it. The inline profile rows (`{{.Get, "/", …}}`) compile under `$V` inside a
package-level `[?][]web.Route`.

The static check, which the binary can't do (it can't tell which feature owns a profile row's handler, or which
table a row came from):
```
$ odin build tools/check $V -out:bin/check.exe    [exit 0]
$ ./bin/check.exe app/cmd/skeleton
host main: 7 rows, 2 prefixes, 1 root
app/cmd/skeleton: 1 hosts, 0 problems
$ ./bin/check.exe app/cmd/full
host main: 6 rows, 2 prefixes, 1 root
host lab: 8 rows, 4 prefixes, 1 root
app/cmd/full: 2 hosts, 0 problems
$ ./bin/check.exe app/cmd/bad
app/features/oops/web/web.odin(9): host main: the root row of oops sits in its ROUTES; write it in the profile's routes.odin
main: 2 root rows, want exactly 1
app/cmd/bad/routes.odin(23): host lab: dashboard may not claim "/chat"
app/features/chat/web/web.odin(9): host lab: prefix "/chat" claimed by dashboard (app/cmd/bad/routes.odin(23)) and chat
lab: 0 root rows, want exactly 1
app/cmd/bad: notes_web is imported, but no host mounts notes_web.ROUTES
app/cmd/bad: 2 hosts, 6 problems
[exit 1]
```
It reads `HOSTS` and each `[?][]web.Route` literal, follows every `x.ROUTES[:]` into its package, takes each row's
owner from the package's import path (or, for a profile row, from its handler's), and keys rows as D9 does, with the
README exceptions `/ui/ping` (dashboard) and `/ui` (gallery).
