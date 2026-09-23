# Hyperframes Composition Brief: odin-htmx-skeleton

## Objective
Create a short launch-style brag video for odin-htmx-skeleton. The video is built on real footage
of the live site: it shows what each interaction costs on the wire, not a mock-up of the UI.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080, 60 fps
- Duration: 24.5s

## Source Material
- Project root: `C:\Projects\www\odin-htmx-demo` (branch `brag-local`, from master `c75a477`)
- Primary files read: `README.md`, `PHILOSOPHY.md`, `app/src/views/brand.odin`, `app/src/routes.odin`,
  `app/src/views/views_pages.odin` (forms), `app/static/app.css` (tokens, picker), `app/static/app.js`
  (theme picker: "Pure presentation… No server round-trip"), `app/static/favicon.svg`,
  `load-tests/RESULTS.md`
- Product name: odin-htmx-skeleton (wordmark `odin·htmx`)
- Tagline / strongest claim: "A server-rendered web stack in one binary" (the app's own H1)
- Key UI moments, **filmed on https://odin-htmx.alexh95.com** in headless Chrome 153 at 3x DPR
  (1120×700 CSS viewport → 3360×2100 frames, CDP screencast). Read-only actions only:
  - take 1: the dashboard paints and counts up → hx-boost to *Data & CRUD* → *Ada Lovelace* → drawer
  - take 2: *Forms* → type `grace@hopper` → server error → `.dev` → *Looks good.* → Tab →
    theme picker → Skeuo / Terminal / Brutalist / Editorial / Arcade on the music's beat → close
- Copy that must appear verbatim:
  - `This whole website is one 3 MB binary.`
  - `Clone it. Rename it. Build your thing.` (the README's closing line)
  - `odin-htmx.alexh95.com` · `github.com/alexh95/odin-htmx-skeleton`
- Measured numbers, all taken from the recordings or the repo:
  - response bodies captured by Chrome: `/data` 25,638 B (boosted full page), `/contacts/1` 6,468 B,
    `/validate/email` 69 B (error) and 43 B (ok); re-skin = 0 requests
  - 3,060 lines of Odin (`app/src/**/*.odin`), 169 lines of JS (`app/static/app.js`)
  - 27,959 req/s: `load-tests/RESULTS.md`, two-host `search` @ 200 VUs (k6 → 1 GbE → i3-7100)
  - "3 MB" is rounded deliberately; see `brag-plan.md` → honesty notes

## Creative Direction
- Tone preset: polished
- Creative direction: a quiet engineering demo: real UI in motion, and the bytes that moved it
- Interpretation: restrained type, deliberate camera moves, one persistent wire log. The only fast
  passage is the on-beat re-skin.
- Angle: "watch the wire". Each filmed interaction logs the HTML that came back, and the sizes
  count down: 6,468 → 69 → 43 → 0 bytes.
- Hook: the live dashboard paints in a tilted browser; **This whole website / is one 3 MB binary.**
- Outro / punchline: `odin·htmx` lockup → **Clone it. Rename it. Build your thing.** → both URLs
- Avoid: generic SaaS language, abstract filler, restyling the product (the footage is untouched)

## Visual Identity
- Background: `#0b0d17`; surfaces `#151a2c`; line `#2a3252`
- Text: `#eef1fb`; muted `#aeb6d6`; faint `#8a93b8` (lifted from the app's `#9aa3c4`/`#6b769e` so
  small type clears WCAG AA over the video)
- Accent: `linear-gradient(135deg, #7c5cff, #5b8cff 55%, #22d3ee)`
- Display font: Inter (variable, local woff2), the family named in the app's `--font` stack
- Mono font: JetBrains Mono (variable, local woff2), from the app's `--mono` stack. Used for every
  number, URL and wire-log line.
- Visual references: the brand mark (`favicon.svg`), the app's violet/cyan glows, its browser-card
  depth

## Storyboard (as built)
1. Hook — 0.00–3.27 — tilted browser rises, dashboard paints; headline in two beats (0.15 / 0.56),
   gradient bar under "3 MB", kicker `running live at odin-htmx.alexh95.com` (1.64)
2. Click → HTML — 3.27–7.45 — camera squares up; nav click (3.89), boosted `/data` (4.06); Ada click
   (5.45), drawer (5.63); wire log bottom-left; slow push toward the drawer
3. Type → HTML — 7.45–11.35 — hard cut to a 2.1x close-up on the email field; keystrokes; error at
   9.39 (69 B), *Looks good.* at 10.78 (43 B); wire log bottom-right
4. Re-skin → 0 B — 11.35–16.62 — pull back; picker opens (12.06); re-skins visible at
   **13.12 / 13.67 / 14.20 / 14.73 / 15.29**. The beat grid is 13.11 / 13.66 / 14.20 / 14.75 / 15.29,
   so each lands within ±20 ms. The log collapses to a `no request · 0 B` chip.
5. Receipts — 16.62–21.28 — browser recedes and blurs; 3,060 / 169 / 27,959 on 17.47 / 18.56 / 19.66;
   dependencies line at 20.19
6. Outro — 21.28–24.5 — lockup 21.84 (bell), CTA 22.37, URLs 22.75, music out by 24.5

## Audio
- Audio role: sparse professional accents over a steady, clean bed
- Audio arc: fades in under the hook, lifts at ~11s into the re-skin, stays present through the
  receipts, fades out under the URLs
- Music: `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` (109.96 BPM)
- Music treatment: volume lane 0 → 0.34 (1.0s) → 0.36 (10.6s) → 0.44 (12.9s) → 0.44 (23.2s) → 0 (24.5s)
- Music cue guidance: bundled preset `cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`.
  Beat-locked: first re-skin 13.11 (strong); receipts on 17.47 / 18.56 / 19.66 (strong, every
  other beat); CTA 22.37 (strong). The re-skins were **filmed** on the beat. The take-2 recorder
  scheduled each chip click at T0 + n·60/109.96 s, and the composition offset puts T0's visible frame
  on 13.11.
- Audio-reactive treatment: subtle. Per-frame `tl.set` from `assets/audio-data.js`
  (`extract-audio-data.py`, 30 fps): bass drives the violet glow and low-mids the cyan glow. No
  visualiser graphics.
- Audio-coupled moments: recorded clicks → `ui/mouseclick1`; drawer landing → `interface/drop_002`;
  each recorded keystroke → one of 8 `keyboard/keypress-*.wav`; *Looks good.* → `interface/bong_001`;
  receipts → `impact/impactSoft_medium_001/004/002`; wordmark → `impact/impactBell_heavy_000`
- SFX analysis guidance: `skills/brag/assets/sfx/sfx-analysis.md`, low-HF-risk picks for everything
  repeated
- Audio files: copied into `composition/assets/`

## Hyperframes Implementation
- Hyperframes 0.8.66; GSAP 3.14.2 vendored locally (no render-time network)
- `index.html` (root, 24.5s) holds the persistent layers: background, browser + two `<video>` takes
  + arcade still, the cursor (replayed from the logged mouse path in page CSS px), captions + scrim,
  wire log + chip, and all audio
- Sub-compositions with scene-local timelines: `compositions/hook.html`, `receipts.html`,
  `outro.html`
- `assets/capture-data.js` is generated from the recorder's `capture.json` files
  (`../capture/export-data.mjs`); it carries every click, key, cursor sample, response and re-skin
  time in composition seconds
- Gate: `npx hyperframes check` → 0 errors, 0 warnings; 31/31 text checks pass WCAG AA
