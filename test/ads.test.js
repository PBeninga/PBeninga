import test from 'node:test';
import assert from 'node:assert/strict';
import * as ads from '../src/ads.js';
import { LOSSES_PER_BREAK, BREAK_COOLDOWN_MS } from '../src/ads.js';

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed));
  return {
    get: (k) => (map.has(k) ? map.get(k) : null),
    set: (k, v) => map.set(k, v),
    dump: () => Object.fromEntries(map),
  };
}

/** A provider that says yes to everything and counts what it was asked for. */
function fakeProvider(answers = {}) {
  const calls = { interstitial: 0, rewarded: [], purchase: [], restore: 0 };
  return {
    calls,
    interstitial: async () => { calls.interstitial++; },
    rewarded: async (kind) => { calls.rewarded.push(kind); return answers.rewarded !== false; },
    purchase: async (p) => { calls.purchase.push(p); return answers.purchase !== false; },
    restore: async () => { calls.restore++; return answers.restore === true; },
  };
}

test('with no provider attached nothing is offered and nothing runs', async () => {
  ads.adsReset();
  await ads.adsInit({ store: fakeStore() });
  assert.equal(ads.adsReady(), false, 'no ad interface is drawn on the web');
  assert.equal(ads.canReward('reprieve'), false);
  assert.equal(await ads.playReward('reprieve'), false);
  assert.equal(await ads.lossBreak(), false);
  assert.equal(await ads.buyPremium(), false);
  assert.equal(await ads.restorePremium(), false);
});

test('a reward is only earned when the ad runs to the end', async () => {
  ads.adsReset();
  const yes = fakeProvider();
  await ads.adsInit({ provider: yes, store: fakeStore() });
  assert.equal(ads.adsReady(), true);
  assert.equal(await ads.playReward('undo'), true);
  assert.deepEqual(yes.calls.rewarded, ['undo']);

  ads.adsReset();
  const no = fakeProvider({ rewarded: false });
  await ads.adsInit({ provider: no, store: fakeStore() });
  assert.equal(await ads.playReward('undo'), false, 'a dismissed ad grants nothing');
});

test('an unknown reward is never asked for', async () => {
  ads.adsReset();
  const p = fakeProvider();
  await ads.adsInit({ provider: p, store: fakeStore() });
  assert.equal(ads.canReward('free_win'), false);
  assert.equal(await ads.playReward('free_win'), false);
  assert.equal(p.calls.rewarded.length, 0);
});

test('a provider that throws is a decline, never an error', async () => {
  ads.adsReset();
  await ads.adsInit({
    provider: {
      rewarded: async () => { throw new Error('no fill'); },
      interstitial: async () => { throw new Error('no fill'); },
      purchase: async () => { throw new Error('store down'); },
    },
    store: fakeStore(),
  });
  assert.equal(await ads.playReward('undo'), false);
  assert.equal(await ads.buyPremium(), false);
  for (let i = 0; i < LOSSES_PER_BREAK; i++) assert.equal(await ads.lossBreak(), false);
});

test('forced breaks come every few losses, never on the first', async () => {
  ads.adsReset();
  const p = fakeProvider();
  let now = 0;
  await ads.adsInit({ provider: p, store: fakeStore(), now: () => now });

  const seen = [];
  for (let loss = 1; loss <= LOSSES_PER_BREAK * 2; loss++) {
    now += BREAK_COOLDOWN_MS + 1;         // plenty of time between runs
    seen.push(await ads.lossBreak());
  }
  assert.equal(seen[0], false, 'the first loss of a session is never interrupted');
  assert.equal(seen[LOSSES_PER_BREAK - 1], true);
  assert.equal(seen[LOSSES_PER_BREAK * 2 - 1], true);
  assert.equal(p.calls.interstitial, 2, `two breaks in ${LOSSES_PER_BREAK * 2} losses`);
});

test('a break never follows hard on the last one, however fast runs end', async () => {
  ads.adsReset();
  const p = fakeProvider();
  let now = 1_000_000;
  await ads.adsInit({ provider: p, store: fakeStore(), now: () => now });
  for (let i = 0; i < LOSSES_PER_BREAK; i++) await ads.lossBreak();
  assert.equal(p.calls.interstitial, 1);

  now += BREAK_COOLDOWN_MS - 1;           // a flurry of instant losses
  for (let i = 0; i < LOSSES_PER_BREAK; i++) await ads.lossBreak();
  assert.equal(p.calls.interstitial, 1, 'the cooldown held');

  now += BREAK_COOLDOWN_MS + 1;
  for (let i = 0; i < LOSSES_PER_BREAK; i++) await ads.lossBreak();
  assert.equal(p.calls.interstitial, 2);
});

test('the loss tally survives a restart, so a break is not dodged by quitting', async () => {
  ads.adsReset();
  const store = fakeStore();
  await ads.adsInit({ provider: fakeProvider(), store });
  await ads.lossBreak();
  ads.adsReset();

  const p = fakeProvider();
  await ads.adsInit({ provider: p, store });
  for (let i = 0; i < LOSSES_PER_BREAK - 1; i++) await ads.lossBreak();
  assert.equal(p.calls.interstitial, 1, 'the count carried over');
});

test('buying premium stops forced breaks for good, rewards included', async () => {
  ads.adsReset();
  const p = fakeProvider();
  const store = fakeStore();
  let now = 0;
  await ads.adsInit({ provider: p, store, now: () => now });
  assert.equal(ads.adsPremium(), false);
  assert.equal(await ads.buyPremium(), true);
  assert.equal(ads.adsPremium(), true);

  for (let i = 0; i < LOSSES_PER_BREAK * 2; i++) {
    now += BREAK_COOLDOWN_MS + 1;
    assert.equal(await ads.lossBreak(), false);
  }
  assert.equal(p.calls.interstitial, 0, 'a paying player is never interrupted');
  assert.equal(await ads.playReward('undo'), true, 'but rewards are still theirs to take');

  // And it is remembered.
  ads.adsReset();
  await ads.adsInit({ provider: fakeProvider(), store });
  assert.equal(ads.adsPremium(), true);
});

test('a failed purchase does not hand out the goods', async () => {
  ads.adsReset();
  const store = fakeStore();
  await ads.adsInit({ provider: fakeProvider({ purchase: false }), store });
  assert.equal(await ads.buyPremium(), false);
  assert.equal(ads.adsPremium(), false);
  assert.equal(store.dump()['ascendant.premium.v1'], undefined);
});

test('restoring a purchase made elsewhere brings premium back', async () => {
  ads.adsReset();
  await ads.adsInit({ provider: fakeProvider({ restore: true }), store: fakeStore() });
  assert.equal(ads.adsPremium(), false);
  assert.equal(await ads.restorePremium(), true);
  assert.equal(ads.adsPremium(), true);
});
