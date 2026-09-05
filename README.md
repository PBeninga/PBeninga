# Nine Meridians 九脈

A cultivation roguelike played in Spider solitaire.

Clearing a whole board of **K→A runs** is a cultivation breakthrough. Break
through and you choose a boon — but the next realm deals *one more sequence
than the last*, and every one of them has to go. Realm 1 is a 52-card game.
Realm 6 is a 117-card, four-suit game. The paths you walk are the only thing
that closes that gap.

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

**Clear the whole board → break through → choose a path → a bigger board.**

A realm is a complete game of solitaire, not a quota: every sequence in the
deck has to be sealed before you break through. Finishing the first K→A of a
realm is progress, not a level-up. Each realm then deals **one more sequence
than the last**, and all of them must go.

| Realm | 境界 | Sequences to clear | Cards | Suits (Adept) |
|---|---|---|---|---|
| 1 | 練氣 Qi Condensation | 4 | 52 | 1 |
| 2 | 築基 Foundation Establishment | 5 | 65 | 1 |
| 3 | 結丹 Core Formation | 6 | 78 | 2 |
| 4 | 元嬰 Nascent Soul | 7 | 91 | 2 |
| 5 | 化神 Spirit Severing | 8 | 104 | 3 |
| 6 | 問道 Dao Seeking | 9 | 117 | 4 |
| — | 飛昇 Immortal Ascension | *you win* | — | — |

Five breakthroughs means **five boons out of twelve** in a full run — the
choices are what make one climb differ from the next, and by the last realm
you are playing a bigger, four-suit board than standard Spider deals.

Three difficulties change the starting deck and the suit ramp: **Novice**
(3 sequences up to 8, suits 1‑1‑1‑2‑2‑2), **Adept** (4 up to 9,
suits 1‑1‑2‑2‑3‑4), **Immortal** (4 up to 9, suits 1‑2‑2‑4‑4‑4).

## Solitaire rules

Standard Spider, with two additions.

- Build **down by rank** onto any card; suit is irrelevant while stacking.
- Lift a group only when it is a **descending run of a single suit**.
- Empty columns accept anything, and the stock deals one card to every column,
  empty ones included. The stock is drawn as **one card back per remaining
  deal**, so how many rows are still to come is something you read off the
  board rather than count. Spider forbids dealing while a column stands empty; that
  rule is dropped here, because a realm only ends once the board is clear, so
  every meridian you seal would otherwise strand the stock.
- A **K→A run of one suit** at the foot of a column seals itself as a meridian
  and leaves play.
- **Chaos talismans** (☯) are wild: they adopt whatever rank and suit the run
  needs at their position, including inside a sealed meridian.
- **Reserve cells** hold one card each, outside the tableau.

## Playing

**Tap a card and it goes** — it slides to its new column over half a second
rather than teleporting. A tap plays it straight to whichever column builds
the longest sequence — the same ranking the hint carousel uses, so a tap is
always the move a hint would recommend for that card. Drag instead when you
want a say in the destination, or to park a card in a reserve cell.

Cards you cannot lift yet — face-up but pinned under a run that has to move
first — are **dimmed**, so the board shows at a glance what is actually in
play.

The scoring is deliberately literal: *how long is the run this creates?*
Landing on a matching suit beats landing on a stranger, because it actually
extends the run; a card that completes a K→A meridian outranks everything,
because that run is thirteen long. Only after run length do ties break on
flipping a face-down card, emptying a column, and finally on not wasting an
empty column.

**Hint** at the bottom walks the moves worth making, one a second — a
translucent copy of the cards drifts to exactly where it would land, source and
destination lit, and the dock counts `Showing hint 3/8`. It loops until you do
anything at all, then gets out of the way.

It only offers moves that are actually worth something, in this order:

1. **moves that seal a meridian** — worth splitting a run for, so these come first
2. **moves that carry a whole run**, never breaking one up to no purpose
3. failing both, **moves into an empty column**
4. failing that, **deal another row** — the stock pulses instead of a card flying
5. failing that, **the run is over**

That last rung is also the game-over test: a realm ends when every card is
sealed, or when the chain runs out. A charged technique or a reserve cell that
would uncover something still counts as a way out, so those never end a run by
surprise.

`Space` deals · `U` or `Ctrl/⌘+Z` undoes · `H` toggles hints · `Esc` stops them.

Every screen carries a **build stamp** in the bottom-right corner (and in the
dock beside the seed), so a stale cached page is obvious without opening
devtools. `npm run build` stamps a content hash; running from `src/` reads
`dev`.

## The four paths

Each breakthrough offers the next unclaimed tier of three of the four paths.
Tiers are taken in order and are permanent for the run.

| | I | II | III |
|---|---|---|---|
| **靈符 Talismans** | +2 wilds per deal | +2 more, always face up | +2 more; awaken a card into a wild, once per realm |
| **斬道 Severance** | one fewer suit in every deal | change a card's suit, twice per realm | one fewer suit again; +1 transmutation |
| **虛步 Void** | +1 reserve cell | place any card on any card, twice per realm | +1 cell, +2 void steps, and mixed-suit runs move as groups |
| **開脈 Expansion** | +1 column | +1 column; each realm starts with one empty | +1 column; the deal skips your empty columns, leaving them open |

An empty column is the most valuable thing on the board, and Expansion plays
both sides of that: II hands you one at the start of every realm, and III stops
the stock from filling the ones you have fought for.

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
  full list. The stock fan sits in its own band above the tableau, right-aligned,
  and shrinks with the screen. Hint and Undo sit in a bottom dock under the thumbs, and every
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
src/engine.js     realms, boons, stock, undo, move ranking, suggestions — no DOM
src/ui.js         rendering, drag and drop, overlays — no rules
src/style.css     ink-wash dark theme
build.js          inlines the above into dist/index.html, stamped with a hash
test/*.test.js    node:test suites for cards and engine
test/browser.mjs  Chromium end-to-end checks across desktop and four devices
```

The engine never touches the DOM and the UI never encodes a rule, so the whole
rule set is testable headlessly — which is what `test/` does.

## Balance

Requiring a **cleared board** per realm, rather than a quota of sequences, made
this a substantially harder game. Measured with a scripted greedy bot (no
lookahead, random boon choices, never touches reserve cells or charges), over
60 runs per difficulty:

| | clears realm 1 | avg realm reached | ascended |
|---|---|---|---|
| Novice | 35% | 1.5 | 0/60 |
| Adept | 43% | 1.6 | 0/60 |
| Immortal | 43% | 1.6 | 0/60 |

(Measured after the stock stopped being blocked by empty columns, which lifted
every figure a little.) The bot is much weaker than a person — a one-suit board
is very winnable by hand — so read these as a floor, not a forecast. But the
shape is real: under the old quota the same bot reached realm 3–4, and it now
stalls at 1–2.

Two things follow, and both are yours to call:

- **Ascension is close to unreachable.** Adept realm 6 is a 117-card,
  four-suit board where all nine sequences must go — a harder deal than
  standard four-suit Spider, which strong players win a few percent of the
  time. Five boons help, but not that much.
- **Realm 1 is now a real commitment** rather than a tutorial: a full 52-card
  game before you see a single upgrade.

If either bites, the knobs are `DIFFICULTIES` (`startSets` and the `suits`
ramp) and `realmConfig()` in `src/engine.js`. Dropping to four realms, or
holding Adept at two suits until realm 5, would both help a lot.

Known open questions:

- A full Adept run is 39 sequences across six realms, and realm 6 is a harder
  board than standard four-suit Spider. Six realms may want to be four.
- Fortune, the filler boon, is nearly unreachable: paths only run out of tiers
  after ten picks and a run offers five.
- Sealing a meridian has no animation yet, just a toast.
- A tap has no way to reach a reserve cell; that is drag-only on purpose, but
  it may want a gesture of its own.
