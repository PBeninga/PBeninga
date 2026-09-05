# Ascendant

A progression-fantasy roguelike played in Spider solitaire.

Clearing a whole board of **K→A runs** is an advancement. Advance and you take
a boon — but the next rank deals *one more sequence than the last*, and every
one of them has to go into the core. Ember is a 52-card board. Sovereign is a
117-card, four-suit board. The boons you take are the only thing that closes
that gap.

No dependencies, no build step. Open `index.html` in a browser and play.

```
npm test          # 63 rule tests (node:test, no deps)
npm run build     # inline everything into dist/index.html
npm run serve     # http://localhost:8000

npm run test:browser   # end-to-end checks in Chromium, desktop + 4 devices
                       # (needs `npm i -D playwright`; skips cleanly without it)
```

---

## The loop

**Clear the whole board → advance → take a boon → a bigger board.**

A rank is a complete game of solitaire, not a quota: every sequence in the
deck has to be bound before you advance. Finishing the first K→A of a rank is
progress, not a level-up. Each rank then deals **one more sequence than the
last**, and all of them must go.

| Rank | Sequences to clear | Cards | Suits (Adept) |
|---|---|---|---|
| I **Ember** | 4 | 52 | 1 |
| II **Iron** | 5 | 65 | 1 |
| III **Silver** | 6 | 78 | 2 |
| IV **Gold** | 7 | 91 | 2 |
| V **Radiant** | 8 | 104 | 3 |
| VI **Sovereign** | 9 | 117 | 4 |
| — **Transcendence** | *you win* | — | — |

Five advancements means **five boons** in a full run, and by the last rank
you are playing a bigger, four-suit board than standard Spider deals.

Three difficulties change the starting deck and the suit ramp: **Novice**
(3 sequences up to 8, suits 1‑1‑1‑2‑2‑2), **Adept** (4 up to 9,
suits 1‑1‑2‑2‑3‑4), **Merciless** (4 up to 9, suits 1‑2‑2‑4‑4‑4).

## Solitaire rules

Standard Spider, with two additions.

- Build **down by rank** onto any card; suit is irrelevant while stacking.
- Lift a group only when it is a **descending run of a single suit**.
- Empty columns accept anything, and the stock deals one card to every column,
  empty ones included. The stock is drawn as **one card back per remaining
  deal**, so how many rows are still to come is something you read off the
  board rather than count. Spider forbids dealing while a column stands empty; that
  rule is dropped here, because a rank only ends once the board is clear, so
  every rune you seal would otherwise strand the stock.
- A **K→A run of one suit** at the foot of a column binds itself as a rune and
  goes into the core.
- **Wildstones** (✦) are wild: they adopt whatever rank and suit the run needs
  at their position, including inside a bound rune.
- **Vault slots** hold one card each, off the board.

## Playing

The screen is laid out the way a solitaire app is: a stat row at the top
(rank mark, **Rank / Runes / Moves**, power), the stock band
beneath it holding your techniques on the left and the deal fan on the right,
the tableau, and a toolbar of **Menu · Boons · Deal · Hint · Undo** across the
bottom. The status line floats just above the toolbar and costs no board
height when it has nothing to say.

Behind the tableau sits **the core**: a speck of light at the first deal that
grows with everything the run has bound, until by the last rank it is a glow
across most of the board. It burns the colour of the rank you are on — ember,
iron, silver, gold, radiant, sovereign — and when a rank ends it **detonates**,
throwing a shockwave across the board and coming back in the next rank's
colour. The advancement panel waits for that, because covering it would throw
away the one moment the run visibly changes. Binding a rune sends its thirteen cards down into it — bleaching white on the way, coming apart into dust, and absorbed.

**Tap a card and it goes** — it slides to its new column over half a second
rather than teleporting. **Dealing** throws the new row out of the stock one
card at a time, about 40ms apart, so you can see where it lands. A tap plays it straight to whichever column builds
the longest sequence — the same ranking the hint carousel uses, so a tap is
always the move a hint would recommend for that card. Drag instead when you
want a say in the destination, or to park a card in a reserve cell.

Cards you cannot lift yet — face-up but pinned under a run that has to move
first — are **dimmed**, so the board shows at a glance what is actually in
play.

The scoring is deliberately literal: *how long is the run this creates?*
Landing on a matching suit beats landing on a stranger, because it actually
extends the run; a card that completes a K→A rune outranks everything,
because that run is thirteen long. Only after run length do ties break on
flipping a face-down card, emptying a column, and finally on not wasting an
empty column.

**Hint** at the bottom walks the moves worth making, one a second — a
translucent copy of the cards drifts to exactly where it would land, source and
destination lit, and the dock counts `Showing hint 3/8`. It loops until you do
anything at all, then gets out of the way.

It only offers moves that are actually worth something, in this order:

1. **moves that bind a rune** — worth splitting a run for, so these come first
2. **moves that carry a whole run**, never breaking one up to no purpose
3. failing both, **moves into an empty column**
4. failing that, **deal another row** — the stock pulses instead of a card flying
5. failing that, **the run is over**

That last rung is also the game-over test: a rank ends when every card is
bound, or when the chain runs out. A vault slot that would uncover something
still counts as a way out, so it never ends a run by surprise.

`Space` deals · `U` or `Ctrl/⌘+Z` undoes · `H` toggles hints · `Esc` stops them.

Every screen carries a **build stamp** in the bottom-right corner (and in the
dock beside the seed), so a stale cached page is obvious without opening
devtools. `npm run build` stamps a content hash; running from `src/` reads
`dev`.

## The two boons

Every advancement offers the same two, and both repeat, so the only question a
run ever asks is how to split five picks between them.

| | | |
|---|---|---|
| ✦ **Wildstone** | +2 wildstones per deal | Answers to whatever rank and suit a sequence needs, bound runes included |
| ❖ **Vault Slot** | +1 vault slot | Holds a single card off the board, for as long as you need it out of the way |

They solve different problems. Wildstones fix the board you were dealt — a gap
in a sequence stops mattering. Slots fix the board you have made — somewhere to
put the card that is in the way. Wildstones compound (each deal carries them
all); slots are a standing allowance you spend and reclaim.

Wildstones are dealt face down like any other card, so buying them is a bet on
finding them.

## Layout

```
index.html        page shell
src/rng.js        seeded mulberry32 — a seed reproduces a whole run
src/cards.js      card model, run validation, wild-card gap filling
src/paths.js      the four paths and the breakthrough offer
src/engine.js     ranks, boons, stock, undo, move ranking, suggestions — no DOM
src/ui.js         rendering, drag and drop, overlays — no rules
src/style.css     ink-wash dark theme
build.js          inlines the above into dist/index.html, stamped with a hash
test/*.test.js    node:test suites for cards and engine
test/browser.mjs  Chromium end-to-end checks across desktop and four devices
```

The engine never touches the DOM and the UI never encodes a rule, so the whole
rule set is testable headlessly — which is what `test/` does.

## Balance

Requiring a **cleared board** per rank, rather than a quota of sequences, made
this a substantially harder game. Measured with a scripted greedy bot (no
lookahead, random boon choices, never touches reserve cells or charges), over
60 runs per difficulty:

| | clears Ember | avg rank reached | ascended |
|---|---|---|---|
| Novice | 35% | 1.5 | 0/60 |
| Adept | 43% | 1.5 | 0/60 |
| Merciless | 43% | 1.5 | 0/60 |

Cutting twelve boons down to two barely moved these, which is the least
interesting result possible and worth saying plainly: the bot picks randomly
and never touches a reserve cell, so it was never using the boons it lost.
Adept and Merciless also sit on top of each other, though the suit ramp is
supposed to separate them — runs end before the extra suits arrive. Both are
arguments that the numbers describe the bot more than the game.

(Measured after the stock stopped being blocked by empty columns, which lifted
every figure a little.) The bot is much weaker than a person — a one-suit board
is very winnable by hand — so read these as a floor, not a forecast. But the
shape is real: under the old quota the same bot reached rank 3–4, and it now
stalls at 1–2.

Two things follow, and both are yours to call:

- **Transcendence is close to unreachable.** Adept Sovereign is a 117-card,
  four-suit board where all nine sequences must go — a harder deal than
  standard four-suit Spider, which strong players win a few percent of the
  time. Five boons help, but not that much.
- **Ember is a real commitment** rather than a tutorial: a full 52-card board
  before you see a single boon.

If either bites, the knobs are `DIFFICULTIES` (`startSets` and the `suits`
ramp) and `rankConfig()` in `src/engine.js`. Dropping to four ranks, or holding
Adept at two suits until Radiant, would both help a lot.

Known open questions:

- A full Adept run is 39 sequences across six ranks, and Sovereign is a harder
  board than standard four-suit Spider. Six ranks may want to be four.
- With two upgrades and five picks, a run has only six possible builds. That is
  a clean decision but a shallow one; it may want a third option.
- A tap has no way to reach a reserve cell; that is drag-only on purpose, but
  it may want a gesture of its own.
- Wildstones are invisible until flipped, so their value is felt rather than
  seen. Dealing them face up would read better but leak information.
