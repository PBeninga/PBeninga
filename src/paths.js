// The upgrades offered at a breakthrough. Both are repeatable, so every
// breakthrough is the same question asked again: more talismans, or more room?

export const UPGRADES = [
  {
    key: 'talisman',
    name: 'Blank Talisman',
    hanzi: '靈符',
    each: '+2 chaos talismans',
    desc: 'Two more chaos talismans shuffled into every deal. A talisman stands '
      + 'in for whatever rank and suit the run needs, sealed meridians included.',
  },
  {
    key: 'cell',
    name: 'Dantian Cell',
    hanzi: '虛步',
    each: '+1 reserve cell',
    desc: 'One more reserve cell. A cell holds a single card outside the '
      + 'tableau, for as long as you need somewhere to put it.',
  },
];

export const UPGRADE_BY_KEY = Object.fromEntries(UPGRADES.map((u) => [u.key, u]));

/** Both upgrades, every time, annotated with what you already hold. */
export function offerBoons(boons) {
  return UPGRADES.map((u) => {
    const held = boons[u.key] || 0;
    return {
      key: u.key,
      name: u.name,
      hanzi: u.hanzi,
      each: u.each,
      desc: u.desc,
      held,
      next: held + 1,
    };
  });
}

/** "靈符 Blank Talisman ×2" for each upgrade held, in a stable order. */
export function boonSummary(boons) {
  return UPGRADES
    .filter((u) => boons[u.key])
    .map((u) => ({ ...u, count: boons[u.key] }));
}
