# Hyperframes Composition Brief: odin-htmx-skeleton

## Objective
Create a short launch-style brag video for the odin-htmx-skeleton — a starter skeleton for
server-rendered websites built with Odin + HTMX + SQLite that ships as one binary.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 23s

## Source Material
- Project root: `/home/user/odin-htmx-skeleton`
- Primary files read: `README.md`, `PHILOSOPHY.md`, `CLAUDE.md`, `app/src/views/*.odin`,
  `app/src/views/brand.odin`, `app/static/app.css`, `app/static/app.js`, `app/prepare.sh`
- Product name: odin-htmx-skeleton (wordmark `odin·htmx`)
- Tagline / strongest claim: "A server-rendered web stack in one binary"
- Key UI moments to show: **real screenshots of the app built and run from this repo**
  (`app/bin/demo.bin`, served on localhost and captured headless at 2x) — not recreations:
  - `assets/ui/theme-modern-midnight.png` — the dashboard
  - `assets/ui/data.png` + `assets/ui/drawer-panel.png` — the contacts table and the detail
    drawer, used to simulate the click that swaps the drawer in
  - `assets/ui/email-invalid.png` → `assets/ui/email-valid.png` — the live server-side
    validation flipping from error to valid
  - five more theme captures of the *same* dashboard for the style sweep
- Copy that must appear verbatim:
  - `odin build src`
  - `bin/demo.bin` / `3.2 MB`
  - `Same HTML. 6 styles × 23 schemes.`
  - `Clone it. Rename it. Build your thing.`
  - `github.com/alexh95/odin-htmx-skeleton`
- Numbers are measured, not invented: 3,218,432-byte binary, 3,060 lines of Odin, 169 lines
  of JS, 3 runtime dependencies (HTMX, odin-http, SQLite), a 19,000-byte dashboard document.
  Every figure is a property of the app, not of the machine that measured it — a latency taken
  over loopback would not be.

## Creative Direction
- Tone preset: polished
- Creative direction: an engineering-craft film — quiet confidence, real UI, real numbers
- Interpretation: restrained type and deliberate reveals, except the theme sweep, which is
  the one place the film moves fast. Numbers in mono so they read as measurements.
- Angle: no pitch, just receipts. Every claim on screen is measured from the running app.
- Hook: a typed `odin build src`, then `bin/demo.bin — 3.2 MB`. That is the whole website.
- Outro / punchline: the wordmark, then "Clone it. Rename it. Build your thing."
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign — the app's own palette and wordmark only

## Visual Identity
- Background: `#0b0d17` (`--bg`); surfaces `#151a2c` / `#1b2138`; lines `#2a3252`
- Text: `#eef1fb` (`--text`); muted `#9aa3c4`; faint `#6b769e`
- Accent: `linear-gradient(135deg, #7c5cff, #5b8cff 55%, #22d3ee)` (`--grad`)
- Display font: Inter (shipped as `assets/fonts/inter-*.woff2`) — stands in for the app's
  `--font` system-sans stack
- Body/number font: JetBrains Mono (`assets/fonts/jbmono-*.woff2`) — the app's `--mono` role
- Visual references from the project: the browser-window framing, the `odin·htmx` wordmark
  with its accent dot, the violet→cyan gradient, the six theme styles

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. The build — 0.0–3.2s — `odin build src` types out; `bin/demo.bin  3.2 MB` lands.
2. The thing it built — 3.2–6.6s — the real dashboard in a browser window; caption
   `rendered by Odin · swapped by HTMX`.
3. The app working — 6.6–12.65s — the contacts table, a simulated row click, the detail
   drawer sliding in (`one request → one HTML fragment`); then the email field flipping from
   "That doesn't look like an email." to "Looks good." (`validated as you type — on the server`).
4. Same HTML, six skins — 12.65–17.5s — the same dashboard cut through Modern, Skeuo,
   Terminal, Brutalist, Editorial, Arcade on the beat grid, then
   `Same HTML. 6 styles × 23 schemes.`
5. Receipts — 17.5–23.0s — 3,060 / 169 / 3 / 19 KB count up, then the wordmark and
   `Clone it. Rename it. Build your thing.`

## Audio
- Audio role: sparse professional accents over a low, warm bed
- Audio arc: nearly silent under the typed opening, opens up on the dashboard, carries the
  theme sweep at its fullest, settles under the numbers and fades out on the wordmark
- Music: `assets/music/bed.mp3`
  (happy-beats-business-moves-vol-11-by-ende-dot-app, 114.84 BPM)
- Music treatment: volume automation lane — fade in to 0.22 under the terminal, up to 0.46
  on the dashboard cut, 0.62 through the sweep, back to 0.45 under the receipts, out by 23s
- Music cue guidance: bundled preset `cues/happy-beats-business-moves-vol-11-…json`.
  Strong cues used: **12.65s** (theme sweep starts) and **17.91s** (first receipt lands).
  Beat grid used: 12.65 / 13.18 / 13.70 / 14.22 / 14.76 / 15.28 for the six theme cuts, and
  17.91 / 18.44 / 18.96 / 19.49 for the four receipts.
- Audio-reactive treatment: subtle — the background glow's opacity and scale breathe with
  bass energy (`assets/audio-data.js`, bands 0–1), ±12%. No waveform or equalizer visuals.
- Audio-coupled moments:
  - Scene 1 typed command — per-character key ticks
  - Scene 1 result line — one soft impact
  - Scene 3 row click and drawer latch — simulated interaction
  - Scene 4 six theme cuts — beat-grid ticks
  - Scene 5 four count-ups and the wordmark — beat-grid ticks + one bell
- SFX selection guidance: low high-frequency-risk files only, since the ticks repeat; every
  sound matched to something moving on screen
- SFX analysis guidance: `skills/brag/assets/sfx/sfx-analysis.md` — picks taken from the
  "Safest General Picks" and "Lower-Risk Picks By Use Case" lists
- Exact SFX choice: `interface/click_003`, `interface/click_005`, `interface/drop_001`,
  `impact/impactSoft_medium_001`, `impact/impactSoft_medium_004`,
  `impact/impactBell_heavy_000`, `keyboard/keypress-0{03,07,11,15,19,23}`
- Audio files: copied into `brag-output/composition/assets/`

## Hyperframes Instructions
Built with the Hyperframes domain skills (`hyperframes-core`, `hyperframes-animation`,
`hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`). Single paused GSAP
timeline registered on `window.__timelines["brag"]`; all timing declared with `data-*`.
`npx hyperframes check` is the gate before render.
