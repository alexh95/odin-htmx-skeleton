# Resolutions of the open items (lead architect, 2026-10-25)

When the writing round assembled `docs/PLAN.md`, the writers, fact-checkers, editor and final critic left about 30
"Open:" items. Most are internal inconsistencies in `DECISIONS.md`, or gaps that need a design call rather than
Alex's judgement. This file decides each one (X1–X35), and X36–X43 (2026-10-26) decide what folding round 3 and the
device inventory raised. The resolutions are applied to both `DECISIONS.md` and `PLAN.md`, so the two stay in step.
Items that are genuinely Alex's choice become questions (Q29–Q33).

## Philosophy and ledger

- **X1. The ledger counts everything that bends the philosophy** (D3, PLAN §3.3).
  - "The line we hold" becomes: htmx plus the profile's extensions, odin-http (our fork), optionally SQLite, and
    optionally _hyperscript. An optional client runtime is still a dependency, and is counted as one.
  - The ledger grows from 5 to 7 rows:
    - **`tools/bundle`**: a prepare-time Odin tool. It concatenates pinned, SHA-verified files in a fixed order and
      precompresses them with the `brotli` and `gzip` CLIs, because core Odin has no compressor (09 §0.8). It has no
      module graph, no transpile step, no npm, and costs nothing at runtime. It is a bundler only in the sense of
      concatenation. It is counted because the skeleton's prepare ran once, while this one reruns when CSS, `_hs`
      or extension files change.
    - **`platform/guard`**: non-local control flow (setjmp/longjmp, formally UB, R4), confined to one package and
      the fork's callback entry points. It exists because Odin has no recover, so a single trap would otherwise
      kill every stream on every loop (13 §0). Pure-or-exit keeps it from hiding bugs: every trap is logged, and a
      dirty one exits with code 70.
  - Add a "what is *not* a runtime dependency" note:
    - Each profile still runs bare (`./bin/<profile>`) with no proxy. The compose + stack-Caddy setup on apollo is
      hosting topology for running five witnesses on one box, not something a profile needs.
    - hx-pending's optimistic copies and hx-history-cache's sessionStorage snapshots are transient caches of
      server-rendered HTML. The server stays the source of truth.

## Layering and the feature contract

- **X30. `platform/app` moves to the top of the platform as L4, the composition package** (D4, D5, PLAN §5.1).
  - It imports L1–L3. Only feature web packages and `cmd/*` import it, so no layer exception is needed.
  - `platform/web` re-exports `web.Request :: http.Request` and `web.Response :: http.Response`, so no feature
    package ever imports odin-http.
  - `platform/obs` (L2) supplies counters and health state, and `platform/web` serves `/metrics`, `/livez`,
    `/readyz` and `/healthz` from it.
  - `tools/check imports` enforces all of this.
  - **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.3.
- **X4. Reword D5 boot check 5.** A route whose prefix or flags need a perm (`/admin/*`, `.Step_Up`, `.Lan_Only`)
  but that declares `.Public` fails boot. The editor flagged a "duplicate perm" check in D5: make it mean "the same
  `Perm` member listed twice in `ROLE_PERMS` for one role is a compile-time impossibility (a bit_set)", and drop it
  as a boot check.
- **X5 / X28. Who owns `/`: exactly one root feature.**
  - The root feature is `home` by default, `dashboard` in the `skeleton` profile, and `landing` in `lab`. The three
    are mutually exclusive, and the generator refuses two of them.
  - D9's list of skeleton URLs adds `/` and `/ui/ping` under `dashboard`.
  - D27 changes from "every generated project includes `home`" to "every generated project has a root feature:
    `home` unless the selection includes `dashboard` or `landing`".
  - The skeleton's dashboard stays byte-identical, so it shows no home cards. The home cards appear only where
    `home` is the root.
  - **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.3.
- **X29. Implementation packages may declare `EXTS` too** (D19, D21, D24).
  - The bundle is the union of `EXTS` over every imported package, web and impl alike:
    - `chat_transport_ws` declares `.Ws`, `chat_transport_sse` `.Sse`, `chat_transport_multipart` `.Multipart`, and
      `chat_transport_poll` `.Ptag`.
    - `chat_web` declares only what the feature needs regardless of transport: `.Pending .Upsert .Prompt .Targets`.
    - `bot_web` adds `.Browser_Indicator`.
  - D24's bundle column is labelled "derived", and its lists are recomputed. `streams` gains hx-prompt and
    browser-indicator.
  - The fatal header check stays. §6.1's chat `EXTS` and §7.4's sample follow this.
  - **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.3.

## Names

- **X7.** `NICK_FROM` becomes `ACCOUNTS_NICK_FROM`, following D10's prefix rule.
- **X9.** `user_prefs` becomes `accounts_prefs`, owned by `accounts`. This applies everywhere: D8, D23 and D35, and
  PLAN §6, §11, §12, §14 and §17.
- **X12.** Every room route is keyed by slug, `/chat/r/<slug>/...`, including `read`. DMs get an opaque generated
  slug.
- **X6.** `tools/init` keeps the skeleton's naming flags (`--wordmark --suffix --repo --site`) unchanged. They write
  `cmd/app/brand.odin` (D26).

## Hub, data and features

- **X8. `.Latest` keeps the newest message per publish key.** The default key is the topic key. Publishers may
  pass a key, which is the element id the message targets. `jobs.runs` publishes with key = the run id, so its
  replay holds the latest row of each run, capped at the ring size (D13).
- **X13. `uploads` owns its session rows** (`uploads_blobs`, `uploads_parts`).
  - With SQLite present it stores them through `uploads/store_sqlite`. With `uploads/store_memory` they live in
    memory and are lost on restart, so resumable uploads need SQLite. `uploads` itself does not require SQLite.
  - Video's `store_sqlite` holds video metadata, not uploads. Fix D33's wording, and add the store axis for
    `uploads` in D8 and D18.
- **X14. The chunks go through the app.js shim** (fetch), so no htmx timeout applies to them. `hx-config`
  `timeout:0` sits only on the finish request (`POST /uploads/<id>/finish`), which can run long while the server
  hashes and moves the file. **UNVERIFIED (M6)**.
- **X10. Terminal recordings keep both caps:** 30 days or 1 GiB in total, whichever comes first. The size cap
  protects apollo's disk (NEW). Q12's default says so.
- **X27.** Drop "on the cut list" from D33. In-app transcoding with a host ffmpeg is Q21's non-default option and is
  not built.
- **X32. The bot's place in the starter.**
  - Reading: "not part of the starter" means no model, no llama.cpp and nothing AI ships. The `bot` package (chat
    UI, the stream contract, the `Bot_Backend` vtable, the llama.cpp binding, the mock) is exactly what the brief
    calls relevant, so it stays a catalog feature and is in `streams`.
  - If Alex meant the bot to live only in Houston, the change is one line: drop `bot` from `streams` and mark it
    showcase-only in the catalog.
  - New **Q32**, default: keep it as a catalog feature.

## Security and headers

- **X11. `report-to`.** `full`, `streams` and `lab` send `Reporting-Endpoints: csp="/csp-report"` and add `report-to
  csp` to their CSP. `minimal` and `skeleton` never do, because they keep the skeleton's exact header set.
  `/csp-report` logs at warn and is rate-limited (§17.5).
- **X31. Trusted proxies on apollo.**
  - The stack Caddy trusts `X-Forwarded-For` only from the address NPM connects from. S0.12 records that address;
    until then the list is empty.
  - So at stage 1a, a LAN host that connects straight to :8120 is identified by its TCP peer and cannot choose its
    client address.
  - The app's `TRUST_PROXY` is the stack network's subnet, which means Caddy only.
  - Replace `trusted_proxies static private_ranges` in D41's Caddyfile accordingly.
  - **Superseded in part** (X39): the address was measured as the stack network's gateway, Caddy's one entry.
  - **Superseded in part** (X43): the app's `TRUST_PROXY` is Caddy's fixed address as a /32, not the subnet.
- **X16. The default role grants become Q31** (they are judgement calls):
  - `Term_Watch` goes to Moderator and Admin;
  - `Video_Upload` goes to Moderator and Admin;
  - `Admin_Audit` is Admin only.
  - Default: as tabled; `rbac.spec` freezes them at M4.
- **X19. A spec for revoked streams.** `revoke.spec` (M4) has the server send the named `kicked` event, which
  triggers a full navigation to `/login` and so removes `#live`. A reconnect without auth gets 403, and the spec
  asserts that the server sees at most 3 reconnects in 30 s. Whether hx-sse itself stops retrying after a 403 is
  **UNVERIFIED (M4)**.

## Gates, CI and milestones

- **X2 / X3. apollo first, Fly last.**
  - The Fly witness is not redeployed at the M1 exit. odin-htmx.alexh95.com keeps serving 709bc94 (v1.2.0)
    untouched until the M3 exit.
  - By then `starter-skeleton` has passed the parity gate and the 40-item checklist on apollo's LAN (stage 1a).
  - Order at the M3 exit: Alex sets `FLY_DEPLOY=true` first, then the agent pushes the v2.2.0 tag, and its
    `deploy-fly` run deploys `cmd/skeleton`.
  - v2.0.0 at the M1 exit is tagged with `FLY_DEPLOY` still off.
  - This honours the brief's "apollo before the web". Q29's default becomes "hold the Fly redeploy until M3", with
    "redeploy at M1" as the alternative.
- **X25.** M3's exit gate gains "parity gate green": the rule is every milestone exit (D38).
- **X26.** The `e2e-proxy` job and a CI Caddyfile (the same `deploy/Caddyfile`, run in CI) are scoped to M2, whose
  exit needs them. M3 adds `proxy-config` for NPM's nginx and the apollo deploy.
- **X18.** `lab` runs in chromium and webkit locally and in all three engines in CI, Firefox included. This matches
  D44's M2 exit, and D37's matrix is updated.
- **X17.** The file-DB write result of 0.98× is a watched margin, not an open question.
  - S0.1 and S0.4 settle it.
  - If the cell fails, the file DB also gets D17's candidate C (group commit through the writer task) for skeleton
    writes.
  - Add it to R-register as a sub-item of the parity risk.
- **X22.** `lab` is a witness: it gets the witness resource class (the same limits as `minimal` and `streams`).
  This applies to D2's witness definition and to D38's budget table.

## Hosting and the terminal

- **X20. D41's healthcheck becomes valid compose:**
  `healthcheck: {test: ["CMD", "/app/bin", "--healthcheck"], interval: 10s, timeout: 3s, retries: 3}`.
- **X21.** `promote.ps1` stages `deploy/docker/seccomp-io-uring.json` next to `compose.yaml` on apollo, and compose
  references `./seccomp-io-uring.json`. The `docker` job and M3 confirm the path.
- **X23. Port 8120 and requests without a known host.**
  - Compose publishes `8120:80`.
  - The Caddyfile ends with a catch-all `:80` block that answers 421 with one line pointing to `docs/OPS.md`
    (use a host name).
  - Stage-1a LAN testing uses split DNS or a hosts-file entry (§20.3).
  - `proxy-config` asserts both the publish and the catch-all.
  - **Superseded in part** (X41): split DNS is decided, so stage-1a testing needs no hosts-file entry.
- **X24. What the starter takes from spark's wsserver** (fixes D12/D43, which cited test cases that don't exist).
  - Take its RFC 6455 coverage table as a checklist, its limits, and the fault-injection idea. wsserver has no unit
    tests (03 §5.1).
  - The starter's strict codec gets new unit tests.
  - A nightly run of the Autobahn|Testsuite fuzzing client (dev-time Docker image, exempt like Playwright and k6)
    runs against the lab's WS echo (NEW).
- **X15. The Pi agent's delivery** (Q30).
  - The `release` workflow attaches the linux_arm64 `term-agent` binary and its SHA-256 as a GitHub release asset.
  - Alex copies it to the Pi.
  - The systemd unit reads `/etc/houston/term-agent.env` as an EnvironmentFile: `TERM_AGENT_URL`,
    `TERM_AGENT_HOST`, and `TERM_AGENT_TOKEN_FILE` → `/etc/houston/term-agent.token`, mode 0600.
  - The agent sends its version in `hello`, and `/admin/term` flags outdated agents.
  - Q30 keeps this as its default.

## Found while applying X1–X32

- **X33. The `Ext` enum moves to `platform/ext`**, an L1 leaf package that imports nothing, with its
  registration-name and file tables. `platform/web` re-exports it as `web.Ext`.
  - An implementation package imports `platform/ext` (D4's impl row allows it) and declares
    `EXTS :: bit_set[ext.Ext]{...}`.
  - Every vtable struct carries `exts: bit_set[ext.Ext]`, set by each implementation's constructor from its `EXTS`.
    The feature's `register()` unions its web `EXTS` with the `exts` of the implementations it was given, into
    `Feature.extensions`.
  - `tools/bundle` derives the same union from the imported packages' `EXTS` lines. D5's boot check compares the two,
    and a mismatch is fatal: an implementation was imported but never registered, or the reverse.
  - **Superseded in part** (ANSWERS round 3): see `DECISIONS.md` §0.3.
- **X34. `chat_web` declares `.Download`** for chat's own transcripts (D21), so a selection with chat and without bot
  still ships hx-download.
- **X35. The `skeleton` profile keeps the base headers** (D20): the skeleton's CSP verbatim, plus Permissions-Policy,
  COOP and CORP. Only `minimal` keeps the skeleton's exact header set.
  - The three extra headers are static strings built at boot, so they have no measurable cost. They don't change
    the feature set either.
  - The 40-item checklist lists them as intentional differences.
  - `report-to` stays off in `skeleton` (X11), so its CSP string is the skeleton's own.

## Found while folding round 3 and the device inventory (2026-10-26)

- **X36. `about` goes on houston-lab** in `full`, next to the skeleton's other demo pages. This confirms the fold's
  reading. Houston proper has no "about the stack" page; its footer links to houston-lab.
- **X37. The bot's room mode uses two static topic rows**: `bot.ask`, consumed by bot, and `chat.reply`, consumed by
  chat, which stores the answer as a chat message.
  - Neither feature imports the other, and each works alone.
  - This is what ANSWERS round 3's "a hub topic with a static `TOPICS` row" needs in practice: one row each way.
- **X38. Demo caps on houston-lab**: `NOTES_CAP` 500 and `CONTACTS_CAP` 2000.
  - Two nightly jobs, `notes.reset` and `contacts.reset`, put the demo rows back at 04:00 local time.
  - The caps apply only where `full` mounts these features on its lab host. The `skeleton` profile stays uncapped,
    so parity and the 20k-row scale scenario are untouched.
- **X39. Trusted proxy on apollo: trust the stack network's gateway.**
  - The devices session measured `<NPM_UPSTREAM_ADDR>` as the gateway of the stack's own Docker network, so Caddy's
    single `trusted_proxies` entry is that gateway.
  - The residual risk is written down: any container on apollo that reaches the published port could claim a client
    address. Those containers are Alex's own services, so the risk is accepted.
  - Joining NPM to the stack's network is rejected: it would change NPM's configuration, which is Alex's service,
    and §20.4 never names containers.
- **X40. apollo's NPM is older than the version the plan modelled.** The `e2e-proxy` job pins and models apollo's
  actual NPM version, recorded in `SITE.md`. Upgrading NPM is Alex's optional step and never an agent's. Raising
  `worker_connections` (Q14: yes) stays Alex's step at M3.
- **X41. Device roles enter the plan** (from `DEVICES-SUMMARY.md`, as PLAN §20.8, plus edits where each fact lands):
  - **Bot host:** apollo's spare GPU (`<APOLLO_GPU>`) runs llama.cpp's official Vulkan server image, in a compose
    project Alex owns that agents never restart.
    - It publishes `<LLAMA_PORT>` with an API key, and `BOT_LLAMA_URL` = `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`.
    - It fits a 4–8B Q4 model with about 8k of context. Tokens/s are measured with `llama-bench` at M7.
    - Alex's step at M7.
  - **Terminal:** the target is a Pi 4 (64-bit Pi OS Lite, wired). A Pi 3B+ is the second device for multi-device
    tests, and Pi Zero class boards can't run the agent.
  - **Split DNS** (Alex, decided):
    - seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, added at M3 before the first LAN deploy;
    - the records of names that go public are deleted at M12, so the wildcard applies again;
    - k6 no longer needs `hosts` overrides on the LAN.
  - **Uplink:** `<HOME_UPLINK>` is not a binding stage-2 trigger, so Q26's CDN becomes optional.
  - **The game embed** gets `xr-spatial-tracking` in its `allow` list and a WebXR spec in `games-frame.spec`, for
    the VR headset (M10).
  - **An old Android phone** is the oldest-browser test device. D22's core flows (links, forms, SSE) must work there
    without the client behaviours. Whether htmx 4 runs on that browser is UNVERIFIED (M6).
  - **The other roles** (uptime watcher, Windows test client, second load generator, tablet, Steam Deck) are listed
    in §20.8 as optional. None of them blocks a milestone.
- **X42. The device-driven features become an optional milestone, M14 Devices** (after M12, like M13). Q33: yes (Alex, 2026-10-26; ANSWERS round 4):
  - a device registry and feed: `/admin/devices` generalises `/admin/term`'s device tokens, plus a plain-text
    `text/event-stream` for screens that can't render HTML. One line in the ledger: a non-HTML representation, still
    rendered by the server;
  - cameras (`cams`): Houston pulls each camera's MJPEG stream once and fans it out to members as
    `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS. LAN-only and members-only first;
  - a wall and TV dashboard: a kiosk view of Today, signed in by a device token.

  Live video (Pi → ffmpeg → live HLS), the radio feed, the mesh bridge and WireGuard stay in an "ideas" list and are
  not scheduled.
- **X43. The app trusts Caddy's address only, not the stack subnet.**
  - `deploy/compose.yaml` pins the stack network's subnet and gives `caddy` a fixed `ipv4_address`, and every app
    container's `TRUST_PROXY` is that one address, as a /32.
  - The gateway that Caddy trusts (X39) sits inside the subnet. With `TRUST_PROXY` set to the whole subnet, a process
    on apollo's host that connected to an app container directly would arrive from the gateway and be trusted for
    `X-Real-IP`.
  - App containers publish no ports, and only Caddy publishes `:8120`.
