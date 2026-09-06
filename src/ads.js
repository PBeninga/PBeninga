// The monetization boundary. Nothing in here knows what an ad network is: a
// host attaches a `provider` and this module decides when to ask it for
// something. Without a provider every call resolves to "no", so the web build
// and the tests run exactly as they did before ads existed.
//
// Three surfaces, in order of how much they are worth and how much they cost
// the player:
//
//   reward       opt-in. The player asks for it, at the moment they want it.
//   interstitial forced, and therefore rationed -- see the cap below.
//   premium      a one-off purchase that switches the interstitial off for good.
//
// Rewards are never rationed by us: if a player wants to watch ten ads for ten
// undos that is between them and the network's own fill limits. What is capped
// is the reward's effect on the game, and that cap lives in the engine.

/** Losses between forced breaks. The first loss of a session is never one. */
export const LOSSES_PER_BREAK = 3;
/** No forced break within this long of the last one, whatever the count says. */
export const BREAK_COOLDOWN_MS = 90_000;

export const REWARDS = {
  reprieve: { key: 'reprieve', label: 'Second wind', blurb: 'A wildcard and an undo.' },
  undo: { key: 'undo', label: 'One more undo', blurb: 'Take back one more move this rank.' },
};

const PREMIUM_KEY = 'ascendant.premium.v1';
const TALLY_KEY = 'ascendant.breaks.v1';

// Every export is flat-named on purpose: the release build inlines these
// modules into one scope, where a namespace import has nowhere to live.
//
// A store is anything with get/set. localStorage satisfies it; so does the
// native key-value store a wrapper hands us, and so does a plain object in a
// test.
const memoryStore = () => {
  const map = new Map();
  return { get: (k) => (map.has(k) ? map.get(k) : null), set: (k, v) => map.set(k, v) };
};

let provider = null;
let store = memoryStore();
let clock = () => Date.now();
let premium = false;
let losses = 0;
let lastBreak = 0;

/**
 * Attach a host. `provider` is null on the web and an object natively:
 *
 *   interstitial()      -> Promise, resolves when the ad is done or fails
 *   rewarded(kind)      -> Promise<boolean>, true only if it ran to the end
 *   purchase(product)   -> Promise<boolean>
 *   restore()           -> Promise<boolean>
 *
 * Any of them may be missing; a missing one simply means that surface is off.
 */
export async function adsInit({ provider: p = null, store: s, now } = {}) {
  provider = p;
  if (s) store = s;
  if (now) clock = now;
  premium = (await store.get(PREMIUM_KEY)) === '1';
  const tally = Number(await store.get(TALLY_KEY)) || 0;
  losses = tally;
  lastBreak = 0;
  return { provider: !!provider, premium };
}

/** Is there anything to show at all? False on the web, so no ad UI is drawn. */
export function adsReady() { return !!provider; }
export function adsPremium() { return premium; }

/** Can this reward be offered right now? */
export function canReward(kind) {
  return !!(provider && provider.rewarded && REWARDS[kind]);
}

/**
 * Play a rewarded ad for `kind`. Resolves true only when the player actually
 * earned it -- a dismissed, failed or unavailable ad grants nothing, and a
 * network that throws is treated as a decline rather than an error, because a
 * broken ad must never break the game.
 */
export async function playReward(kind) {
  if (!canReward(kind)) return false;
  try {
    return (await provider.rewarded(kind)) === true;
  } catch {
    return false;
  }
}

/**
 * A run just ended. Show a forced break if one is due, and report whether one
 * ran. Premium players are never interrupted; neither is a first loss, nor one
 * that follows too closely on the last break.
 */
export async function lossBreak() {
  losses++;
  await store.set(TALLY_KEY, String(losses));
  if (premium || !provider || !provider.interstitial) return false;
  if (losses % LOSSES_PER_BREAK !== 0) return false;
  const now = clock();
  if (lastBreak && now - lastBreak < BREAK_COOLDOWN_MS) return false;
  lastBreak = now;
  try {
    await provider.interstitial();
    return true;
  } catch {
    return false;
  }
}

/** Buy the ad-free version. Resolves true if the player now owns it. */
export async function buyPremium(product = 'remove_ads') {
  if (!provider || !provider.purchase) return false;
  let ok = false;
  try { ok = (await provider.purchase(product)) === true; } catch { ok = false; }
  if (ok) { premium = true; await store.set(PREMIUM_KEY, '1'); }
  return ok;
}

/** Re-check a purchase made on another device, or before a reinstall. */
export async function restorePremium() {
  if (!provider || !provider.restore) return false;
  let ok = false;
  try { ok = (await provider.restore()) === true; } catch { ok = false; }
  if (ok) { premium = true; await store.set(PREMIUM_KEY, '1'); }
  return ok;
}

/** Test seam: forget everything learned this session. */
export function adsReset() {
  provider = null;
  store = memoryStore();
  clock = () => Date.now();
  premium = false;
  losses = 0;
  lastBreak = 0;
}
