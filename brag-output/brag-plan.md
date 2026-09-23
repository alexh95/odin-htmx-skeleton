# Brag Plan: odin-htmx-skeleton

## What is this app?
A starter skeleton for server-rendered websites: Odin writes the HTML, HTMX swaps it in, SQLite
holds the data, and the whole thing, every asset included, ships as one ~3 MB binary. It runs
live at odin-htmx.alexh95.com.

## The angle
**Watch the wire.** The project's own thesis is "render HTML on the server… send it over the
wire" and "measure the wire, not the server". So the video does exactly that. Every interaction
is filmed on the **live production site**, and a small wire log records what each one actually
cost. The sizes shrink as the film goes on, and that countdown is the joke:

- click a contact → **6,468 bytes** of HTML
- type an email → **69 bytes** ("That doesn't look like an email.")
- finish typing → **43 bytes** ("Looks good.")
- re-skin the whole app → **0 bytes**. There is no request, because it's only CSS.

Every byte count is the real response body, measured from the live site on 2026-09-23.

## Hook (first 2-3 seconds)
The real dashboard paints and counts up inside a tilted browser window whose address bar reads
`odin-htmx.alexh95.com`. Next to it the claim lands in two beats: **This whole website** /
**is one 3 MB binary.**

## Key moments (the middle)
- **Click → HTML.** The cursor goes to *Data & CRUD*, and the page swaps without a reload. It
  clicks *Ada Lovelace* and the detail drawer slides in. The wire log adds `GET /contacts/1 · 200 ·
  6,468 B`, with a peek at the fragment (`<aside class="drawer drawer-detail">…`).
- **Type → HTML.** The camera moves in close on the email field. `grace@hopper` is typed and the
  server answers *That doesn't look like an email.*, shown with the whole 69-byte response
  beside it. Typing `.dev` turns it into *Looks good.* (43 bytes).
- **Re-skin → 0 bytes.** The cursor opens the real theme picker and clicks through Skeuo,
  Terminal, Brutalist, Editorial and Arcade on the beat. The same page keeps its typed values
  while its skin changes, and the wire log says `no request · 0 B`.
- **Receipts.** `3,060` lines of Odin, `169` lines of JavaScript, `27,959` req/s on a 2-core
  home server, plus the 3 dependencies.

## Outro / punchline
The `odin·htmx` wordmark, then the README's own line: **Clone it. Rename it. Build your thing.**
Under it: `odin-htmx.alexh95.com · github.com/alexh95/odin-htmx-skeleton`.

## User flow worth showing
Entry: the live dashboard, hx-boost navigating to *Data & CRUD*. Key action: open a contact,
which pulls in one server-rendered HTML fragment. Result: the detail drawer, then inline
server-side validation while typing, then the theme picker re-skinning the page with no
request at all. It is filmed as two continuous takes against production, using read-only
actions only (no creates, edits or deletes), so the footage is real and is the live site.

## Tone
- Preset: polished
- Creative direction: a quiet engineering demo: real UI in motion, and the bytes that moved it
- Interpretation: restrained type, deliberate camera moves, one persistent wire log in the
  corner. The only fast passage is the re-skin sweep. No hype words; the byte counts do the
  talking.

## Format: landscape — 1920x1080 (rendered at 60 fps: the camera moves and cursor stay smooth)
## Duration: 24.5s

## Visual identity (from the project)
- Background: `#0b0d17` (`--bg`); surfaces `#151a2c` / `#1b2138`; line `#2a3252`
- Accent: `#7c5cff` violet → `#5b8cff` indigo → `#22d3ee` cyan (`--grad`, 135deg)
- Text: `#eef1fb` (`--text`); muted `#9aa3c4`; faint `#6b769e`
- Display font: Inter (the app's `--font` stack names it). The UI footage itself renders in
  the system face, just as the site does on Windows.
- Mono font: JetBrains Mono (the app's `--mono` stack), for every number and wire-log line so
  they read as measurements
- Strongest visual element: the live app itself, above all the theme picker re-skinning a
  page in place, plus the brand mark from `app/static/favicon.svg`

## Share copy (draft)
A whole website in one ~3 MB binary: Odin renders the HTML, HTMX swaps it in, SQLite stores it.
A click costs 6 KB of HTML, live validation 69 bytes, a theme switch nothing at all —
odin-htmx.alexh95.com

## Audio direction
- Role: sparse professional accents over a steady, clean bed
- Music: `happy-beats-business-moves-vol-12` (109.96 BPM, "steady and clean"). It sits low for
  the first ~10s and fills out from ~11s, which suits a quiet open and a fuller sweep and
  receipts.
- Music treatment: fade in over the first second; let it lift with the track into the re-skin
  sweep; stay present under the receipts; fade out over the last second under the wordmark.
- Music cue guidance: bundled preset `cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`.
  Strong cues to target: **13.11s**, the first re-skin click (sweep clicks on the beat grid at
  13.11 / 13.66 / 14.20 / 14.75 / 15.29); **17.47s / 18.56s / 19.66s**, the three receipts on
  every other beat so each label gets a full read; **22.37s**, the CTA line under the wordmark.
- Audio-reactive treatment: subtle. The background glow breathes with bass energy. No
  waveform visuals.
- SFX posture: sparse and motion-matched. Only filmed actions and landed payloads get sound.
- Audio-coupled moments: the two recorded clicks, the drawer landing, per-key ticks on the
  typed email (taken from the recorded keystroke times), the validation flip, five
  switch-ticks on the re-skin beats, one tick per receipt, one bell on the wordmark.
- Restraint rule: no whooshes or risers. If nothing on screen moves, nothing sounds.

## Storyboard

### Scene 1 — Hook — 3.27s (0.00–3.27)
Dark `#0b0d17` with a violet glow. A browser window sits tilted on the right and bleeds off the
frame edge. Inside it is the real live dashboard, painting and counting up (filmed). On the
left the headline lands in two beats: **This whole website** / **is one 3 MB binary.**
Sequential/interaction: yes. The page paints for real, and the headline arrives line by line
(0.15s, 0.56s).
Audio intent: small and confident; the bed fades in.
Audio-coupled idea: one soft impact when line 2 lands.
Music: low, fading in.
Transition mood: clean → Scene 2 (the window swings square to camera and the headline slides out)

### Scene 2 — Click → HTML — 4.18s (3.27–7.45)
The browser fills the frame. Filmed and continuous with scene 1: the cursor clicks *Data &
CRUD* (boosted swap, no reload), then *Ada Lovelace*, and the detail drawer slides in. Caption:
**Click. The server answers in HTML.** The wire log appears bottom-left, adding `GET /data ·
25,638 B` and then `GET /contacts/1 · 6,468 B`, each with a one-line peek at the body. The camera
eases in toward the drawer.
Sequential/interaction: yes. Two real clicks, a real page swap, a real drawer.
Audio intent: tactile and dry.
Audio-coupled idea: a mouse click on each click; a soft drop as the drawer lands.
Music: low bed.
Transition mood: clean cut → Scene 3

### Scene 3 — Type → HTML — 3.90s (7.45–11.35)
A second continuous take, with the camera in close (2.1x) on the Forms email field. `grace@hopper`
is typed, and the server's message *That doesn't look like an email.* appears under the field. The
wire log (now bottom-right, over the page's empty column) adds `POST /validate/email · 69 B` with
the entire response body as its peek line. `.dev` is typed and it flips to *Looks good.* (**43 B**).
Caption: **Type. Validation runs on the server.**
Sequential/interaction: yes. Real typing, two real server responses.
Audio intent: precise, with small mechanical satisfaction.
Audio-coupled idea: per-key ticks from the recorded keystroke times; a soft tick on the error
and a light positive accent on *Looks good.*
Music: the bed starts to lift.
Transition mood: clean (the camera pulls back) → Scene 4

### Scene 4 — Re-skin → 0 bytes — 5.27s (11.35–16.62)
Same take, pulled back to the full browser. The cursor opens the real theme picker and clicks
Skeuo, Terminal, Brutalist, Editorial and Arcade, one per beat from 13.11s. The same page, with
the same typed values, re-skins each time. The wire log collapses to a chip in the lower-right
corner, clear of the form: `— no request · 0 B` / `<html data-style="…"> set in the browser`,
which follows each skin. The cursor closes the picker. Caption: **Re-skin. 6 styles, 23 schemes, 0
requests.**
Sequential/interaction: yes. Five real clicks on the beat grid.
Audio intent: the one place the film moves fast; each swap is felt.
Audio-coupled idea: a quiet switch tick on each re-skin.
Music: fullest so far; the 13.11 strong cue lands on the first re-skin.
Transition mood: soft → Scene 5

### Scene 5 — Receipts — 4.66s (16.62–21.28)
The Arcade-skinned browser recedes and blurs. Three measured figures arrive on every other beat
(17.47 / 18.56 / 19.66) and count up in mono: **3,060** lines of Odin · **169** lines of
JavaScript · **27,959** req/s on a 2-core home server (search, over LAN). At 20.19 a line
adds: **3 dependencies: HTMX · odin-http · SQLite**. The full set holds for at least 1s.
Sequential/interaction: yes. Three figures one by one, then a hold.
Audio intent: settled and certain.
Audio-coupled idea: one tick per figure.
Music: present.
Transition mood: soft → Scene 6

### Scene 6 — Outro — 3.22s (21.28–24.50)
The brand mark and the **odin·htmx** wordmark land (21.84). Then **Clone it. Rename it. Build your
thing.** (22.37, strong cue), then `odin-htmx.alexh95.com · github.com/alexh95/odin-htmx-skeleton`.
The music fades out under the hold.
Sequential/interaction: none beyond the three-step lockup.
Audio intent: close cleanly.
Audio-coupled idea: one bell on the wordmark.
Music: fade out.
Transition mood: soft → end

**Music mood for this video:** steady, clean, quietly upbeat. Technical, not corporate.
**Audio summary:** A low bed under a real product loading, dry clicks and key ticks on real
interactions, the track's lift carrying the on-beat re-skin, one tick per receipt, and a bell
and fade on the wordmark.

## Sources and honesty notes
- The footage is the live production site (Fly `fra` behind Cloudflare), filmed on 2026-09-23 in
  headless Chrome at 3x device scale, 1120×700 CSS viewport. Read-only actions only. The cursor
  is drawn in the composition from the logged mouse path, because the capture has none.
- Byte counts are raw HTML response bodies from the live site: `/contacts/1` 6,468 B,
  `/validate/email` 69 B (error) and 43 B (ok), boosted `/data` ~26.6 KB. The 0 B re-skin comes
  from `app.js` ("Pure presentation… No server round-trip").
- "3 MB binary" is rounded on purpose. A Linux build of this commit measured 3,218,432 B in an
  earlier session, and a local Windows build is ~2.6 MB. Production builds with `-o:speed`,
  which wasn't measured here, and the README says "~3 MB".
- 3,060 lines = `app/src/**/*.odin`; 169 lines = `app/static/app.js`.
- 27,959 req/s = `load-tests/RESULTS.md` → "Two-host" → `search` at 200 VUs: k6 on a separate
  machine over 1 GbE LAN to an Intel i3-7100 (2C/4T) home server. Real network, not loopback.
- "6 styles · 23 schemes": the picker has 7 + 3 + 4 + 3 + 3 + 3 = 23 schemes spread across 6
  styles. That is a sum, not 6 × 23.
- The on-screen data is the demo's seeded contacts (historical computer scientists at
  `@example.dev`). No real user data.
