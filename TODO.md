# TODO

Source of truth for outstanding work. Check items off as you finish them; add follow-ups you
discover. See `CLAUDE.md` for the standing policy. Keep this and `CHANGELOG.md` current.

## The project, in one line

This is a **starter skeleton** for a simple, server-rendered website on Odin + HTMX + SQLite —
clone it, rename it, strip the demo, build your thing. The bundled app (contacts/events admin
console + the theme library + the test/deploy harness) is the **worked example** that proves the
patterns, *not* the product. So "done" means *a great starting point*, not *a finished app*:
copy-and-start ergonomics and good defaults matter more than feature depth.

> Reframe: earlier docs ([`docs/USE_CASES.md`](docs/USE_CASES.md)) framed this as evolving into a
> "flagship admin console." That app is now explicitly the **example**, not the goal. Product-depth
> items (**bulk actions**, a **named console identity**) are **out of scope as goals** — they'd just
> be cruft a copier deletes — and survive only as "example extensions you might add."

## M2 — stream substrate, `streams` and the lab pages, generator v1 (v2.1.0)

The starter's second milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M2's row; §8.2 streams, §9 the hub, §12 the
client stack, §14.1–14.3 chat, notify and bot, §15.4–15.5 ops, status and the lab pages, §7.4 the generator, §19.1
the tests). Slices in order, each done only when its check passes; a later slice builds only on earlier ones (§22.4).
The S0.3 prototype (`docs/spikes/S0.3/server/`) and its specs (`e2e/spikes/S0.3/`) are where slices 1, 2 and 5
start. Every exit re-runs the skeleton parity gate (§18.2); tag v2.1.0 only when Alex says so; `FLY_DEPLOY` stays off.

- [x] **1. Stream protocols** (`platform/stream`, L3, over F-1 through `platform/web`, which stays the one importer of
      odin-http): the SSE encoder (CR, LF and CRLF each start a `data:` line; ids, named events; `: open` with the
      headers), the WS handshake (`Origin` = the host's origin, or none; version 13, else 426), the strict RFC 6455
      codec (RSV, masking, control frames, fragmentation, UTF-8 across fragments; 1002, 1007, 1009 at 64 KiB), ping
      and the 45 s pong deadline, 1013 before the queue passes its cap with F-1's 2 s deadline, 1012 on drain, 1011
      from `on_crash`; the multipart writer (boundary, CRLF framing, `Content-Length` per part, a preamble); the
      `.Stream` flag's headers; a `virtual.Arena` per stream. *Check:* unit tests from spark's RFC 6455 coverage
      table (03 §5.1, X24), the SSE encoder and a multipart round trip, leaks fatal; `tools/check imports` knows the
      package. Done: 10 unit tests, leak-free; the codec is exercised end to end by slice 5's lab specs. A
      stream's state is on the heap, not a per-stream arena (D12's as-built note: §18.4's 6 KiB a stream).
- [ ] **2. The hub** (`platform/hub`, §9.2–9.4): a shard per loop from F-4's thread hooks, one wakeup per loop per
      burst, the hub mutex a `guard.Mutex`, a ring per topic (`HUB_RING` 256), one refcounted message encoded once
      per transport, `.Queue`/`.Latest` (with the publish key)/`.Sample`, `TOPICS` rows mounted per host
      (`{family, policy, ring, persisted, subscribe, deliver}`), `<epoch ms>-<seq>` ids, the connect procedure
      (`Last-Event-ID`, then `after`, then the row's keyset replay, else `resync`), the caps (256 KiB per stream, 64
      MiB in all, 8/16/8192 streams, 64 KiB messages, 20 connects a minute per client → 429), a 20 s heartbeat per
      loop, kicks with close codes; `/events` in `platform/app`. *Check:* hub unit tests (publish, drain, replay,
      resync, each policy, each cap); a TSan build of hub and stream on Linux with only the nbio mpsc suppression.
      Progress: the hub, the caps (in `platform/stream`, since they cover every stream) and `/events` (`hub.ROUTES`,
      mounted by the profile, with `hub.mount` for its `TOPICS`: PLAN §7.2, D13 as built) are in, with unit tests of
      the rings, policies, cursors and topic names. End to end: the lab specs (slice 5) pass on Windows in Chromium,
      WebKit and the api project, replay, resync and the kick included, and drain and restart on a `TEST_ROUTES`
      build. Left: the Linux leg (CI's lab e2e, slice 16) and TSan (slice 13).
- [ ] **3. Page bundles and flags → CSP** (§12.1–12.2): `web.Bundle` and `BUNDLES` lines; `tools/bundle` builds
      Main plus every bundle a reached package names; the layout takes the bundle; the htmx-config meta from the
      union (strict JSON); `.Private` (no-store, noindex, `hx-history="false"`), `.Stream`, `.Nonce_Csp` (a nonce
      per response, the `hx-nonce` marker the writer replaces, no-store) and the `.Lab_Host` mount rule;
      `Reporting-Endpoints`, `report-to` and a rate-limited `/csp-report` in `streams` and `lab`; boot check 6 over
      every bundle. *Check:* CSP-builder unit tests; `headers.spec` (api) per flag class; `minimal`'s and
      `skeleton`'s headers unchanged. Progress: all of it in the platform (a boosted request for a fixed-bundle page
      gets `HX-Redirect`, PLAN §12.1 as built; `/csp-report` in `web.REPORT_ROUTES`, 10 a minute per client),
      `headers.spec` green on the three profiles, the CSP builder's unit test. Left: `.Private` exercised by a real
      page (chat, slice 8; `.Nonce_Csp` and the page bundles are, since slice 5), and `.Lab_Host`'s `noindex` with
      houston-lab (M4). `tools/check routes` refuses a bare `-` after a literal since slice 12 (`/csp-report` had
      matched nothing until it was `/csp%-report`).
- [x] **4. `client/hyperscript` and `html.behave`** (§12.4, D22): _hyperscript 0.9.94 core pinned (SHA, upstream
      `.br`) by prepare and in `pins`; the `client` family's second member; the `Behaviour` table and `html.behave`
      (`_="install X"` or `data-behave="x"`); the gate in app.js; the platform's core `._hs` set with its vanilla
      twins. *Check:* behave's output per client in a unit test; the gate refuses an injected `_` and an injected
      `text/hyperscript` script (a lab spec); `escaping.spec`'s `_` and `data-behave` rules. Done: both members, the
      table of twenty, `client/core.js` shared by both, lab on hyperscript; `behave_writes_installs` (lab) and
      `behave_writes_twins` (skeleton) under `CMD=test`; `escaping.spec` on every sitemap page and the gate test;
      lab 164, skeleton 195 (api, Chromium, WebKit) and minimal 61 passed, and the skeleton's specs on a hyperscript
      build of it. Changed from the plan: the skeleton's markup moved to `html.behave` as well (D22's M2 note: one
      dispatcher by name), and the notices gained hx-multipart's Shopify MIT notice, owed since slice 3.
- [ ] **5. The lab pages and `cmd/lab`** (§15.5): features `lab` (`/lab/streams`: the SSE, WS and multipart contract
      pages and the WS echo), `scripting` (`/scripting/*`: the nonce class, `live`, `streams`, `tt`) and `compat`
      (`/compat/htmx2`, `/compat/alpine`); `cmd/lab` on memory, anonymous, hyperscript and full, its root row the
      lab index until `landing` (M3), with `about`. *Check:* S0.3's 29 contract checks, plan checks and 20 extension
      checks as `e2e/tests/lab/` specs, green in chromium and webkit on both legs; `csp-clean`, `csp-enforced`,
      `harness-csp`, `streams-hxcsp` and `bundle-race`; load scenarios for every lab route; `lab` builds with no
      SQLite library. Progress: the `lab` feature and `cmd/lab` (on the hyperscript client since slice 4; its root is
      the lab index until `landing`) with S0.3's checks ported to `e2e/tests/lab/` and green on Windows (157 passed with
      the platform specs, Chromium, WebKit, api), load scenarios for every lab route, route parity clean. Two
      lessons in the port: a burst of five 60 KB frames passes the 256 KiB cap while the kernel still has room (the
      never-reads check now fills the kernel first, one message at a time), and a k6 iteration cut off mid-await
      stalls its VU's later awaits (the streams scenario lets the warmup's last iterations finish). Then `scripting`
      (`/scripting`, `/live`, `/streams`, `/tt`) and `compat` (`/compat`, `/htmx2`, `/alpine`) with `.Trusted_Types`,
      `PAGE_BUNDLES` in boot check 6 and feature `static/*.js`; `csp-clean`, `csp-enforced`, `harness-csp`,
      `bundle-race` and `streams-hxcsp` with `scripting.spec` and `compat.spec`: lab 226 passed (api, Chromium,
      WebKit); load scenarios for both. Found on the way: the fork's F-18 (a request right after a stream on its
      keep-alive connection lost its first bytes) and a robots.txt that hid `/lab/streams`. `lab` reaches no SQLite file
      (its dependency list; CI's no-SQLite build of it is slice 16's). Left: the Linux leg of the lab specs.
- [ ] **6. `platform/stream/client` and `tools/streamload`** (§8.2, §19.1.7): one non-blocking chunked, SSE and WS
      client on `core:net`; a multi-threaded fan-out generator with publisher-stamped `data-t` for delivery
      percentiles. *Check:* the client's parsers under table-driven random bytes; fan-out (1000 × 50, 3000), restart
      (4000 back ≤ 3 s), replay and resync, and back-pressure measured on Linux into `docs/perf/`, against §9.5 and
      §18.4. Done but the random-bytes tables: the parsers' tests split every input at every byte; streamload's
      fanout, restart and hold runs meet every §18.4 row on Linux (`docs/perf/STREAMS.md`), per-stream RSS once the
      fork's F-17 was in (16.2 KiB an idle stream before, 3.0 after). Follow-ups: random-bytes tables for the client's
      parsers (slice 13's fuzz tier 2); streamload into the nightly soak (slice 13).
- [ ] **A load sweep on Windows after the socket scenarios** fails a few dials (k6 1213: loopback pairs in
      TIME_WAIT; `load-tests/README.md` "Caveats"), so `--strict` can trip on a scenario that runs clean alone.
      Ways out, for slice 13 or 16: pause between scenarios until TIME_WAIT drains, run the socket scenarios last,
      or gate the parity sweep on Linux only.
- [x] **The skeleton's size budget**: F-17 put the skeleton 512 B past 2.75 MiB, and slices 3 and 4 11,264 B (the
      shared `client/core.js`, the twins' dispatcher, `html.behave`). Alex chose (a), 3 MiB (ANSWERS round 10), in CI,
      the drills, D38 and §18.4; no OMIT flags, no re-encode.
- [x] **6a. The `nick` identity** (`features/accounts/identity_nick`, §17.1, ANSWERS round 9): a signed nickname cookie,
      role User for clients in `LAN_CIDRS` (`ACCOUNTS_NICK_FROM=lan`), Admin for those in `ACCOUNTS_NICK_ADMIN_CIDRS`
      (none by default), Guest for the rest; `NAME`, `SETS_COOKIE`, `load_viewer`, `cli` and its `ROUTES` (the
      nickname form), checked against `authz.Load_Viewer` by `tools/check contracts`; the rest of `accounts` stays at
      M4. *Check:* unit tests (signing, tamper, each CIDR rule); e2e of the nickname form; load. Done: 3 unit tests,
      `nick.spec` (5, chromium and webkit, an off-LAN server of its own among them), k6's `accounts/nick.js`; the
      layout's one `#live` came with it (`web.render_page(…, live =)`, the hub's `member` rows).
- [x] **7. `notify` (memory)** (§14.2): models, domain, the memory store (200 per user), views, web (`/notify`, the
      bell, `notify_web.send`), `notify.user:<uid>` over `#live` with hx-targets on `.notify-count`. *Check:* e2e and
      load, both suites reaching every route. Done: the counts go out of band on the class selector (core htmx swaps
      into every match), so no hx-targets; the store's unit test, `notify.spec` (3), k6's `notify/notify.js`.
- [x] **8. `chat` (memory, four transports)** (§14.1): models, domain (2,000 runes, the 10-minute edit window, the
      caps), the memory store (100 per room, `CHAT_RING_BYTES`), `transport_{ws,sse,poll,multipart}` with their
      `EXTS`, `chat_web`'s switch (cookie, `?transport=`, `CHAT_TRANSPORT`; `x-impl`), topics `chat.room`,
      `chat.presence`, `chat.typing`, read receipts by POST, the post and frame limits, `Composer` and `AutoScroll`
      twinned. *Check:* the chat specs once per transport (`@chat-ws` …), resume without duplicates across
      `setOffline` and a server restart; a load scenario per transport. Progress: all of it, with presence through
      the hub's new `watch`, typing, edits and tombstones, the menu, unread counts and mentions; unit tests of the store
      and the domain; `chat.spec` once per transport by `?transport=` (tags name features and family members, so the
      transports are describe blocks: delivery once and escaped, edit and delete, and a server restart with nothing
      lost or doubled), plus presence and typing, the refusals and the 429, and the setting, 138 of 138 over three
      repeats in chromium and webkit; k6's `chat/chat.js` (every route, the transport rotating) and
      `chat/chat_streams.js` (the socket, the poll's 304, the held streams). Found on the way: memory ids restarted at
      1, so a page's upsert would have replaced old messages with new ones (now the boot epoch × 10⁶ plus the
      sequence), and ranging over `m[k]` of a nil map traps (CLAUDE.md's gotchas). The `setOffline` spec is in too,
      but Playwright's offline emulation cuts only new requests and Chromium's socket: an open SSE or multipart
      response, and WebKit's socket, keep delivering, so for those the restart spec is the resume check. Slice 8 done.
- [x] **9. `bot` (memory, mock)** (§14.3): models, the conversations' memory store, `backend_mock` (`BOT_SEED`,
      `BOT_DELAY_MS`), `bot_web`'s backend switch (`.Llama` joins at M7), SSE delivery (the four frames,
      `hx:release`) and multipart delivery, Stop, `bot.health`, the guest and member limits. *Check:* e2e per
      delivery (deterministic with `BOT_SEED`); Stop ≤ 100 ms; load with 1000 mock generations and a Stop storm.
      Done: `bot.spec` (14, chromium and webkit; 42 of 42 over three repeats), Stop timed in the page well under
      100 ms on both deliveries, the store's unit test; k6's `bot/bot.js` makes thousands of generations a quick run
      (about 23k requests a second at 20 VUs, p95 1.6 ms). Changed: the Stop storm is the e2e timing, since k6 reads a
      stream's body (and with it the generation's id) only at its end; `/admin/bot` waits for a second backend (M7).
- [x] **10. `ops` and `status` (basic)** (§15.4): ops's 1 Hz `.Sample` publisher rendering obs's registry once into
      OOB fragments and SVG sparklines on `ops.panel`, refreshed by SSE, `?mode=poll` (ptag 304s) or multipart;
      `last-crash.txt` after a restart. `status`: one `multipart/parallel` response of each module's health, a
      ptag poll variant. *Check:* e2e per refresh mode; load. Done: ops's `panel.spec` (each mode, the 304, the
      crash file, 403 and the guest's redirect; servers of its own with loopback admin) and `status.spec` (both modes,
      the 304), chromium and webkit; k6's `ops/panel.js` (the load driver makes loopback admin) and `status/status.js`.
- [x] **11. `cmd/streams`** (§7.1): home, notes, chat, notify, bot, ops, status, about on memory, vanilla and lite, with
      the `nick` identity (slice 6a); `build.*` and CI's matrix (tools/init reads the profiles from `build.sh`).
      *Check:* builds with no SQLite library; its e2e in chromium and webkit; its bundle's size recorded (§12.1's
      UNVERIFIED (M2)); route coverage with 0 unexplained waivers. Progress: the profile with home, notes, chat,
      notify, bot, ops, status, the nick identity and about, in `build.*` and every per-profile CI job; the generator composes it
      again; its e2e 151 passed (chromium, webkit, api), its k6 quick run clean, its drills 25/25 on Windows (binary
      1,714,176 B, idle 10.06 MB). The generator's identity handling too (nick by default unless scripting or
      compat, accounts with it, `identity.EXTS`, the host flag; a chat project made, tested, checked and built in a
      scratch copy). Its bundle measured into §12.1: Main 68,186 B raw, 19,967 B br, the four transports' extensions
      28,965 and 8,217 of it; it builds with no SQLite library present (WSL, prepare's SQLite step skipped). Slice 11
      done.
- [x] **12. `tools/check topics` and `exts`**: every `TOPICS` row mounted per host, families unique and in their
      feature's prefix; `BUNDLE_EXTS` names every mounted package with `EXTS` or `BUNDLES`. *Check:* a bad fixture
      trips each. Done: `topics` (families the feature's and declared once; every host's packages with `TOPICS`
      named by its `hub.mount`, and nothing it doesn't mount; `hub.init` called; a literal `hub.publish` names a
      declared family), `exts` (every mounted web package declares `EXTS`; `BUNDLE_EXTS` and `PAGE_BUNDLES` name
      exactly the mounted packages with `EXTS` or `BUNDLES`, an inline row's handler counting as mounted), and in
      `routes` the `-` rule; both in `all`, so CI's check job runs them. The bad fixture trips 13 more (43 in all).
- [x] **13. Stream drills** (§19.1.10): `wsdata` → 1011 with the server up; shutdown ≤ 6 s with 500 SSE + 500 WS
      (WS got 1012); the fd ceiling with 3000 streams; restart, 4000 back ≤ 3 s; TSan with 0 reports on hub, stream,
      workers and store/sqlite (S0.11, one nbio suppression, S0.9); the 1 h soak. *Check:* `tools/drills` on both
      legs and in CI's `linux-ops`; TSan and soak as nightly jobs. Progress: the drills `wsdata`, `streamdrain`
      (which found the drain sending SSE no `retry:`) and `streamfd` in `drills.mjs`, lab in `linux-ops`;
      `tools/drills/tsan.sh` at 0 reports (138 at first: the fork's F-21, a shutdown that woke released loops, and
      F-22, connection arenas TSan can't follow, plus a store test's loop released under the writer);
      `tools/drills/soak.sh`, whose first hour found the hub's idle-ring sweep freeing a ring twice (fixed) and whose
      hour after it passed (RSS 16.3 MB, +0.3 % and +1.0 % a half, 2000 of 2000 back in 1.5 s); both nightly. Slice 13
      done.
- [x] **14. M1's carried findings** (`docs/audit/M1.md`, owner M2): the MEDIUMs M1-02 (a send deadline), M1-03,
      M1-04 with M1-26 (a crash in a continuation or a stream's end), M1-05 and M1-07, now that streams rework the
      drain and the deferred paths; the profile's follow-ups (the connection arena's mutex and header reserves as a
      fork change, one read transaction per page, `tools/profile`). *Check:* each finding's own regression test or
      drill, and the parity gate. Progress: M1-04 (the guard's unwind and the fork's `response_crashed`; the
      `continuation` drill), M1-26 (with F-18; the `streamcrash` drill), M1-02 (`SEND_TIMEOUT_MS`, with F-19 for
      Windows; the `slowread` drill), M1-03 (the exits arm before they log; the `logstall` drill), M1-07 (a reader
      that can't open is a 500; the store's test; opening them at boot cost 1.65 MB idle, so they stay lazy) and M1-05 (the loop gate, the writer's intake,
      the clean path's bound; the `latewrite` drill) fixed. The profile's follow-ups: the header maps reserved
      (F-20), a handler's reads in one transaction (+2.1 % `pages`, Linux), the arena's mutex measured and left
      (95 ns a request), and `tools/profile` (perf samples, folded stacks, the top functions and a spall
      trace; its README), checked on the skeleton's `pages` and `write` in WSL. Slice 14 done.
      The Linux leg of the new drills, with slice 13's: every profile passes (minimal 24/24, skeleton 26/26, lab
      28/28, streams 24/24), once `streamfd`'s curl was taken from PATH on a native Linux run.
- [ ] **Report core:nbio's `SO_UPDATE_ACCEPT_CONTEXT` bug upstream** (found in slice 14; the fork's F-19 works around
      it): `impl_windows.odin` passes no value, so Windows rejects the call and `shutdown` fails on accepted sockets.
      Ask Alex before filing anything.
- [ ] **15. Generator v1** (`tools/init` compose mode, §7.4): `--list [--json]` (committed as `docs/catalog.json`,
      checked fresh in CI), `--explain`, `--profile`, `--features`, `--add`, `--without`, the family commands,
      `--dry-run`, `--verify` (scratch copy, `build.*`, `tools/check profile`, `--features --json` against the plan),
      `--yes`; edits planned against the parsed profile files, any miss aborting with nothing written. *Check:* the
      generator CI job with a rotating singleton per push; a plan that misses aborts cleanly. Progress: all of it in
      `tools/init` (tree, catalog, profiles, compose, explain, project, edit, verify), each feature's lines taken from
      a committed profile that mounts it (D26 as built); `odin test tools/init` composes the three profiles again;
      checked on scratch copies: a new project from `--features notes,about`, `--without about` there, `--add notes
      --profile lab`, `--store sqlite --profile lab`, a client swap that verify refused (lab's test pins hyperscript).
      The rename-only path, broken since M1 (a token the README no longer held), runs again. All nine singletons
      made and verified on Windows (`init ci-<f> --features <f> --yes`). Left: the CI job's first run (a push).
- [ ] **16. CI**: `streams` (chromium, webkit) and `lab` (all three, Firefox included) e2e; `e2e-proxy` ({streams,
      lab} × chromium through `deploy/Caddyfile` and through nginx with the config apollo's NPM version generates;
      X26, X40); nightly Autobahn|Testsuite against the lab's WS echo (X24), TSan and soak; `pins` with hyperscript.
      *Check:* every job green on a pushed commit. Progress: lab in every per-profile job, three engines in e2e; the
      `generator` job; `e2e-proxy` for lab through `deploy/Caddyfile` and through `tests/proxy/npm.conf` (NPM's
      rendering at apollo's version, which the config models without naming: the version is a private value), with
      the suite's proxy mode, 84 passed through each in WSL; nightly TSan, soak and Autobahn (247 cases, none
      failed); `pins` already covers _hyperscript. Locally, the lab's chromium and api legs pass on Linux (148).
      `streams` is in check, build, e2e, coverage, linux-ops and `e2e-proxy` (79 passed through each proxy in WSL).
      Left: every job's first run on a pushed commit.
- [ ] **Ask Alex**: X40 says `e2e-proxy` pins apollo's NPM version, which `docs/private/SITE.md` keeps private. The job
      pins the config that version renders instead (`tests/proxy/npm.conf`); naming the image tag in CI would publish
      it. Confirm, or say the version may be public.
- [ ] **17. Exit**: the parity gate on both legs; the budgets (bundle sizes, idle, no SQLite in `minimal`, `streams`
      and `lab`); `docs/audit/M2.md` by an agent that didn't write the code, 0 open CRITICAL/HIGH (M1-04 and M1-26
      are due here); `Audited:` stamps; CHANGELOG's 2.1.0 entry; then ask Alex about tagging v2.1.0.
      Progress: the audit at `db27254` (0 CRITICAL, 2 HIGH, 9 MEDIUM, 5 LOW, 5 NIT; M1-04 and M1-26 borne out) is
      resolved but for M2-18 and M2-21 (below); its Resolution section maps each fix to its test. The re-read of the
      fixes at `a6bc5de` found M2-22 (HIGH: JSON5 hid brackets from M2-01's scan) to M2-29, all fixed since; a second
      re-read at `5c5ebf2` found M2-30 (HIGH: a raw line feed did) to M2-32, fixed since but for M2-31's socket part;
      a third at `5395ae0` read them sound (no CRITICAL or HIGH open), and the stamps are on. Left: the parity gate on
      both legs, 2.1.0's entry.
- [ ] **M2's open audit findings** (`docs/audit/M2.md`, owner M3): M2-18, a topic has no `.Lan_Only`, so an Admin by
      `ACCOUNTS_NICK_ADMIN_CIDRS` outside `LAN_CIDRS` gets ops' panel stream but not its page (give `hub.Topic` the
      flag, or have boot refuse such CIDRs; no exposure at the empty default); M2-21, a POST stream keeps its request
      arena until it ends (documented in UPSTREAM's F-17 row; give it back where the handler returns on both paths);
      M2-31's socket part, a chat socket's reconnect upserts the room's last 50 with no cursor, so a page away for more
      than that sees no gap (the page should send its newest id as the socket's first frame, and a snapshot past it
      replace the log); and the third re-read's (`docs/audit/M2.md`): M2-33, core:encoding/json `alloca`s stack per
      key, which neither of `ws_json`'s bounds counts (count `:` outside strings, `#assert` the target's size,
      measure `{"":` nesting, report it upstream); M2-35, SSE's resync and the poll transport upsert across a gap the
      room let go (`changed` reports whether it reached the version; SSE's pane gets a tag); M2-36, a message past the
      socket's bracket bound is refused after the composer cleared it.
- [ ] **A WebKit flake to watch**: `chat over sse: an edit and a delete reach the other member` failed once in a full
      streams run on Windows (2026-10-27), then passed 79 targeted runs and the next full run.

**Answered by Alex (ANSWERS round 9, 2026-10-26), before slices 7–11:** nick is built in M2 (slice 6a);
`ACCOUNTS_NICK_ADMIN_CIDRS` (none by default, loopback in e2e) makes its clients there Admin, so `/admin/ops` opens in
`streams`; off-LAN visitors stay Guests under D35's table, and chat shows them a "chat is open on the LAN" notice.

## M1 — request-path substrate, `skeleton` at parity (v2.0.0)

The starter's first milestone of code ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M1's row; M0's spikes are
in [`docs/spikes/`](docs/spikes/)). Slices in order, each done only when its check passes. `app/src`
(the 1.2.x app on the fork) keeps building and passing its tests until slice 7 retires it, so
every slice before that can be compared with it. Released as v2.0.0 on 2026-10-26 at Alex's go; `FLY_DEPLOY`
stays off and Fly keeps serving 6d37506.

- [x] **1. Build line.** `build.{sh,bat} <profile>` at the root (`minimal`, `skeleton`; `CMD=check|test|run`;
      the four collection flags; `-vet -strict-style -warnings-as-errors`; `-define:VERSION`), `ols.json`
      at the root on `skeleton`'s families until `full` exists, and `prepare.*` building SQLite with
      D16's `SQLITE_FLAGS`, recorded in `vendor/sqlite/.flags` so a flag change rebuilds the lib (S0.11).
      *Check:* an unknown profile is refused; `app/src` builds and passes its store and views tests on
      the tuned lib on Windows and Linux.
- [x] **2. Platform L1–L2**, each checking alone: `sys`, `ext`, `sqlite` (`in_sqlite` around every call),
      `escape` (the injection boundary, below `markdown`), `guard` (S0.6), `obs` (logfmt buffers,
      request ids, per-thread counters, health, limits), `env`
      (the typed table), `authz`, `authz/anonymous`, `store`, `markdown`, `workers` (pools, `next_tick`
      replies over F-13, the scheduler). *Check:* `odin check -no-entry-point` per package with the strict
      flags; `odin test` per package under a `Tracking_Allocator` (guard classification, logfmt, env
      parsing, markdown caps, worker replies on the submitting loop). Follow-ups: daily jobs at a local
      time (M4's nightly resets); the jobs page's run history (M5).
- [x] **3. Store families.** `store/sqlite` (v3, `MEMMODE` ephemeral/single, the boot sweep, tmpfs; the
      writer task with group commit and no timer; the query pool; the reader reset pulled from guard;
      `migrate` adopting 709bc94 and v1.1.1 databases; `--backup`, `--adopt-profile`) and `store/memory`.
      *Check:* the runner's 6 cases plus fixture databases written by the real 709bc94 and v1.1.1 binaries;
      a reader sees the writer's commits; 0 re-prepares in 1000 pages; a batch answers each write as a lone
      write would; the reader reset after a pure trap. Follow-ups: the dashboard and ops numbers
      (`sqlite3_db_status`, WAL bytes) pushed to obs at M5; keyset paging helpers with chat (M6).
- [x] **4. Platform L3–L4.** `web` (per-host prefix router, `Route` and flags, `respond_*`, body caps, the
      trusted client address, assets with crc32 names and br/gz/identity, robots, sitemap, Bing, IndexNow,
      `/licenses`, `/healthz /livez /readyz /metrics`), `html` (the escaping boundary, layout, NAV, the
      components, `behave`), `client/vanilla`, `theme/full`, `theme/lite`, `app` (`front`, `Host`,
      `boot check serve wait shutdown`, the CLI, the 8 boot checks, `TEST_ROUTES`). *Check:* router,
      escaping and boot-check unit tests, a deliberately bad table tripping checks 1, 3 and 5. Done:
      `platform/escape`'s tests; the router and the bad table in the skeleton's `routes_test.odin`
      (`platform/web` reaches the family collections, so it can't be tested alone), which trips checks
      1, 3 and 5 and nothing else; both profiles' boot checks under `CMD=test`, leak-free. Moved to M2:
      `html.behave` and the `Behaviour` table, with `client/hyperscript`, the family's second member
      (D22's as-built note; the skeleton's markup stays byte for byte until then).
- [x] **5. `minimal`.** Features `home`, `about`, `notes` (both store families, `storetest`); `cmd/minimal`'s
      four files. *Check:* builds with no SQLite library present; ≤ 1.0 MB; the skeleton's exact header
      set; its bundle is `htmx.min.js` byte for byte; the minimal starter's specs pass. Done: no SQLite
      file in its build, the exact header set, the bundle byte for byte, the storetest on both families,
      its boot checks under `CMD=test`. Moved on: the specs run in slice 7's ported suite; the size
      (1.31 MB at `-o:speed`, og.png alone 230 KB) is slice 10's budget work.
- [x] **6. `skeleton`.** Features `contacts` (SQLite store, migrations 0001–0003 with their hashes plus
      `0004_sort_indexes`, group-committed writes over F-13), `dashboard`, `gallery`, `about`;
      `cmd/skeleton`. *Check:* every skeleton URL answers byte for byte as `app/src` does (a route diff,
      intended differences listed: X35's three headers, `x-request-id`); `app/src`'s e2e and k6 smoke
      pass against it. Done: 32 of 33 GET URLs byte for byte (asset hashes and the ping token
      normalised); robots.txt is now derived from the `.Fragment` rows (the same Disallows, single
      routes kept exact); the access log is logfmt (ops.spec follows). The suite: 181 passed in
      chromium, webkit and api; the k6 quick smoke: 10 scenarios, 0 % failed. On Linux (WSL2):
      prepare, the build and both profiles' `CMD=test` boot checks pass; the smoke URLs answer, a
      create round-trips, SIGTERM exits 0 and `/dev/shm` is left clean.
- [x] **7. Retire `app/src`.** The 23 specs ported to `e2e/tests/<f>/` and tagged; global setup through
      `build.sh` and `--features --json`; `load-tests/scenarios/<f>/` and `run.sh --parity`; per-route
      counters and `tests/parity-waivers.txt` (S0.4's three documented exceptions); `run.*`, the
      Dockerfile and `tools/init` through `build.*`; `app/src` deleted. *Check:* 3 engines + `api` green
      on `skeleton`, chromium on `minimal`; route coverage with 0 unexplained waivers. Done: `skeleton`
      190 passed in chromium, webkit and api (10 skipped: the notes and home specs it doesn't mount;
      Firefox waits for CI), `minimal` 58 passed in chromium and api (every skip names a feature it
      lacks); both quick k6 runs `--strict` green; every route of both profiles reached by both suites
      (31/31 and 14/14), so no route waiver; the three `perf` lines are S0.4's. New: `ops.spec` covers
      `/livez`, `/readyz`, `/metrics`, `/licenses`, and load scenarios `ops`, `ping`, `gallery`, `home`,
      `about` cover the routes the skeleton never load-tested. `tools/init` renames every profile's
      brand (tried on a scratch copy: both renamed profiles build); `--minimal` and its overlay are gone,
      the `minimal` profile replaces them. The skeleton image builds through `build.sh` (WSL Docker).
      `run.sh` skips ports another process listens on (WSL's relay held 8192 and answered k6).
- [x] **8. `tools/check`**: `imports`, `profile`, `routes`, `contracts` (and `parity`). *Check:* clean on
      both profiles; a bad fixture trips each. Done: `odin run tools/check -- all parity` exits 0 on the
      repo; `odin test tools/check` runs every check on the repo (clean) and on `testdata/bad` (all 30
      expected problems, nothing else). Feature READMEs carry the D9 prefix tables; `platform/app`'s
      `store:.` import is in PLAN §5.1. Follow-ups: per-host route counters when a profile has two hosts
      (M2's `lab`), and `topics`/`exts` with M2. `parity` reads `bin --routes --json`, the counter files in
      `app/build/coverage/{e2e,load}/<profile>/` and the `route` lines of `tests/parity-waivers.txt`
      (e2e/README and load-tests/README already describe it).
- [x] **9. CI**: `pins`, `check`, `build` ({minimal, skeleton} × 4 OSes, the no-SQLite build), `e2e`,
      `docker`, `linux-ops`, nightly ASan, all through `build.*`. *Check:* a green run (needs the push,
      which waits for Alex's go and the token's `workflow` scope). Written: `pins`, `check`, `build`
      (minimal and skeleton × ubuntu, ubuntu-arm, macOS, Windows; minimal with `NO_SQLITE=1` on ubuntu
      and Windows; size budgets on Windows), `e2e` (`E2E_PROFILE`), `coverage` (k6 quick + `tools/check
      parity`), `docker`; the `setup-odin` action; `check-pins` covers the prepare scripts and the
      odin-http base. Checked locally: the pins, every `check` command, the smoke script on both
      profiles, `NO_SQLITE=1` on Linux; actionlint wasn't run (no local install; the Docker image was
      refused). `linux-ops` and the nightly ASan land with slice 10's drills, which they run. Open
      until the push: the green run itself. Done: run 40383619999 on `7fe60a5`, every job green.
- [x] **10. Drills and budgets.** Crash drills (panic, bounds, div, nil, stack, lock, async, sqlite, hang)
      on both OSes; the fuzz smoke; the shutdown bound with slowloris, half body and idle peers; restart;
      the fd ceiling; `skeleton` ≤ 2.75 MB, idle ≤ 10 MB, boot → `/readyz` ≤ 50 ms. Done: every drill
      passes for both profiles on Windows and on Linux (WSL): pure 500 with 20/20 bystanders, dirty exit
      70 in 0.5–1.2 s, burst, the watchdog's exit 70 in 9.8–10.1 s naming the route and request, 10k
      malformed requests with 0 deaths, the shutdown bound 5.6 s, restart at 0/50/100 ms, the fd ceiling
      (past the cap 503 in 1.4–1.9 ms, 200 after); boot → `/readyz` 26 ms (skeleton) and 11 ms (minimal)
      from the spawn on Windows, 3–5 ms boot_ms on Linux, after moving the ephemeral files to a directory
      of their own (it was 167–181 ms). The ASan build runs clean with `use_sigaltstack=0`. **Budgets,
      decided** (ANSWERS round 7, option (a)): binaries in MiB as CI reads them (skeleton ≤ 2.75 MiB holds
      at 2,881,536 B; minimal raised to ≤ 1.5 MiB) and idle ≤ 6 MB + 0.4 MB per loop; the drills read
      the same figures; the idle budget is measured at 16 loops and gated by the dev PC's drills, while
      CI's Linux runner (about 5 MB above this PC's Linux) reports it (ANSWERS round 8). What was
      measured before the decision (decimal MB as PLAN's 2.42 MB was):
      skeleton 2,876,416 B against 2,750,000 and minimal 1,313,792 B against 1,000,000 (Windows
      `-o:speed`); skeleton idle 11.3 MB working set (Windows) and 12.0 MB RSS (Linux) against 10 MB, at
      16 loops (about 0.37 MB per loop on Linux; 6.0 MB at one loop). Minimal idles at 9.6 MB on both.
      The levers measured: og.png is 230 KB of each binary (a lossless re-encode saves 31 KB; a palette
      one 168 KB but bands the gradients); SQLite's `OMIT_JSON`, `OMIT_DEPRECATED`, `OMIT_UTF16`,
      `OMIT_COMPLETE`, `OMIT_DECLTYPE`, `OMIT_GET_TABLE` and `OMIT_TCL_VARIABLE` save 69 KB of skeleton;
      the JSON CLI is 25 KB. Even with all three skeleton stays about 10 KB over, and minimal reaches
      1.0 MB only without the social card. Also seen: on Linux a client that half-closes right after
      its request often gets no response (the malformed run's "none": 5,560 of 10,000 against 1,250 on
      Windows); no crash, but worth the audit's look.
- [ ] **The M1 audit's open findings** (`docs/audit/M1.md`; M1-01 CRITICAL, M1-06 and M1-08 are
      fixed, and so are the re-read's M1-17 (CRITICAL once confirmed) to M1-23, by the fork's F-16,
      and F-16's re-read's M1-24, M1-25, M1-27, M1-28 and M1-29. M1-26 (a trap in a request a stream's
      end starts, latent until a profile streams) is open, owner M2, with M1-04). MEDIUM, owner M2 (the stream substrate reworks the drain and the deferred paths):
      M1-02 a response send has no deadline (a client that never reads holds the connection);
      M1-03 the watchdog's and the dirty crash's exits log before they arm the exit, so a stalled
      stderr hangs them; M1-04 a crash in a write continuation after `web.resume` leaves its
      connection open; M1-05 at shutdown the writer can post replies into a released loop, and the
      store close has no deadline; M1-07 a reader that can't be opened at runtime exits the process
      (open readers in the loop's init hook, answer 500 at runtime). LOW, owner M2 or later: M1-09
      request identity per thread where requests interleave; M1-10 the drain's log lines aren't
      flushed; M1-11 half-closed clients and resets (likely the Linux "none" count in the drills);
      M1-12 callbacks outside the guard; M1-13 `tools/check locks` and `entry-points`, plain
      `sync.Mutex` in four packages; M1-14 Markdown's quadratic worst case; M1-15 the watchdog's lock
      limit equals busy_timeout; M1-16 unchecked setup results. (`web.count_and_log` and
      `store_sqlite.query_drain`, which had no caller, are removed: the audit's vet triage.)
- [x] **`Audited:` stamps for the packages without a README**: the M1 audit stamps the features,
      `platform/web` and the fork (`UPSTREAM.md`); the other platform packages, the stores and the
      profiles need a README (or `tools/check audit-debt` another place to read stamps). F-14, M1-06's
      and M1-08's fixes are audit debt until an independent re-read. Done: a README with its purpose
      and the M1 stamp (`bf831da`) in each of the 19 platform packages, both store families, the three
      stores and both profiles; the changes since `bf831da` went to an independent re-read
      (`docs/audit/M1.md`, Re-read). `tools/check audit-debt` itself is still to write (PLAN §19.2.1).
- [ ] **The M1 profile's follow-ups** (`docs/audit/M1.md`, Profile; owner M2): the connection arena without its
      mutex (21 lock pairs a request on a one-thread arena) and the header maps reserved up front (3.7 regrowths a
      request), as fork change F-16; one read transaction per page request (`unixShmLock` is 13 % of `pages`); a
      `tools/profile` that makes the spall trace and the perf flame graph repeatable at each milestone exit.
- [x] **`--limits` misses the store's rows** (`DB_PATH`, `SEED`, `MEMMODE`): `store_sqlite.open`
      records them at step 5, after `app.check` answers the CLI at step 4. Record them in an init
      before `app.check` (PLAN §8.5: every row printed, secrets masked). Done: `store_sqlite.init()`
      in the skeleton's `main` before `app.check` (`open` records them itself if a profile skips it).
- [x] **11. The parity gate** on both legs (`skeleton` against 709bc94 and v1.1.1; §18.2 with Q6's and
      Q35's references), into `docs/perf/PARITY.md`; the 01 (A) checklist. Done: PASS on both legs, 20 of
      20 cells each counting §18.2's n = 5 re-runs (Windows `8c4f1a9`, Linux `72590f6`, the box quiet);
      Linux `write@mem` at 0.99 of HEAD on its re-run, under the 0.93 floor Alex accepted (round 6). The
      checklist is 40 of 40. Both legs' drills
      pass at `72590f6`, budgets included (skeleton 2,883,584 B, exactly 2.75 MiB: no headroom left).
- [x] **12. Audit and release prep.** `docs/audit/M1.md` by an agent that didn't write the code, 0 open
      CRITICAL/HIGH; `Audited:` stamps; CLAUDE.md, README and app/README rewritten for the starter (and
      the docs still describing `app/src`: docs/DATA.md, DATA_IMPL.md, STRIP.md, USE_CASES.md's
      `init --minimal`, e2e/PLAN.md, load-tests/PLAN.md — rewritten or removed, PLAN §4);
      CHANGELOG's 2.0.0 entry; then ask Alex about tagging v2.0.0. Done: the audit and two independent
      re-reads (0 open CRITICAL or HIGH; M1-01 and M1-17 fixed), stamps in every package README, the docs
      rewritten, Alex's pass by hand (`docs/testing/M1.md`), and the CHANGELOG cut as 2.0.0; tagged
      v2.0.0 once CI was green on that commit (Alex: "(a) Confirmed. Release 2.0.0.").

## Roadmap to 1.0 — template-ize (Phase F) — ✅ shipped as v1.0.0 (2026-07-01)

Make it trivial to start a new project from. Bounded: mostly docs + one script. **All items below are
done** — the repo is a GitHub template with `tools/init` (+ `--minimal`), a centralized brand, and
the starter docs. Next up is **1.x** (below), headlined by auth.

- [x] **GitHub *template repository*.** Repo set as a Template Repository (the "Use this template"
      button is live); README has the use-template → `init` steps.
- [x] **An `init` / scaffold script** — `tools/init` (an Odin program: the skeleton's own tooling on
      the stack it teaches). Renames the app everywhere it's hardcoded in one pass — the binary
      (`demo`), the `fly.toml` app, the docker image, the apollo-11 service + volume, the `main.odin`
      banner, the test-package names, and the three `brand.odin` constants — across a fixed, audited
      file set. `--wordmark`/`--suffix`/`--repo` override the brand defaults; a confirm prompt +
      name validation guard it. Tested (run → build → revert).
  - [x] `--minimal`: strips the contacts/events demo to a one-page **Notes** starter (the full
        model→repo→service→view→controller stack over one entity), keeping the shell + theme +
        data-layer + harness. Deletes the demo domain/pages/specs/scenarios and drops in minimal
        templates (`tools/init/minimal/`, embedded via `#load`). Tested end-to-end: run → build
        (`-warnings-as-errors`) → curl smoke → **12/12 e2e** → revert.
- [x] **Parameterize the brand / app name** to one place — `app/src/views/brand.odin` holds
      `BRAND_WORDMARK` (the topbar wordmark, inline markup allowed) and `BRAND_SUFFIX` (the
      `<title>` / og:title suffix); `layout` is the only reader. The display name is now a
      two-constant edit instead of literals scattered through the views. The remaining name
      touch-points are outside the views (binary/app name in run/build scripts + `fly.toml` +
      `Dockerfile`, and the `main.odin` startup banner) — the `init` script will tie them together.
- [x] **README as a starter guide**, not a demo tour: use-template → run `init` → keep-vs-strip →
      the `CLAUDE.md` **Recipes** for adding a page / entity / endpoint. (Live in the README's
      "Using this as a starter".)
- [x] **`docs/STRIP.md` — "remove the demo."** Written: the demo-vs-scaffold map + the file-by-file
      seams to delete the contacts/events domain and demo pages, leaving the shell + data layer +
      theming + harness. Cross-links `init --minimal` (the automated version) and the CLAUDE recipes.
- [x] **Re-skin the docs to the skeleton framing** — `USE_CASES.md`'s "flagship (the app's
      direction)" section is now "the worked example" (built, past tense), the retired product-depth
      items (bulk actions, named console) are called out as out-of-scope, and the "read first" banner
      is tightened.

## 1.x — what *every new site* needs (so the skeleton should ship it)

- [ ] **Auth: sessions + CSRF.** The highest-leverage addition for a *starter* — every new site
      reinvents login/sessions/CSRF and it's easy to get wrong. A minimal, in-philosophy
      session-cookie pattern (login page, a protected-route guard, a CSRF token on POST/DELETE),
      held to the "few dependencies" line. Also closes the current CSRF gap on the mutating surface.
- [ ] **Per-thread WAL connections** — already **load-justified** (reads scale ~3–4× not ~5× under
      the v1 single shared connection; the `detail` JOIN worst at 1.9×). Ship the right concurrency
      default and re-measure in `load-tests/RESULTS.md`.
- [ ] **A second entity as a worked "add your own resource" example** (e.g. teams/companies a
      contact belongs to) — doubles as the multi-resource nav pattern *and* the literal tutorial for
      extending the skeleton. App / e2e / load at par, as always.

## Discoverability — the half that isn't code

The crawler-facing plumbing shipped (canonical/og/JSON-LD, `robots.txt`, `sitemap.xml`, the
`*.fly.dev` → canonical 301). What's left needs an account, not a commit:

- [x] **GitHub repo description, topics and homepage set.** All three were empty, which meant
      nothing on the web linked to the site and the repo carried no keywords — the highest-impact
      item of the lot, since the homepage field is the inbound link that gets *either* property
      crawled in the first place.
- [x] **Google Search Console** — `alexh95.com` verified as a *Domain* property (DNS TXT via
      Cloudflare, which covers every subdomain at once); `/sitemap.xml` submitted and indexing
      requested for `/` and `/about`.
- [ ] **Bing Webmaster Tools** — DNS verification cost two wrong record values and a resolver-cache
      stall, so ownership moved to `/BingSiteAuth.xml`, served from the binary and deterministic on
      deploy. **IndexNow is wired too** (`/<key>.txt`), which covers Bing, Yandex, Seznam and Naver
      from one key. Bing reports the URL as *known but not indexed*; the delivery path is ruled out
      — a bingbot-UA fetch returns 200 with our own `robots.txt` (not a Cloudflare-managed one), TLS
      1.2 negotiates, and Cloudflare's Security Events log shows **no bingbot mitigations at all**
      (that log records only *mitigated* requests, so the absence is the edge clearing itself, not
      evidence of a crawl). Crawl Information reports **no data**, i.e. Bingbot has barely fetched.
      Left: submit `/sitemap.xml` in Bing's console, watch the IndexNow tab for rejected
      submissions, run Site Scan, and re-inspect once Bing has actually crawled.
- [x] **Cloudflare is not blocking the crawl** — SSL/TLS set to **Full (strict)** (`force_https` in
      `fly.toml` plus Flexible mode would be an infinite redirect loop), and Bot Fight Mode left
      **off**: the free tier lacks the verified-bot allowlist that Super Bot Fight Mode has, and a
      challenged crawler fails in a way that reads as "Google is just slow".
- [x] **Add a LICENSE** — **zlib**, chosen for being the most permissive of the common licences
      while still asking that altered versions say so: exactly the ask of a skeleton meant to be
      cloned and rewritten. Deliberately *not* mirrored into the JSON-LD `license` field: the
      minimal templates are shared with forks, and a hardcoded licence URL there would have every
      fork asserting a licence its author never chose.
- [ ] **Distribution beats meta tags.** `r/odinlang`, the Odin Discord, `awesome-odin`, htmx's
      "in the wild" page, a Show HN. Backlinks from those outweigh any on-page tuning for a new
      project; `odin htmx skeleton` itself has ~no search volume. Note the correction to the GitHub
      item above: GitHub applies `rel="nofollow"` to the repo homepage link, so it aids *discovery*
      (which is why Bing knows the URL) but passes no authority — a zero-authority subdomain with no
      followed inbound link is the likeliest reason Bing crawls it and declines to index.

## Stretch goals

- [x] **A `--minimal` scaffold variant** — delivered as `init --minimal` (see Phase F above): a
      fully-wired one-page **Notes** starter you generate on demand (blank-but-wired), instead of a
      second variant to maintain beside the showcase.
- [ ] **Common-need recipes** as documented patterns (file upload, an env/config story, a background
      task) — kept as *recipes*, not framework features, to stay true to the philosophy.
- [ ] **Reporting/export** (CSV of the filtered table) and a focused **a11y pass** (drawer/modal
      focus management, keyboard nav) — cheap reinforcement of the "exemplar" claim.

## Shipped — the foundation the skeleton provides

The patterns + harness a fork inherits. (Was "Now / next"; the initiative below is built.)

- [~] **Vision + flagship + style library** (this initiative). Anchored by
      [`PHILOSOPHY.md`](PHILOSOPHY.md), [`docs/USE_CASES.md`](docs/USE_CASES.md),
      [`docs/DATA.md`](docs/DATA.md). Keep app/e2e/load-tests **at par** at every phase.
  - [x] **Phase A — direction docs.** PHILOSOPHY (vision), USE_CASES (sweet spot + flagship
        direction), DATA (datasource future-proofing). Wired into README/CLAUDE.
  - [x] **Phase B — theming foundation.** `data-style` × `data-scheme` on `<html>` (SSR default
        `modern`/`midnight`, restored pre-paint from localStorage); token contract; stateless
        `<details>` picker in the topbar (vanilla JS apply/persist, no endpoint → load par).
        **Modern** is the reference style with four schemes (Midnight/Daylight/Nebula/Aurora).
        e2e: picker switch + persist. Build clean, 32/32 e2e.
  - [x] **Phase C — the styles.** All five shipped — Skeuomorphic, Terminal/CRT, Brutalist,
        Editorial/Paper, Arcade (video-game) — each a pure `[data-style]` block with multiple
        schemes, every style incl. a light option. Plus cache-busting (`?v=hash`) so style edits
        show without a hard refresh. Library: 6 styles, 23 schemes.
    - [x] Turned `/components` into a live style/scheme **showroom**: a catalog of all 6 styles ×
          23 schemes at the top of the page; click any swatch to jump to that exact style+scheme and
          the whole page (components below) re-skins live. e2e covers it; no new server surface.
  - [~] **Phase D — flagship app.** Evolve the sampler into one cohesive internal admin console.
        Each new endpoint gets e2e **and** load scenarios in the same change.
    - [x] **Contact detail drilldown** — click a row's name → `GET /contacts/:id` opens a drawer
          with the full record, a derived **activity trail**, and **related** contacts (same role,
          each a one-click jump). Read-only for now. e2e + `detail.js` load scenario added.
    - [x] Inline edit + actions in the detail drawer (edit fields, cycle, delete — all swapped in
          place; edits OOB-refresh the table row; `repo_update` persists score). e2e + load at par.
          Phase-D review fix: an invalid drawer edit now surfaces an OOB error toast instead of
          silently reverting.
      - Known limitation: an in-drawer edit/cycle OOB-refreshes the row *in place*, so a
        filtered/sorted table can briefly show a row that no longer matches until the next
        interaction. A deeper fix would thread the table's q/status/sort into the drawer and
        re-render the whole region; acceptable for the POC.
    - [~] Richer table.
      - [x] Saved/quick **status filters** (chips: All/Active/Invited/Disabled; compose with search +
            sort + paginate via a threaded `status` arg).
      - [-] Bulk actions (select rows → set status / delete) — **out of scope as a goal** (skeleton:
            app-specific; a copier would strip it). Keep only as an example extension if ever wanted.
    - [x] Coherent product frame — the dashboard stat cards drill into the filtered/sorted data view
          (overview → tool). A *named* console identity + deeper nav IA is **out of scope** for a
          skeleton: the fork names and structures its own console.
  - [x] **Phase E — parity + polish sweep.** Parity closed: Phase D endpoints all have e2e + load
        (detail.js, the create→edit→delete write path, the new **list.js** for `GET /contacts`
        filter/sort); CHANGELOG/docs current; the Phase D review fix landed. Also wrote the
        **Odin data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md)).
        Phase E review pass swept the whole Phase D+E surface and caught a reflected
        HTML-injection via the `sort` query param (unescaped reflection into the table's `hx-get`
        attributes) — fixed by `url_encode`ing `sort` everywhere, pinned by an e2e regression test.
- [x] **Data layer — persistent SQLite** (replaces the in-memory POC).
  - [x] Implemented per [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md): amalgamation binding
        (`src/sqlite/`), the seven `repo_*` over SQLite, `prepare.*` fetch+compile (pinned + SHA-256),
        `DB_PATH` (`:memory:` default / file persists), WAL + migrations + `schema_version`. Contract
        unchanged; e2e + load pass untouched. apollo-11 persists to a named volume; Fly stays
        `:memory:` pending a volume (documented in `fly.toml`).
  - [x] **Repository cleanup + split.** Split into a **common** part (`repo.odin` — connection
        lifecycle incl. `repo_close`, the migration runner, the shared `exec`/`prep`/`bind`/`clone`/
        `scalar` helpers + the lock) and **per-entity** files (`contacts.odin`, `events.odin`), each
        owning its statements + procs. Helpers grouped, error handling documented (fatal at boot,
        best-effort per request), `repo_close` wired via `defer` in main.
  - [x] **Multi-table case — events between contacts.** `events(actor_id, target_id → contacts,
        ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`). The detail drawer's
        activity feed is now **real**: `event_timeline` JOINs back to contacts to resolve the other
        party, each a one-click jump (replaces the faked `service_activity`). Deleting a contact
        cascades its interactions. End-to-end at par: model + repo + service + view + e2e (incl. a
        cascade test; **42 e2e**) + load (`detail.js` now exercises the JOIN). Load re-measured:
        reads scale ~3–4× under the single-connection exclusive lock (`detail` JOIN worst at 1.9×) —
        see `load-tests/RESULTS.md`.
  - [ ] **Per-thread WAL connections** — moved to the **1.x roadmap** above (load-justified).
- [~] **Set up infrastructure** per [`infra/PLAN.md`](infra/PLAN.md). Code + config landed;
      what's left are operator actions on Fly/GitHub/Cloudflare (no repo changes).
  - [x] Prereq code change: `app/main.odin` reads `PORT` and binds `0.0.0.0` on `BIND_ALL`
        (loopback stays the local default).
  - [x] Pin odin-http as a submodule (`app/odin-http` @ `112c49b`) for reproducible builds.
  - [x] `Dockerfile` + `.dockerignore` + `fly.toml`; `.github/workflows/ci.yml` (build,
        smoke, deploy-on-`master`).
  - [x] Operator: created the Fly app + `FLY_API_TOKEN` secret; CI deploys on green push and the app
        is live (Fly `fra`, Cloudflare-fronted at `odin-htmx.alexh95.com`).
  - [x] Operator: front the Fly app with a **proxied Cloudflare record** (`fly certs add` + the
        `_fly-ownership` TXT and `_acme-challenge` CNAME for DNS-01 validation, CF SSL Full-strict).
        This was also a latency fix: Fly's IPv6 anycast mis-routed an EU ISP to the `jnb`
        (Johannesburg) edge (~785 ms TTFB) while IPv4 hit `ams` (~160 ms); routing through
        Cloudflare's edge bypasses Fly's anycast and serves both v4/v6 in **~105 ms** with
        `/static` edge-cached. The Fly region was also moved `iad`→`fra` so the origin is nearby.
  - [ ] Stand up the dedicated load-test environment when load-tests are implemented.
- [x] Implement the e2e suite per [`e2e/PLAN.md`](e2e/PLAN.md) — Playwright, 31 tests incl. the
      three regressions; wired into CI as a gating job. It surfaced (and we fixed) the `fmt`
      brace bug in the page `<head>` and the OOB-toast wrapper.
- [x] Implement the load-tests per [`load-tests/PLAN.md`](load-tests/PLAN.md) — k6 scenarios
      (static/pages/search/api/write/mixed), a `run.sh`/`run.bat` sweep driver, and
      `RESULTS.md`. Single-thread baseline captured.
  - [x] Headline follow-up: guarded the store with an `sync.RW_Mutex` and set `thread_count`
        to the core count (`THREADS` env overrides). Before/after in `RESULTS.md`: reads scale
        **~5×** (1→8 threads), writes ~1.8× (exclusive-lock-bound, as predicted), and the
        500-VU overload failures (13–34%) drop to **0%**. Also ran it against prod (Fly).
  - [x] Two-host absolute numbers: deployed to the apollo-11 home server
        (then `deploy/apollo-11`, now the generic [`deploy/docker-host`](deploy/docker-host)), k6 on
        the workstation over a 1 GbE LAN. Found the
        wire ceiling (static/pages saturate ~912 Mbit vs 2.4 GB/s loopback) and the reverse-proxy
        cost (~12× for NPM+TLS on the shared box). Surfaced the io_uring-vs-Docker-seccomp gotcha.
        Results in `RESULTS.md`. (Further: a generator *outside* the LAN for the true external path.)
- [~] **Sync gate:** every endpoint now has both an e2e and a load scenario for its *class*
      (static, page, search, api, write). `/healthz` is hit by the run driver's readiness
      probe rather than a dedicated scenario; add one if it ever does real work.

## Backlog

- [x] Data table: the actions column overflowed into horizontal scroll on narrow viewports. Fixed
      in the mobile pass — below 560px the table folds email/role/engagement into the detail drawer
      (name · status · actions remain); the topbar was the larger culprit (page-wide scroll), also
      fixed. No horizontal overflow 320–1280px, pinned by e2e.
- [x] Pin htmx to an exact version in `prepare.*` (was the floating `@2`) for reproducible builds —
      pinned to **4.0.0-beta5** with a SHA-256 check (same discipline as ODIN_VERSION / SQLite), and
      migrated htmx 2 → 4 (renamed config keys `defaultSwap`/`transitions`, `htmx:after:process`
      re-init, the form auto-reset moved to `app.js` over `ctx.sourceElement`).
- [ ] Optional: a build-flag-gated `/__reset` endpoint to reseed the store (useful for load
      tests; must never ship in a normal build). Tie to `load-tests/PLAN.md`.
- [ ] Optional: `-o:speed` build path for benchmarking vs. the default showcase build.
- [x] CI guard for `init --minimal` rot — a `minimal` CI job strips a fresh checkout to the Notes
      starter and runs its e2e (global-setup builds it `-warnings-as-errors`, so one job catches
      compile- **and** runtime-rot, and exercises the rename path too). Chromium only; gates deploy.
      Keeps the `tools/init/minimal/` templates honest as the skeleton evolves.
- [ ] `/forms` email validates one value twice: `keyup changed delay:400ms` checks it as you type,
      then `change` re-sends it on blur — a redundant request, and the `.msg` fade-up replays. Since
      #8's fix it no longer costs a click, only the round-trip. htmx 4's `changed` modifier keeps its
      last value *per trigger*, so `change changed` can't dedupe against the keyup; a lone
      `input changed delay:400ms` would (it also covers a mouse paste, which keyup misses). Keep the
      e2e's click-during-a-swap case exercising a real swap if you change it.
- [ ] Optional: crossfade back/forward too. Since #8, only the boosted links opt into a view
      transition, and htmx 4 takes a history restore's from the global `transitions` flag alone — so
      it would take one `htmx:config:request` listener in `app.js` setting `ctx.transition` on
      `HX-History-Restore-Request` requests. It reopens a (brief) dead-click window each time.
- [ ] Move the CI `e2e` + `minimal` containers off `mcr.microsoft.com/playwright:v*-jammy` before
      Ubuntu 22.04 leaves standard support (2027). `noble` is the conservative step. It changes the
      jobs' apt `clang` (14 → 18), which compiles SQLite and links Odin, so land it alone and not
      inside a dependency sweep. Same rule as the Debian base in the `Dockerfile`. (The apt
      mirror outages of 2026-10-07 are another reason; `apt-install.sh`'s HTTPS failover covers them
      meanwhile.)

### Left over from the 2026-10-07 review (tracker #12)
What the fixes for #13–#44 didn't finish, by area. Each names its issue where one exists.
- [ ] **Reads under load** (#14). Lists and counts are in SQL now, but search still scans every
      row (FTS5 if that matters) and every op still takes the one global exclusive lock, so at 20k
      rows and 20 VUs p95 only drops 1.7 s → 1.2 s. Per-thread WAL read connections is the fix (the
      1.x item above). The dashboard's `GROUP BY` is O(n), about 6–10 ms at 20k rows.
- [ ] **`--minimal` still carries demo weight** (#29). `CLAUDE.md`, `app/README.md`,
      `docs/USE_CASES.md`, `e2e/PLAN.md`, `load-tests/RESULTS.md`, `load-tests/lib/config.js`'s
      `TERMS`, and the full `app.css`/`app.js` theme library (≈134 of 190 classes unused by the
      starter) all describe or serve the demo.
- [ ] **Load parity is checked, not enforced** (#40). `load-tests/parity.sh` reports the routes
      with no load scenario (about 14 of 26 in the demo) but isn't in CI. Wire it in once the gaps
      are closed, and consider `run.sh --quick --strict` in the minimal job.
- [ ] **Test-suite gaps** (#42): order-dependent "first row" tests; the toast
      test races a 3.6 s timer; occasional Firefox-only flakes in `search.spec` and the
      `components.spec` drawer under local parallel load. The concurrent-cycle test documents the
      single-UPDATE contract but doesn't reproduce the old race.
- [ ] **Supply chain** (#44): pin `debian:trixie-slim`, the Playwright image and the actions by
      digest; add Dependabot or Renovate; turn on branch protection with required checks (today
      nothing is required, so GitHub auto-merge would merge immediately).
- [ ] **CI cost** (#43): document the per-run minutes for private forks in the README.
- [ ] **Ops polish**: origin gzip (#23); request ids in the access log (#20); optionally run e2e
      against the `-o:speed` binary (#37); a CSS watch loop for local dev (#35).
- [ ] **Auth will need**: a session CSRF token and `SameSite=Lax` cookies on top of today's
      `Sec-Fetch-Site`/`Origin` guard (#18).
- [ ] **`init --minimal` and the planning docs**: since the starter's plan lives in `docs/` (`PLAN.md`, `BRIEF.md`,
      `README.md`, `design/`, `spikes/`), a minimal fork inherits it, and init's report lists those files as
      still naming the upstream. The generator (M2) strips them; until then the `minimal` CI job passes regardless.
- [ ] **Upstream (odin-http)**: its shared `Date`-header buffer is rewritten every second while
      other threads read it. k6 saw 2 malformed `Date:` headers with NUL bytes in about 800k
      requests. Fixed in the vendored fork (F-11, `app/vendor/odin-http/UPSTREAM.md`); still to
      report upstream.
- [ ] **Upstream (odin-http): a negative `Content-Length` aborts the process.** `_body_length`
      (`body.odin`) checks only the upper bound, so `-5` reaches `assert(n >= 0)` in
      `scan_num_bytes`. `front` refuses it for every request it sees, but odin-http answers
      `OPTIONS *` itself and then drains the body, so `OPTIONS * HTTP/1.1` with `Content-Length: -5`
      still kills the server. Report it upstream with the chunked path's `size < 0` guard (#117) as
      the fix. Fixed in the vendored fork (F-6, `app/vendor/odin-http/UPSTREAM.md`); the issue is
      drafted, still to post upstream.

## Done

- [x] Initial showcase app (dashboard, components, forms, data + CRUD, search, JSON API).
- [x] Bug fixes: modal outside-click, `/forms` field reset, static slider fill.
- [x] Restructure into `app/` + `e2e/` + `load-tests/`; project docs (`CLAUDE.md`, this file,
      `CHANGELOG.md`).
- [x] git init + first commit; adopted Conventional Commits; infrastructure plan
      (`infra/PLAN.md`).
