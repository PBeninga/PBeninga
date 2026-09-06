// Sound, synthesised rather than sampled: the whole game ships as one HTML
// file, and a handful of oscillators cost nothing next to a folder of audio.
//
// Everything here is best-effort. A browser that refuses an AudioContext, a
// device with no vibrator, a player who has muted the tab -- all of it comes
// back as silence, never as an error.

const KEY = 'ascendant/sound';

let ctx = null;
let on = true;
let store = null;

/** Read the saved preference. Sound is on unless the player turned it off. */
export function soundSetup(s) {
  store = s;
  try { on = store.get(KEY) !== 'off'; } catch (_) { on = true; }
  return on;
}

export function soundOn() { return on; }

export function setSoundOn(next) {
  on = !!next;
  try { if (store) store.set(KEY, on ? 'on' : 'off'); } catch (_) { /* private browsing */ }
  if (on) resume();
  return on;
}

/**
 * An AudioContext may only be built inside a gesture, and starts suspended if
 * it was built too early, so every entry point tries to wake it.
 */
function audio() {
  if (!on) return null;
  try {
    if (!ctx) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      if (!Ctor) return null;
      ctx = new Ctor();
    }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  } catch (_) {
    return null;
  }
}

function resume() { audio(); }

/** One shaped tone. Everything in the game is built out of these. */
function tone(ac, { freq, to = freq, type = 'sine', at = 0, len = 0.12, gain = 0.05 }) {
  const osc = ac.createOscillator();
  const amp = ac.createGain();
  const t0 = ac.currentTime + at;
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  if (to !== freq) osc.frequency.exponentialRampToValueAtTime(Math.max(1, to), t0 + len);
  // A quick rise and a soft tail: a click with no attack reads as a pop.
  amp.gain.setValueAtTime(0.0001, t0);
  amp.gain.exponentialRampToValueAtTime(gain, t0 + 0.012);
  amp.gain.exponentialRampToValueAtTime(0.0001, t0 + len);
  osc.connect(amp).connect(ac.destination);
  osc.start(t0);
  osc.stop(t0 + len + 0.02);
}

const VOICES = {
  // A card landing: short, woody, no pitch to speak of.
  move: (ac) => tone(ac, { freq: 420, to: 240, type: 'triangle', len: 0.08, gain: 0.045 }),
  // Picking one up, an octave under the landing so the pair reads as a gesture.
  lift: (ac) => tone(ac, { freq: 260, to: 320, type: 'triangle', len: 0.05, gain: 0.03 }),
  // A row of cards falling, one after another.
  deal: (ac) => {
    for (let i = 0; i < 5; i++) {
      tone(ac, { freq: 300 + i * 18, to: 200, type: 'triangle', at: i * 0.045, len: 0.06, gain: 0.03 });
    }
  },
  // A rune binding: a rising third, the only pleasant sound in the game.
  seal: (ac) => {
    tone(ac, { freq: 523.25, type: 'sine', len: 0.5, gain: 0.05 });
    tone(ac, { freq: 659.25, type: 'sine', at: 0.09, len: 0.5, gain: 0.045 });
    tone(ac, { freq: 783.99, type: 'sine', at: 0.18, len: 0.6, gain: 0.04 });
  },
  // The core going up at the end of a rank.
  burst: (ac) => {
    tone(ac, { freq: 180, to: 40, type: 'sawtooth', len: 0.75, gain: 0.07 });
    tone(ac, { freq: 880, to: 220, type: 'sine', at: 0.04, len: 0.6, gain: 0.03 });
  },
  // Something refused.
  deny: (ac) => tone(ac, { freq: 150, to: 110, type: 'square', len: 0.1, gain: 0.025 }),
  // The run ending.
  over: (ac) => {
    tone(ac, { freq: 300, to: 90, type: 'sine', len: 0.9, gain: 0.06 });
    tone(ac, { freq: 200, to: 60, type: 'triangle', at: 0.12, len: 0.9, gain: 0.04 });
  },
};

export function playSound(name) {
  const voice = VOICES[name];
  if (!voice) return false;
  const ac = audio();
  if (!ac) return false;
  try { voice(ac); return true; } catch (_) { return false; }
}

/**
 * A tap the player feels. `navigator.vibrate` covers Android and desktop
 * Chrome; iOS Safari has no equivalent and simply does nothing, which is why
 * the native wrapper hands its own haptics in through `setBuzzer`.
 */
let buzzer = null;
export function setBuzzer(fn) { buzzer = fn; }

export function buzz(pattern = 10) {
  if (!on) return false;
  if (buzzer) { try { buzzer(pattern); return true; } catch (_) { return false; } }
  try { return !!(navigator.vibrate && navigator.vibrate(pattern)); } catch (_) { return false; }
}

/** Test seam. */
export function soundReset() { ctx = null; on = true; store = null; buzzer = null; }
