# Brag Plan: odin-htmx-skeleton

## What is this app?
A starter skeleton for server-rendered websites: an Odin backend writes the HTML, HTMX swaps
the fragments, SQLite holds the data — and the whole thing, assets included, ships as one
3.2 MB binary with no npm, no bundler and no build step.

## The angle
No pitch, just receipts. Every claim in this video is a number measured from the running app
on screen: the binary size, the line counts, the dependency count, the response time, the
theme matrix. The joke, such as it is, is how small the numbers are.

## Hook (first 2-3 seconds)
A cursor on a black terminal types `odin build src`, and the answer lands hard:
`bin/demo.bin — 3.2 MB`. That is the entire website. One file.

## Key moments (the middle)
- The real dashboard snaps in from the built binary — stat cards, sparklines, live counts.
- The working app: the contacts table, then the detail drawer sliding in over it — one
  request, one fragment of server-rendered HTML.
- The theme sweep: the *same* dashboard HTML re-skinned through Modern, Skeuo, Terminal,
  Brutalist, Editorial and Arcade, one per beat. Nothing in the markup changed.
- The receipts row counting up: 3,060 lines of Odin, 169 lines of JS, 3 dependencies, 19 KB.

## Outro / punchline
The wordmark, then the line the README ends on: **Clone it. Rename it. Build your thing.**

## User flow worth showing
Entry → the dashboard served by the binary. Key action → click a contact row in the Data &
CRUD table; the drawer swaps in from the server. Result → the detail panel with activity,
engagement meter and edit/delete, plus a toast confirming the round trip. Secondary flow:
type into the email field on /forms and watch it validate inline as you type.

## Tone
- Preset: polished
- Creative direction: an engineering-craft film — quiet confidence, real UI, real numbers
- Interpretation: restrained typography and slow, deliberate reveals everywhere except the
  theme sweep, which is the one place the film is allowed to move fast. No hype words, no
  "streamline your workflow", no abstract motion graphics. The product does the talking.

## Format: landscape — 1920x1080
## Duration: 21s

## Visual identity (from the project)
- Background: `#0b0d17` (`--bg`), surfaces `#151a2c` / `#1b2138`
- Accent: `#7c5cff` violet → `#5b8cff` indigo → `#22d3ee` cyan (`--grad`, 135deg)
- Text: `#eef1fb` (`--text`), muted `#9aa3c4`, faint `#6b769e`
- Display font: system sans (`ui-sans-serif, system-ui, Inter`) — the app's `--font`
- Body/mono font: `ui-monospace, "JetBrains Mono", Menlo` — the app's `--mono`, used for
  every number and terminal line so the receipts read as measurements
- Strongest visual element: the theme matrix — one document, 6 styles × 23 schemes

## Share copy (draft)
A whole website in one 3.2 MB binary: Odin renders the HTML, HTMX swaps it, SQLite stores it.
3,060 lines of Odin, 169 lines of JS, three dependencies, a 19 KB page.

## Audio direction
- Role: sparse professional accents over a low, warm bed
- Music: restrained upbeat/technical bed; quiet under the hook, present under the sweep
- Music treatment: fade in under the terminal line, hold low through the UI scenes, let it
  carry the theme sweep, fade out under the outro card
- Music cue guidance: bundled track cue preset if one exists, otherwise detect cues at
  composition time; target one strong cue at the theme-sweep start (~12.5s) and one at the
  receipts row (~17s); the six theme cards ride the beat grid, one per beat
- Audio-reactive treatment: none to subtle — at most a touch of presence on the sweep
- SFX posture: sparse and motion-matched — key ticks on the typed terminal line, one soft
  latch when the drawer lands, one quiet tick per theme card, one dry hit on the wordmark
- Audio-coupled moments: the typed command, the drawer landing, the six-card theme sweep,
  the number count-up
- Restraint rule: no whooshes, no risers, no stingers under the numbers. If a sound is not
  matched to something moving on screen, it does not go in.

## Storyboard

### Scene 1 — The build — 3.2s
Black (`#0b0d17`). Centred mono line types out: `$ odin build src`. A beat, then the result
prints beneath it in the accent gradient: `bin/demo.bin   3.2 MB`, with `one binary` in muted
grey under it. Nothing else on screen.
Sequential/interaction: yes — the command types character by character, then the result line
prints as one block after a ~0.3s pause.
Audio intent: quiet and precise; the film starts small.
Audio-coupled idea: subtle key ticks on the typed characters; one soft mono hit on the result.
Music: barely there, fading in.
Transition mood: clean → Scene 2

### Scene 2 — The thing it built — 4.0s
The real dashboard screenshot (`theme-modern-midnight.png`) rises into frame and settles with
a slow, small scale-down. A single line sits over the top edge: **A server-rendered web stack
in one binary** — the app's own H1, held long enough to read. Muted sub-line: `Odin renders the
HTML · HTMX swaps it · SQLite stores it`.
Sequential/interaction: none — one settled reveal.
Audio intent: the bed opens up; confidence, not fanfare.
Audio-coupled idea: none.
Music: low bed, present.
Transition mood: soft → Scene 3

### Scene 3 — The app working — 5.3s
The contacts table (`data.png`) holds, then the detail drawer (`data-drawer.png`) slides in
from the right and latches. Caption, mono, lower-left: `one click → one request → one fragment
of HTML`. Then a fast cut to the live-validation moment (`forms-invalid.png` → `forms-valid.png`)
with the caption `validated as you type — on the server`.
Sequential/interaction: yes — simulated row click, drawer slide-in from the right, then the
email field flipping from invalid to valid.
Audio intent: mechanical satisfaction; small, dry, precise.
Audio-coupled idea: soft latch as the drawer lands; a quiet tick on the validation flip.
Music: bed continues, slight lift.
Transition mood: clean → Scene 4

### Scene 4 — Same HTML, six skins — 4.8s
The showstopper. The same dashboard cycles through six themes, one per beat: Modern ·
Skeuo · Terminal · Brutalist · Editorial · Arcade. Each card lands with its style name in the
corner. On the last one the grid pulls back to show them together and the line lands:
**Same HTML. 6 styles × 23 schemes.**
Sequential/interaction: yes — six full-frame theme cards on the beat grid, then a pull-back to
the set. Style names are 1-2 words, so beat spacing is legible; the summary line holds ~1.4s.
Audio intent: the one place the film moves; each swap is felt.
Audio-coupled idea: one quiet tick per theme card, aligned to the beat grid.
Music: strongest cue of the track lands on the first swap.
Transition mood: clean → Scene 5

### Scene 5 — Receipts — 3.7s
Back to black. Four mono figures count up on one row, arriving left to right: `3,060` lines of
Odin · `169` lines of JS · `3` dependencies · `19 KB` of HTML. They hold together, then fall
away to the wordmark **odin·htmx** in the accent gradient, with `Clone it. Rename it. Build your
thing.` beneath and `github.com/alexh95/odin-htmx-skeleton` in faint mono.
Sequential/interaction: yes — the four figures count up and arrive one by one, then hold as a
set for ~1s before the outro card.
Audio intent: settle and close; the last number is the last beat.
Audio-coupled idea: a quiet tick per figure arrival; one dry hit on the wordmark.
Music: fades out under the wordmark.
Transition mood: soft → end

**Music mood for this video:** upbeat but restrained — technical, warm, not corporate
**Audio summary:** A quiet typed opening, a low bed under the working app, the track's
strongest cue carrying the six-theme sweep, and a clean fade under the closing numbers.
