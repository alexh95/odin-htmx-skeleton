# Alex's answers

Answers Alex gave in conversation, recorded as given. Each is followed by how the plan reads it. Where a reading is
an interpretation, it is marked **(reading, to confirm)**. Every round is folded into `DECISIONS.md` and
`PLAN.md`; round 5 answers the gate questions M0's spikes raised.

## Round 1 (2026-10-25)

The topics were the nine decisions most worth discussing, as numbered in the conversation.

| # | Topic | Alex said | What it means for the plan |
|---|---|---|---|
| 1 | Package shape per feature | "Let's keep the packages in separate files for more flexibility, let's also keep the layering done explicit (one calling the other directly) and as simple and lean, not using injection or DI or stuff like heavy frameworks such as spring likes to do." | Keep the per-feature split (domain / views / web, plus implementations) as separate units. **Layers call each other directly**, like the skeleton (`controllers → services → repository`, qualified calls). **No dependency injection**: no proc-field vtables handed in from `cmd`, no `ports` struct, no registration framework. This overturns the mechanism in D5–D8 and X33 (vtables, `register(impl values)`, `ports`), so a lean replacement is needed **(reading, to confirm: see round 2)**. |
| 2 | Two client implementations (_hyperscript + vanilla twins) | "Fine let's dupe it for now." | Keep both (D22) as planned. |
| 3 | Effort (about 610 agent-hours) | "It's going to take however long it's going to take." | No cap on effort. The estimates stay as a guide only. |
| 4 | A container per profile on its own subdomain | "Using separate domains and independent containers for each is sensible as long as full integrates all." | D25 stands. **`full` must integrate every feature** **(reading, to confirm)**. That includes the four lab-only extensions (hx-live, hx-csp, htmx-2-compat, hx-alpine-compat), which today live only in `lab` on an origin with no sessions, for security. See round 2. |
| 5 | Rename in place | "Great, make sure to use this workspace then and not the old folder in www." | Q1 = **yes** (rename `alexh95/odin-htmx-skeleton` to `odin-htmx-starter` in place). All starter work happens in `<WORKSPACE>`, never `<OLD_DEMO_DIR>`. This workspace becomes the renamed repo's checkout (how is a round-2 question). |
| 6 | Houston as the showcase | "I like it." | Q3 = **Houston**. |
| 7 | Fork odin-http | "That is fine, also keep it somewhere in this workspace." | Q4: fork it. The fork's code lives **in this workspace**, vendored inside the repo (e.g. `app/vendor/odin-http/` with an `UPSTREAM.md`), rather than only in a separate GitHub repo **(reading, to confirm)**. |
| 8 | _hyperscript where the CSP allows; four extensions only in the lab | "ok" | D21/D22 stand, subject to #4. |
| 9 | The VT parser in the Pi agent | "That's sensible." | Q8 = **agent-side VT** (D32). |
| — | Licensing spark modules | "you can [license] it to zlib." | Q17 = **yes**: the spark modules the starter adopts are licensed zlib, and spark gets a LICENSE. The scrubbing of LAN and host details still applies. |

## Round 2 (2026-10-25)

| Item | Alex said | What it means for the plan |
|---|---|---|
| F1 | (not commented; #1 is Alex's own direction) | The no-DI mechanism goes ahead. `LEAN-COMPOSITION.md` is shown to Alex before it is folded in. |
| F2 | "Misunderstanding, fully implements independently is what I meant. Push back if there are important reasons not to do this." | `full` implements every feature itself, with no dependency on any other profile's container. That includes the four lab-only extensions (hx-live, hx-csp, htmx-2-compat, hx-alpine-compat). **Pushback, with a fix that keeps the intent:** those pages need `eval`, or change htmx's semantics, so they must not share an origin with Houston's sessions. The `full` binary serves them on a second, session-free host, `houston-lab.alexh95.com`: one binary, one container, two origins. That host never sets or reads a session, and its routes answer only on it. The `lab` profile stays its own independent witness. **Alex confirmed:** "Yes: full serves the four lab-only extension pages on houston-lab.alexh95.com, with no sessions there." |
| F3 | "Good choice actually." | The odin-http fork is vendored in-tree at `app/vendor/odin-http/`, with `UPSTREAM.md` (laytan fac113f plus F-1..F-12). There is no separate GitHub repo; an upstream offer later goes through a fork made at that time. |
| F4 | "Yes, absolutely." | The public docs get scrubbed. LAN addresses, apollo's hardware and the services running on it, user names and host paths move to a git-ignored `docs/private/SITE.md`, and the public docs use placeholders. `docs/research/`, the proposals and `OUTLINE.md` stay out of git. |
| F5 | "Yes." | This workspace becomes the renamed repo's checkout at M0, and `_ref/` goes. The skeleton crash fix was committed and pushed by the fix session as `6d37506` on `master`, so it becomes v1.2.1. v1.2.0 is still to be tagged at 709bc94 (only v1.0.0–v1.1.1 exist on origin), and the S18 baseline stays 709bc94 + v1.1.1. The separate clone `<SKELETON_FIX_CLONE>` is deleted once the workspace is the checkout. |
| Q2 | "Fine." | Hosts as recommended, plus `houston-lab.alexh95.com` (F2). |
| Q29 | "Yes." | Fly keeps today's build until the M3 exit. The fix commit's CI run failed on a toolchain-setup timeout, so its deploy never ran, and Fly still serves 709bc94. Once the fix deploys, that build is `6d37506` (v1.2.1). |
| Q15 | "Disregard but warn if it's more than $10 a month." | Keep the Fly witness. Warn Alex if its cost goes above $10/month. |
| Q5 | "Yes" | Install Odin dev-2026-10 in WSL2 for the Linux legs. |
| Q24 | "fine." | The apollo facts are collected at M0, and agents may run LAN load tests of 10 minutes or less. |
| Q14 | "yes." | Raise NPM's global `worker_connections` to 4096 before the M3 soak. |
| Q32 | "Yes." | The bot stays a catalog feature, and it is in `streams`. |

The remaining questions keep their recommended defaults, since Alex overrode none of them. Raised and not overridden:
Q10, Q11, Q12, Q13, Q18, Q19, Q20, Q21, Q22, Q23, Q25, Q27 and Q31. Not yet raised in conversation: Q6
(conditional), Q7, Q9, Q16, Q26, Q28 and Q30, and Q33, which came later (RESOLUTIONS X42, 2026-10-26).

## Round 2: follow-ups as asked

The questions as they were put to Alex.

- **F1. The lean composition mechanism for #1**: layers call each other directly, with no DI. The proposed shape is
  being prototyped (see `LEAN-COMPOSITION.md` once written):
  - an implementation that depends on a C library or is chosen per build (the store: SQLite or memory) is picked at
    build time by the profile's build line, through an Odin collection. The domain calls it directly;
  - an implementation chosen per request (the chat transports, the bot backend) is a plain `enum` plus `switch` with
    direct calls;
  - routes, nav and migrations are listed explicitly in each profile's entry files, as in the skeleton's
    `routes.odin`, and written by the generator.
- **F2. "full integrates all"**: either the `full` binary also serves the four lab-only extensions' pages on a
  second, session-free host (recommended), or they stay in `lab` only and Houston links to them.
- **F3. Where the fork lives**: in-tree at `app/vendor/odin-http/` (recommended), or as a separate repo checked out
  inside the workspace.
- **F4. Public repo hygiene**: the research notes and the plan name Alex's LAN IP, apollo's hardware and the
  services that run on it. Before the planning docs are committed to the public repo, scrub them, or keep
  `docs/research/` and the proposals out of git.

## Round 3 (2026-10-25)

| Item | Alex said | What it means for the plan |
|---|---|---|
| No-DI choices (`LEAN-COMPOSITION.md` §13) | "I'll go with your recommendation for the two questions." | **The simpler set** (the main session's recommendation, which overrides the doc's own recommendations):<br>- each package keeps its own `ROUTES` table, and the profile's hand-written `routes.odin` mounts one line per package;<br>- one Odin collection per family, four flags in all: `store` (`app/stores/{sqlite,memory}/<feature>/`), `identity`, `client`, `theme`. There are no generated `sel/` alias packages, and imports land straight on the real code;<br>- one hand-written `switch` in `chat_web` over all four transports, and a switch for the bot backend (chosen by env). Every chat profile ships all four transports;<br>- `build.{sh,bat} <profile>` is the one place the flags live;<br>- `main.odin` and `routes.odin` are hand-written per profile, like the skeleton. The generator writes them for new projects and edits them when a feature is added or removed, and CI checks that they are consistent;<br>- the bot's default backend is set on `/admin/bot`;<br>- cross-feature calls: chat imports notify directly (a hard dependency), the audit log goes through `store:audit` (the memory build writes log lines only), and the bot's room mode runs over a hub topic with a static `TOPICS` row. |
| What "every feature" in `full` covers | Same answer: the main session's recommendation. | `full` carries every catalog feature. Houston proper stays on `houston.alexh95.com`. Every starter demo and lab page goes to the session-free `houston-lab.alexh95.com`: the skeleton's notes, contacts/events, components gallery and dashboard; the lab's stream demos; scripting and compat; and the catalog explorer (`landing`) at that host's root. Each host has its own root feature. The demo data there is capped and reset nightly. |

## Round 4 (2026-10-26)

| Item | Alex said | What it means for the plan |
|---|---|---|
| Q33 (M14 Devices) | "Yes, add M14 Devices with the default scope: device registry and feed, cams, and the wall dashboard; live video, radio, mesh and WireGuard stay ideas." | **Answered.** M14 Devices is scheduled as an optional milestone after M12: the device registry and feed (with its ledger line), cams (an MJPEG fan-out as `multipart/x-mixed-replace`, LAN-only and members-only first) and the wall/TV dashboard. Its gates, proposed in D44, become its gates. Live video, the radio feed, the mesh bridge and WireGuard stay in the ideas list. |

## Round 5 (2026-10-26)

The gate questions M0's spikes S0.1, S0.4 and S0.5 raised, relayed by the planning session. Alex's message was cut off
by the reply box's length limit; its last words are the button Alex clicked, "1 argon thread on ≤ 2 CPUs".

| Item | Alex said | What it means for the plan |
|---|---|---|
| Q6 (`:memory:` parity) | "Q6 take the default (pick C, gate the failing :memory: cells against HEAD 709bc94 with a documented exception, never waive file-DB cells)" | **Answered: the default.** Candidate C (store v3, sort indexes, the ephemeral file unsynced, on tmpfs on Linux, and group commit through the writer task) is the `skeleton` profile's `:memory:` mode. The `:memory:` cells C fails against max(HEAD, v1.1.1) are gated against HEAD 709bc94 instead, each named in a documented exception (`tests/parity-waivers.txt`); a file-DB cell is never waived (S0.4). |
| Q35 (the light routes' reference) | "light routes (static, seo) gate against HEAD 709bc94 only, store routes against max(HEAD, v1.1.1)" | **Answered.** On `static` and `seo` the gate compares the candidate with HEAD alone, because v1.1.1 is faster there only by lacking 1.2.0's security middleware (S0.1); every other scenario keeps max(HEAD, v1.1.1). |
| Q34 (the login-storm budget) | "Q34 take the default (absolute budget, 1 argon thread on ≤ 2 CPUs" | **Answered: the default.** 50 logins/s under `cpus: 2.0`: other routes' p99 ≤ their base + 0.5 ms, the cgroup never throttled, every login answered; `ACCOUNTS_ARGON_THREADS` is 1 when the container has ≤ 2 CPUs, else 2 (S0.5). |

## Round 10 (2026-10-27)

The skeleton's binary budget, relayed by the planning session with three options: (a) 3 MiB, (b) SQLite's OMIT flags
(about 69 KB), (c) keep 2.75 MiB. The fork's F-17 had put the skeleton 512 B over 2.75 MiB, and M2's shared client
code (slices 3 and 4) 11,264 B over.

| Item | Alex said | What it means for the plan |
|---|---|---|
| The skeleton's binary budget | "Tell it (a)" | **(a).** `skeleton` ≤ 3 MiB on Windows `-o:speed`, in CI's size check, the drills, D38 and §18.4. No SQLite OMIT flags and no re-encode of the social card; nothing byte-neutral is needed to hold the old figure. |

## Round 9 (2026-10-26)

The three gaps M2's slices 7–11 found in the plan, relayed by the planning session with a recommendation for each:
(1) §7.1 builds `streams` on the `nick` identity, while §22.3 puts nick with accounts at M4; (2) `/admin/ops` needs
`Admin_Ops`, which only Admin holds, and nick gives only User, so nobody could open ops in `streams`; (3) §17.1 says
off-LAN visitors to a nick witness "can read but not post", but D35's table gives a Guest no `Chat_Read`.

| Item | Alex said | What it means for the plan |
|---|---|---|
| (1) nick at M2 | "Go with the recommended options." | **Build `features/accounts/identity_nick` in M2**: a signed nickname cookie with role User, granted by `ACCOUNTS_NICK_FROM=lan` to clients in `LAN_CIDRS`. The rest of `accounts` (sessions, passwords, TOTP, `identity_accounts`) stays at M4. |
| (2) ops in `streams` | (the same) | **`ACCOUNTS_NICK_ADMIN_CIDRS`**, empty by default: nick gives Admin to clients in it, so `/admin/ops` opens in `streams` for them. The e2e suite sets it to loopback; on apollo Alex may set his PC's address. |
| (3) off-LAN visitors | (the same) | **D35's role table stands**: an off-LAN visitor is a Guest, with no `Chat_Read`. Chat shows them a "chat is open on the LAN" notice instead of the rooms, and §17.1 says so in place of "can read but not post". |

## Round 8 (2026-10-26)

CI's first run on the restated budgets, relayed by the planning session with two options: (a) gate the idle budget on
the dev PC only, CI reporting; (b) push the diagnostic drill alone and decide after its run.

| Item | Alex said | What it means for the plan |
|---|---|---|
| Where the idle budget is gated | "Go with option A." | **(a).** The dev PC's drills gate idle memory on both legs, measured at the 16 loops the budget states, as the binary budget is gated on Windows. CI's Linux runner (4 vCPUs, about 5 MB above the dev PC's Linux at 4 loops: skeleton 12.2 MB against 7.0) prints its idle RSS with its anon/file/shmem makeup and the kernel's hugepage mode, and doesn't fail on it. |

## Round 7 (2026-10-26)

The M1 budgets the drills and CI's first run measured over (§18.4), relayed by the planning session with two options:
(a) restate them, (b) keep them and cut.

| Item | Alex said | What it means for the plan |
|---|---|---|
| Binary size and idle memory | "Pick a" | **(a).** Binary budgets are in MiB, the reading CI's size check already used: `skeleton` ≤ 2.75 MiB holds (2,881,536 B at M1's end). `minimal` is raised to ≤ 1.5 MiB (1.25 MiB at M1: the M1 platform and the 230 KB social card). Idle memory is ≤ 6 MB + 0.4 MB per event loop, 12.4 MB at the default 16 loops (12.2 MB measured on Linux, 11.3 MB working set on Windows). The drills read the same figures. None of (b)'s cuts (the social card's re-encode, SQLite OMITs, the JSON CLI) are taken. |

## Round 6 (2026-10-26)

The M1 parity gate's one remaining miss, relayed by the planning session with three options: (a) a documented
exception at the measured level, (b) fewer sort indexes (D36), (c) a different `:memory:` mode (Q6).

| Item | Alex said | What it means for the plan |
|---|---|---|
| Linux `write@mem` | "Go ahead with your recommendations." | **(a), the recommendation.** The cell, already gated against HEAD by Q6, passes at a median of 0.93 of HEAD instead of 0.97: a `perf-floor` line in `tests/parity-waivers.txt`, read by `load-tests/lib/parity.mjs`; the other two rules (no round below 0.85, p99 within 1.10×) stand. The diagnosis is in `docs/perf/PARITY.md`: the server's CPU per write equals HEAD's, and the gap is the writer task's hop under a closed-loop client. The five sort indexes stay (D36). |
