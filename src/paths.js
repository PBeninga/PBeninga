// The boons offered on advancement. Both are repeatable, so every advancement
// is the same question asked again: more wildcards, or more room?

export const UPGRADES = [
  {
    key: 'talisman',
    name: 'Wildcard',
    sigil: '✦',
    each: '+2 wildcards in hand',
    desc: 'Drop it on any column; it takes the value that fits there, and a '
      + 'matching card is removed from the game.',
  },
  {
    key: 'cell',
    name: 'Reserve Slot',
    sigil: '❖',
    each: '+1 reserve slot',
    desc: 'Holds one card off the board.',
  },
];

export const UPGRADE_BY_KEY = Object.fromEntries(UPGRADES.map((u) => [u.key, u]));

/** Both boons, every time, annotated with what you already hold. */
export function offerBoons(boons) {
  return UPGRADES.map((u) => {
    const held = boons[u.key] || 0;
    return { ...u, held, next: held + 1 };
  });
}

/** "✦ Wildcard ×2" for each boon held, in a stable order. */
export function boonSummary(boons) {
  return UPGRADES
    .filter((u) => boons[u.key])
    .map((u) => ({ ...u, count: boons[u.key] }));
}
