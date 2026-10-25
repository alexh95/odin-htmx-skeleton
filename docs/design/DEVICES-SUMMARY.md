# Home devices: roles in the plan (summary)

A public-safe summary of the device discussion with Alex on 2026-10-25, for the main session to fold into the plan.
It names device classes and roles only. Models, addresses, services and measurements are in the git-ignored
`docs/private/DEVICES.md` and `docs/private/APOLLO.md`; site values use the placeholders of `docs/private/SITE.md`
(two new ones are listed at the end).

Status: **Decided** means Alex said yes; **Proposed** means Alex has not objected, to confirm at the milestone;
**Open** means Alex is undecided; **No role** means none.

## Roles

| Device | Role | Status | When |
|---|---|---|---|
| apollo, the home server | Houston's stack as planned; **the bot's llama.cpp server on its spare GPU** (`<APOLLO_GPU>`); video sources on its spare disk | GPU: Decided | M3; bot M7 |
| The dev PC | as in §18.5 and §20.5; its 16 GB GPU runs bigger models for occasional bot smoke tests, never as Houston's always-on backend | Decided | M0– |
| A Raspberry Pi 4 (4 GB), Alex's own | **the terminal-console target** (64-bit Pi OS, wired); host for a USB camera | Decided | M11 |
| A Raspberry Pi 3B+ | an uptime watcher of apollo from off the box; a second terminal device for multi-device tests; LAN DNS only as a fallback | Proposed | M3, M11 |
| A Raspberry Pi 3B | a TV dashboard (kiosk browser on Houston's Today page), or a radio receiver (below) | Proposed | after M6 |
| A Raspberry Pi Zero W | none: ARMv6 and 32-bit only, so it can't run the linux_arm64 `term-agent` | No role | — |
| An ESP32 board with a 2.8" touch screen | a notification and presence panel on a device feed | Proposed (new feature) | after M6 |
| An ESP32-S3 camera board | a camera source | Proposed (new feature) | after M9 |
| A second camera board without USB | a second camera source later (needs a separate programmer) | Parked | — |
| Two ESP32-S3 boards with small OLEDs | status tiles on the device feed, or spares | Proposed, optional | after M6 |
| A USB action camera | on the Pi 4 through ffmpeg, for cameras or live video | Proposed (new feature) | after M9 |
| A 64 GB workstation laptop | not in the pipeline; optional agent-safe Linux sandbox or CPU trials of larger MoE models | Open | — |
| A gaming laptop with a 6 GB GPU | a Windows test client and a second load generator; the bot's fallback only if apollo's GPU route fails | Proposed, optional | M3 |
| A large Android tablet | the touch and tablet test client; an occasional docked dashboard | Proposed | M4– |
| Two old Android phones | the oldest-browser test device; IP cameras or kiosks if wanted | Proposed | M6– |
| A handheld Linux gaming PC | a test client with a gamepad, for spark games embedded in Houston | Proposed | M10 |
| A standalone VR headset | a test client for Houston's pages and for WebXR games inside Houston's game embed | Proposed | M10 |
| A spare Wi-Fi 6 router that runs OpenWrt | later, a fenced network for cameras and microcontrollers, and maybe WireGuard into the LAN (Q9) | Open | — |
| An old 802.11n router | none (a spare gigabit switch at most) | No role | — |
| Two handheld VHF/UHF radios | a receive-only radio feed idea (below); transmitting waits for Alex's amateur licence | Open | — |

**The pipeline needs none of the optional devices.** M0–M12 run on the dev PC (builds, both gate legs, transcodes,
`promote.ps1`, k6), GitHub CI and apollo. Two-host load runs stay dev PC → apollo: apollo's CPU saturates long before
the dev PC does, so a second load generator adds nothing to a pass rule.

## Facts that change the plan

- **§14.3: the bot has a host.** llama.cpp's official Vulkan server image on `<APOLLO_GPU>`, in a separate compose
  project that Alex owns (agents never restart it), published on one LAN port with an API key, which the plan's
  `BOT_LLAMA_KEY_FILE` already carries. It fits a current 4–8B instruct model at Q4 (about 2.5–5 GB) with about 8k of
  context; est. 40–60 tokens/s, to be measured with `llama-bench` at M7. Cost to the box: about one CPU thread and
  the GPU's power only while a reply is being written. `BOT_LLAMA_URL` becomes `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`.
- **§20.3, D41: the uplink is not a binding stage-2 trigger.** The home uplink is `<HOME_UPLINK>`, so public video
  from home is plausible at family scale before apollo's CPU or disks bind; Q26's CDN becomes optional.
- **§20.3, §20.7, M3: split DNS is decided: public records with apollo's LAN address** (Alex, 2026-10-26). The M3
  step becomes seven DNS-only `A` records, one per apollo name, pointing at `<APOLLO_LAN_IP>`. Each overrides the
  public wildcard for its name; every resolver gets the same answer, secure DNS included; outside the LAN the names
  lead nowhere, which is what stages 1a and 1b mean. Alex accepted the private address appearing in public DNS. At M12
  the records for the names that go public are deleted, so the wildcard applies again (inside the LAN those names then
  hairpin through the router unless a LAN DNS is added: a stage-2 question). Why not the alternatives: the ISP router
  forwards the LAN's DNS and passes private-address answers, but its static host table fails for these names (with a
  test entry, added and removed with Alex's go, it served its own address next to the wildcard's alias, and resolvers
  that follow the alias, systemd-resolved for one, reached the public address); a Pi as the LAN DNS would miss
  devices on secure DNS and adds a device to keep alive; hosts files don't reach the family. k6 `hosts` overrides are
  no longer needed on the LAN.
- **S0.12, X31: `<NPM_UPSTREAM_ADDR>` is the gateway of the stack's own Docker network**, not NPM's container address
  (measured on apollo). Docker masquerades traffic from another bridge, or from the host, to that gateway, while LAN
  clients that connect directly keep their own address. Trusting the gateway therefore trusts every container on
  apollo that reaches the published port, not NPM alone. The narrower alternative, NPM on the stack's network by
  container name, contradicts §20.4's "never a container name". The main session decides.
- **§2.2, §20.1: apollo's NPM is older than the version the plan models** (the exact version is in `SITE.md`), and its
  `worker_connections` is still the default 512. The `e2e-proxy` job either models apollo's version, or Alex updates
  NPM before M3.
- **§16.7: `:8120` is free** (2026-10-25; recheck at M3), and the host kernel allows io_uring, so the staged seccomp
  profile is still what's needed.
- **§16: the terminal target is a Pi 4**, and a Pi 3B+ can be the second device for multi-device tests. A Pi Zero
  class board can't run the agent.
- **§15.3: WebXR games in Houston's iframe** need `allow="xr-spatial-tracking; fullscreen; gamepad"` on the embed, and
  a spec, if the VR headset is to play them inside Houston.
- **§19, D22: an old phone is the oldest-browser device.** Whether htmx 4 runs on its browser is UNVERIFIED; the plain
  links, forms and SSE of D22's core flows are what it should still get.

## Feature ideas the devices open

Optional, each Alex's choice; none is in the plan.

| Idea | Devices | Fit |
|---|---|---|
| **A device feed and registry**: `/admin/devices`, generalising `/admin/term`'s device tokens; a plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML | ESP32 touch panel, OLED tiles | reuses the term tokens and the hub; a non-HTML route family, so it needs a line against the philosophy |
| **Cameras** (`cams`): Houston pulls each camera's MJPEG once and fans it out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS; snapshots on Today; LAN-only and members-only first | ESP32-S3 camera, old phones, the USB camera on the Pi | shows off the multipart transport the starter already has; microcontroller cameras serve only one or two clients, so the fan-out is the point |
| **Live video**: the USB camera → Pi → ffmpeg's hardware H.264 encoder → a sliding live HLS playlist under `/media` | Pi 4, USB camera | a small step from M9's VOD HLS; ffmpeg on the Pi is a new ledger line (outside every image, so the GPL rule holds) |
| **Wall and TV dashboard**: a kiosk view of Today, signed in by a device token | Pi 3B on a TV, old phones, the tablet | reuses Today and the device token |
| **WebXR in the game embed** | VR headset | one `allow` attribute and a spec |
| **Radio feed**: a Pi decodes APRS packets (Direwolf, or a radio with a built-in KISS TNC) and an agent posts them to a hub topic; after a licence, the licensee's own messages out under a licensee-only, audited permission (relaying other members' messages over the air is third-party traffic, which CEPT rules restrict) | Pi 3B, radios | the agent pattern again, speaking KISS |
| **Mesh bridge**: a Houston room ↔ a licence-free LoRa mesh (Meshtastic, 868 MHz), where any member may send | a LoRa node on a Pi | the agent pattern again; text only |
| **WireGuard into the LAN** for the LAN-only pages from outside (Q9) | the OpenWrt router, or a container on apollo | gives Q9's existing answer a home |

## Alex's steps per device

| When | Device | Step |
|---|---|---|
| M3 | the DNS provider | the seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, before the first LAN deploy |
| M12 | the DNS provider | delete the records of the names that go public, so the wildcard applies again |
| M7 | apollo | create the llama.cpp compose project (Vulkan image pinned to a build, the render device, an API key file, `cpus: 1.0`), put a model on the spare disk; check the power supply's rating for sustained GPU load |
| M11 | Pi 4 | bring it home, flash 64-bit Pi OS Lite, wire it, reserve its address, then §16.7's steps |
| any | spare router | nothing until a camera or microcontroller feature is chosen; then OpenWrt and a fenced network |

## New placeholders for SITE.md

| Placeholder | Meaning |
|---|---|
| `<APOLLO_GPU>` | apollo's spare GPU, the bot's host |
| `<HOME_UPLINK>` | the home uplink's speed |
| `<LLAMA_PORT>` | the LAN port of the llama.cpp server on apollo |

Their values are in `docs/private/APOLLO.md` and `docs/private/DEVICES.md`.
