import test from 'node:test';
import assert from 'node:assert/strict';
import {
  dayKey, dailySeed, dayLabel, previousDay, readRuns, addRun, summarise,
  readDaily, noteDaily, playedToday, shareText, HISTORY_LIMIT,
} from '../src/records.js';

const store = (seed = {}) => {
  const map = new Map(Object.entries(seed));
  return { get: (k) => (map.has(k) ? map.get(k) : null), set: (k, v) => map.set(k, v) };
};
const run = (over = {}) => ({
  day: '2026-09-06', seed: 'X', difficulty: 'adept', rank: 2, rankName: 'Iron',
  runes: 7, moves: 200, score: 950, won: false, ...over,
});

test('the daily seed is the same for everyone on the same day, and only then', () => {
  const a = new Date('2026-09-06T04:35:00Z');
  const b = new Date('2026-09-06T23:59:59Z');
  const c = new Date('2026-09-07T00:00:01Z');
  assert.equal(dailySeed(a), dailySeed(b), 'the whole UTC day is one board');
  assert.notEqual(dailySeed(a), dailySeed(c));
  assert.equal(dailySeed(a), 'DAILY20260906');
  assert.equal(dayLabel(dayKey(a)), 'Sep 6');
});

test('previousDay steps back over month and year ends', () => {
  assert.equal(previousDay('2026-09-06'), '2026-09-05');
  assert.equal(previousDay('2026-09-01'), '2026-08-31');
  assert.equal(previousDay('2026-01-01'), '2025-12-31');
  assert.equal(previousDay('2028-03-01'), '2028-02-29', 'leap years included');
});

test('runs are kept newest first and capped', () => {
  const s = store();
  assert.deepEqual(readRuns(s), []);
  for (let i = 0; i < HISTORY_LIMIT + 12; i++) addRun(s, run({ score: i }));
  const runs = readRuns(s);
  assert.equal(runs.length, HISTORY_LIMIT);
  assert.equal(runs[0].score, HISTORY_LIMIT + 11, 'newest first');
});

test('a corrupt or missing store reads as empty rather than throwing', () => {
  assert.deepEqual(readRuns(store({ 'ascendant/history': '{not json' })), []);
  assert.deepEqual(readRuns(store({ 'ascendant/history': '"a string"' })), []);
  assert.deepEqual(readDaily(store({ 'ascendant/daily': 'nonsense' })).results, {});
  const blind = { get() { throw new Error('blocked'); }, set() { throw new Error('blocked'); } };
  assert.deepEqual(readRuns(blind), []);
  assert.doesNotThrow(() => addRun(blind, run()));
});

test('bests are kept per difficulty, since the ranks are not comparable', () => {
  const runs = [
    run({ difficulty: 'novice', rank: 4, score: 1800 }),
    run({ difficulty: 'novice', rank: 2, score: 600 }),
    run({ difficulty: 'immortal', rank: 2, score: 900, won: false }),
    run({ difficulty: 'adept', rank: 6, score: 7000, won: true }),
  ];
  const s = summarise(runs);
  assert.equal(s.played, 4);
  assert.equal(s.won, 1);
  assert.equal(s.best, 7000);
  assert.equal(s.runes, 28);
  assert.equal(s.byDifficulty.novice.bestRank, 4);
  assert.equal(s.byDifficulty.novice.played, 2);
  assert.equal(s.byDifficulty.immortal.bestRank, 2);
  assert.equal(s.byDifficulty.adept.won, 1);
});

test('a streak grows on consecutive days and resets after a gap', () => {
  const s = store();
  assert.equal(readDaily(s).streak, 0);
  noteDaily(s, run(), '2026-09-04');
  assert.equal(readDaily(s).streak, 1);
  noteDaily(s, run(), '2026-09-05');
  noteDaily(s, run(), '2026-09-06');
  assert.equal(readDaily(s).streak, 3);
  assert.equal(readDaily(s).best, 3);

  noteDaily(s, run(), '2026-09-08');            // a day missed
  const after = readDaily(s);
  assert.equal(after.streak, 1, 'the streak starts over');
  assert.equal(after.best, 3, 'but the best is remembered');
});

test('replaying a daily does not rewrite the day or the streak', () => {
  const s = store();
  noteDaily(s, run({ score: 500 }), '2026-09-06');
  noteDaily(s, run({ score: 9999 }), '2026-09-06');
  const d = readDaily(s);
  assert.equal(d.results['2026-09-06'].score, 500, 'the first finish is the one that counts');
  assert.equal(d.streak, 1);
  assert.equal(playedToday(s, '2026-09-06'), true);
  assert.equal(playedToday(s, '2026-09-07'), false);
});

test('the share card shows how far you got and nothing about the board', () => {
  const lost = shareText(run({ daily: '2026-09-06', rank: 3, rankName: 'Silver', runes: 12, score: 1400 }));
  assert.match(lost, /Ascendant — Daily Sep 6/);
  assert.match(lost, /Silver · 12 runes · 1400/);
  assert.equal(lost.split('\n')[1], '🟨🟨🟦⬜⬜⬜', 'two ranks cleared, stopped on the third');

  const won = shareText(run({ daily: '2026-09-06', rank: 6, won: true, runes: 41, score: 7850 }));
  assert.equal(won.split('\n')[1], '🟨🟨🟨🟨🟨🟨');
  assert.match(won, /Immortal · 41 runes/);

  const seedless = shareText(run({ rank: 1, rankName: 'Ember' }));
  assert.match(seedless, /Ascendant — adept/);
  assert.ok(!/DAILY|X/.test(seedless.split('\n')[0]), 'no seed is given away');
});
