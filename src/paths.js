// The four cultivation paths. Each breakthrough offers a choice of the next
// tier along three of them; taking a tier is permanent for the rest of the run.

export const PATHS = [
  {
    key: 'talisman',
    name: 'Path of Talismans',
    hanzi: '靈符',
    blurb: 'Chaos talismans that stand in for any card.',
    tiers: [
      { name: 'Blank Talisman', desc: '+2 wild talismans shuffled into every deal. A talisman fills any gap in a sequence.' },
      { name: 'Talisman Scripture', desc: '+2 more talismans (4 total), and they are always dealt face up.' },
      { name: 'Grand Talisman Array', desc: '+2 more talismans (6 total). Once per realm, awaken a face-up card into a talisman.' },
    ],
  },
  {
    key: 'severance',
    name: 'Path of Severance',
    hanzi: '斬道',
    blurb: 'Cut away whole suits until only one dao remains.',
    tiers: [
      { name: 'Sever One Dao', desc: 'Every future deal uses one fewer suit.' },
      { name: 'Transmutation', desc: 'Twice per realm, change one face-up card to any suit.' },
      { name: 'Dao of Unity', desc: 'One fewer suit again, and +1 transmutation each realm.' },
    ],
  },
  {
    key: 'void',
    name: 'Path of the Void',
    hanzi: '虛步',
    blurb: 'Set cards down where the dao says you may not.',
    tiers: [
      { name: 'Dantian Cell', desc: '+1 reserve cell. A cell holds one card outside the tableau.' },
      { name: 'Void Step', desc: 'Twice per realm, place any card onto any card, ignoring rank.' },
      { name: 'Severed Gravity', desc: '+1 cell, +2 void steps, and you may move descending runs of mixed suit.' },
    ],
  },
  {
    key: 'expansion',
    name: 'Path of Expansion',
    hanzi: '開脈',
    blurb: 'Open new meridians for the qi to run through.',
    tiers: [
      { name: 'Open Meridian', desc: '+1 tableau column.' },
      { name: 'Wide Channels', desc: '+1 column, and every realm begins with one column left empty.' },
      { name: 'Boundless Field', desc: '+1 column, and you may draw from the stock even with empty columns.' },
    ],
  },
];

export const PATH_BY_KEY = Object.fromEntries(PATHS.map((p) => [p.key, p]));

// Always-available filler, so there is a choice even once paths are maxed.
export const FORTUNE = {
  key: 'fortune',
  name: 'Heavenly Fortune',
  hanzi: '天緣',
  desc: 'The next realm demands one fewer meridian (never below one).',
};

/** Boons on offer at a breakthrough: the next unclaimed tier of three paths. */
export function offerBoons(boons, rng, count = 3) {
  const available = PATHS.filter((p) => (boons[p.key] || 0) < p.tiers.length).map((p) => ({
    type: 'path',
    key: p.key,
    tier: (boons[p.key] || 0) + 1,
    name: p.tiers[boons[p.key] || 0].name,
    hanzi: p.hanzi,
    path: p.name,
    desc: p.tiers[boons[p.key] || 0].desc,
  }));
  // Fisher-Yates on a copy, then top up with Fortune.
  for (let i = available.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [available[i], available[j]] = [available[j], available[i]];
  }
  const chosen = available.slice(0, count);
  while (chosen.length < count) {
    chosen.push({
      type: 'fortune',
      key: 'fortune',
      name: FORTUNE.name,
      hanzi: FORTUNE.hanzi,
      path: 'Heavenly Fortune',
      desc: FORTUNE.desc,
    });
  }
  return chosen;
}
