# Shipping Ascendant as an iOS and Android app

The game is one self-contained HTML file with no dependencies, no network calls
and no server. Everything below is the shell around it.

**What is already done in this repo:** the monetization logic (`src/ads.js`),
the reward hooks in the game (`Game.reprieve`, `Game.grantUndo`), the interface
that appears only when a host is attached, the native bridge
(`mobile/bridge.js`), the Capacitor config, and a `dist/www/` build target.
All of it is covered by `npm test` and `npm run test:browser`.

**What is not done, and cannot be done from a Linux container:** installing the
Capacitor CLI, generating the `ios/` and `android/` projects, compiling, and
signing. Those need a Mac with Xcode (iOS) and Android Studio (Android). The
bridge is written against the plugin APIs named below but has never been run.

---

## 1. Scaffold (once)

```sh
npm i @capacitor/core @capacitor/app @capacitor/preferences @capacitor-community/admob
npm i -D @capacitor/cli @capacitor/assets
cp mobile/capacitor.config.json .
npm run build            # writes dist/www/index.html
npx cap add ios          # Mac only
npx cap add android
```

`capacitor.config.json` points `webDir` at `dist/www`, so the app bundles the
exact file the web build serves.

The bridge needs to be loaded by the page in the native build only. The simplest
route is a tiny entry that Capacitor bundles:

```sh
# esbuild is the least invasive bundler for one file
npx esbuild mobile/bridge.js --bundle --format=iife --outfile=dist/www/bridge.js
# then add <script src="bridge.js"></script> to dist/www/index.html
```

Wire that into `build.js` once it works, rather than editing `dist/` by hand.

## 2. Icons and splash

Put a 1024×1024 PNG at `resources/icon.png` and a 2732×2732 at
`resources/splash.png`, then:

```sh
npx capacitor-assets generate
```

The core against the dark ground is the obvious icon.

## 3. Ad units

`mobile/bridge.js` ships with Google's public test unit IDs and uses them until
you fill in `REAL`. Create an AdMob account, add both apps, create one
interstitial and one rewarded unit per platform, and paste the four IDs into
`REAL`. Shipping the test IDs live is a policy violation against your own
AdMob account, so make it a release check.

Also required by AdMob:

- `GADApplicationIdentifier` in `ios/App/App/Info.plist`
- `com.google.android.gms.ads.APPLICATION_ID` in `AndroidManifest.xml`
- `NSUserTrackingUsageDescription` in `Info.plist` if you want personalised ads
  on iOS. Most players decline; non-personalised still pays, just less.

## 4. Purchases

`provider.purchase` and `provider.restore` in the bridge return `false`, so the
pause screen draws no shop until you wire a store plugin. For a solo developer
RevenueCat (`@revenuecat/purchases-capacitor`) is the least painful: it handles
both stores, receipt validation and restore-across-devices behind one call.
Create a non-consumable product `remove_ads` in both stores, then have
`purchase` return whether the entitlement is now active.

The premium flag is cached in native Preferences, but the store is the source
of truth — that is what **Restore** is for, and why it is on the pause screen.

## 5. Store accounts and review

| | Apple | Google |
|---|---|---|
| Account | $99/year | $25 once |
| Build machine | Mac + Xcode required | any |
| Review | typically 1–3 days | hours to days |

Both stores need: app name, description, an age rating questionnaire, a privacy
policy URL (required once ads are in), and screenshots at several sizes — the
Playwright suite already renders the game on iPhone, Pixel and iPad, so
`node test/browser.mjs --shots ./shots` is most of that work.

**Privacy answers change once ads exist.** Without ads the game collects
nothing. With AdMob you declare device identifiers and advertising data on
both stores, and Apple wants a privacy manifest — the AdMob SDK ships its own,
but yours must declare it too.

**Apple guideline 4.2** rejects apps that are a wrapper around a website. This
one bundles the game locally and runs offline, which is the distinction that
matters; do not switch the config to load a remote URL.

## 6. What the player actually sees

| Surface | When | Capped by |
|---|---|---|
| Rewarded — Second wind | The run has ended, on the loss screen | once per rank (`REPRIEVES_PER_RANK`) |
| Rewarded — One more undo | Undo is empty and there is a move to take back | 3 per rank (`EXTRA_UNDOS_PER_RANK`) |
| Interstitial | Leaving the loss screen | every 3rd loss, min 90s apart, never the first |
| Remove ads | Pause screen | — |

There is deliberately **no banner**. A banner would have to sit on the dock,
which is the one part of the layout with no room to give, and it earns a small
fraction of what the rewarded ads do.

The caps live in the engine, not in the ad layer, so an ad network cannot lift
them — and `undo()` carries the granted-reward ledger across a restore, so a
reward cannot be undone and re-earned.
