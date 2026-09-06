# Ascendant

A progression-fantasy roguelike played in Spider solitaire.

Every card is a spade. Clearing a whole board of **K→A runs** is an
advancement — take a boon, and the next rank deals *one more sequence than the
last*, every one of which has to go into the core. Ember opens on a deck and a
half. Sovereign is a 143-card board. The boons you take are the only thing that
closes that gap.

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

| Rank | Sequences to clear | Cards |
|---|---|---|
| I **Ember** | 6 | 78 |
| II **Iron** | 7 | 91 |
| III **Silver** | 8 | 104 |
| IV **Gold** | 9 | 117 |
| V **Radiant** | 10 | 130 |
| VI **Sovereign** | 11 | 143 |
| — **Transcendence** | *you win* | — |

Five advancements means **five boons** in a full run — fifty-one sequences on
Adept. Silver is the classic two-deck single-suit Spider board; everything
before it is smaller and everything after is deeper.

With one suit, the deck's depth is the only dial left, so it is the one the
difficulties turn: **Novice** opens on 5 sequences, **Adept** on 6, **Merciless**
on 8. Each adds one per rank from there.

## Solitaire rules

Standard Spider, with two additions.

- Build **down by rank** onto any card. Every card is a spade, so any
  descending run lifts as a group — the punishment for a mixed stack is gone,
  and what is left is the puzzle of what to bury and when.
- Empty columns accept anything, and the stock deals one card to every column,
  empty ones included. The stock is drawn as **one card back per remaining
  deal**, so how many rows are still to come is something you read off the
  board rather than count. Spider forbids dealing while a column stands empty; that
  rule is dropped here, because a rank only ends once the board is clear, so
  every rune you seal would otherwise strand the stock.
- A **K→A run** at the foot of a column binds itself as a rune and goes into
  the core.
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
A card that completes a K→A rune outranks everything, because that run is
thirteen long. Only after run length do ties break on
flipping a face-down card, emptying a column, and finally on not wasting an
empty column.

**Hint** at the bottom walks the moves worth making, one a second — a
translucent copy of the cards drifts to exactly where it would land, source and
destination lit, and the dock counts `Showing hint 3/8`. It loops until you do
anything at all, then gets out of the way.

It only offers moves that are actually worth something, in this order:

1. **moves that bind a rune** — worth splitting a run for, so these come first
2. **moves that carry a whole run**, never breaking one up to no purpose
3. failing both, **moves into an empty column** — but only while something is
   still face down for that to uncover, and always the whole run rather than
   the card on top of it
4. failing that, **deal another row** — the stock pulses instead of a card flying
5. failing that, an empty column after all, or **the run is over**

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
| ✦ **Wildstone** | +2 wildcards in hand each rank | Drop one on any column; it fixes to one below what it lands on, and takes a card out of the game |
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

Measured with the same greedy bot as before (no lookahead, random boon choices,
never parks a card in a slot), 60 runs per difficulty:

| | clears Ember | avg rank reached | transcended |
|---|---|---|---|
| Novice | 38% | 1.5 | 0/60 |
| Adept | 17% | 1.2 | 0/60 |
| Merciless | 7% | 1.1 | 0/60 |

Half a deck off the opening moved the bot a long way: Novice went from 8% to
38%, Adept from 7% to 17%. That is worth reading carefully. It does not say the
game is now three times easier for a person — it says **the bot's clear rate is
mostly a function of board size**, which is what a greedy heuristic with no
lookahead would be. Single-suit Spider is the forgiving variant, and a person
clears the standard board most of the time; the bot cannot clear a smaller one
half the time.

So the table still measures the bot more than the game. It is useful for one
thing only: comparing two builds of *this* game against each other. Getting a
number that means something about play needs a solver with real lookahead or a
person, and the second is cheaper.

Two things follow, and both are yours to call:

- **Sovereign is a 143-card board** where all eleven sequences must go.
  Single-suit Spider is a game strong players win most of the time, but this
  is still nearly half again the standard deal.
- **Ember is a 78-card board** before you see a single boon — smaller than the
  standard Spider deal, but still a whole game.

If either bites, the knobs are `DIFFICULTIES` (`startSets` and the `suits`
ramp) and `rankConfig()` in `src/engine.js`. Dropping to four ranks, or a shallower
opening deck, would both help.

Known open questions:

- A full Adept run is 51 sequences across six ranks. Six ranks may want to be
  four.
- With two upgrades and five picks, a run has only six possible builds. That is
  a clean decision but a shallow one; it may want a third option.
- A tap has no way to reach a reserve cell; that is drag-only on purpose, but
  it may want a gesture of its own.
- Nothing tells you what a wildcard is about to cost, or what rank it will
  take, before you spend it. The deck's tooltip explains the order; the board
  shows neither the card that would go nor the value that would be taken.
