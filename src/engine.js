// Game engine. Pure logic, no DOM: the UI reads `game.state` and calls methods.

import { makeRng, shuffle, randomSeed } from './rng.js';
import {
  SUITS, KING, SEQUENCE_LENGTH, buildDeck, runInfo, canStackOn,
  completedMeridian, movableTail, resetCardIds, bumpCardIds,
} from './cards.js';
import { offerBoons } from './paths.js';

export const REALMS = [
  { name: 'Qi Condensation', hanzi: '練氣' },
  { name: 'Foundation Establishment', hanzi: '築基' },
  { name: 'Core Formation', hanzi: '結丹' },
  { name: 'Nascent Soul', hanzi: '元嬰' },
  { name: 'Spirit Severing', hanzi: '化神' },
  { name: 'Dao Seeking', hanzi: '問道' },
];
export const ASCENSION = { name: 'Immortal Ascension', hanzi: '飛昇' };

export const DIFFICULTIES = {
  novice: { name: 'Novice', suits: [1, 1, 1, 2, 2, 2], spare: 4 },
  adept: { name: 'Adept', suits: [1, 1, 2, 2, 3, 4], spare: 3 },
  immortal: { name: 'Immortal', suits: [1, 2, 2, 4, 4, 4], spare: 2 },
};

export const BASE_COLUMNS = 10;
export const UNDOS_PER_REALM = 3;
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
      realm: 1,
      required: 1,
      meridians: 0,           // completed this realm
      totalMeridians: 0,
      collected: [],          // {suit, realm} of every meridian sealed this run
      columns: [],
      reserve: [],
      stock: [],
      boons: {},              // pathKey -> tier
      fortune: 0,
      charges: { voidStep: 0, transmute: 0, awaken: 0 },
      undosLeft: UNDOS_PER_REALM,
      moves: 0,
      offer: [],
      log: [],
    };
    this.dealRealm(1);
  }

  // ---------------------------------------------------------------- config

  tier(pathKey) { return this.state.boons[pathKey] || 0; }

  realmConfig(realm) {
    const s = this.state;
    const diff = DIFFICULTIES[this.difficulty];
    const required = Math.max(1, realm - s.fortune);
    const sets = required + diff.spare;
    const severed = this.tier('severance') >= 3 ? 2 : this.tier('severance') >= 1 ? 1 : 0;
    const suitCount = Math.max(1, Math.min(SUITS.length, diff.suits[realm - 1] - severed));
    const columns = BASE_COLUMNS + this.tier('expansion');
    const wilds = this.tier('talisman') * 2;
    return { required, sets, suitCount, columns, wilds };
  }

  reserveCells() {
    const t = this.tier('void');
    return (t >= 1 ? 1 : 0) + (t >= 3 ? 1 : 0);
  }

  mixedSuitMoves() { return this.tier('void') >= 3; }
  wildsFaceUp() { return this.tier('talisman') >= 2; }
  mayDealOverEmpties() { return this.tier('expansion') >= 3; }

  freshCharges() {
    const v = this.tier('void');
    const s = this.tier('severance');
    return {
      voidStep: (v >= 2 ? 2 : 0) + (v >= 3 ? 2 : 0),
      transmute: (s >= 2 ? 2 : 0) + (s >= 3 ? 1 : 0),
      awaken: this.tier('talisman') >= 3 ? 1 : 0,
    };
  }

  // ----------------------------------------------------------------- deal

  dealRealm(realm) {
    const s = this.state;
    const cfg = this.realmConfig(realm);
    const deck = buildDeck(cfg, this.rng);
    if (this.wildsFaceUp()) for (const c of deck) if (c.wild) c.faceUp = true;

    const total = deck.length;
    const stockDeals = Math.max(2, Math.min(6, Math.floor((total - cfg.columns * 4) / cfg.columns)));
    const initialCount = total - stockDeals * cfg.columns;

    // Wide Channels leaves one column empty at the deal.
    const dealInto = this.tier('expansion') >= 2 ? cfg.columns - 1 : cfg.columns;
    const columns = Array.from({ length: cfg.columns }, () => []);
    for (let i = 0; i < initialCount; i++) columns[i % dealInto].push(deck.pop());
    for (const col of columns) {
      for (let i = 0; i < col.length; i++) col[i].faceUp = col[i].wild ? col[i].faceUp : false;
      if (col.length) col[col.length - 1].faceUp = true;
    }

    s.realm = realm;
    s.required = cfg.required;
    s.meridians = 0;
    s.columns = columns;
    s.stock = deck;
    s.reserve = Array.from({ length: this.reserveCells() }, () => null);
    s.charges = this.freshCharges();
    s.undosLeft = UNDOS_PER_REALM;
    s.phase = 'play';
    s.offer = [];
    this.undoStack = [];
    this.log(`${REALMS[realm - 1].name}: seal ${cfg.required} meridian${cfg.required > 1 ? 's' : ''}.`);
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
    return movableTail(this.state.columns[colIndex], { mixedSuit: this.mixedSuitMoves() });
  }

  /** Can the player pick up `count` cards from the foot of column `i`? */
  canGrab(colIndex, count) {
    const col = this.state.columns[colIndex];
    if (count < 1 || count > col.length) return false;
    return count <= this.columnTail(colIndex);
  }

  /** Where can a grabbed run legally land? `force` spends a void step. */
  canDrop(run, dest, { force = false } = {}) {
    const s = this.state;
    if (dest.zone === 'reserve') {
      if (run.length !== 1) return false;
      return s.reserve[dest.index] === null;
    }
    const col = s.columns[dest.index];
    const target = col.length ? col[col.length - 1] : null;
    if (!target) return true;
    if (force) return target.faceUp;
    const info = runInfo(run, { sameSuit: !this.mixedSuitMoves() });
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
  move(from, to, { force = false } = {}) {
    const s = this.state;
    if (s.phase !== 'play') return false;
    if (from.zone === to.zone && from.index === to.index) return false;
    if (force && s.charges.voidStep <= 0) return false;

    const run = this.takeRun(from);
    if (!run || !run.length) return false;
    if (from.zone === 'col' && !this.canGrab(from.index, run.length)) return false;
    if (run.some((c) => !c.faceUp)) return false;
    if (!this.canDrop(run, to, { force })) return false;
    // Shuffling a whole column into an empty one achieves nothing.
    if (from.zone === 'col' && to.zone === 'col'
      && run.length === s.columns[from.index].length && s.columns[to.index].length === 0) return false;

    this.pushUndo();
    if (from.zone === 'reserve') s.reserve[from.index] = null;
    else s.columns[from.index].length -= run.length;

    if (to.zone === 'reserve') s.reserve[to.index] = run[0];
    else s.columns[to.index].push(...run);

    if (force) {
      s.charges.voidStep--;
      this.log(`Void Step: ${run.length} card${run.length > 1 ? 's' : ''} placed against the dao.`);
    }
    s.moves++;
    this.settle();
    return true;
  }

  /** Deal one card onto every column. */
  deal() {
    const s = this.state;
    if (s.phase !== 'play' || !s.stock.length) return false;
    if (!this.mayDealOverEmpties() && s.columns.some((c) => c.length === 0)) return false;
    this.pushUndo();
    for (let i = 0; i < s.columns.length && s.stock.length; i++) {
      const card = s.stock.pop();
      card.faceUp = true;
      s.columns[i].push(card);
    }
    s.moves++;
    this.log('The heavens deal another row.');
    this.settle();
    return true;
  }

  canDeal() {
    const s = this.state;
    return s.phase === 'play' && s.stock.length > 0
      && (this.mayDealOverEmpties() || !s.columns.some((c) => c.length === 0));
  }

  // ------------------------------------------------------------- charges

  transmute(ref, suit) {
    const s = this.state;
    if (s.phase !== 'play' || s.charges.transmute <= 0) return false;
    if (!SUITS.includes(suit)) return false;
    const card = this.cardAt(ref);
    if (!card || !card.faceUp || card.wild || card.suit === suit) return false;
    this.pushUndo();
    card.suit = suit;
    s.charges.transmute--;
    s.moves++;
    this.log('Transmutation: a card is reforged.');
    this.settle();
    return true;
  }

  awaken(ref) {
    const s = this.state;
    if (s.phase !== 'play' || s.charges.awaken <= 0) return false;
    const card = this.cardAt(ref);
    if (!card || !card.faceUp || card.wild) return false;
    this.pushUndo();
    card.wild = true;
    card.rank = 0;
    card.suit = 'wild';
    s.charges.awaken--;
    s.moves++;
    this.log('A card awakens into a chaos talisman.');
    this.settle();
    return true;
  }

  cardAt(ref) {
    const s = this.state;
    if (ref.zone === 'reserve') return s.reserve[ref.index];
    const col = s.columns[ref.index];
    const i = ref.cardIndex === undefined ? col.length - 1 : ref.cardIndex;
    return col[i];
  }

  // ---------------------------------------------------------- resolution

  /** Flip exposed cards, seal finished meridians, then check win/loss. */
  settle() {
    const s = this.state;
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < s.columns.length; i++) {
        const col = s.columns[i];
        if (col.length && !col[col.length - 1].faceUp) {
          col[col.length - 1].faceUp = true;
          changed = true;
        }
        const done = completedMeridian(col);
        if (done) {
          col.length -= SEQUENCE_LENGTH;
          s.meridians++;
          s.totalMeridians++;
          s.collected.push({ suit: done.suit || 'wild', realm: s.realm });
          this.log(`Meridian sealed (${s.meridians}/${s.required}).`);
          changed = true;
        }
      }
    }
    if (s.phase !== 'play') return;
    if (s.meridians >= s.required) {
      if (s.realm >= REALMS.length) {
        s.phase = 'ascended';
        this.log('You step beyond the mortal coil. Ascension.');
      } else {
        s.phase = 'breakthrough';
        s.offer = offerBoons(s.boons, this.rng);
        this.log(`Breakthrough! ${REALMS[s.realm - 1].name} complete.`);
      }
      return;
    }
    if (!this.hasLegalMove()) {
      s.phase = 'failed';
      this.log('Your qi scatters. The dao is closed to you.');
    }
  }

  hasLegalMove() {
    const s = this.state;
    if (this.canDeal()) return true;
    if (s.charges.voidStep > 0 || s.charges.transmute > 0 || s.charges.awaken > 0) return true;
    // An open cell always affords a move: it either exposes a buried card or
    // empties a column, and both change the position.
    if (s.reserve.some((r) => r === null) && s.columns.some((c) => c.length >= 1)) return true;

    for (let i = 0; i < s.reserve.length; i++) {
      const card = s.reserve[i];
      if (!card) continue;
      for (let j = 0; j < s.columns.length; j++) {
        if (this.canDrop([card], { zone: 'col', index: j })) return true;
      }
    }
    for (let i = 0; i < s.columns.length; i++) {
      const tail = this.columnTail(i);
      for (let n = 1; n <= tail; n++) {
        const run = s.columns[i].slice(s.columns[i].length - n);
        for (let j = 0; j < s.columns.length; j++) {
          if (i === j) continue;
          if (s.columns[j].length === 0 && n === s.columns[i].length) continue;
          if (this.canDrop(run, { zone: 'col', index: j })) return true;
        }
      }
    }
    return false;
  }

  /** No stock and no tableau-to-tableau move: the player is very likely stuck. */
  isStagnant() {
    const s = this.state;
    if (s.phase !== 'play' || this.canDeal()) return false;
    for (let i = 0; i < s.columns.length; i++) {
      const tail = this.columnTail(i);
      for (let n = 1; n <= tail; n++) {
        const run = s.columns[i].slice(s.columns[i].length - n);
        for (let j = 0; j < s.columns.length; j++) {
          if (i === j) continue;
          if (s.columns[j].length === 0 && n === s.columns[i].length) continue;
          if (this.canDrop(run, { zone: 'col', index: j })) return false;
        }
      }
    }
    return true;
  }

  concede() {
    if (this.state.phase === 'play') {
      this.state.phase = 'failed';
      this.log('You abandon the climb.');
    }
  }

  // ------------------------------------------------------- breakthrough

  chooseBoon(index) {
    const s = this.state;
    if (s.phase !== 'breakthrough') return false;
    const boon = s.offer[index];
    if (!boon) return false;
    if (boon.type === 'fortune') s.fortune++;
    else s.boons[boon.key] = boon.tier;
    this.log(`You walk the ${boon.path}: ${boon.name}.`);
    this.dealRealm(s.realm + 1);
    return true;
  }

  // -------------------------------------------------------------- helper

  /** Best legal destination for the run at the foot of `colIndex`, or null. */
  autoTarget(colIndex, count) {
    const s = this.state;
    if (!this.canGrab(colIndex, count)) return null;
    const run = s.columns[colIndex].slice(s.columns[colIndex].length - count);
    const info = runInfo(run, { sameSuit: !this.mixedSuitMoves() });
    let empty = null;
    let offSuit = null;
    for (let j = 0; j < s.columns.length; j++) {
      if (j === colIndex) continue;
      const col = s.columns[j];
      if (!col.length) {
        if (count !== s.columns[colIndex].length && empty === null) empty = j;
        continue;
      }
      if (!this.canDrop(run, { zone: 'col', index: j })) continue;
      const target = col[col.length - 1];
      if (target.wild || info.suit === null || target.suit === info.suit) return j;
      if (offSuit === null) offSuit = j;
    }
    if (offSuit !== null) return offSuit;
    return empty;
  }

  score() {
    const s = this.state;
    return s.totalMeridians * 100 + (s.realm - 1) * 250 + (s.phase === 'ascended' ? 2500 : 0);
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

export function deserialize(json) {
  const data = typeof json === 'string' ? JSON.parse(json) : json;
  if (!data || data.v !== 1 || !data.state) return null;
  const game = Object.create(Game.prototype);
  game.seed = data.seed;
  game.difficulty = data.difficulty;
  game.rng = makeRng(data.seed);
  game.rng.setState(data.rng);
  game.state = data.state;
  game.undoStack = [];
  const ids = [
    ...data.state.columns.flat(),
    ...data.state.stock,
    ...data.state.reserve.filter(Boolean),
  ].map((c) => c.id);
  bumpCardIds(ids.length ? Math.max(...ids) + 1 : 1);
  return game;
}
