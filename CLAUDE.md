# Ascendant

Spider solitaire played as a roguelike run. Zero dependencies; `build.js`
inlines every module into one self-contained HTML file.

- `npm test` — unit tests (engine, cards, ads, sound, records)
- `npm run test:browser` — builds, then drives the real page across five form
  factors. It boots the built bundle first: the shipped file is one scope, and
  can break in ways the module version cannot.

The engine holds the rules and touches no DOM; the UI draws and encodes no
rules. Keep it that way.

## Design rules (UI / pages / menus)

Aesthetic: a dark card table lit by embers. Serious, tactile,
slightly occult. Think letterpress and coal, not SaaS.

### Palette
- Base: near-black warm grays (#141210, #1e1a17) — never pure #000
- Ink/text: bone white (#e8e2d6), muted ash gray for secondary
- Accent: ember orange (#e2622b family), used sparingly — rank-ups,
  streaks, the active boon. One accent, no secondary accent color.
- Rank identity may shift accent warmth (Ember hot → Sovereign gold)
- BANNED: purple, blue-purple gradients, teal, neon anything

### Type
- Headings: a serif or blackletter-adjacent display face — something
  with edge. Never Inter, Roboto, or system-ui for display.
- Body/UI: one workhorse font max alongside it
- Numerals: tabular figures for scores, streaks, timers

### Layout & surfaces
- Flat or subtly textured surfaces; hairline borders over drop shadows
- Sharp or barely-rounded corners (≤4px). No pill buttons.
- Left-aligned text by default; center only card-table elements
- Density over airiness — this is a game screen, not a landing page

### BANNED (AI tells)
- Gradient backgrounds of any kind
- Glassmorphism / backdrop-blur cards
- Emoji as icons or decoration, ✨ especially
- Hero + three-column feature cards layout
- "Delightful" microcopy ("Oops!", "You're all set! 🎉")
- Rounded-square icon chips with pastel backgrounds

### Copy
- Every sentence must tell the player something they do not already have.
  If it restates, elaborates, or can be seen from the interface, delete it.
  Do not merge it into the sentence before: redundant information is still
  redundant when merged. "Build down by rank." is complete; "Build down by
  rank, regardless of suit." is not better, it is longer.
- Before shipping a string, remove its last sentence and check whether
  anything is lost. Usually nothing is.
- The log records events ("Dealt a row."); it does not narrate or comment.
- Buttons and the hint bar are labels, not sentences.
