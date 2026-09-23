# brag-output

A 24.5-second launch short for the skeleton, made with [`/brag`](https://github.com/latent-spaces/brag)
(a Claude Code skill) on top of [Hyperframes](https://github.com/heygen-com/hyperframes) 0.8.66.

**This directory is not part of the app.** It lives on its own branch (`brag-local`) and stays off
`master`: nothing here is built, tested, embedded or deployed. The app's dependency rules
(`CLAUDE.md` → "Dependencies — the line we hold") don't apply to it. It is dev-time media tooling,
in the same category as `e2e/` and `load-tests/`.

```
brag.mp4              the short: 1920x1080, 60 fps, 24.5 s, ~9 MB, -16.6 LUFS
brag.jpg              the poster (the hook at 2.8 s), also baked in as frame 0 of the mp4
share-copy.txt        the caption
brag-plan.md          the creative plan, storyboard and honesty notes
composition-brief.md  the Hyperframes handoff brief, as built
composition/          the Hyperframes project that renders brag.mp4
capture/              the recorder that filmed the live site for it
```

## What's in it: "watch the wire"

Every frame of UI is **real footage of the live site**, https://odin-htmx.alexh95.com (Fly `fra`
behind Cloudflare). It was filmed on 2026-09-23 in headless Chrome at 3x device scale, with
read-only actions only: no creates, edits or deletes. Two continuous takes:

1. the dashboard paints and counts up → hx-boost to *Data & CRUD* → click *Ada Lovelace* → the drawer
2. *Forms* → type `grace@hopper` → the server says no → `.dev` → *Looks good.* → the theme picker
   re-skins the same page on the music's beat

A small wire log records what each interaction cost. The byte counts are the response bodies
Chrome received, read over CDP:

| interaction | request | response body |
|---|---|---|
| boosted page navigation | `GET /data` | 25,638 B (the whole page) |
| open a contact | `GET /contacts/1` | 6,468 B |
| validate as you type (bad) | `POST /validate/email` | 69 B |
| validate as you type (good) | `POST /validate/email` | 43 B |
| re-skin the app | none | 0 B, because `app.js` sets `data-style` on `<html>` |

The receipts are properties of the repo or of its own load tests: 3,060 lines of Odin
(`app/src/**/*.odin`), 169 lines of JS (`app/static/app.js`), and 27,959 req/s from
`load-tests/RESULTS.md` → "Two-host" → `search` (k6 on a separate machine, 1 GbE, i3-7100 home
server; a real network, not loopback). "3 MB" is rounded on purpose. The binary measured
3,218,432 B in a Linux build of this commit and ~2.6 MB on Windows, while production builds with
`-o:speed`, which wasn't measured here.

The cursor is not in the footage. The composition draws it at 60 fps from the logged mouse path,
so it stays smooth through the camera moves. The five re-skins were **filmed on the beat**: the
recorder scheduled each click at `T0 + n × 60/109.96 s`, and the edit puts them on the track's
beat grid within ±20 ms.

## Re-rendering

Needs Node 22+, FFmpeg, and a Chrome that Hyperframes can drive (`npx hyperframes doctor`).

```sh
cd composition
npm run check                                   # the gate: 0 errors, 0 warnings, 31/31 WCAG AA
npx hyperframes render --fps 60 --quality delivery --output ../brag.raw.mp4
```

Then bake the poster into frame 0 and normalise loudness. The raw mix lands at about -22 LUFS;
+6 dB through a limiter gives -16.6 LUFS integrated and a -1.9 dBFS true peak:

```sh
cd ..
ffmpeg -y -ss 2.8 -i brag.raw.mp4 -frames:v 1 -q:v 2 brag.jpg
ffmpeg -y -i brag.raw.mp4 -i brag.jpg \
  -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" -map "[v]" -map 0:a \
  -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  -af "volume=6dB,alimiter=limit=0.7:attack=3:release=60:level=disabled" \
  -c:a aac -b:a 192k -movflags +faststart brag.mp4
```

## Re-filming

The footage goes stale when the UI changes. To re-shoot it:

```sh
cd capture
npm install
node take1.mjs out/take1 && node take2.mjs out/take2   # films the live site (edit BASE in lib.mjs for a local server)
node export-data.mjs ../composition/assets/capture-data.js
cp out/take1/clip.mp4 ../composition/assets/footage/take1.mp4
cp out/take2/clip.mp4 ../composition/assets/footage/take2.mp4
```

`take2.mjs` checks its own work: it confirms the picker opened, that every chip was clickable and
applied its style, and that the picker closed. If any check fails it prints `PROBLEMS:`, so re-run
it. `export-data.mjs` maps footage time to composition time (`OFFSETS`). If a new take drifts,
retune `OFFSETS.take2` so the first re-skin still lands on 13.11 s. The keystroke and click SFX
times in `composition/index.html` come from the same export.

`lib.mjs` hard-codes the Windows Chrome path (`CHROME`).

## Found while filming

On the live site, a click that lands while an htmx swap is running gets swallowed. The app turns
on view transitions globally (`<meta name="htmx-config" content='{"transitions":true}'>`), and
Chrome hit-tests to `<html>` while one is running. After typing in the email field, the first
click on the theme picker (the field's blur fires a validation swap) never opened it. `take2.mjs`
presses Tab first to keep the take clean. The app bug itself is left for a separate fix.

## Third-party assets

`composition/assets/` carries files this repo did not author. They are vendored so the render is
reproducible offline:

| Asset | Source | Licence |
|---|---|---|
| `music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` | "Happy Beats / Business Moves vol. 12" by Sascha Ende, [ende.app](https://ende.app/en), bundled with `/brag` | [CC BY 4.0](https://ende.app/en/license): use, share and adapt, commercial use allowed. Credited here |
| `sfx/impact/*`, `sfx/interface/*`, `sfx/ui/*` | [Kenney](https://kenney.nl/), bundled with `/brag` | CC0 |
| `sfx/keyboard/*` | [Keyboard Soundpack #1](https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes) by unicae_games | CC0 |
| `fonts/inter-var-latin.woff2` | [Inter](https://rsms.me/inter/) | SIL OFL 1.1 (`fonts/OFL-inter.txt`) |
| `fonts/jetbrains-mono-var-latin.woff2` | [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | SIL OFL 1.1 (`fonts/OFL-jetbrains-mono.txt`) |
| `vendor/gsap.min.js` | [GSAP](https://gsap.com/) 3.14.2 | GSAP standard licence |
| `footage/*`, `ui/forms-arcade.jpg` | this project's own live site | the repo's zlib licence |
