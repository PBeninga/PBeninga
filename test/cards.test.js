import test from 'node:test';
import assert from 'node:assert/strict';
import {
  makeCard, makeWild, runInfo, completedRune, movableTail, buildDeck,
  canStackOn, SEQUENCE_LENGTH, resetCardIds,
} from '../src/cards.js';
import { makeRng } from '../src/rng.js';

const up = (rank, suit) => makeCard(rank, suit, true);
const wildUp = () => makeWild(true);

test('a descending same-suit run is valid', () => {
  const run = [up(9, 'spade'), up(8, 'spade'), up(7, 'spade')];
  const info = runInfo(run);
  assert.equal(info.valid, true);
  assert.equal(info.suit, 'spade');
  assert.equal(info.topRank, 9);
});

test('a mixed-suit run is rejected unless mixing is allowed', () => {
  const run = [up(9, 'spade'), up(8, 'heart')];
  assert.equal(runInfo(run).valid, false);
  assert.equal(runInfo(run, { sameSuit: false }).valid, true);
});

test('a gap in rank breaks the run', () => {
  assert.equal(runInfo([up(9, 'spade'), up(7, 'spade')]).valid, false);
});

test('face-down cards are never part of a run', () => {
  assert.equal(runInfo([makeCard(9, 'spade', false), up(8, 'spade')]).valid, false);
});

test('a wild fills the gap it sits in', () => {
  const run = [up(9, 'spade'), wildUp(), up(7, 'spade')];
  const info = runInfo(run);
  assert.equal(info.valid, true);
  assert.equal(info.suit, 'spade');
  assert.equal(info.topRank, 9);
});

test('a wild leading a run still pins the rank from below', () => {
  const info = runInfo([wildUp(), up(7, 'heart')]);
  assert.equal(info.valid, true);
  assert.equal(info.topRank, 8);
  assert.equal(info.suit, 'heart');
});

test('an all-wild run is valid and unconstrained', () => {
  const info = runInfo([wildUp(), wildUp()]);
  assert.equal(info.valid, true);
  assert.equal(info.suit, null);
  assert.equal(info.topRank, null);
});

test('a wild cannot imply a rank above King', () => {
  assert.equal(runInfo([wildUp(), wildUp(), up(13, 'club')]).valid, false);
});

test('a wild cannot imply a rank below Ace', () => {
  assert.equal(runInfo([up(1, 'club'), wildUp()]).valid, false);
});

test('stacking only cares about rank, not suit', () => {
  const run = [up(8, 'spade')];
  assert.equal(canStackOn(runInfo(run), run, up(9, 'heart')), true);
  assert.equal(canStackOn(runInfo(run), run, up(10, 'heart')), false);
  assert.equal(canStackOn(runInfo(run), run, null), true);
});

test('anything stacks on a wild, and a wild stacks on anything', () => {
  const run = [up(8, 'spade')];
  assert.equal(canStackOn(runInfo(run), run, wildUp()), true);
  const w = [wildUp()];
  assert.equal(canStackOn(runInfo(w), w, up(3, 'club')), true);
});

test('a full K-A same-suit tail is a meridian', () => {
  const col = [makeCard(5, 'heart', false)];
  for (let r = 13; r >= 1; r--) col.push(up(r, 'club'));
  const done = completedRune(col);
  assert.ok(done);
  assert.equal(done.suit, 'club');
  assert.equal(done.cards.length, SEQUENCE_LENGTH);
});

test('a K-A run of the wrong length or rank is not a meridian', () => {
  const short = [];
  for (let r = 12; r >= 1; r--) short.push(up(r, 'club'));
  assert.equal(completedRune(short), null);

  const offset = [];
  for (let r = 12; r >= 0; r--) offset.push(up(Math.max(r, 1), 'club'));
  assert.equal(completedRune(offset), null);
});

test('a meridian may contain wilds', () => {
  const col = [];
  for (let r = 13; r >= 1; r--) col.push(r === 7 ? wildUp() : up(r, 'club'));
  const done = completedRune(col);
  assert.ok(done);
  assert.equal(done.suit, 'club');
});

test('movableTail measures the longest run at the foot', () => {
  const col = [makeCard(2, 'heart', false), up(5, 'spade'), up(9, 'club'), up(8, 'club')];
  assert.equal(movableTail(col), 2);
  assert.equal(movableTail(col, { mixedSuit: true }), 2);
  const mixed = [up(9, 'club'), up(8, 'heart'), up(7, 'heart')];
  assert.equal(movableTail(mixed), 2);
  assert.equal(movableTail(mixed, { mixedSuit: true }), 3);
});

test('buildDeck produces whole sets over the requested suits', () => {
  resetCardIds();
  const deck = buildDeck({ sets: 4, suitCount: 2, wilds: 3 }, makeRng('seed'));
  assert.equal(deck.length, 4 * 13 + 3);
  assert.equal(deck.filter((c) => c.wild).length, 3);
  const suits = new Set(deck.filter((c) => !c.wild).map((c) => c.suit));
  assert.deepEqual([...suits].sort(), ['heart', 'spade']);
  for (const suit of suits) {
    const ranks = deck.filter((c) => c.suit === suit).map((c) => c.rank).sort((a, b) => a - b);
    assert.equal(ranks.length, 26);
    assert.equal(ranks.filter((r) => r === 1).length, 2);
  }
});
