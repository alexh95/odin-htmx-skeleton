# brag-output

A 23-second launch short for the skeleton, made with [`/brag`](https://github.com/latent-spaces/brag)
(a Claude Code skill) on top of [Hyperframes](https://hyperframes.heygen.com/).

**This directory is not part of the app.** It lives on its own branch and is deliberately kept
off `master` — nothing here is built, tested, embedded, or deployed. The app's dependency rules
(`CLAUDE.md` → "Dependencies — the line we hold") don't apply: this is dev-time media tooling, in
the same category as `e2e/` and `load-tests/`.

```
brag.mp4              the short — 1920x1080, 23.0s, 30fps, ~7 MB
brag.jpg              the poster frame, also baked in as frame 0 of the mp4
brag-plan.md          the creative plan and beat-by-beat storyboard
composition-brief.md  the handoff brief (source material, tone, audio, beat grid)
share-copy.txt        the caption
composition/          the Hyperframes project that renders brag.mp4
```

## What's in it

Every frame of UI is a **real screenshot of this repo's binary**, not a recreation: `app/bin/demo.bin`
was built and served on `localhost:8080`, then captured headless at 2x. The numbers are measured,
not written: a 3,218,432-byte binary, 3,060 lines of Odin, 169 lines of JS, 3 runtime dependencies,
sub-millisecond time-to-first-byte.

The screenshots under `composition/assets/ui/` are the dashboard, the contacts table, the detail
drawer (cropped out of a drawer-open capture so it can slide in), the email field before and after
validation, and the same dashboard under five more theme styles.

## Re-rendering it

Needs Node 22+, FFmpeg, and a Chrome the renderer can drive (`npx hyperframes browser ensure`).

```sh
cd composition
npm run check     # lint + runtime + layout + motion + WCAG contrast — the gate
npm run render -- -o ../brag.mp4
npm run dev       # or: live preview in Hyperframes Studio
```

`check` must come back with **0 errors**. It currently reports five
`nested_structure_needs_subcomposition` warnings: the composition is authored monolithically
(one `index.html`) rather than split into sub-composition files. That's a Studio-ergonomics
preference, not a render problem — split the scenes out if you plan to edit it in Studio.

After a re-render, re-bake the poster so every player's idle thumbnail is the frame you chose
rather than the black first frame:

```sh
ffmpeg -y -ss 5.6 -i brag.mp4 -frames:v 1 -q:v 2 brag.jpg
ffmpeg -y -i brag.mp4 -i brag.jpg \
  -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" \
  -map "[v]" -map 0:a -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  -af "volume=4dB" -c:a aac -b:a 192k -movflags +faststart out.mp4 && mv out.mp4 brag.mp4
```

The `volume=4dB` is deliberate: the raw render lands at −21.3 LUFS, which is ~7 dB under what
social platforms expect. A flat gain gets it to −17.3 LUFS (true peak −1.4 dBFS) without
flattening the quiet-opening-to-loud-sweep arc that a `loudnorm` pass would squash.

## Re-capturing the screenshots

They came from the running app, so they go stale when the UI changes:

```sh
cd ../app && ./prepare.sh && odin build src -out:bin/demo.bin
DB_PATH=:memory: ./bin/demo.bin 8080
```

Then drive a headless browser over `/`, `/data`, `/forms` — setting `localStorage.style` /
`localStorage.scheme` before load to pick a theme — and crop the drawer and email-field regions
out of the full-page captures.

## Third-party assets — check before publishing

`composition/assets/` carries files this repo did not author. They are vendored here so the
render is reproducible offline, but the licences are **not** the repo's zlib licence:

| Asset | Source | Licence |
|---|---|---|
| `music/bed.mp3` | [ende.app](https://ende.app/en) "Happy Beats / Business Moves vol. 11", bundled with `/brag` | **not CC0** — check ende.app's terms before redistributing the file itself |
| `sfx/**` | [Kenney](https://kenney.nl/) + [Keyboard Soundpack #1](https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes) | CC0 |
| `fonts/inter-*.woff2` | [Inter](https://rsms.me/inter/) | SIL Open Font License 1.1 |
| `fonts/jbmono-*.woff2` | [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | SIL Open Font License 1.1 |
| `vendor/gsap.min.js` | [GSAP](https://gsap.com/) 3.14.2 | GSAP standard licence |

Using the music in the video is what `/brag` ships it for. Committing the raw `bed.mp3` into a
public repo is a separate act of redistribution — if that isn't clearly permitted, delete
`composition/assets/music/bed.mp3` and re-copy it from the skill when you re-render.
