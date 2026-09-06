// Card model and the sequence rules that drive the whole game.
//
// A "rune" is what solitaire calls a completed sequence: a full K->A run of one
// suit sitting at the foot of a column. Binding one is the only way to advance
// a rank.

import { shuffle } from './rng.js';

export const SUITS = ['spade', 'heart', 'club', 'diamond'];
export const SUIT_GLYPH = { spade: '♠', heart: '♥', club: '♣', diamond: '♦', wild: '✦' };
export const SUIT_NAME = { spade: 'Shadow', heart: 'Flame', club: 'Stone', diamond: 'Frost' };
export const RANK_LABEL = ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
export const KING = 13;
export const SEQUENCE_LENGTH = 13;

let nextId = 1;
export function resetCardIds() { nextId = 1; }

export function makeCard(rank, suit, faceUp = false) {
  return { id: nextId++, rank, suit, faceUp, wild: false };
}

/**
 * A wildcard. Unfixed (rank 0) it fills whatever gap it sits in; once placed it
 * is given a rank and a suit and is a card like any other, marked only so you
 * can see where it came from.
 */
export function makeWild(faceUp = false, rank = 0, suit = 'wild') {
  return { id: nextId++, rank, suit, faceUp, wild: true };
}

/** A wildcard still free to be anything. Placed ones never are. */
export function isFlexible(card) {
  return card.wild && card.rank === 0;
}

export function cardLabel(card) {
  if (isFlexible(card)) return '✦';
  return RANK_LABEL[card.rank] + (card.wild ? '✦' : SUIT_GLYPH[card.suit]);
}

/**
 * Build a deck of `sets` full A-K runs spread round-robin over the first
 * `suitCount` suits, plus `wilds` wildcards, shuffled.
 */
export function buildDeck({ sets, suitCount, wilds = 0 }, rng) {
  const suits = SUITS.slice(0, Math.max(1, Math.min(SUITS.length, suitCount)));
  const deck = [];
  for (let s = 0; s < sets; s++) {
    const suit = suits[s % suits.length];
    for (let r = 1; r <= KING; r++) deck.push(makeCard(r, suit));
  }
  for (let w = 0; w < wilds; w++) deck.push(makeWild());
  return shuffle(deck, rng);
}

/**
 * Inspect a candidate run. `cards[0]` is the highest card (nearest the top of
 * the pile); each following card sits one rank lower.
 *
 * An unfixed wildcard is a gap filler: it adopts whatever rank and suit the run
 * needs at its position. Once a wildcard has been placed it carries a real rank
 * and is read like any other card.
 *
 * @returns {{valid:boolean, suit:string|null, topRank:number|null}}
 *   `suit`/`topRank` are null when only wilds pinned them down.
 */
export function runInfo(cards, { sameSuit = true } = {}) {
  const bad = { valid: false, suit: null, topRank: null };
  if (!cards.length) return bad;
  if (cards.some((c) => !c.faceUp)) return bad;

  let suit = null;
  let anchorRank = null;
  let anchorIndex = 0;
  for (let i = 0; i < cards.length; i++) {
    const c = cards[i];
    if (isFlexible(c)) continue;
    if (anchorRank === null) {
      anchorRank = c.rank;
      anchorIndex = i;
      suit = c.suit;
      continue;
    }
    if (sameSuit && c.suit !== suit) return bad;
    if (c.rank !== anchorRank - (i - anchorIndex)) return bad;
  }
  if (anchorRank === null) return { valid: true, suit: null, topRank: null };
  const topRank = anchorRank + anchorIndex;
  if (topRank > KING) return bad;
  const bottomRank = topRank - (cards.length - 1);
  if (bottomRank < 1) return bad;
  return { valid: true, suit: sameSuit ? suit : null, topRank };
}

/** Effective rank of a card at `index` within a run whose top rank is known. */
export function effectiveRank(info, index) {
  return info.topRank === null ? null : info.topRank - index;
}

/**
 * May `run` (already validated as movable) land on `target`?
 * Empty destinations take anything. Otherwise only rank matters -- suits are
 * free to mix while stacking, exactly as in Spider. Wilds match anything.
 */
export function canStackOn(runTopInfo, run, target) {
  if (!target) return true;
  if (!target.faceUp) return false;
  if (isFlexible(target) || isFlexible(run[0])) return true;
  if (runTopInfo.topRank === null) return true;
  return runTopInfo.topRank === target.rank - 1;
}

/**
 * Does the foot of this column hold a finished K->A rune?
 * @returns {{cards:Array, suit:string|null}|null}
 */
export function completedRune(column) {
  if (column.length < SEQUENCE_LENGTH) return null;
  const tail = column.slice(column.length - SEQUENCE_LENGTH);
  const info = runInfo(tail, { sameSuit: true });
  if (!info.valid) return null;
  // All-wild runs (topRank null) are free to be a King-high sequence.
  if (info.topRank !== null && info.topRank !== KING) return null;
  return { cards: tail, suit: info.suit };
}

/**
 * Length of the longest movable run sitting at the foot of `column`.
 * `mixedSuit` is kept for rule variants; the base game never mixes suits.
 */
export function movableTail(column, { mixedSuit = false } = {}) {
  let best = 0;
  for (let n = 1; n <= column.length; n++) {
    const slice = column.slice(column.length - n);
    if (!runInfo(slice, { sameSuit: !mixedSuit }).valid) break;
    best = n;
  }
  return best;
}

/** Keep freshly dealt cards from colliding with ids restored from a save. */
export function bumpCardIds(minNext) {
  if (minNext > nextId) nextId = minNext;
}
