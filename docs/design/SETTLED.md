# Settled by evidence (input to the design round)

The research round (`docs/research/00-digest.md` and notes 01–13) left the completeness critic's contradictions
open. The gap-fill notes ran experiments that settle most of them. These are the **working assumptions** for the
design round. A proposal may overturn one only with new evidence, and must say so explicitly.

## Server substrate

- **S1. Fork odin-http and own the fork** (03 Option A). The no-fork seam (07 §0.2) only covers client
  disconnect. Three things need code inside odin-http: server shutdown (it waits forever on Active connections,
  and `connection_close` is private), crash containment (13), and timeouts and limits (02). Use 03's prototype
  seam: about 4 lines in `server.odin` plus `stream.odin` holding open responses, chunked or raw after a 101. Keep
  the protocol code (the WS codec, the SSE encoder, multipart/mixed, the hub) in the starter, outside the fork, and
  offer the seam upstream.
- **S2. SSE, WebSocket and multipart run inside the nbio event loops, on the HTTP port.** There is no second
  port and no separate realtime server. spark's `wsserver` contributes its limits, its fault-injection ideas and
  its RFC 6455 test cases, not its I/O loop (03, 06).
- **S3. Fan-out is a cross-thread hub with one shard per event loop.** Each loop gets one wakeup per publish
  batch, and a replay ring serves `Last-Event-ID`. Event ids carry a boot epoch, so a stale id after a restart
  forces a resync (13). nbio's cross-thread queue holds 128 slots and spins when full, so never post per message
  per connection (07 saw a livelock).
- **S4. Long-lived connections get a connection-owned allocator.** The request temp arena is freed after each
  flush, so stream state must never live in it (02).
- **S5. Crash model (13).** Odin has no in-process recover: `Assertion_Failure_Proc` is noreturn, and bounds
  checks trap without a context. What works:
  - A setjmp guard in the fork, at each callback. It catches all 15 crash kinds tested.
  - On a trap, continue only if the thread held no locks and posted no async ops. Otherwise answer 500, drain,
    and exit with code 70.
  - A loop watchdog turns hangs into exits.
  - A supervisor restarts the process. Docker outside Swarm does not restart unhealthy containers, so the app
    exits on an unhealthy state itself, and compose `restart: unless-stopped` handles the rest.
  - Raise `ulimit nofile`, use `SO_REUSEADDR`, and give shutdown deadlines.
- **S6. Fix before any public exposure:**
  - A `Content-Length` below zero aborts the process (02 F1).
  - Enum columns cast unchecked.
  - Idle and read timeouts, and a max-connections cap.
  - The Date-header race.
  - spark's `client_address` trusts any peer (it needs a trusted-proxy check).
  - spark's markdown renderer needs a nesting-depth cap before it touches user content.
- **S7. Route by prefix first** (each feature owns a prefix), then by pattern within the feature. odin-http's
  linear Lua-pattern scan costs about 140 ns per route tried (09).

## Data

- **S8. Store "v3"** (12, measured):
  - one read-only connection per nbio loop, opened lazily through `@(thread_local)`;
  - `SQLITE_DBCONFIG_ENABLE_QPSG` at open;
  - `SQLITE_DEFAULT_MEMSTATUS=0`;
  - one writer connection behind a mutex, with `BEGIN IMMEDIATE` and per-tick batching for chat inserts;
  - a 2-thread query pool for slow reads, whose results return to the owning loop by `next_tick`;
  - sort indexes for list pages;
  - deletes done in chunks.

  `:memory:` cannot serve concurrent readers. Where the store must be concurrent and ephemeral, use a WAL temp
  file, and accept the measured write cost.
- **S9. SQLite stays optional** through a Store vtable. A pure-memory implementation serves profiles without
  SQLite, so they need no C toolchain (09: dead-code elimination drops the foreign lib). Migrations are keyed by
  (feature, seq, name, sha256) and are compatible with existing skeleton and spark databases (12, 6/6 tests).

  **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.2 and §0.3, and `LEAN-COMPOSITION.md`.
- **S10. FTS5 needs `-DSQLITE_ENABLE_FTS5`**, which the skeleton's flags lack. Use the unicode61 tokenizer.
- **S11. argon2id runs on a worker pool, never on an event loop.** Measured timings ranged from 25 to 190 ms
  on a noisy shared box. Size the pool and pick the parameters from a fresh measurement in M0.

## Client stack

- **S12. CSP: the skeleton's hash CSP holds app-wide.**
  - `hx-csp`, `hx-live`, `hx-on` and trigger filters run only on `/scripting/*`, with a per-response nonce.
  - App-wide hx-csp fails on evidence (11): it strips `hx-*` from stream fragments, and injected connect
    attributes bypass it.
  - `connect-src 'self'` covers same-origin ws:/wss:; it was verified in Chromium and WebKit, and Firefox goes
    into the e2e matrix.
  - Add Permissions-Policy, COOP and CORP. Never send COEP. HSTS belongs at the proxy.
- **S13. One concatenated, fingerprinted bundle per profile.** It is built at prepare/build time, precompressed
  with the brotli and gzip CLIs, and `#load`ed. Order: htmx, then hx-csp (only on /scripting), then the
  extensions, then hyperscript. It is mandatory because a `defer` load-order race leaves later extension scripts
  uninitialised (04, verified).
- **S14. The htmx-config meta stays strict JSON**, not HCON, because hyperscript `JSON.parse`s it. An
  `extensions` allowlist must name `hs-include` when hyperscript is in the profile.
- **S15. _hyperscript 0.9.94: core only.**
  - Behaviours live in `.\_hs` files served by the binary, and markup only says `install Name`.
  - A `hyperscript:before:init` gate refuses everything else. Escaping does not protect a value spliced into
    `_`.
  - SSE and WS go through hx-sse and hx-ws, not hyperscript's `socket` or `eventsource`; `worker`, `component`
    and `hdb` are blocked by the CSP.
  - It is an optional per-profile feature and the 4th line in the "90% honestly" ledger.
- **S16. htmx 4.0.0 (2026-08-28) is the pin.** The `four-dev` branch has fixes and is a watch item.
  - Every extension ships in the htmx.org tarball at `dist/ext/<name>.min.js`.
  - Loading an extension registers it, and there is no `hx-ext`.
  - hx-preload sends no `HX-Preloaded` header in 4.0.0.
  - `htmx-2-compat` and `hx-alpine-compat` live on `/compat/*` pages with their own bundles.
  - hx-multipart carries an MIT notice for its Shopify parser port.

## Granularity

- **S17. Select features with packages, not flags** (09, experiments):
  - one package per feature;
  - one entry package per profile, `cmd/<profile>/main.odin`, whose import list *is* the feature selection;
  - explicit `register()` calls;
  - proc-field vtables for alternative implementations, each implementation its own package;
  - runtime env selection only among the implementations the profile imports;
  - `tools/init` grown into a composing generator, using the skeleton's plan-then-commit engine.

  `#config` stays for `VERSION` and rare build switches.

  **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.2 and §0.3, and `LEAN-COMPOSITION.md`.

## Performance baseline

- **S18. "The skeleton's performance" means skeleton HEAD (709bc94) and v1.1.1, measured on the same box in the
  same session**, on both the 20-row suite and the 20k-row scale scenario, with the noise band recorded. The
  stale v1.0.0 RESULTS.md is not the target. The starter's `skeleton` profile must match or beat the better of the
  two on every scenario. 12 shows store v3 does.

## Repo and hosting

- **S19. Repo: rename in place to `odin-htmx-starter`** (10). This is a recommendation; Alex decides.
  - Before the rename: tag v1.2.0 plus a `skeleton-1.x` branch, and gate `FLY_DEPLOY`.
  - odin-htmx.alexh95.com stays on Fly, serving the `skeleton`-parity profile as the standing witness.
  - Versioning continues at v2.0.0.
  - spark repoints through Ark at Alex's pace.
- **S20. Hosting goes in stages: dev PC → apollo LAN → apollo public behind nginx-proxy-manager → a VPS if
  needed** (08).
  - NPM gives HTTP/2, which fixes the 6-connections-per-origin SSE limit. On the LAN that means split DNS plus a
    LAN-only Access List.
  - Pitfalls: a 90 s `proxy_read_timeout` (so heartbeat every 15–25 s), buffering on (send
    `X-Accel-Buffering: no`), `worker_connections` 512, and Advanced-tab directives that don't reach NPM's
    `location /`.
  - apollo is a modest home server shared with Alex's other self-hosted services; NPM plus TLS caps out at about
    1.9k RPS. It is not a perf box.
  - Video goes to bunny.net when public. Cloudflare's terms forbid video.
  - The VPS fallback is OVH VPS-2, Hetzner CX33 or Netcup, running spark's compose + Caddy prod flavour.

  **Refined** (RESOLUTIONS X41): bunny.net is optional, because the home uplink is not a binding limit; see
  `DECISIONS.md` §0.2.
- **S21. Deploys run from the dev PC over SSH** with `compose pull`. GitHub runners can't reach apollo, and
  self-hosted runners on a public repo are unsafe. Images go to GHCR with semver tags. ffmpeg never goes in a
  published image (GPL).

## Games

- **S22. Games: an iframe embed of `/play/<g>/?embed=1`**, verified working today with no spark change.
  - The starter renders the catalog server-side, polls healthz and scores, and pushes updates over SSE.
  - Phones link out to the full game.
  - spark adds `GET /api/games` (about 50 lines), a `frame-ancestors` allow-list on `/play/*`, and an embed-mode
    test.
  - Reverse-proxying the games under the starter's domain is rejected, and so is SSO for now (it would reopen
    D3).
  - Rebuilding the portal on the starter is a later dogfooding milestone.

## Still open — for the design round to decide

- **What a profile is at hosting time.** Options: one binary serving several route-prefixed profiles; one
  container per profile; or both (e.g. a `showcase` binary with `/minimal` and `/full` mounted, plus separate
  containers as representative witnesses). Also paths vs one-label subdomains. A two-level subdomain is not
  covered by the `*.alexh95.com` wildcard.
- The showcase app's concept, information architecture and full feature list.
- The terminal approach: a server-side VT emulator vs xterm.js vs line mode, and in what order.
- Chat transports offered as alternative full implementations.
- Milestone order, effort, and the exit gates.
- The profile catalog (which profiles exist, and what each contains).
