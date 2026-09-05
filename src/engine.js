// Game engine. Pure logic, no DOM: the UI reads `game.state` and calls methods.

import { makeRng, shuffle, randomSeed } from './rng.js';
import {
  SUITS, KING, SEQUENCE_LENGTH, buildDeck, runInfo, canStackOn,
  completedRune, movableTail, resetCardIds, bumpCardIds,
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
// left, so it is what the difficulties turn: Adept opens on two full decks,
// which is the classic single-suit Spider board.
export const DIFFICULTIES = {
  novice: { name: 'Novice', startSets: 7 },
  adept: { name: 'Adept', startSets: 8 },
  immortal: { name: 'Merciless', startSets: 10 },
};

export const BASE_COLUMNS = 10;
export const UNDOS_PER_RANK = 3;
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
      wilds: this.held('talisman') * 2,
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

  undo() {
    if (this.state.phase !== 'play') return false;
    if (!this.undoStack.length || this.state.undosLeft <= 0) return false;
    const snap = this.undoStack.pop();
    const left = this.state.undosLeft - 1;
    this.state = snap.state;
    this.rng.setState(snap.rng);
    this.state.undosLeft = left;
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
   * The run continues while there is something worth doing: a suggestion, or a
   * cell to park a card in -- and a cell only counts when parking would uncover
   * a face-down card or empty a column, since shuffling one card in and out
   * forever is not a way out.
   */
  hasLegalMove() {
    const s = this.state;
    if (s.reserve.some((r) => r === null)
      && s.columns.some((c) => c.length === 1 || (c.length > 1 && !c[c.length - 2].faceUp))) return true;
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
   * Only the best lift is kept per source/destination pair, and only one empty
   * destination per source; without that the same idea appears many times over.
   * What survives runs a median of seven moves and tops out around fourteen,
   * which is short enough to page through in full.
   */
  listMoves({ limit = 0 } = {}) {
    const s = this.state;
    if (s.phase !== 'play') return [];
    const out = [];
    const emptySeen = new Set();

    const consider = (from, key, wholeRun) => {
      const run = this.takeRun(from);
      if (!run || !run.length || run.some((c) => !c.faceUp)) return;
      for (let j = 0; j < s.columns.length; j++) {
        if (from.zone === 'col' && j === from.index) continue;
        const destEmpty = s.columns[j].length === 0;
        if (destEmpty && from.zone === 'col' && from.count === s.columns[from.index].length) continue;
        if (destEmpty && emptySeen.has(key)) continue;
        if (!this.canDrop(run, { zone: 'col', index: j })) continue;
        if (destEmpty) emptySeen.add(key);
        out.push({
          from, to: { zone: 'col', index: j }, wholeRun,
          ...this.moveScore(from, { zone: 'col', index: j }),
        });
      }
    };

    for (let i = 0; i < s.columns.length; i++) {
      const tail = this.columnTail(i);
      const perDest = new Map();
      for (let n = 1; n <= tail; n++) {
        const from = { zone: 'col', index: i, count: n };
        const before = out.length;
        consider(from, `c${i}`, n === tail);
        for (const m of out.splice(before)) {
          const key = m.to.index;
          if (!perDest.has(key) || Game.better(m, perDest.get(key))) perDest.set(key, m);
        }
      }
      out.push(...perDest.values());
    }
    for (let i = 0; i < s.reserve.length; i++) {
      if (s.reserve[i]) consider({ zone: 'reserve', index: i }, `r${i}`, true);
    }

    out.sort((a, b) => (Game.better(a, b) ? -1 : Game.better(b, a) ? 1 : 0));
    return limit ? out.slice(0, limit) : out;
  }

  /**
   * What to suggest, in the order a player actually wants to hear it:
   *
   *   1. moves that bind a rune -- worth splitting a run for
   *   2. moves that carry a whole run somewhere, never breaking one up
   *   3. failing both, moves into an empty column
   *   4. failing that, deal another row
   *   5. failing that, the run is over
   *
   * @returns {{kind:'moves'|'empty'|'deal'|'over', moves: Array}}
   */
  suggest() {
    if (this.state.phase !== 'play') return { kind: 'over', moves: [] };
    const all = this.listMoves();
    const useful = all.filter((m) => m.seals || (m.wholeRun && !m.destEmpty));
    if (useful.length) return { kind: 'moves', moves: useful };
    const intoEmpty = all.filter((m) => m.destEmpty);
    if (intoEmpty.length) return { kind: 'empty', moves: intoEmpty };
    if (this.canDeal()) return { kind: 'deal', moves: [] };
    return { kind: 'over', moves: [] };
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
  game.state = state;
  game.undoStack = [];

  const inPlay = [...state.columns.flat(), ...state.stock, ...state.reserve.filter(Boolean)];
  const cfg = game.rankConfig(state.rank);
  if (inPlay.length + SEQUENCE_LENGTH * state.runes !== cfg.sets * SEQUENCE_LENGTH + cfg.wilds) {
    return null;
  }
  state.required = cfg.required;

  const ids = inPlay.map((c) => c.id);
  bumpCardIds(ids.length ? Math.max(...ids) + 1 : 1);
  return game;
}
