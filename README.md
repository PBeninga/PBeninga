# Nine Meridians 九脈

A cultivation roguelike played in Spider solitaire.

Sealing a complete **K→A run of one suit** is a cultivation breakthrough. Break
through and you choose a boon — but the next realm demands *one more sequence
than the last*. Realm 1 asks for one. Realm 6 asks for six. The paths you walk
are the only thing that closes that gap.

No dependencies, no build step. Open `index.html` in a browser and play.

```
npm test          # 41 rule tests (node:test, no deps)
npm run build     # inline everything into dist/index.html
npm run serve     # http://localhost:8000

npm run test:browser   # end-to-end checks in Chromium, desktop + 4 devices
                       # (needs `npm i -D playwright`; skips cleanly without it)
```

---

## The loop

**Realm → seal the quota → breakthrough → choose a path → a bigger tableau.**

| Realm | 境界 | Meridians demanded | Suits (Adept) |
|---|---|---|---|
| 1 | 練氣 Qi Condensation | 1 | 1 |
| 2 | 築基 Foundation Establishment | 2 | 1 |
| 3 | 結丹 Core Formation | 3 | 2 |
| 4 | 元嬰 Nascent Soul | 4 | 2 |
| 5 | 化神 Spirit Severing | 5 | 3 |
| 6 | 問道 Dao Seeking | 6 | 4 |
| — | 飛昇 Immortal Ascension | *you win* | — |

Each realm deals a fresh tableau of `demanded + 3` full A–K sets, so the deck
grows with the demand and you always have a few sets of slack. Five
breakthroughs means **five boons out of twelve** in a full run — the choices
are what make one climb differ from the next.

Three difficulties change the suit ramp and the slack: **Novice** (suits
1‑1‑1‑2‑2‑2, four spare sets), **Adept** (1‑1‑2‑2‑3‑4, three), **Immortal**
(1‑2‑2‑4‑4‑4, two).

## Solitaire rules

Standard Spider, with two additions.

- Build **down by rank** onto any card; suit is irrelevant while stacking.
- Lift a group only when it is a **descending run of a single suit**.
- Empty columns accept anything. The stock deals one card to every column, and
  only when no column stands empty.
- A **K→A run of one suit** at the foot of a column seals itself as a meridian
  and leaves play.
- **Chaos talismans** (☯) are wild: they adopt whatever rank and suit the run
  needs at their position, including inside a sealed meridian.
- **Reserve cells** hold one card each, outside the tableau.

## Playing

**Tap a card and it goes.** A tap plays it straight to whichever column builds
the longest sequence — the same ranking the hint carousel uses, so a tap is
always the move a hint would recommend for that card. Drag instead when you
want a say in the destination, or to park a card in a reserve cell.

The scoring is deliberately literal: *how long is the run this creates?*
Landing on a matching suit beats landing on a stranger, because it actually
extends the run; a card that completes a K→A meridian outranks everything,
because that run is thirteen long. Only after run length do ties break on
flipping a face-down card, emptying a column, and finally on not wasting an
empty column.

**Hint** at the bottom walks every move the position offers, one a second, best
first — a translucent copy of the cards drifts to exactly where it would land,
with the source and destination lit, and the dock counts `Showing hint 3/8`.
It loops until you do anything at all, at which point it gets out of the way.
Deduplication (the best lift per source-and-destination pair, one empty column
per source) keeps the list to a median of seven moves.

`Space` deals · `U` or `Ctrl/⌘+Z` undoes · `H` toggles hints · `Esc` stops them.

## The four paths

Each breakthrough offers the next unclaimed tier of three of the four paths.
Tiers are taken in order and are permanent for the run.

| | I | II | III |
|---|---|---|---|
| **靈符 Talismans** | +2 wilds per deal | +2 more, always face up | +2 more; awaken a card into a wild, once per realm |
| **斬道 Severance** | one fewer suit in every deal | change a card's suit, twice per realm | one fewer suit again; +1 transmutation |
| **虛步 Void** | +1 reserve cell | place any card on any card, twice per realm | +1 cell, +2 void steps, and mixed-suit runs move as groups |
| **開脈 Expansion** | +1 column | +1 column; each realm starts with one empty | +1 column; deal from the stock even with empty columns |

The paths pull against each other. Expansion III lets you deal over empty
columns — which matters precisely because Expansion II hands you an empty
column every realm and the base rule forbids dealing while one exists.

## On phones

Ten columns on a 390px screen is the hard constraint, so the phone layout is
built around it rather than against it.

- Cards shrink to fit all ten columns — never a sideways scroll — and below
  54px they drop the centre pip so the corner rank can grow into the space.
  The exposed sliver of a stacked card grows to match, so a buried rank stays
  readable.
- The board claims every touch gesture over it (`touch-action: none`), so a
  drag is never stolen by the page trying to scroll. A dragged stack floats
  above the fingertip instead of hiding under it, and the drop lands where the
  cards are, not where the finger is.
- A tap plays the card immediately, which is the whole interaction on a phone —
  no pick-up-then-place, no double-tap, nothing to mis-aim. A cancelled gesture
  (an incoming call, a system swipe) puts the cards back rather than leaving
  them floating.
- The HUD collapses to two short rows; boons fold into one chip that opens the
  full list. Hint and Undo sit in a bottom dock under the thumbs, and every
  control stays at least 40px tall.
- Landscape gets nearly double the card size and a single-line HUD.
- Overlays are laid out three ways — full cards on desktop, compact rows in
  portrait, three abreast in landscape — because at 342px tall a stacked offer
  pushed the third choice off screen where nobody would find it.

`test/browser.mjs` asserts all of this on iPhone portrait and landscape,
Pixel 7 and iPad Mini: no overflow, real touch drags, tap targets, and every
overlay fitting its viewport without scrolling.

## Layout

```
index.html        page shell
src/rng.js        seeded mulberry32 — a seed reproduces a whole run
src/cards.js      card model, run validation, wild-card gap filling
src/paths.js      the four paths and the breakthrough offer
src/engine.js     realms, boons, stock, undo, move ranking, deadlock — no DOM
src/ui.js         rendering, drag and drop, overlays — no rules
src/style.css     ink-wash dark theme
build.js          inlines the above into dist/index.html
test/*.test.js    node:test suites for cards and engine
test/browser.mjs  Chromium end-to-end checks across desktop and four devices
```

The engine never touches the DOM and the UI never encodes a rule, so the whole
rule set is testable headlessly — which is what `test/` does.

## Balance

Tuned by eye, then sanity-checked with a scripted greedy bot
(no lookahead, random boon choices, never uses reserve cells or charges).
It clears realm 1 about 85% of the time on Novice and stalls around realm 3–4.
A human using the techniques should get considerably further; nobody has
ascended yet. Treat the difficulty tables as a first pass — the knobs are
`DIFFICULTIES` and `realmConfig()` in `src/engine.js`.

Known open questions:

- Six realms is a long run (21 meridians). It may want to be four.
- Fortune, the filler boon, is nearly unreachable: paths only run out of tiers
  after ten picks and a run offers five.
- Sealing a meridian has no animation yet, just a toast.
- A tap has no way to reach a reserve cell; that is drag-only on purpose, but
  it may want a gesture of its own.
