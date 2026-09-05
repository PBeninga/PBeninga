import test from 'node:test';
import assert from 'node:assert/strict';
import { Game, REALMS, BASE_COLUMNS, DIFFICULTIES, serialize, deserialize } from '../src/engine.js';
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

test('a realm is a whole game: the quota is every sequence in the deck', () => {
  const g = new Game({ seed: 'ABC', difficulty: 'adept' });
  assert.equal(g.state.realm, 1);
  assert.equal(g.state.required, DIFFICULTIES.adept.startSets);
  assert.equal(g.realmConfig(1).sets, g.state.required, 'nothing may be left on the table');
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

test('one sequence is not a breakthrough -- the board has to be cleared', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  // Leave a legal move on the board, or the run ends for want of one.
  const g = rigged([col, [up(1, 'club')], [up(9, 'spade')], [up(8, 'heart')]]);
  assert.equal(g.state.required, DIFFICULTIES.adept.startSets);
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  assert.equal(g.state.totalMeridians, 1);
  assert.equal(g.state.phase, 'play', 'no upgrade after the first K-A');
  assert.deepEqual(g.state.offer, []);
});

test('clearing the last sequence triggers a breakthrough', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]], { required: 1 });
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  assert.equal(g.state.phase, 'breakthrough');
  assert.deepEqual(g.state.offer.map((o) => o.key), ['talisman', 'cell']);
});

test('choosing a boon opens the next realm, one sequence larger', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')]], { required: 1 });
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
  const boon = g.state.offer[0];
  g.chooseBoon(0);
  assert.equal(g.state.realm, 2);
  assert.equal(g.state.required, DIFFICULTIES.adept.startSets + 1);
  assert.equal(g.state.meridians, 0);
  assert.equal(g.state.phase, 'play');
  if (boon.type === 'path') assert.equal(g.state.boons[boon.key], boon.tier);
});

test('the stock deals one card per column, empty ones included', () => {
  const g = new Game({ seed: 'STOCK' });
  const before = g.state.stock.length;
  assert.equal(g.deal(), true);
  assert.equal(g.state.stock.length, before - g.state.columns.length);
  assert.ok(g.state.columns.every((c) => c[c.length - 1].faceUp));

  // Sealing a meridian empties a column; that must not strand the stock.
  g.state.columns[3] = [];
  assert.equal(g.canDeal(), true);
  assert.equal(g.deal(), true);
  assert.equal(g.state.columns[3].length, 1, 'the empty column was dealt into');
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
  const start = DIFFICULTIES.adept.startSets;
  let expected = 0;
  for (let r = 0; r < REALMS.length; r++) expected += start + r;
  assert.equal(g.state.totalMeridians, expected);
});

test('tapping sends a card where it builds the longest run', () => {
  // 6♣ can sit on either 7, but only the club makes a longer sequence.
  const g = rigged([
    [up(9, 'club'), up(8, 'club'), up(7, 'club')],
    [up(7, 'heart')],
    [up(6, 'club')],
  ]);
  assert.equal(g.autoTarget(2, 1), 0);
  assert.deepEqual(
    { ...g.moveScore({ zone: 'col', index: 2, count: 1 }, { zone: 'col', index: 0 }) },
    { resultRun: 4, seals: false, exposes: false, empties: true, destEmpty: false },
  );
});

test('a longer run beats exposing a card, and exposing breaks a tie', () => {
  const long = rigged([
    [up(9, 'club'), up(8, 'club')],
    [up(8, 'heart')],
    [makeCard(2, 'spade', false), up(7, 'club')],
  ]);
  assert.equal(long.autoTarget(2, 1), 0, 'run of three beats flipping a card');

  const tie = rigged([
    [up(8, 'heart')],
    [up(8, 'diamond')],
    [makeCard(2, 'spade', false), up(7, 'club')],
    [up(7, 'spade')],
  ]);
  // Both 8s give a run of one; the tiebreak is whichever exposes -- neither
  // does here, so the first legal destination wins and stays deterministic.
  assert.equal(tie.autoTarget(2, 1), 0);
});

test('a meridian-completing move outranks everything else', () => {
  const nearly = [];
  for (let r = 13; r >= 2; r--) nearly.push(up(r, 'club'));
  const g = rigged([nearly, [up(2, 'heart')], [up(1, 'club')]]);
  assert.equal(g.autoTarget(2, 1), 0);
  const moves = g.listMoves();
  assert.equal(moves[0].to.index, 0);
  assert.equal(moves[0].resultRun, 13);
});

test('an empty column is a last resort, not a first choice', () => {
  const g = rigged([[up(4, 'spade'), up(7, 'club')], [up(8, 'heart')], []]);
  assert.equal(g.autoTarget(0, 1), 1, 'stacking beats burning an empty column');
  const only = rigged([[up(4, 'spade'), up(7, 'club')], [up(2, 'heart')], []]);
  assert.equal(only.autoTarget(0, 1), 2);
});

test('autoTarget returns null when nothing is legal', () => {
  const g = rigged([[up(3, 'spade')], [up(9, 'heart')]]);
  assert.equal(g.autoTarget(0, 1), null);
});

test('listMoves ranks best first and keeps the list short', () => {
  const g = rigged([
    [up(9, 'club'), up(8, 'club')],
    [up(10, 'club')],
    [up(10, 'heart')],
    [up(5, 'spade')],
  ]);
  const moves = g.listMoves();
  assert.ok(moves.length > 1);
  assert.equal(moves[0].from.index, 0);
  assert.equal(moves[0].to.index, 1, 'the same-suit landing comes first');
  assert.equal(moves[0].resultRun, 3);
  for (let i = 1; i < moves.length; i++) {
    assert.equal(Game.better(moves[i], moves[i - 1]), false, 'list must be sorted');
  }
  assert.ok(g.listMoves({ limit: 2 }).length <= 2);
});

test('listMoves offers only one empty column per source', () => {
  const g = rigged([[up(4, 'spade'), up(7, 'club')], [], [], []]);
  const moves = g.listMoves();
  assert.equal(moves.filter((m) => m.destEmpty).length, 1);
});

test('listMoves includes reserve cells and is empty once the run ends', () => {
  const g = rigged([[up(9, 'spade')]], { reserve: [up(8, 'heart')] });
  const moves = g.listMoves();
  assert.equal(moves.length, 1);
  assert.equal(moves[0].from.zone, 'reserve');
  assert.equal(moves[0].to.index, 0);
  g.state.phase = 'failed';
  assert.deepEqual(g.listMoves(), []);
});

test('a saved run round-trips', () => {
  const g = new Game({ seed: 'SAVE', difficulty: 'adept' });
  g.deal();
  const back = deserialize(serialize(g));
  assert.ok(back);
  assert.equal(back.seed, g.seed);
  assert.equal(back.difficulty, g.difficulty);
  assert.equal(back.state.required, g.state.required);
  assert.deepEqual(
    back.state.columns.map((c) => c.map((x) => x.id)),
    g.state.columns.map((c) => c.map((x) => x.id)),
  );
});

test('a save written under the old quota is repaired, not obeyed', () => {
  // Before a realm meant "clear the board", realm 1 asked for a single
  // sequence. Resuming such a save must not break through after one K-A.
  const g = new Game({ seed: 'OLD', difficulty: 'adept' });
  const stale = JSON.parse(serialize(g));
  stale.state.required = 1;
  const back = deserialize(JSON.stringify(stale));
  assert.ok(back);
  assert.equal(back.state.required, g.realmConfig(1).required);
});

test('a save whose cards do not match its realm is discarded', () => {
  const g = new Game({ seed: 'MISMATCH', difficulty: 'adept' });
  const bad = JSON.parse(serialize(g));
  bad.state.stock.pop();                       // a card that cannot be accounted for
  assert.equal(deserialize(JSON.stringify(bad)), null);

  const wrongRealm = JSON.parse(serialize(g));
  wrongRealm.state.realm = 4;                  // a realm-4 deck is much larger
  assert.equal(deserialize(JSON.stringify(wrongRealm)), null);
});

test('a mid-realm save survives sealed meridians and spent stock', () => {
  const g = new Game({ seed: 'MID', difficulty: 'novice' });
  g.state.meridians = 2;
  g.state.totalMeridians = 2;
  for (let n = 0; n < 2 * 13; n++) {           // stand in for two sealed runs
    if (g.state.stock.length) g.state.stock.pop();
    else g.state.columns.find((c) => c.length).pop();
  }
  const back = deserialize(serialize(g));
  assert.ok(back, 'conservation must count sealed cards, not just cards in play');
  assert.equal(back.state.required, g.realmConfig(1).required);
});

test('junk in the save slot is ignored', () => {
  assert.equal(deserialize('not json'), null);
  assert.equal(deserialize('{}'), null);
  assert.equal(deserialize(JSON.stringify({ v: 99, state: {} })), null);
  const g = new Game({ seed: 'BADDIFF' });
  const bad = JSON.parse(serialize(g));
  bad.difficulty = 'nonsense';
  assert.equal(deserialize(JSON.stringify(bad)), null);
});

test('the hint only suggests whole-run moves and meridian seals', () => {
  const g = rigged([
    // A movable run of two: only the pair moving together should be offered.
    [makeCard(2, 'heart', false), up(9, 'club'), up(8, 'club')],
    [up(10, 'club')],
    [up(9, 'heart')],
  ]);
  const s = g.suggest();
  assert.equal(s.kind, 'moves');
  for (const m of s.moves) assert.ok(m.wholeRun || m.seals, 'a run was broken up: ' + JSON.stringify(m));
  // 8♣ alone onto 9♥ is legal, splits the run, and seals nothing -- not offered.
  assert.ok(!s.moves.some((m) => m.from.count === 1 && m.to.index === 2));
  assert.ok(s.moves.some((m) => m.from.count === 2 && m.to.index === 1));
});

test('a meridian seal is offered even though it splits a run', () => {
  const col = [];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  // A♣ sits at the foot of a 3♣-2♣-A♣ run, so lifting it alone splits that run.
  const g = rigged([col, [up(3, 'club'), up(2, 'club'), up(1, 'club')], [up(9, 'heart')]]);
  const s = g.suggest();
  assert.equal(s.kind, 'moves');
  const seal = s.moves.find((m) => m.seals);
  assert.ok(seal, 'the sealing move must be offered');
  assert.equal(seal.wholeRun, false, 'even though it is not a whole run');
  assert.equal(s.moves[0], seal, 'and it must come first');
});

test('with nothing better, the hint points at an empty column', () => {
  const g = rigged([[up(4, 'spade'), up(7, 'club')], [up(2, 'heart')], []]);
  const s = g.suggest();
  assert.equal(s.kind, 'empty');
  assert.ok(s.moves.length);
  assert.ok(s.moves.every((m) => m.destEmpty));
});

test('with no empty column either, the hint says deal', () => {
  const g = rigged([[up(4, 'spade'), up(7, 'club')], [up(2, 'heart')]]);
  g.state.stock = [makeCard(5, 'club'), makeCard(6, 'club')];
  assert.equal(g.suggest().kind, 'deal');
  assert.equal(g.state.phase, 'play');
});

test('no moves, no empty column and no stock ends the run', () => {
  const g = rigged([[up(4, 'spade'), up(7, 'club')], [up(2, 'heart')]]);
  assert.equal(g.suggest().kind, 'over');
  assert.equal(g.hasLegalMove(), false);
  g.settle();
  assert.equal(g.state.phase, 'failed');
});

test('an empty column never stops the stock', () => {
  const g = new Game({ seed: 'BLOCK', difficulty: 'adept' });
  assert.equal(g.dealBlockedReason(), null);
  g.state.columns[3] = [];
  g.state.columns[5] = [];
  assert.equal(g.canDeal(), true);
  assert.equal(g.dealBlockedReason(), null);
  g.state.stock = [];
  assert.equal(g.canDeal(), false);
  assert.match(g.dealBlockedReason(), /spent/);
});


test('both upgrades are offered at every breakthrough, and both repeat', () => {
  const g = new Game({ seed: 'UPGRADE', difficulty: 'adept' });
  const reachBreakthrough = () => {
    g.state.required = g.state.meridians + 1;
    const col = [];
    for (let r = 13; r >= 1; r--) col.push(up(r, 'club'));
    g.state.columns[0] = col;
    g.settle();
  };

  for (let round = 1; round <= 3; round++) {
    reachBreakthrough();
    assert.equal(g.state.phase, 'breakthrough');
    assert.deepEqual(g.state.offer.map((o) => o.key), ['talisman', 'cell']);
    assert.equal(g.state.offer[0].held, round - 1, 'the offer names what you already hold');
    assert.equal(g.state.offer[0].next, round);
    g.chooseBoon(0);                       // always the talismans
  }
  assert.equal(g.state.boons.talisman, 3);
});

test('each Blank Talisman puts two more wilds in the deal', () => {
  const g = new Game({ seed: 'WILDS', difficulty: 'adept' });
  assert.equal(g.realmConfig(1).wilds, 0);
  g.state.boons = { talisman: 1 };
  assert.equal(g.realmConfig(1).wilds, 2);
  g.state.boons = { talisman: 3 };
  assert.equal(g.realmConfig(1).wilds, 6);

  g.dealRealm(2);
  const inPlay = [...g.state.columns.flat(), ...g.state.stock];
  assert.equal(inPlay.filter((c) => c.wild).length, 6);
  assert.equal(inPlay.length, g.realmConfig(2).sets * 13 + 6);
});

test('each Dantian Cell adds one reserve slot, and a slot holds one card', () => {
  const g = new Game({ seed: 'CELLS', difficulty: 'adept' });
  assert.equal(g.state.reserve.length, 0);
  g.state.boons = { cell: 2 };
  g.dealRealm(2);
  assert.equal(g.state.reserve.length, 2);
  assert.ok(g.state.reserve.every((c) => c === null));

  // One card per slot, and no more.
  const col = g.state.columns.find((c) => c.length > 1);
  const first = col[col.length - 1];
  assert.equal(g.move({ zone: 'col', index: g.state.columns.indexOf(col), count: 1 }, { zone: 'reserve', index: 0 }), true);
  assert.equal(g.state.reserve[0], first);
  const other = g.state.columns.find((c) => c.length > 1);
  assert.equal(
    g.move({ zone: 'col', index: g.state.columns.indexOf(other), count: 1 }, { zone: 'reserve', index: 0 }),
    false,
    'a full slot takes no second card',
  );
});

test('a cell that would uncover something keeps the run alive; an idle one does not', () => {
  const withCell = rigged([[makeCard(4, 'spade', false), up(7, 'club')], [up(2, 'heart')]], { reserve: [null] });
  assert.equal(withCell.hasLegalMove(), true);

  const idleCell = rigged(
    [[up(4, 'spade'), up(7, 'club')], [up(2, 'heart'), up(9, 'diamond')]],
    { reserve: [null] },
  );
  assert.equal(idleCell.suggest().kind, 'over');
  assert.equal(idleCell.hasLegalMove(), false);
});

test('the deck grows only by realm and talismans', () => {
  const g = new Game({ seed: 'DECK', difficulty: 'adept' });
  assert.equal(g.realmConfig(1).columns, BASE_COLUMNS);
  g.state.boons = { talisman: 2, cell: 5 };
  const cfg = g.realmConfig(4);
  assert.equal(cfg.columns, BASE_COLUMNS, 'cells do not add columns');
  assert.equal(cfg.wilds, 4);
  assert.equal(cfg.required, cfg.sets);
});

test('sealing records what left the board and where it sat', () => {
  const col = [makeCard(6, 'heart', false)];
  for (let r = 13; r >= 2; r--) col.push(up(r, 'club'));
  const g = rigged([col, [up(1, 'club')], [up(9, 'spade')], [up(8, 'heart')]]);
  g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });

  assert.equal(g.state.lastSealed.length, 1);
  const sealed = g.state.lastSealed[0];
  assert.equal(sealed.column, 0);
  assert.equal(sealed.remaining, 1, 'the face-down card under the run stayed');
  assert.equal(sealed.cards.length, 13);
  assert.equal(sealed.cards[0].rank, 13);
  assert.equal(sealed.cards[12].rank, 1);
  assert.ok(sealed.cards.every((c) => c.suit === 'club'));
});

test('lastSealed is cleared by the next action', () => {
  const g = new Game({ seed: 'SEALED' });
  assert.deepEqual(g.state.lastSealed, []);
  g.deal();
  assert.deepEqual(g.state.lastSealed, []);
});

test('progress runs from nothing to one across a whole climb', () => {
  const g = new Game({ seed: 'PROGRESS', difficulty: 'adept' });
  assert.equal(g.totalSequences(), 4 + 5 + 6 + 7 + 8 + 9);
  assert.equal(g.progress(), 0);
  g.state.totalMeridians = g.totalSequences();
  assert.equal(g.progress(), 1);
  g.state.totalMeridians = 999;
  assert.equal(g.progress(), 1, 'and never past it');

  const novice = new Game({ seed: 'PROGRESS', difficulty: 'novice' });
  assert.equal(novice.totalSequences(), 3 + 4 + 5 + 6 + 7 + 8);
});
