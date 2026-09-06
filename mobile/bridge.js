// The native half of the monetization boundary.
//
// This file runs only inside the Capacitor app. It builds the provider object
// `src/ads.js` expects -- interstitial / rewarded / purchase / restore -- and
// hands it to the game, along with a key-value store that survives a reinstall
// better than localStorage does. On the web this file is never loaded, which is
// why the browser build has no ad code in it at all.
//
// It is deliberately defensive: every ad path resolves rather than throws, and
// a plugin that is missing simply switches its surface off. A game that will
// not start because an ad network is down is worth less than the ads.

import { AdMob, BannerAdPosition, BannerAdSize } from '@capacitor-community/admob';
import { App } from '@capacitor/app';
import { Preferences } from '@capacitor/preferences';
import { Capacitor } from '@capacitor/core';

// Google's public test units. They always fill and they never earn a cent --
// swap in your own before shipping, and check Google's current test-ad page if
// a test ad fails to appear. Shipping with these live is a policy violation on
// your own account, so treat REAL_IDS below as a release checklist item.
const TEST = {
  ios: { interstitial: 'ca-app-pub-3940256099942544/4411468910', rewarded: 'ca-app-pub-3940256099942544/1712485313' },
  android: { interstitial: 'ca-app-pub-3940256099942544/1033173712', rewarded: 'ca-app-pub-3940256099942544/5224354917' },
};
const REAL = {
  ios: { interstitial: '', rewarded: '' },
  android: { interstitial: '', rewarded: '' },
};

const platform = Capacitor.getPlatform() === 'ios' ? 'ios' : 'android';
const live = REAL[platform].interstitial && REAL[platform].rewarded;
const UNITS = live ? REAL[platform] : TEST[platform];

/** Native key-value storage, so a purchase is not lost with the web cache. */
const store = {
  async get(key) { return (await Preferences.get({ key })).value; },
  async set(key, value) { await Preferences.set({ key, value }); },
};

async function startAdMob() {
  await AdMob.initialize({ initializeForTesting: !live });
  // Consent, where it is required. Without a form the SDK serves
  // non-personalised ads, which is the correct fallback rather than an error.
  try {
    const info = await AdMob.requestConsentInfo();
    if (info.isConsentFormAvailable && info.status === 'REQUIRED') await AdMob.showConsentForm();
  } catch (_) { /* no form, no consent needed, or offline */ }
  // iOS only, and only after consent: asking before the player has seen the
  // game is the fastest way to be denied.
  if (platform === 'ios') {
    try { await AdMob.trackingAuthorizationStatus(); } catch (_) { /* pre-iOS 14 */ }
  }
}

const provider = {
  async interstitial() {
    if (!UNITS.interstitial) return;
    await AdMob.prepareInterstitial({ adId: UNITS.interstitial });
    await AdMob.showInterstitial();
  },

  /**
   * Resolves true only when the player watched to the reward. A dismissed ad
   * resolves false, and so does a failure to load -- the game then simply does
   * not grant the reward, and says so.
   */
  async rewarded(kind) {
    if (!UNITS.rewarded) return false;
    await AdMob.prepareRewardVideoAd({ adId: UNITS.rewarded });
    const item = await AdMob.showRewardVideoAd();
    return !!(item && (item.amount > 0 || item.type));
  },

  // Purchases go through a store plugin. Wire whichever you set up -- the game
  // only needs a boolean back. Until then there is nothing to sell, and the
  // pause screen simply does not draw a shop.
  async purchase(_product) { return false; },
  async restore() { return false; },
};

/**
 * Android's back button, which otherwise quits the app mid-run. An overlay
 * closes, a live board pauses, and only the title screen exits.
 */
function bindBackButton() {
  App.addListener('backButton', () => {
    const overlay = document.querySelector('#overlay');
    const playing = window.Ascendant && window.Ascendant.game;
    if (overlay && !overlay.hidden) {
      if (playing) { overlay.hidden = true; window.Ascendant.render(); }
      return;
    }
    if (playing) { document.querySelector('#btn-menu').click(); return; }
    App.exitApp();
  });
}

export async function startNative() {
  bindBackButton();
  try { await startAdMob(); } catch (_) { /* ads off, game on */ }
  // The game reads this on boot; attachAds also works after boot, which is what
  // this call uses so the SDK's start-up never delays the first frame.
  await window.Ascendant.attachAds(provider, store);
}

if (Capacitor.isNativePlatform()) {
  if (window.Ascendant) startNative();
  else window.addEventListener('DOMContentLoaded', startNative);
}
