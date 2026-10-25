# The starter's planning docs

This folder plans the next step for Alex's **odin-htmx-skeleton**: turning it into **odin-htmx-starter**, a superset
of the skeleton with every htmx 4 extension, _hyperscript, features you can pick one by one, and a large showcase
app (Houston). The repo is the renamed skeleton, so until M1 restructures it the code at the root is still the
skeleton's. The skeleton's own docs (`USE_CASES.md`, `DATA.md`, `DATA_IMPL.md`, `STRIP.md`) sit next to these.

Start with **[PLAN.md](PLAN.md)**. §1 summarises it on one screen, §22 holds the milestones and the questions only
Alex can answer, and the M0 spike records are in [spikes/](spikes/).

## Committed docs

| Path | What it is |
|---|---|
| [BRIEF.md](BRIEF.md) | Alex's request, as given (2026-10-25) |
| [PLAN.md](PLAN.md) | The plan: 22 sections |
| [design/DECISIONS.md](design/DECISIONS.md) | Source of truth: decisions D1–D45 (ADR style) and questions Q1–Q33 |
| [design/ANSWERS.md](design/ANSWERS.md) | Alex's answers to the plan's questions (rounds 1–4), as given, with how the plan reads each |
| [design/RESOLUTIONS.md](design/RESOLUTIONS.md) | How the lead resolved the last open items (X1–X43) |
| [design/LEAN-COMPOSITION.md](design/LEAN-COMPOSITION.md) | The no-DI composition mechanism for ANSWERS #1, which round 3 chose ("LC") |
| [design/DEVICES-SUMMARY.md](design/DEVICES-SUMMARY.md) | The home devices' roles in the plan (device classes only), from the device discussion with Alex (2026-10-25 and 2026-10-26) |
| [design/SETTLED.md](design/SETTLED.md) | Working assumptions (S1–S22) that experiments settled before the design round |
| [spikes/](spikes/) | M0's decision records, `S0.<n>.md`: each spike's criterion, result and decision (PLAN §22.2) |

## Local-only docs (git-ignored)

The repo is public, so these stay on the workstation (the root `.gitignore`; ANSWERS F4, F5). The committed docs
still cite them in place ("08 §3", "RF §11.2"); the citations are for agents working in this checkout.

| Path | What it is | Why it stays local |
|---|---|---|
| `docs/private/SITE.md` | The real site values behind the public docs' placeholders (`<APOLLO_LAN_IP>`, `<APOLLO_CPU>`, `<APOLLO_SERVICES>`, `<WORKSPACE>` …), and where agents look them up | It names the LAN address, apollo's hardware and the services it runs, the SSH alias and user, and host and local paths |
| `docs/private/APOLLO.md`, `docs/private/DEVICES.md` | The device inventory behind `design/DEVICES-SUMMARY.md`: models, addresses, services and measurements | It names the home network's devices, addresses and hardware |
| `docs/research/` | `00-digest.md` (condensed research: summaries, facts with sources, risks, unverified items), notes 01–13 (skeleton, audit, streams, htmx 4, hyperscript, spark, features, hosting, toolchain, repo, CSP, data, operability) and note 14 (the lean composition's prototypes) | The notes record LAN and host details as measured; DECISIONS.md and PLAN.md carry what the design needs from them |
| `docs/design/proposal-*.md` | The three competing designs (risk-first, product-first, composition-first) | Superseded by DECISIONS.md, and they name LAN and host details |
| `docs/design/OUTLINE.md` | How PLAN.md was cut into sections for the writers | A working file for the writing round |

`SK/<path>:<line>` citations resolve against tag v1.2.0 (709bc94): the read-only reference clone the planning used,
`_ref/`, went at M0 (D1 step 5).

How it was made: research agents read the skeleton, odin-http, spark and the htmx and _hyperscript sources, ran
experiments (prototypes and measurements, kept in the session scratchpad) and wrote notes 01–09. A critic found the
gaps, and four more agents filled them (notes 10–13). Three architects then proposed designs, three judges scored
them, and a synthesizer merged the best into DECISIONS.md. Writers and fact-checkers turned that into PLAN.md, and an
editor and a final critic checked it against the brief.
