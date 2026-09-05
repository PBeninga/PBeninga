import test from 'node:test';
import assert from 'node:assert/strict';
import { Game, REALMS, BASE_COLUMNS, DIFFICULTIES } from '../src/engine.js';
import { makeCard, makeWild, SEQUENCE_LENGTH } from '../src/cards.js';

const up = (rank, suit) => makeCard(rank, suit, true);

/** A game with a hand-built tableau, so tests are not at the mercy of a deal. */
function rigged(columns, patch = {}) {
  const g = new Game({ seed: 'TEST', difficulty: 'adept' });
  g.state.columns = columns;
  g.state.stock = [];
  g.state.reserve = [];
  Object.assign(g.state, patch);
  g.undoStack = [];
  return g;
}

test('a new run starts in the first realm needing one meridian', () => {
  const g = new Game({ seed: 'ABC' });
  assert.equal(g.state.realm, 1);
  assert.equal(g.state.required, 1);
  assert.equal(g.state.phase, 'play');
  assert.equal(g.state.columns.length, BASE_COLUMNS);
});

test('the deal conserves every card and hides all but the foot of each column', () => {
  for (const difficulty of Object.keys(DIFFICULTIES)) {
    const g = new Game({ seed: 'DEAL', difficulty });
    const cfg = g.realmConfig(1);
    const dealt = g.state.columns.flat().length + g.state.stock.length;
    assert.equal(dealt, cfg.sets * 13 + cfg.wilds, `${difficulty} card count`);
    for (const col of g.state.columns) {
      col.forEach((card, i) => {
        if (i < col.length - 1 && !card.wild) assert.equal(card.faceUp, false);
      });
      if (col.length) assert.equal(col[col.length - 1].faceUp, true);
    }
  }
});

test('the same seed deals the same game', () => {
  const a = new Game({ seed: 'REPEAT' });
  const b = new Game({ seed: 'REPEAT' });
  const flat = (g) => g.state.columns.flat().map((c) => `${c.rank}${c.suit}`).join(',');
  assert.equal(flat(a), flat(b));
});

test('a card moves onto the next rank up regardless of suit', () => {
  const g = rigged([[up(9, 'spade')], [up(8, 'heart')]]);
  assert.equal(g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 }), true);
  assert.equal(g.state.columns[0].length, 2);
  assert.equal(g.state.columns[1].length, 0);
});

test('an illegal rank is refused', () => {
  const g = rigged([[up(9, 'spade')], [up(7, 'heart')]]);
  assert.equal(g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 }), false);
  assert.equal(g.state.columns[1].length, 1);
});

test('only a same-suit run may be lifted as a group', () => {
  const g = rigged([
    [up(9, 'club'), up(8, 'heart')],
    [up(10, 'spade')],
  ]);
  assert.equal(g.canGrab(0, 2), false);
  assert.equal(g.move({ zone: 'col', index: 0, count: 2 }, { zone: 'col', index: 1 }), false);
});

test('Severed Gravity lifts mixed-suit runs', () => {
  const g = rigged([
    [up(9, 'club'), up(8, 'heart')],
    [up(10, 'spade')],
  ], { boons: { void: 3 } });
  assert.equal(g.canGrab(0, 2), true);
  assert.equal(g.move({ zone: 'col', index: 0, count: 2 }, { zone: 'col', index: 1 }), true);
  assert.equal(g.state.columns[1].length, 3);
});

test('moving a whole column into an empty one is refused', () => {
  const g = rigged([[up(9, 'spade')], []]);
  assert.equal(g.move({ zone: 'col', index: 0, count: 1 }, { zone: 'col', index: 1 }), false);
});

test('the card under a lifted run is turned face up', () => {
  const g = rigged([[makeCard(4, 'heart', false), up(8, 'club')], [up(9, 'spade')]]);
  g.move({ zone: 'col', index: 0, count: 1 }, { zone: 'col', index: 1 });
  assert.equal(g.state.columns[0][0].faceUp, true);
});

test('completing K-A seals a meridian and clears the column', () => {
  const col = [makeCard(6, 'heart', false)];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]]);
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  assert.equal(g.state.totalMeridians, 1);
  assert.equal(g.state.columns[0].length, 1);
  assert.equal(g.state.columns[0][0].faceUp, true);
});

test('sealing the required meridian triggers a breakthrough with three boons', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]]);
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  assert.equal(g.state.phase, 'breakthrough');
  assert.equal(g.state.offer.length, 3);
  assert.equal(new Set(g.state.offer.map((o) => o.key)).size, 3);
});

test('choosing a boon opens the next realm and raises the demand', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]]);
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  const boon = g.state.offer[0];
  g.chooseBoon(0);
  assert.equal(g.state.realm, 2);
  assert.equal(g.state.required, 2);
  assert.equal(g.state.meridians, 0);
  assert.equal(g.state.phase, 'play');
  if (boon.type === 'path') assert.equal(g.state.boons[boon.key], boon.tier);
});

test('each path tier changes the next deal', () => {
  const g = new Game({ seed: 'BOON', difficulty: 'adept' });
  g.state.boons = { expansion: 3, talisman: 2, severance: 1, void: 3 };
  g.state.realm = 4;
  const cfg = g.realmConfig(5);
  assert.equal(cfg.columns, BASE_COLUMNS + 3);
  assert.equal(cfg.wilds, 4);
  assert.equal(cfg.suitCount, DIFFICULTIES.adept.suits[4] - 1);
  g.dealRealm(5);
  assert.equal(g.state.columns.length, BASE_COLUMNS + 3);
  assert.equal(g.state.reserve.length, 2);
  assert.equal(g.state.charges.voidStep, 4);
  assert.ok(g.state.columns.flat().concat(g.state.stock).filter((c) => c.wild).every((c) => c.faceUp));
});

test('Wide Channels leaves one column empty at the deal', () => {
  const g = new Game({ seed: 'WIDE', difficulty: 'adept' });
  g.state.boons = { expansion: 2 };
  g.dealRealm(2);
  assert.equal(g.state.columns.filter((c) => c.length === 0).length, 1);
});

test('the stock deals one card per column, and not over an empty column', () => {
  const g = new Game({ seed: 'STOCK' });
  const before = g.state.stock.length;
  assert.equal(g.deal(), true);
  assert.equal(g.state.stock.length, before - g.state.columns.length);
  assert.ok(g.state.columns.every((c) => c[c.length - 1].faceUp));

  g.state.columns[3] = [];
  assert.equal(g.canDeal(), false);
  assert.equal(g.deal(), false);

  g.state.boons = { expansion: 3 };
  assert.equal(g.canDeal(), true);
});

test('reserve cells hold exactly one card and give it back', () => {
  const g = rigged([[up(4, 'heart'), up(7, 'spade')], [up(8, 'club')]], { reserve: [null] });
  assert.equal(g.move({ zone: 'col', index: 0, count: 1 }, { zone: 'reserve', index: 0 }), true);
  assert.equal(g.state.reserve[0].rank, 7);
  assert.equal(g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'reserve', index: 0 }), false);
  assert.equal(g.move({ zone: 'reserve', index: 0 }, { zone: 'col', index: 1 }), true);
  assert.equal(g.state.reserve[0], null);
  assert.equal(g.state.columns[1].length, 2);
});

test('a void step forces an illegal placement and spends a charge', () => {
  const g = rigged([[up(9, 'spade')], [up(3, 'heart')]], { charges: { voidStep: 1, transmute: 0, awaken: 0 } });
  const from = { zone: 'col', index: 1, count: 1 };
  const to = { zone: 'col', index: 0 };
  assert.equal(g.move(from, to), false);
  assert.equal(g.move(from, to, { force: true }), true);
  assert.equal(g.state.charges.voidStep, 0);
  assert.equal(g.move({ zone: 'col', index: 0, count: 1 }, { zone: 'col', index: 1 }, { force: true }), false);
});

test('transmutation changes a suit and can finish a meridian', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  col.push(up(1, 'heart'));
  const g = rigged([col], { charges: { voidStep: 0, transmute: 1, awaken: 0 } });
  assert.equal(g.state.totalMeridians, 0);
  assert.equal(g.transmute({ zone: 'col', index: 0, cardIndex: 12 }, 'club'), true);
  assert.equal(g.state.totalMeridians, 1);
  assert.equal(g.state.charges.transmute, 0);
});

test('awakening turns a card into a talisman', () => {
  const g = rigged([[up(5, 'heart')]], { charges: { voidStep: 0, transmute: 0, awaken: 1 } });
  assert.equal(g.awaken({ zone: 'col', index: 0 }), true);
  assert.equal(g.state.columns[0][0].wild, true);
  assert.equal(g.awaken({ zone: 'col', index: 0 }), false);
});

test('undo restores the board and is limited per realm', () => {
  const g = new Game({ seed: 'UNDO' });
  const snapshot = JSON.stringify(g.state.columns.map((c) => c.map((x) => x.id)));
  g.deal();
  assert.equal(g.undo(), true);
  assert.equal(JSON.stringify(g.state.columns.map((c) => c.map((x) => x.id))), snapshot);
  assert.equal(g.state.undosLeft, 2);
  g.state.undosLeft = 0;
  g.deal();
  assert.equal(g.undo(), false);
});

test('a dead board with no stock and no moves ends the run', () => {
  const g = rigged([[up(3, 'spade')], [up(3, 'heart')], [up(5, 'club')]]);
  g.settle();
  assert.equal(g.state.phase, 'failed');
  assert.equal(g.isStagnant(), false); // already failed, no longer "play"
});

test('stagnation is reported while a board is still live', () => {
  const g = rigged([[up(3, 'spade')], [up(3, 'heart')]], { reserve: [null] });
  g.settle();
  assert.equal(g.state.phase, 'play', 'an open cell keeps the run alive');
  assert.equal(g.isStagnant(), true);
});

test('clearing the final realm ascends', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]], { realm: REALMS.length, required: 1 });
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  assert.equal(g.state.phase, 'ascended');
  assert.ok(g.score() > 2500);
});

test('autoTarget prefers a same-suit landing spot', () => {
  const g = rigged([
    [up(7, 'club')],
    [up(8, 'heart')],
    [up(8, 'club')],
    [],
  ]);
  assert.equal(g.autoTarget(0, 1), 2);
  g.state.columns[2] = [up(2, 'spade')];
  assert.equal(g.autoTarget(0, 1), 1);
  g.state.columns[1] = [up(2, 'spade')];
  assert.equal(g.autoTarget(0, 1), null); // whole column into an empty one is pointless
  g.state.columns[0] = [up(4, 'diamond'), up(7, 'club')];
  assert.equal(g.autoTarget(0, 1), 3);
});

test('a full run of every realm is reachable with the right cards', () => {
  // Drive the machine through all six realms to prove the loop closes.
  const g = new Game({ seed: 'FULL' });
  for (let realm = 1; realm <= REALMS.length; realm += 1) {
    assert.equal(g.state.realm, realm);
    while (g.state.meridians < g.state.required) {
      const col = [];
      for (let r = 13; r >= 1; r--) col.push(up(r, 'club'));
      g.state.columns[0] = col;
      g.settle();
    }
    if (realm < REALMS.length) {
      assert.equal(g.state.phase, 'breakthrough');
      g.chooseBoon(0);
    }
  }
  assert.equal(g.state.phase, 'ascended');
  assert.equal(g.state.totalMeridians, 1 + 2 + 3 + 4 + 5 + 6);
});
