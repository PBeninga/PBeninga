// What survives a run: the daily seed, the streak, and the log of past climbs.
// Pure functions over a store, so the same code runs in a test with a plain
// object and in the browser against localStorage.
//
// Flat export names on purpose: the release build inlines these modules into
// one scope, where a namespace import has nowhere to live.

const HISTORY_KEY = 'ascendant/history';
const DAILY_KEY = 'ascendant/daily';

/** How many past runs are kept. Enough for a record screen, not a database. */
export const HISTORY_LIMIT = 60;

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** The day, in UTC, so everyone is on the same board at the same time. */
export function dayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

/** The seed everyone gets today. Deterministic, and readable when typed back. */
export function dailySeed(date = new Date()) {
  return 'DAILY' + dayKey(date).replace(/-/g, '');
}

export function dayLabel(key) {
  const [y, m, d] = key.split('-').map(Number);
  return `${MONTHS[m - 1]} ${d}`;
}

/** The day before `key`, as a key. */
export function previousDay(key) {
  const t = Date.parse(key + 'T00:00:00Z') - 86_400_000;
  return new Date(t).toISOString().slice(0, 10);
}

// ------------------------------------------------------------- past runs

function read(store, key, fallback) {
  try {
    const raw = store.get(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : fallback;
  } catch (_) {
    return fallback;
  }
}

function write(store, key, value) {
  try { store.set(key, JSON.stringify(value)); } catch (_) { /* private browsing */ }
}

export function readRuns(store) {
  const runs = read(store, HISTORY_KEY, []);
  return Array.isArray(runs) ? runs : [];
}

/** Record a finished run, newest first. */
export function addRun(store, run) {
  const runs = [run, ...readRuns(store)].slice(0, HISTORY_LIMIT);
  write(store, HISTORY_KEY, runs);
  return runs;
}

/**
 * What the record screen shows. Bests are per difficulty because a Merciless
 * rank 2 is not the same achievement as a Novice rank 2, and averaging them
 * would say nothing about either.
 */
export function summarise(runs) {
  const out = {
    played: runs.length,
    won: runs.filter((r) => r.won).length,
    runes: runs.reduce((n, r) => n + (r.runes || 0), 0),
    moves: runs.reduce((n, r) => n + (r.moves || 0), 0),
    best: 0,
    byDifficulty: {},
  };
  for (const r of runs) {
    if ((r.score || 0) > out.best) out.best = r.score || 0;
    const d = out.byDifficulty[r.difficulty] || (out.byDifficulty[r.difficulty] = {
      played: 0, won: 0, bestRank: 0, bestScore: 0,
    });
    d.played++;
    if (r.won) d.won++;
    if ((r.rank || 0) > d.bestRank) d.bestRank = r.rank || 0;
    if ((r.score || 0) > d.bestScore) d.bestScore = r.score || 0;
  }
  return out;
}

// ----------------------------------------------------------------- daily

export function readDaily(store) {
  const d = read(store, DAILY_KEY, {});
  return {
    streak: Number(d.streak) || 0,
    best: Number(d.best) || 0,
    last: typeof d.last === 'string' ? d.last : null,
    results: d.results && typeof d.results === 'object' ? d.results : {},
  };
}

/** Has today's daily already been played? */
export function playedToday(store, today = dayKey()) {
  return !!readDaily(store).results[today];
}

/**
 * File the result of a daily run.
 *
 * Only the first finish of a day counts. Replaying is allowed -- the board is
 * there, and refusing to deal it again would be prissy -- but it does not
 * rewrite what you got, or the streak would mean nothing.
 */
export function noteDaily(store, result, today = dayKey()) {
  const daily = readDaily(store);
  if (daily.results[today]) return daily;

  daily.results[today] = result;
  daily.streak = daily.last === previousDay(today) ? daily.streak + 1 : 1;
  daily.last = today;
  if (daily.streak > daily.best) daily.best = daily.streak;
  // Yesterday and today are all a streak needs; the rest is for the record
  // screen, and sixty days of it is plenty.
  const keys = Object.keys(daily.results).sort().slice(-HISTORY_LIMIT);
  daily.results = Object.fromEntries(keys.map((k) => [k, daily.results[k]]));
  write(store, DAILY_KEY, daily);
  return daily;
}

/**
 * The result as something worth pasting somewhere. Six pips, one per rank:
 * filled for cleared, half for the one you died on, empty for what you never
 * saw. It gives away nothing about the board.
 */
export function shareText(result, ranks = 6) {
  const cleared = result.won ? ranks : Math.max(0, result.rank - 1);
  const pips = [];
  for (let i = 0; i < ranks; i++) {
    pips.push(i < cleared ? '🟨' : (i === cleared && !result.won ? '🟦' : '⬜'));
  }
  const head = result.daily
    ? `Ascendant — Daily ${dayLabel(result.daily)}`
    : `Ascendant — ${result.difficulty || 'adept'}`;
  const line = result.won
    ? `Immortal · ${result.runes} runes · ${result.score}`
    : `${result.rankName} · ${result.runes} runes · ${result.score}`;
  return `${head}\n${pips.join('')}\n${line}`;
}
