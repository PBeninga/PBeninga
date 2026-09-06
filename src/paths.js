// The boons offered on advancement. Both are repeatable, so every advancement
// is the same question asked again: more wildstones, or more room?

export const UPGRADES = [
  {
    key: 'talisman',
    name: 'Wildstone',
    sigil: '✦',
    each: '+2 wildcards in hand',
    desc: 'Two more each rank. Drop one anywhere; it fixes to one below what '
      + 'it lands on, and eats the last copy of that same rank — stock '
      + 'first, then a buried one, then one on the board.',
  },
  {
    key: 'cell',
    name: 'Vault Slot',
    sigil: '❖',
    each: '+1 vault slot',
    desc: 'One more slot in the vault. A slot holds a single card off the '
      + 'board, for as long as you need it out of the way.',
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

/** "✦ Wildstone ×2" for each boon held, in a stable order. */
export function boonSummary(boons) {
  return UPGRADES
    .filter((u) => boons[u.key])
    .map((u) => ({ ...u, count: boons[u.key] }));
}
