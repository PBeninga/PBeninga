import test from 'node:test';
import assert from 'node:assert/strict';
import { soundSetup, soundOn, setSoundOn, playSound, buzz, setBuzzer, soundReset } from '../src/sound.js';

const store = (seed = {}) => {
  const map = new Map(Object.entries(seed));
  return { get: (k) => (map.has(k) ? map.get(k) : null), set: (k, v) => map.set(k, v), dump: () => Object.fromEntries(map) };
};

test('sound is on until it is turned off, and the choice is remembered', () => {
  soundReset();
  const s = store();
  assert.equal(soundSetup(s), true);
  setSoundOn(false);
  assert.equal(soundOn(), false);
  assert.equal(s.dump()['ascendant/sound'], 'off');

  soundReset();
  assert.equal(soundSetup(s), false, 'it comes back off');
  setSoundOn(true);
  soundReset();
  assert.equal(soundSetup(s), true);
});

test('with no audio available nothing plays and nothing throws', () => {
  // Node has no window and no AudioContext: exactly the hostile case.
  soundReset();
  soundSetup(store());
  assert.equal(playSound('seal'), false);
  assert.equal(playSound('nonexistent'), false);
});

test('a storage that throws does not stop the game starting', () => {
  soundReset();
  const blind = { get() { throw new Error('blocked'); }, set() { throw new Error('blocked'); } };
  assert.doesNotThrow(() => soundSetup(blind));
  assert.doesNotThrow(() => setSoundOn(false));
});

test('haptics go through the host when it supplies one', () => {
  soundReset();
  soundSetup(store());
  const felt = [];
  setBuzzer((p) => felt.push(p));
  assert.equal(buzz(25), true);
  assert.deepEqual(felt, [25]);

  setSoundOn(false);
  assert.equal(buzz(25), false, 'muted means muted, including the buzz');
  assert.equal(felt.length, 1);
});

test('a host buzzer that throws is silence, not a crash', () => {
  soundReset();
  soundSetup(store());
  setBuzzer(() => { throw new Error('no motor'); });
  assert.equal(buzz(), false);
});
