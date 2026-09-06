// Game engine. Pure logic, no DOM: the UI reads `game.state` and calls methods.

import { makeRng, shuffle, randomSeed } from './rng.js';
import {
  SUITS, SEQUENCE_LENGTH, buildDeck, runInfo, canStackOn,
  completedRune, movableTail, resetCardIds, bumpCardIds, makeWild, KING, RANK_LABEL,
} from './cards.js';
import { offerBoons } from './paths.js';

// The ladder. Each rank is a whole board cleared, and the names run from a
// banked ember to something that no longer needs a name.
export const RANKS = [
  { name: 'Ember', mark: 'I' },
  { name: 'Iron', mark: 'II' },
  { name: 'Silver', mark: 'III' },
  { name: 'Gold', mark: 'IV' },
  { name: 'Radiant', mark: 'V' },
  { name: 'Sovereign', mark: 'VI' },
];
export const TRANSCENDENCE = { name: 'Transcendence', mark: '✧' };

// A rank is a whole game of solitaire: you must clear the entire tableau, not
// just a quota of it. `startSets` is how many A-K sequences the first rank
// deals; every rank after adds one more set to the deck, and all of them must
// be bound. That is what "one more sequence each time" means in practice.
//
// Every card is a spade. With suits gone, the deck's depth is the only dial
// left, so it is what the difficulties turn. Adept opens on a deck and a half
// and reaches the classic two-deck Spider board at its third rank.
export const DIFFICULTIES = {
  novice: { name: 'Novice', startSets: 5 },
  adept: { name: 'Adept', startSets: 6 },
  immortal: { name: 'Merciless', startSets: 8 },
};

export const BASE_COLUMNS = 10;
export const UNDOS_PER_RANK = 3;
// What a player may claw back out of a rank beyond the undos it grants.
// The caps are the game's, not the ad network's: a reward is worth taking
// and cannot be farmed into a rank that plays itself.
export const REPRIEVES_PER_RANK = 1;
export const EXTRA_UNDOS_PER_RANK = 3;
const MAX_UNDO_STACK = 60;

export class Game {
  constructor({ seed = randomSeed(), difficulty = 'adept' } = {}) {
    this.seed = String(seed).toUpperCase();
    this.difficulty = DIFFICULTIES[difficulty] ? difficulty : 'adept';
    this.rng = makeRng(this.seed);
    resetCardIds();
    this.undoStack = [];
    this.state = {
      phase: 'play',          // play | breakthrough | ascended | failed
      rank: 1,
      required: 1,
      runes: 0,               // bound at this rank
      totalRunes: 0,
      collected: [],          // {suit, rank} of every rune bound this run
      columns: [],
      reserve: [],
      stock: [],
      boons: {},              // upgrade key -> how many times taken
      wilds: 0,               // wildcards in hand, refreshed each rank
      conjured: 0,            // wildcards this rank that found nothing to eat
      reprieves: 0,           // second winds taken this rank
      extraUndos: 0,          // undos granted beyond the rank's own
      undosLeft: UNDOS_PER_RANK,
      moves: 0,
      offer: [],
      lastSealed: [],
      log: [],
    };
    this.dealRank(1);
  }

  // ---------------------------------------------------------------- config

  /** How many times an upgrade has been taken. */
  held(key) { return this.state.boons[key] || 0; }

  rankConfig(rank) {
    const diff = DIFFICULTIES[this.difficulty];
    const sets = diff.startSets + (rank - 1);
    return {
      required: sets,            // a rank ends when the board is clear
      sets,
      suitCount: 1,              // spades, all the way down
      columns: BASE_COLUMNS,
      // The deck is nothing but spades. Wildcards are held, not shuffled in,
      // so the deal is exactly sets x 13 and clears exactly.
      wilds: 0,
    };
  }

  reserveCells() { return this.held('cell'); }

  // ----------------------------------------------------------------- deal

  dealRank(rank) {
    const s = this.state;
    const cfg = this.rankConfig(rank);
    const deck = buildDeck(cfg, this.rng);

    const total = deck.length;
    const stockDeals = Math.max(2, Math.min(6, Math.floor((total - cfg.columns * 4) / cfg.columns)));
    const initialCount = total - stockDeals * cfg.columns;

    const columns = Array.from({ length: cfg.columns }, () => []);
    for (let i = 0; i < initialCount; i++) columns[i % cfg.columns].push(deck.pop());
    for (const col of columns) {
      for (let i = 0; i < col.length; i++) col[i].faceUp = col[i].wild ? col[i].faceUp : false;
      if (col.length) col[col.length - 1].faceUp = true;
    }

    s.rank = rank;
    s.required = cfg.required;
    s.runes = 0;
    s.columns = columns;
    s.stock = deck;
    s.reserve = Array.from({ length: this.reserveCells() }, () => null);
    s.wilds = this.held('talisman') * 2;
    s.conjured = 0;
    s.reprieves = 0;
    s.extraUndos = 0;
    s.undosLeft = UNDOS_PER_RANK;
    s.phase = 'play';
    s.offer = [];
    this.undoStack = [];
    this.log(`${RANKS[rank - 1].name}: bind ${cfg.required} rune${cfg.required > 1 ? 's' : ''}.`);
    this.settle();
  }

  log(text) {
    this.state.log.unshift(text);
    if (this.state.log.length > 40) this.state.log.length = 40;
  }

  // ---------------------------------------------------------------- undo

  snapshot() {
    return {
      state: structuredClone(this.state),
      rng: this.rng.state(),
    };
  }

  pushUndo() {
    this.undoStack.push(this.snapshot());
    if (this.undoStack.length > MAX_UNDO_STACK) this.undoStack.shift();
  }

  /**
   * Step back one move. What the board looked like is restored; what the
   * player has spent or been granted is not. An undo that rolled the ledger
   * back would refund itself, and -- once rewards can grant undos -- would let
   * the same one be earned over and over.
   */
  undo() {
    if (this.state.phase !== 'play') return false;
    if (!this.undoStack.length || this.state.undosLeft <= 0) return false;
    const snap = this.undoStack.pop();
    const ledger = {
      undosLeft: this.state.undosLeft - 1,
      extraUndos: this.state.extraUndos,
      reprieves: this.state.reprieves,
    };
    this.state = snap.state;
    this.rng.setState(snap.rng);
    Object.assign(this.state, ledger);
    return true;
  }

  // ------------------------------------------------------------- querying

  columnTail(colIndex) {
    return movableTail(this.state.columns[colIndex], { mixedSuit: false });
  }

  /** Can the player pick up `count` cards from the foot of column `i`? */
  canGrab(colIndex, count) {
    const col = this.state.columns[colIndex];
    if (count < 1 || count > col.length) return false;
    return count <= this.columnTail(colIndex);
  }

  /** Where can a grabbed run legally land? */
  canDrop(run, dest) {
    const s = this.state;
    if (dest.zone === 'reserve') {
      if (run.length !== 1) return false;
      return s.reserve[dest.index] === null;
    }
    const col = s.columns[dest.index];
    const target = col.length ? col[col.length - 1] : null;
    if (!target) return true;
    const info = runInfo(run, { sameSuit: true });
    if (!info.valid) return false;
    return canStackOn(info, run, target);
  }

  takeRun(from) {
    const s = this.state;
    if (from.zone === 'reserve') {
      const card = s.reserve[from.index];
      return card ? [card] : null;
    }
    const col = s.columns[from.index];
    const count = from.count || 1;
    if (count > col.length) return null;
    return col.slice(col.length - count);
  }

  /**
   * Move cards between tableau columns and reserve cells.
   * @returns {boolean} whether the move happened.
   */
  move(from, to) {
    const s = this.state;
    if (s.phase !== 'play') return false;
    if (from.zone === to.zone && from.index === to.index) return false;

    const run = this.takeRun(from);
    if (!run || !run.length) return false;
    if (from.zone === 'col' && !this.canGrab(from.index, run.length)) return false;
    if (run.some((c) => !c.faceUp)) return false;
    if (!this.canDrop(run, to)) return false;
    // Shuffling a whole column into an empty one achieves nothing.
    if (from.zone === 'col' && to.zone === 'col'
      && run.length === s.columns[from.index].length && s.columns[to.index].length === 0) return false;

    this.pushUndo();
    if (from.zone === 'reserve') s.reserve[from.index] = null;
    else s.columns[from.index].length -= run.length;

    if (to.zone === 'reserve') s.reserve[to.index] = run[0];
    else s.columns[to.index].push(...run);

    s.moves++;
    this.settle();
    return true;
  }

  /**
   * Deal one card onto every column, empty ones included. Spider forbids
   * dealing while a column stands empty; here a rank is only over once the
   * board is clear, so that rule would strand the stock every time a rune
   * was bound.
   */
  deal() {
    const s = this.state;
    if (!this.canDeal()) return false;
    this.pushUndo();
    for (let i = 0; i < s.columns.length; i++) {
      if (!s.stock.length) break;
      const card = s.stock.pop();
      card.faceUp = true;
      s.columns[i].push(card);
    }
    s.moves++;
    this.log('Another row falls.');
    this.settle();
    return true;
  }

  canDeal() {
    return this.state.phase === 'play' && this.state.stock.length > 0;
  }

  /** How many more rows the stock can deal -- the last one may be partial. */
  dealsLeft() {
    const cols = this.state.columns.length;
    return cols ? Math.ceil(this.state.stock.length / cols) : 0;
  }

  // ------------------------------------------------------------ wildcards

  /**
   * The face-down card nearest to being turned over, in whichever column has
   * the most of them -- so a wildcard's cost lands on the worst dig.
   */
  /**
   * The rank a wildcard would take on this column, or null if none is legal.
   * It becomes whatever the position asks for: one below the card it lands on,
   * or a King in an empty column. Nothing continues below an Ace, so a
   * wildcard cannot be dropped on one.
   */
  wildValue(index) {
    const col = this.state.columns[index];
    if (!col) return null;
    const beneath = col[col.length - 1];
    if (!beneath) return { rank: KING, suit: SUITS[0] };
    if (!beneath.faceUp) return null;
    const rank = beneath.rank - 1;
    if (rank < 1) return null;
    return { rank, suit: beneath.suit };
  }

  /**
   * Which copy of `rank` a wildcard becoming that rank would swallow, or null
   * if the board holds none -- in which case the wildcard comes free.
   *
   * It has to be that rank and nothing else. A board clears only while every
   * rank has exactly as many copies left as there are runes still to bind, so
   * a wildcard that arrives as a Six and pays with a Nine leaves seven Sixes
   * and five Nines: two runes that can never be finished. Taking the matching
   * rank keeps the count even and the deal exactly clearable.
   *
   * Order of preference: the undealt stock first -- taking the card furthest
   * from the top, so the shortfall lands in the last row dealt -- then a
   * face-down card out of the deepest dig, then the face-up copy with the
   * least stacked on it, then the reserve.
   */
  wildPayment(rank) {
    const s = this.state;

    for (let i = 0; i < s.stock.length; i++) {
      if (s.stock[i].rank === rank) return { cost: 'stock', index: i };
    }

    let dig = null;
    for (let i = 0; i < s.columns.length; i++) {
      const col = s.columns[i];
      let buried = 0;
      let found = -1;
      for (let k = 0; k < col.length; k++) {
        if (col[k].faceUp) continue;
        buried++;
        if (col[k].rank === rank) found = k;   // nearest to being turned over
      }
      if (found >= 0 && (!dig || buried > dig.buried)) {
        dig = { cost: 'hidden', column: i, index: found, buried };
      }
    }
    if (dig) return dig;

    let open = null;
    for (let i = 0; i < s.columns.length; i++) {
      const col = s.columns[i];
      for (let k = col.length - 1; k >= 0; k--) {
        if (!col[k].faceUp || col[k].rank !== rank) continue;
        const under = col.length - 1 - k;
        if (!open || under < open.under) open = { cost: 'faceup', column: i, index: k, under };
        break;
      }
    }
    if (open) return open;

    const slot = s.reserve.findIndex((c) => c && c.rank === rank);
    return slot >= 0 ? { cost: 'reserve', slot } : null;
  }

  /** What placing a wildcard on `to` would cost, or null if it cannot be paid. */
  wildCost(to) {
    const s = this.state;
    if (s.phase !== 'play' || s.wilds <= 0) return null;
    if (!to || to.zone !== 'col' || !s.columns[to.index]) return null;
    const value = this.wildValue(to.index);
    if (!value) return null;
    // No copy of that rank anywhere is a state a matched payment cannot
    // produce, so it means the deal is already short one. Conjure it rather
    // than refuse a placement the player has every reason to expect.
    const payment = this.wildPayment(value.rank) || { cost: 'free' };
    return { ...payment, value };
  }

  /**
   * Spend a held wildcard onto a column. It takes a rank of its own the moment
   * it lands -- one below whatever it now sits on, or a King in an empty
   * column -- and is an ordinary card from then on.
   *
   * Paying for it takes one card of that same rank out of the game, so the
   * deal stays exactly clearable however many wildcards are spent: the
   * wildcard is not a card gained, it is a card moved to where you need it.
   * An Ace has nothing below it, so a wildcard cannot be dropped on one --
   * that is the only refusal. If no copy of the rank is left to pay with the
   * wildcard is simply conjured, since a board short of a rank was already
   * one rune short of finishing.
   *
   * @returns {false|{cost:'stock'|'hidden'|'faceup'|'reserve'|'free', removed:?object, value:object}}
   */
  placeWild(to) {
    const s = this.state;
    const plan = this.wildCost(to);
    if (!plan) return false;

    this.pushUndo();
    let removed = null;
    if (plan.cost === 'free') s.conjured++;
    else if (plan.cost === 'stock') removed = s.stock.splice(plan.index, 1)[0];
    else if (plan.cost === 'reserve') { removed = s.reserve[plan.slot]; s.reserve[plan.slot] = null; }
    else removed = s.columns[plan.column].splice(plan.index, 1)[0];

    s.columns[to.index].push(makeWild(true, plan.value.rank, plan.value.suit));
    s.wilds--;
    s.moves++;
    const label = RANK_LABEL[plan.value.rank];
    this.log({
      stock: `A wildcard settles as ${label}, taking one out of the undealt stock.`,
      hidden: `A wildcard settles as ${label}, burning a face-down one away.`,
      faceup: `A wildcard settles as ${label}, swallowing the last one on the board.`,
      reserve: `A wildcard settles as ${label}, drawn out of the reserve.`,
      free: `A wildcard settles as ${label}. Nothing was left to pay with, so it comes free.`,
    }[plan.cost]);
    this.settle();
    return { cost: plan.cost, removed, value: plan.value };
  }

  // ---------------------------------------------------------- resolution

  /** Flip exposed cards, bind finished runes, then check win/loss. */
  settle() {
    const s = this.state;
    // What was bound this turn, so the interface can show it leaving.
    s.lastSealed = [];
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < s.columns.length; i++) {
        const col = s.columns[i];
        if (col.length && !col[col.length - 1].faceUp) {
          col[col.length - 1].faceUp = true;
          changed = true;
        }
        const done = completedRune(col);
        if (done) {
          col.length -= SEQUENCE_LENGTH;
          s.lastSealed.push({
            column: i,
            remaining: col.length,
            cards: done.cards.map((c) => ({ ...c })),
          });
          s.runes++;
          s.totalRunes++;
          s.collected.push({ suit: done.suit || 'wild', rank: s.rank });
          this.log(`Rune bound (${s.runes}/${s.required}).`);
          changed = true;
        }
      }
    }
    if (s.phase !== 'play') return;
    if (s.runes >= s.required) {
      if (s.rank >= RANKS.length) {
        s.phase = 'ascended';
        this.log('The core takes the last of it. You do not come back down.');
      } else {
        s.phase = 'breakthrough';
        s.offer = offerBoons(s.boons);
        this.log(`${RANKS[s.rank - 1].name} cleared. Advancement.`);
      }
      return;
    }
    if (!this.hasLegalMove()) {
      s.phase = 'failed';
      this.log('The core goes dark. The climb ends here.');
    }
  }

  /**
   * The run continues while there is anything worth doing. That is exactly the
   * question `suggest` answers, held cards included, so it is the only place
   * the answer lives -- a run can never end on a move the hint would have
   * shown, and the hint can never point at a run the game has ended.
   */
  hasLegalMove() {
    return this.suggest().kind !== 'over';
  }

  /** Nothing worth suggesting is left, though the position may still be poked at. */
  isStagnant() {
    return this.state.phase === 'play' && this.suggest().kind === 'over';
  }

  /** Why the stock will not deal, or null when it will. */
  dealBlockedReason() {
    if (this.canDeal()) return null;
    return this.state.stock.length ? null : 'The stock is spent.';
  }

  /**
   * Is a second wind available? Only a rank that has actually ended, and only
   * so many times, so a run cannot be carried indefinitely on reprieves.
   */
  canReprieve() {
    return this.state.phase === 'failed' && this.state.reprieves < REPRIEVES_PER_RANK;
  }

  /**
   * Bring a dead run back. A wildcard is the one thing that always unsticks a
   * board -- it can go on any column that is not an Ace, and it is always
   * payable -- so a reprieve is a wildcard and one more undo to use it with.
   */
  reprieve() {
    if (!this.canReprieve()) return false;
    const s = this.state;
    s.phase = 'play';
    s.reprieves++;
    s.wilds++;
    s.undosLeft++;
    this.undoStack = [];
    this.log('A second wind: one wildcard, and one more move to take back.');
    return true;
  }

  /** Whether another undo can be granted this rank. */
  canGrantUndo() {
    return this.state.phase === 'play' && this.state.extraUndos < EXTRA_UNDOS_PER_RANK;
  }

  grantUndo() {
    if (!this.canGrantUndo()) return false;
    this.state.extraUndos++;
    this.state.undosLeft++;
    this.log('One more undo.');
    return true;
  }

  concede() {
    if (this.state.phase === 'play') {
      this.state.phase = 'failed';
      this.log('You walk away from it.');
    }
  }

  // ------------------------------------------------------- breakthrough

  chooseBoon(index) {
    const s = this.state;
    if (s.phase !== 'breakthrough') return false;
    const boon = s.offer[index];
    if (!boon) return false;
    s.boons[boon.key] = (s.boons[boon.key] || 0) + 1;
    this.log(`${boon.name} ×${s.boons[boon.key]}.`);
    this.dealRank(s.rank + 1);
    return true;
  }

  // -------------------------------------------------------------- helper

  /** Best legal destination for the run at the foot of `colIndex`, or null. */
  /**
   * How good is this landing? A player reads it as "put the card where it makes
   * the longest sequence", so run length comes first and everything else only
   * breaks ties.
   */
  moveScore(from, to) {
    const run = this.takeRun(from);
    const dest = this.state.columns[to.index];
    const src = from.zone === 'col' ? this.state.columns[from.index] : null;
    const under = src && src.length > run.length ? src[src.length - run.length - 1] : null;
    const landed = dest.concat(run);
    return {
      resultRun: movableTail(landed, { mixedSuit: false }),
      seals: completedRune(landed) !== null,
      exposes: !!(under && !under.faceUp),
      empties: !!(src && src.length === run.length),
      destEmpty: dest.length === 0,
    };
  }

  /** True when `a` is the move a thoughtful player would rather make. */
  static better(a, b) {
    if (a.seals !== b.seals) return a.seals;
    if (a.resultRun !== b.resultRun) return a.resultRun > b.resultRun;
    if (a.exposes !== b.exposes) return a.exposes;
    if (a.empties !== b.empties) return a.empties;
    if (a.destEmpty !== b.destEmpty) return !a.destEmpty;
    return false;
  }

  /** Destination column that builds the longest run, or null if there is none. */
  bestTargetFor(from) {
    const s = this.state;
    if (from.zone === 'col' && !this.canGrab(from.index, from.count)) return null;
    const run = this.takeRun(from);
    if (!run || !run.length || run.some((c) => !c.faceUp)) return null;
    let best = null;
    let bestIndex = null;
    for (let j = 0; j < s.columns.length; j++) {
      if (from.zone === 'col' && j === from.index) continue;
      if (!s.columns[j].length && from.zone === 'col' && from.count === s.columns[from.index].length) continue;
      if (!this.canDrop(run, { zone: 'col', index: j })) continue;
      const score = this.moveScore(from, { zone: 'col', index: j });
      if (!best || Game.better(score, best)) { best = score; bestIndex = j; }
    }
    return bestIndex;
  }

  autoTarget(colIndex, count) {
    return this.bestTargetFor({ zone: 'col', index: colIndex, count });
  }

  /**
   * Every legal tableau move, best first -- the source of the hint carousel.
   *
   * Only the best lift is kept per source and destination, and every empty
   * column counts as the same destination, since dropping into one is the same
   * idea whichever one you pick. "Best" is what settles how much of the run
   * goes: into an empty column a longer run scores higher, so the whole run is
   * what gets offered.
   */
  listMoves({ limit = 0 } = {}) {
    const s = this.state;
    if (s.phase !== 'play') return [];
    const out = [];

    const landings = (from, tail) => {
      const run = this.takeRun(from);
      if (!run || !run.length || run.some((c) => !c.faceUp)) return [];
      const found = [];
      for (let j = 0; j < s.columns.length; j++) {
        if (from.zone === 'col' && j === from.index) continue;
        const destEmpty = s.columns[j].length === 0;
        // Emptying one column to fill another gains nothing.
        if (destEmpty && from.zone === 'col' && from.count === s.columns[from.index].length) continue;
        if (!this.canDrop(run, { zone: 'col', index: j })) continue;
        found.push({
          key: destEmpty ? 'empty' : j,
          move: {
            from,
            to: { zone: 'col', index: j },
            wholeRun: from.zone === 'reserve' || from.count === tail,
            ...this.moveScore(from, { zone: 'col', index: j }),
          },
        });
      }
      return found;
    };

    const keepBest = (into, found) => {
      for (const { key, move } of found) {
        if (!into.has(key) || Game.better(move, into.get(key))) into.set(key, move);
      }
    };

    for (let i = 0; i < s.columns.length; i++) {
      const tail = this.columnTail(i);
      const perDest = new Map();
      for (let n = 1; n <= tail; n++) {
        keepBest(perDest, landings({ zone: 'col', index: i, count: n }, tail));
      }
      out.push(...perDest.values());
    }
    for (let i = 0; i < s.reserve.length; i++) {
      if (!s.reserve[i]) continue;
      const perDest = new Map();
      keepBest(perDest, landings({ zone: 'reserve', index: i }, 1));
      out.push(...perDest.values());
    }

    out.sort((a, b) => (Game.better(a, b) ? -1 : Game.better(b, a) ? 1 : 0));
    return limit ? out.slice(0, limit) : out;
  }

  /**
   * What to suggest, in the order a player actually wants to hear it:
   *
   *   1. moves that bind a rune -- worth splitting a run for
   *   2. moves that carry a whole run somewhere, never breaking one up
   *   3. failing both, moves into an empty column -- but only while something
   *      is still face down for that to uncover
   *   4. failing that, deal another row
   *   5. failing that, an empty column after all, or the run is over
   *
   * @returns {{kind:'moves'|'empty'|'deal'|'over', moves: Array}}
   */
  suggest() {
    if (this.state.phase !== 'play') return { kind: 'over', moves: [] };
    const all = this.listMoves();
    const useful = all.filter((m) => m.seals || (m.wholeRun && !m.destEmpty));
    if (useful.length) return { kind: 'moves', moves: useful };

    const intoEmpty = all.filter((m) => m.destEmpty);
    // Filling an empty column is only ever a way to get at something buried.
    // With nothing face down left it uncovers nothing, so a fresh row is worth
    // more than shuffling the board sideways.
    const buried = this.state.columns.some((col) => col.some((c) => !c.faceUp));
    if (intoEmpty.length && buried) return { kind: 'empty', moves: intoEmpty };
    if (this.canDeal()) return { kind: 'deal', moves: [] };
    if (intoEmpty.length) return { kind: 'empty', moves: intoEmpty };

    // What is held comes last, cheapest first. A reserve slot is lent, not
    // spent -- the card comes back -- so it is tried before a wildcard, which
    // takes a card out of the game for good.
    const park = this.parkMoves();
    if (park.length) return { kind: 'park', moves: park };
    const wild = this.wildMoves();
    if (wild.length) return { kind: 'wild', moves: wild };
    return { kind: 'over', moves: [] };
  }

  /**
   * Cards worth parking in a free reserve slot. A slot is only a way out when
   * lifting the card changes something: it uncovers a face-down card, empties
   * a column, or exposes a card that gives the board a move it did not have.
   * Shuffling one card in and out forever is not a way out, so those are not
   * listed and do not keep a dead run alive.
   */
  parkMoves() {
    const s = this.state;
    if (s.phase !== 'play') return [];
    const slot = s.reserve.indexOf(null);
    if (slot < 0) return [];

    const out = [];
    for (let i = 0; i < s.columns.length; i++) {
      const col = s.columns[i];
      if (!col.length) continue;
      const foot = col[col.length - 1];
      if (!foot.faceUp) continue;
      const move = { from: { zone: 'col', index: i, count: 1 }, to: { zone: 'reserve', index: slot } };

      if (col.length > 1 && !col[col.length - 2].faceUp) { out.push(move); continue; }

      // Nothing is turned over by lifting it -- emptying a column included,
      // since an empty column is only worth what can be moved into it. So the
      // question is whether the board opens up without the card. Try it and
      // see, judging the result the way `suggest` judges any other position.
      col.pop();
      s.reserve[slot] = foot;
      const after = this.listMoves();
      const buried = s.columns.some((c) => c.some((x) => !x.faceUp));
      const opens = after.some((m) => m.seals || (m.wholeRun && !m.destEmpty))
        || (buried && after.some((m) => m.destEmpty));
      s.reserve[slot] = null;
      col.push(foot);
      if (opens) out.push(move);
    }
    return out;
  }

  /** Columns a held wildcard could still be spent on. */
  wildMoves() {
    const s = this.state;
    if (s.phase !== 'play' || s.wilds <= 0) return [];
    const out = [];
    for (let i = 0; i < s.columns.length; i++) {
      const plan = this.wildCost({ zone: 'col', index: i });
      if (plan) out.push({ to: { zone: 'col', index: i }, value: plan.value });
    }
    return out;
  }

  /** Every sequence a full run would have to bind, across all six ranks. */
  totalSequences() {
    const diff = DIFFICULTIES[this.difficulty];
    let n = 0;
    for (let r = 1; r <= RANKS.length; r++) n += diff.startSets + (r - 1);
    return n;
  }

  /** How far through the whole climb, 0 to 1. Drives the core's growth. */
  progress() {
    return Math.min(1, this.state.totalRunes / this.totalSequences());
  }

  score() {
    const s = this.state;
    return s.totalRunes * 100 + (s.rank - 1) * 250 + (s.phase === 'ascended' ? 2500 : 0);
  }
}

export { SUITS, KING };

// ------------------------------------------------------------ persistence

export function serialize(game) {
  return JSON.stringify({
    v: 1,
    seed: game.seed,
    difficulty: game.difficulty,
    rng: game.rng.state(),
    state: game.state,
  });
}

/**
 * Restore a saved run, or return null if the save cannot be trusted.
 *
 * `required` is recomputed rather than believed: what a rank demands has
 * changed before (it used to be a quota, it is now the whole board) and a save
 * written under the old rule would otherwise resume with the old demand. The
 * recomputed value is only safe if the saved cards really are the deal this
 * config describes, so that is checked by conservation -- every card dealt is
 * either still in play or part of a sealed thirteen. A save that fails is from
 * an incompatible build and is discarded rather than resumed into a board that
 * cannot be finished.
 */
export function deserialize(json) {
  let data;
  try {
    data = typeof json === 'string' ? JSON.parse(json) : json;
  } catch {
    return null;
  }
  if (!data || data.v !== 1 || !data.state) return null;
  const state = data.state;
  if (!Array.isArray(state.columns) || !Array.isArray(state.stock) || !Array.isArray(state.reserve)) return null;
  if (!DIFFICULTIES[data.difficulty] || !RANKS[state.rank - 1]) return null;

  const game = Object.create(Game.prototype);
  game.seed = data.seed;
  game.difficulty = data.difficulty;
  game.rng = makeRng(data.seed);
  game.rng.setState(data.rng);
  if (typeof state.wilds !== 'number') state.wilds = 0;
  if (typeof state.conjured !== 'number') state.conjured = 0;
  if (typeof state.reprieves !== 'number') state.reprieves = 0;
  if (typeof state.extraUndos !== 'number') state.extraUndos = 0;
  game.state = state;
  game.undoStack = [];

  const inPlay = [...state.columns.flat(), ...state.stock, ...state.reserve.filter(Boolean)];
  const cfg = game.rankConfig(state.rank);
  // A conjured wildcard is a card the deal never held, so it counts here.
  const dealt = cfg.sets * SEQUENCE_LENGTH + cfg.wilds + state.conjured;
  if (inPlay.length + SEQUENCE_LENGTH * state.runes !== dealt) {
    return null;
  }
  state.required = cfg.required;

  const ids = inPlay.map((c) => c.id);
  bumpCardIds(ids.length ? Math.max(...ids) + 1 : 1);
  return game;
}
