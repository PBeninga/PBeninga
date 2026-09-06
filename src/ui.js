// Board rendering and input. Everything here talks to the engine; no rules live
// in this file.

import { Game, RANKS, TRANSCENDENCE, DIFFICULTIES, serialize, deserialize } from './engine.js';
import { SUIT_GLYPH, RANK_LABEL } from './cards.js';
import { boonSummary } from './paths.js';
import { randomSeed } from './rng.js';
import {
  adsInit, adsReady, adsPremium, canReward, playReward, lossBreak,
  buyPremium, restorePremium, REWARDS,
} from './ads.js';
import {
  soundSetup, soundOn, setSoundOn, playSound, buzz, setBuzzer,
} from './sound.js';
import {
  dayKey, dailySeed, dayLabel, addRun, readRuns, summarise,
  readDaily, noteDaily, playedToday, shareText,
} from './records.js';

// Replaced with a content hash by build.js; stays "dev" when running from src.
const BUILD = '__BUILD__';
const buildTag = () => (BUILD.startsWith('__') ? 'dev' : BUILD);

const SAVE_KEY = 'ascendant/run';
const BEST_KEY = 'ascendant/best';

const $ = (sel) => document.querySelector(sel);
// "Narrow" covers both a phone held upright and one held sideways: either way
// there is no room for the full rules or a row of boon names.
const isNarrow = () => window.innerWidth < 620 || window.innerHeight < 520;
const el = (tag, cls, html) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html !== undefined) n.innerHTML = html;
  return n;
};

let game = null;
let drag = null;
let hint = null;             // {moves, index, timers, layer}
let offsets = { up: 0, down: 0 };
let shownPhase = 'play';   // so a burst fires on the change, not on every check
let wildArmed = false;
let wildDrag = null;
let dailyRun = null;      // the day this run is the daily for, or null
let filed = false;        // this run has already gone into the record

// How far above the fingertip a dragged stack floats, so it stays visible.
const TOUCH_LIFT = 38;

/**
 * What a drag is being dropped on. On touch the card rides above the finger so
 * it is not hidden by it, and the card is what the player aims -- so the lifted
 * point is tried first. But the reserve slots sit at the very top of the
 * screen, where that point lands in the top bar, or clean off the page in
 * landscape. The finger's own position is tried next, so the one row a lifted
 * card cannot reach is not the row it most needs to.
 */
function dropTargetAt(ev, touch) {
  const points = touch
    ? [[ev.clientX, ev.clientY - TOUCH_LIFT], [ev.clientX, ev.clientY]]
    : [[ev.clientX, ev.clientY]];
  for (const [x, y] of points) {
    if (x < 0 || y < 0 || x > window.innerWidth || y > window.innerHeight) continue;
    const under = document.elementFromPoint(x, y);
    if (!under) continue;
    const cell = under.closest('.cell');
    if (cell) return { zone: 'reserve', index: Number(cell.dataset.cell) };
    const col = under.closest('.col');
    if (col) return { zone: 'col', index: Number(col.dataset.col) };
  }
  return null;
}

// ------------------------------------------------------------------ cards

function cardEl(card) {
  const n = el('div', 'card ' + (card.faceUp ? 'up' : 'down'));
  if (card.faceUp) {
    if (card.wild) {
      n.classList.add('wild');
      // A placed wildcard carries its fixed rank; one still in hand does not.
      const label = card.rank ? RANK_LABEL[card.rank] : '';
      n.innerHTML = `<span class="corner">${label}<span class="s">✦</span></span>`
        + '<span class="center">✦</span>';
    } else {
      if (card.suit === 'heart' || card.suit === 'diamond') n.classList.add('red');
      const g = SUIT_GLYPH[card.suit];
      n.innerHTML = `<span class="corner">${RANK_LABEL[card.rank]}<span class="s">${g}</span></span>`
        + `<span class="center">${g}</span>`;
    }
  }
  return n;
}

function miniLabel(card) {
  if (!card) return '';
  if (card.wild) {
    return `<span style="color:var(--gold)">${card.rank ? RANK_LABEL[card.rank] : ''}✦</span>`;
  }
  const red = card.suit === 'heart' || card.suit === 'diamond';
  return `<span style="color:${red ? 'var(--cinnabar)' : 'var(--paper)'}">`
    + `${RANK_LABEL[card.rank]}${SUIT_GLYPH[card.suit]}</span>`;
}

// ----------------------------------------------------------------- layout

function measure() {
  const board = $('#board');
  const cols = game.state.columns.length;
  const narrow = board.clientWidth < 620;
  const gap = narrow ? 3 : (cols > 11 ? 6 : 9);
  const padX = narrow ? 10 : 32;
  const avail = board.clientWidth - padX - gap * (cols - 1);
  // Fit the width, but never let a card grow so tall that a column of five
  // cannot breathe.
  const byWidth = Math.floor(avail / cols);
  const byHeight = Math.floor((board.clientHeight - 20) * 0.34 / 1.4);
  const w = Math.max(narrow ? 30 : 40, Math.min(124, byWidth, byHeight));
  const h = Math.round(w * (narrow ? 1.34 : 1.4));
  // Small cards drop their centre pip and grow the corner instead.
  document.body.classList.toggle('compact-cards', w < 54);
  document.documentElement.style.setProperty('--card-w', w + 'px');
  document.documentElement.style.setProperty('--card-h', h + 'px');
  board.style.setProperty('--gap', gap + 'px');
  board.style.paddingLeft = board.style.paddingRight = padX / 2 + 'px';
  // Too many columns for the screen: let the board scroll sideways instead of
  // shaving the cards down to nothing.
  const needed = w * cols + gap * (cols - 1) + padX;
  const tight = needed > board.clientWidth;
  board.style.justifyContent = tight ? 'flex-start' : 'center';
  board.style.overflowX = tight ? 'auto' : 'hidden';
  return { w, h, compact: w < 54, boardH: board.clientHeight - 20 };
}

/** Stack offsets, squeezed uniformly so the tallest column still fits. */
function offsetsFor(columns, h, boardH, compact) {
  // A compact card carries its rank in the top-left corner only, so the sliver
  // left visible has to be tall enough to show it.
  const upGap = h * (compact ? 0.36 : 0.30);
  const downGap = h * (compact ? 0.13 : 0.15);
  let scale = 1;
  for (const col of columns) {
    let need = 0;
    for (let i = 0; i < col.length - 1; i++) need += col[i].faceUp ? upGap : downGap;
    if (need + h > boardH && need > 0) scale = Math.min(scale, (boardH - h) / need);
  }
  scale = Math.max(0.18, scale);
  return { up: upGap * scale, down: downGap * scale };
}

// ----------------------------------------------------------------- render

function render() {
  if (!game) return;
  // Nothing should be floating over a board that is being drawn fresh. Whatever
  // route a stray layer arrived by, it goes here.
  if (!(drag && drag.active) && !(wildDrag && wildDrag.active)) clearDragLayers();
  renderTop();
  renderBoard();
  renderDock();
  save();
}

function renderTop() {
  const s = game.state;
  const rank = RANKS[s.rank - 1];
  $('#rank-mark').textContent = rank.mark;
  $('#rank-mark').title = `${rank.name} — rank ${s.rank} of ${RANKS.length}`;
  $('#rank-name').textContent = rank.name;
  $('#stat-rank').textContent = `${s.rank}/${RANKS.length}`;
  $('#stat-runes').textContent = `${s.runes}/${s.required}`;
  $('#stat-runes').parentElement.classList.toggle('met', s.runes >= s.required);
  $('#stat-moves').textContent = s.moves;
  $('#stat-score').textContent = game.score();

  const cells = $('#cells');
  cells.innerHTML = '';
  $('#cells-wrap').hidden = s.reserve.length === 0;
  s.reserve.forEach((card, i) => {
    const c = el('div', 'cell' + (card ? ' filled' : ''));
    c.dataset.cell = i;
    if (card) {
      c.dataset.id = card.id;
      c.appendChild(el('span', 'mini', miniLabel(card)));
    }
    cells.appendChild(c);
  });

  renderWilds();
  renderStock();
  renderCore();
}

/**
 * The core grows with everything the run has sealed: a speck at the first
 * deal, most of the board by ascension.
 */
// What the core burns like at each rank, and after. An ember through to
// something with no colour left to take.
const CORE_COLOURS = [
  { a: '255,168,84', b: '226,86,44' },     // I   Ember
  { a: '206,220,238', b: '110,140,182' },  // II  Iron
  { a: '232,242,255', b: '146,186,234' },  // III Silver
  { a: '255,224,150', b: '198,150,60' },   // IV  Gold
  { a: '255,255,255', b: '186,166,255' },  // V   Radiant
  { a: '238,214,255', b: '146,104,232' },  // VI  Sovereign
];
const TRANSCENDENT = { a: '255,255,255', b: '255,240,200' };
const BURST_MS = 1100;
const BURST_SWAP_MS = 430;

function coreColour(rank) {
  return CORE_COLOURS[Math.min(Math.max(rank, 1), CORE_COLOURS.length) - 1];
}

function paintCore(colour) {
  const core = $('#core');
  core.style.setProperty('--core-a', colour.a);
  core.style.setProperty('--core-b', colour.b);
}

/**
 * A rank ends: the core detonates, throws a ring across the board, collapses,
 * and comes back burning the next rank's colour.
 */
function coreBurst(nextColour) {
  const core = $('#core');
  if (!core) return;
  playSound('burst');
  buzz([0, 30, 40, 60]);
  const size = Math.max(core.getBoundingClientRect().width, 30);
  const reach = Math.max(window.innerWidth, window.innerHeight) * 1.25;

  const ring = el('div', 'core-burst');
  const from = coreColour(game.state.rank);
  ring.style.setProperty('--burst', from.a);
  $('#app').appendChild(ring);
  ring.animate([
    { transform: `scale(${size / 100})`, opacity: .95, borderWidth: '3px' },
    { transform: `scale(${reach / 100})`, opacity: 0, borderWidth: '1px' },
  ], { duration: 950, easing: 'cubic-bezier(.16,.72,.3,1)', fill: 'forwards' });
  setTimeout(() => ring.remove(), 1050);

  core.classList.add('bursting');
  core.animate([
    { transform: 'scale(1)', filter: 'brightness(1)' },
    { transform: 'scale(1.9)', filter: 'brightness(3.6)', offset: .16 },
    { transform: 'scale(.3)', filter: 'brightness(.55)', offset: .46 },
    { transform: 'scale(1.12)', filter: 'brightness(1.5)', offset: .74 },
    { transform: 'scale(1)', filter: 'brightness(1)' },
  ], { duration: BURST_MS, easing: 'ease-out' });

  // Swap the colour while it is collapsed, so it comes back changed.
  setTimeout(() => paintCore(nextColour), BURST_SWAP_MS);
  setTimeout(() => core.classList.remove('bursting'), BURST_MS + 40);
}

function renderCore() {
  const core = $('#core');
  if (!core) return;
  const boardH = $('#board').clientHeight || 400;
  const p = game.progress();
  const size = 6 + Math.pow(p, 0.7) * boardH * 0.78;
  core.style.setProperty('--core-size', `${Math.round(size)}px`);
  core.style.setProperty('--core-glow', (0.34 + 0.5 * p).toFixed(2));
  // Not while a burst owns the colour -- it swaps mid-collapse on purpose.
  if (!core.classList.contains('bursting')) {
    paintCore(game.state.phase === 'ascended' ? TRANSCENDENT : coreColour(game.state.rank));
  }
}

/** The wildcards in hand, as a fan you can drag from. */
function renderWilds() {
  const s = game.state;
  const fan = $('#wilds');
  $('#wilds-wrap').hidden = s.wilds === 0 && !wildArmed;
  fan.innerHTML = '';
  for (let i = 0; i < s.wilds; i++) fan.appendChild(el('div', 'wild-card', '✦'));
  fan.classList.toggle('armed', wildArmed && s.wilds > 0);
  fan.title = s.wilds
    ? `${s.wilds} wildcard${s.wilds > 1 ? 's' : ''} — drag onto a column, or tap then tap a column. `
      + 'It fixes to one rank below whatever it lands on (a King in an empty column) and is an '
      + 'ordinary card from then on. Each one takes a card out of the game: off the stock first, '
      + 'then the face-down cards, and last the card it lands on.'
    : 'No wildcards left this rank.';
}

function renderStock() {
  const s = game.state;
  const fan = $('#stock');
  const row = $('#stock-row');
  const deals = game.dealsLeft();
  fan.innerHTML = '';
  fan.classList.toggle('spent', deals === 0);
  fan.classList.toggle('hint-deal', !!hint && hint.kind === 'deal');

  if (deals === 0) {
    fan.appendChild(el('div', 'stock-card empty'));
  } else {
    for (let i = 0; i < deals; i++) fan.appendChild(el('div', 'stock-card'));
  }
  fan.title = deals
    ? `${deals} deal${deals > 1 ? 's' : ''} left — ${s.stock.length} cards`
    : 'The stock is spent.';

  let count = row.querySelector('.stock-count');
  if (!count) {
    count = el('span', 'stock-count');
    row.insertBefore(count, fan);
  }
  count.textContent = deals ? `${deals} deal${deals > 1 ? 's' : ''} left` : 'stock spent';
}

function renderBoard() {
  const board = $('#board');
  const { h, boardH, compact } = measure();
  const cols = game.state.columns;
  const off = offsetsFor(cols, h, boardH, compact);
  offsets = off;

  board.innerHTML = '';
  cols.forEach((col, ci) => {
    const colEl = el('div', 'col' + (col.length ? '' : ' empty'));
    colEl.dataset.col = ci;
    // Everything above the movable run is stuck where it is until the cards
    // below it move, so it reads as dimmed.
    const liftable = col.length - game.columnTail(ci);
    let top = 0;
    col.forEach((card, i) => {
      const n = cardEl(card);
      n.style.top = Math.round(top) + 'px';
      n.dataset.col = ci;
      n.dataset.idx = i;
      n.dataset.id = card.id;
      if (card.faceUp && i < liftable) n.classList.add('stuck');
      if (isHintSource(ci, i)) n.classList.add('hint-src');
      if (drag && drag.active && drag.zone === 'col' && drag.index === ci && i >= col.length - drag.count) {
        n.classList.add('ghost');
      }
      colEl.appendChild(n);
      if (i < col.length - 1) top += card.faceUp ? off.up : off.down;
    });
    if (hint && hint.moves[hint.index] && hint.moves[hint.index].to.index === ci) {
      colEl.classList.add('hint-dest');
    }
    board.appendChild(colEl);
  });
}

function isHintSource(colIndex, cardIndex) {
  const move = hint && hint.moves[hint.index];
  if (!move || move.from.zone !== 'col' || move.from.index !== colIndex) return false;
  return cardIndex >= game.state.columns[colIndex].length - move.from.count;
}

function renderDock() {
  const s = game.state;
  const status = $('#status');
  status.innerHTML = '';
  if (hint) {
    status.appendChild(el('span', 'hint-count', hintStatusText()));
  } else if (game.isStagnant()) {
    status.appendChild(el('span', 'warn', '⚠ Nothing left to play — undo, or call it.'));
  } else if (s.log[0]) {
    status.appendChild(el('span', '', s.log[0]));
  }
  $('#seed-tag').textContent = `${game.seed} · ${DIFFICULTIES[game.difficulty].name} · ${buildTag()}`;

  const undo = $('#btn-undo');
  // Out of undos with a move worth taking back is the one moment a player
  // wants an ad. Offer it there rather than leaving a dead button.
  const canEarnUndo = s.undosLeft <= 0 && game.canGrantUndo() && canReward('undo');
  undo.disabled = !game.undoStack.length || (s.undosLeft <= 0 && !canEarnUndo);
  undo.classList.toggle('earn', canEarnUndo && !!game.undoStack.length);
  undo.querySelector('.label').innerHTML = canEarnUndo
    ? 'Undo <b class="count">▶</b>'
    : `Undo <b class="count">${s.undosLeft}</b>`;
  $('#btn-hint').disabled = s.phase !== 'play';
  $('#btn-hint').classList.toggle('armed', !!hint);
  $('#btn-deal').disabled = !game.canDeal();
  $('#btn-deal').classList.toggle('armed', !!hint && hint.kind === 'deal');
}

function markTargets(run, on) {
  document.querySelectorAll('.col').forEach((colEl) => {
    colEl.classList.remove('drop-ok', 'drop-forced');
    if (!on) return;
    const i = Number(colEl.dataset.col);
    if (drag && drag.zone === 'col' && drag.index === i) return;
    if (game.canDrop(run, { zone: 'col', index: i })) colEl.classList.add('drop-ok');
  });
  document.querySelectorAll('.cell').forEach((cellEl) => {
    cellEl.classList.remove('drop-ok');
    if (!on) return;
    if (game.canDrop(run, { zone: 'reserve', index: Number(cellEl.dataset.cell) })) {
      cellEl.classList.add('drop-ok');
    }
  });
}

// ------------------------------------------------------------- act on move

const FLIGHT_MS = 500;

/** Where every card on the board is right now, keyed by card id. */
function snapshotPositions() {
  const map = new Map();
  document.querySelectorAll('#board .card, #cells .cell[data-id]').forEach((n) => {
    map.set(n.dataset.id, n.getBoundingClientRect());
  });
  return map;
}

/**
 * Slide the cards from where they were to where they now are (FLIP): the board
 * has already re-rendered, so put each card back with a transform and let the
 * transition carry it home. Cards bound into a rune are simply gone and
 * have nothing to animate.
 */
function flyFrom(before) {
  const moving = [];
  document.querySelectorAll('#board .card').forEach((n) => {
    const was = before.get(n.dataset.id);
    if (!was) return;
    const now = n.getBoundingClientRect();
    const dx = was.left - now.left;
    const dy = was.top - now.top;
    if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return;
    n.style.transform = `translate(${dx}px, ${dy}px)`;
    moving.push(n);
  });
  if (!moving.length) return;
  void document.body.offsetHeight;    // paint the offset before undoing it
  for (const n of moving) {
    n.classList.add('flying');
    n.style.transform = '';
  }
  setTimeout(() => {
    for (const n of moving) n.classList.remove('flying');
  }, FLIGHT_MS + 40);
}

/**
 * `animate` belongs to taps only. After a drag the card is already where the
 * player put it, so sliding it would mean snapping it back to its old column
 * first and crossing the board a second time.
 */
const DEAL_STAGGER_MS = 38;
const DEAL_FLIGHT_MS = 240;

/**
 * Send the new row out of the stock one card at a time. The cards are already
 * where they belong; each is thrown back onto the fan and released a beat
 * after the one before it.
 */
function dealAnimation(before) {
  const fan = $('#stock').getBoundingClientRect();
  const fresh = [...document.querySelectorAll('#board .card')].filter((n) => !before.has(n.dataset.id));
  if (!fresh.length) return;
  fresh.forEach((n, i) => {
    const r = n.getBoundingClientRect();
    n.style.transform = `translate(${fan.left - r.left}px, ${fan.top - r.top}px) scale(.55)`;
    n.style.opacity = '0';
    n.style.transitionDelay = `${i * DEAL_STAGGER_MS}ms`;
  });
  void document.body.offsetHeight;
  for (const n of fresh) {
    n.classList.add('dealing');
    n.style.transform = '';
    n.style.opacity = '';
  }
  setTimeout(() => {
    for (const n of fresh) {
      n.classList.remove('dealing');
      n.style.transitionDelay = '';
    }
  }, fresh.length * DEAL_STAGGER_MS + DEAL_FLIGHT_MS + 60);
}

const SEAL_STAGGER_MS = 34;
const SEAL_FLIGHT_MS = 620;

function sealDuration(seals) {
  const cards = seals.reduce((n, s) => n + s.cards.length, 0);
  return cards * SEAL_STAGGER_MS + SEAL_FLIGHT_MS + 120;
}

/** A few motes of white dust drifting the same way the card went. */
function spawnDust(layer, x, y, cx, cy, delay) {
  for (let i = 0; i < 4; i++) {
    const d = el('div', 'dust');
    const jx = (Math.random() - 0.5) * 46;
    const jy = (Math.random() - 0.5) * 46;
    d.style.left = `${x + jx}px`;
    d.style.top = `${y + jy}px`;
    layer.appendChild(d);
    d.animate([
      { transform: 'translate(0,0) scale(1)', opacity: 0 },
      { opacity: .9, offset: .18 },
      { transform: `translate(${cx - x - jx}px, ${cy - y - jy}px) scale(.2)`, opacity: 0 },
    ], {
      duration: SEAL_FLIGHT_MS + 240 + Math.random() * 200,
      delay: delay + 90 + Math.random() * 140,
      easing: 'cubic-bezier(.4,0,.55,1)',
      fill: 'forwards',
    });
  }
}

/**
 * Draw the sealed run back where it sat, then send it down into the core,
 * bleaching to white on the way and coming apart into dust.
 */
function sealAnimation(seals) {
  if (!seals.length) return;
  const coreEl = $('#core');
  const core = coreEl.getBoundingClientRect();
  const cx = core.left + core.width / 2;
  const cy = core.top + core.height / 2;
  const w = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-w'));
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));

  const layer = el('div', 'seal-layer');
  document.body.appendChild(layer);
  let index = 0;

  for (const seal of seals) {
    const colEl = document.querySelector(`.col[data-col="${seal.column}"]`);
    if (!colEl) continue;
    const rect = colEl.getBoundingClientRect();
    // The run sat directly below whatever is left of the column.
    const nodes = colEl.querySelectorAll('.card');
    const last = nodes[nodes.length - 1];
    const col = game.state.columns[seal.column];
    let top = 0;
    if (last) {
      const lastCard = col[nodes.length - 1];
      top = parseFloat(last.style.top || 0) + (lastCard && lastCard.faceUp ? offsets.up : offsets.down);
    }

    // A thirteen-card run at full spacing hangs off the bottom of the screen,
    // and cards nobody sees cannot be watched leaving. Squeeze it to fit.
    const room = window.innerHeight - (rect.top + top) - h - 16;
    const spacing = Math.max(9, Math.min(offsets.up, room / Math.max(1, seal.cards.length - 1)));

    seal.cards.forEach((card, k) => {
      const n = cardEl(card);
      const x = rect.left;
      const y = rect.top + top + k * spacing;
      n.style.left = `${x}px`;
      n.style.top = `${y}px`;
      layer.appendChild(n);

      const dx = cx - (x + w / 2);
      const dy = cy - (y + h / 2);
      const delay = index * SEAL_STAGGER_MS;
      n.animate([
        { transform: 'translate(0,0) scale(1)', opacity: 1, filter: 'brightness(1) saturate(1)' },
        { transform: `translate(${dx * .55}px, ${dy * .55}px) scale(.72)`, opacity: .95,
          filter: 'brightness(2.6) saturate(.15)', offset: .58 },
        { transform: `translate(${dx}px, ${dy}px) scale(.06)`, opacity: 0,
          filter: 'brightness(5) saturate(0)' },
      ], { duration: SEAL_FLIGHT_MS, delay, easing: 'cubic-bezier(.42,0,.5,1)', fill: 'forwards' });
      spawnDust(layer, x + w / 2, y + h / 2, cx, cy, delay);
      index++;
    });
  }

  setTimeout(() => {
    coreEl.classList.add('flare');
    setTimeout(() => coreEl.classList.remove('flare'), 750);
  }, index * SEAL_STAGGER_MS + SEAL_FLIGHT_MS * .55);
  setTimeout(() => layer.remove(), sealDuration(seals) + 400);
}

/** Columns a wildcard could be spent on right now. */
function markWildTargets(on) {
  document.querySelectorAll('.col').forEach((colEl) => {
    colEl.classList.remove('wild-ok');
    if (!on) return;
    if (game.wildCost({ zone: 'col', index: Number(colEl.dataset.col) })) colEl.classList.add('wild-ok');
  });
}

function spendWild(index) {
  const result = game.placeWild({ zone: 'col', index });
  if (!result) return false;
  wildArmed = false;
  markWildTargets(false);
  playSound('move');
  buzz(8);
  const rank = RANK_LABEL[result.value.rank];
  toast(`${rank} ${{
    stock: 'taken from the stock',
    hidden: 'burned out of a face-down pile',
    faceup: 'swallowed off the board',
    reserve: 'drawn out of the reserve',
    free: 'conjured — nothing left to pay with',
  }[result.cost]}`);
  afterAction(game.state.lastSealed || []);
  return true;
}

function onWildPointerDown(ev) {
  if (!game || game.state.phase !== 'play' || game.state.wilds <= 0) return;
  if (ev.isPrimary === false) return;
  endStrayDrag();
  stopHint();
  wildDrag = { startX: ev.clientX, startY: ev.clientY, active: false, touch: ev.pointerType === 'touch' };
  window.addEventListener('pointermove', onWildPointerMove);
  window.addEventListener('pointerup', onWildPointerUp, { once: true });
  window.addEventListener('pointercancel', onWildCancel, { once: true });
}

function onWildPointerMove(ev) {
  if (!wildDrag) return;
  if (!wildDrag.active) {
    if (Math.hypot(ev.clientX - wildDrag.startX, ev.clientY - wildDrag.startY) < (wildDrag.touch ? 10 : 7)) return;
    wildDrag.active = true;
    const layer = el('div', 'drag-layer');
    const card = cardEl({ id: 0, rank: 0, suit: 'wild', faceUp: true, wild: true });
    layer.appendChild(card);
    document.body.appendChild(layer);
    wildDrag.layer = layer;
    wildDrag.node = card;
    markWildTargets(true);
  }
  const w = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-w'));
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  wildDrag.node.style.left = `${ev.clientX - w / 2}px`;
  wildDrag.node.style.top = `${ev.clientY - h / 2 - (wildDrag.touch ? TOUCH_LIFT : 0)}px`;
}

function onWildCancel() {
  window.removeEventListener('pointermove', onWildPointerMove);
  if (wildDrag && wildDrag.layer) wildDrag.layer.remove();
  wildDrag = null;
  markWildTargets(false);
}

function onWildPointerUp(ev) {
  window.removeEventListener('pointermove', onWildPointerMove);
  window.removeEventListener('pointercancel', onWildCancel);
  if (!wildDrag) return;
  const d = wildDrag;
  wildDrag = null;
  if (d.active) {
    d.layer.remove();
    markWildTargets(false);
    const to = dropTargetAt(ev, d.touch);
    if (to && to.zone === 'col') spendWild(to.index);
    else render();
    return;
  }
  // A tap arms it; the next tap on a column spends it.
  wildArmed = !wildArmed;
  render();
  markWildTargets(wildArmed);
}

function doDeal() {
  if (!game || !game.canDeal()) return false;
  playSound('deal');
  buzz(6);
  const before = new Set([...document.querySelectorAll('#board .card')].map((n) => n.dataset.id));
  if (!game.deal()) return false;
  const seals = game.state.lastSealed || [];
  afterAction(seals);
  dealAnimation(before);
  return true;
}

function attempt(from, to, { animate = false } = {}) {
  const positions = animate ? snapshotPositions() : null;
  const ok = game.move(from, to);
  if (!ok) { playSound('deny'); return false; }
  const seals = game.state.lastSealed || [];
  if (seals.length) {
    playSound('seal');
    buzz([12, 40, 18]);
    toast(seals.length > 1 ? `${seals.length} runes bound` : 'Rune bound');
  } else {
    playSound('move');
    buzz(8);
  }
  afterAction(seals);
  if (positions) flyFrom(positions);
  return ok;
}

/**
 * `seals` holds what the engine just sealed. The breakthrough screen waits for
 * the cards to reach the core rather than cutting over the top of them.
 */
function afterAction(seals = []) {
  stopHint();
  markTargets(null, false);
  render();
  if (seals.length) {
    sealAnimation(seals);
    setTimeout(() => { if (game) checkPhase(); }, sealDuration(seals));
  } else {
    checkPhase();
  }
}

function toast(text) {
  const t = el('div', 'toast', text);
  Object.assign(t.style, {
    position: 'fixed', left: '50%', top: '22%', transform: 'translateX(-50%)',
    padding: '12px 26px', border: '1px solid var(--gold)', borderRadius: '6px',
    background: 'rgba(10,16,21,.94)', color: 'var(--gold)', zIndex: 70,
    letterSpacing: '.18em', textTransform: 'uppercase', fontSize: '13px',
    boxShadow: '0 0 30px rgba(232,189,106,.3)', pointerEvents: 'none',
    transition: 'opacity .5s, transform .5s',
  });
  document.body.appendChild(t);
  setTimeout(() => {
    t.style.opacity = '0';
    t.style.transform = 'translateX(-50%) translateY(-16px)';
  }, 700);
  setTimeout(() => t.remove(), 1300);
}

function nudge(node) {
  node.animate(
    [{ transform: 'translateX(0)' }, { transform: 'translateX(-5px)' },
      { transform: 'translateX(5px)' }, { transform: 'translateX(0)' }],
    { duration: 200 },
  );
}

// ------------------------------------------------------------------ hints

/**
 * Walk every move the position offers, one a second, drawing a translucent
 * copy of the cards drifting to where they would land. Any real action stops
 * it -- see cancelHint, wired to the whole document.
 */
function hintStatusText() {
  if (!hint) return '';
  if (hint.kind === 'deal') return 'No moves left — deal another row';
  if (hint.kind === 'wild') return 'Only a wildcard left — drop one on a lit column';
  if (hint.kind === 'over') return 'Nothing left to play';
  const what = hint.kind === 'empty' ? 'Only empty-column moves'
    : hint.kind === 'park' ? 'Only a reserve slot left'
      : hint.kind === 'split' ? 'Only breaking a run leads anywhere'
        : 'Showing hint';
  return `${what} ${hint.index + 1}/${hint.moves.length}`;
}

function startHint() {
  stopHint();
  if (!game || game.state.phase !== 'play') return;
  const s = game.suggest();
  hint = { kind: s.kind, moves: s.moves, index: 0, timers: [], layer: null };
  renderTop();
  renderDock();
  if (hint.kind === 'wild') {
    // No card to fly: the advice is the deck itself and the columns it can go
    // on, which is exactly what arming a wildcard already shows.
    $('#wilds').classList.add('hint-deal');
    markWildTargets(true);
    hint.timers.push(setTimeout(() => { stopHint(); render(); }, 2600));
    return;
  }
  if (!hint.moves.length) {
    // Nothing to draw a ghost for: the advice is the stock pile, or nothing.
    hint.timers.push(setTimeout(() => { stopHint(); render(); }, 2600));
    return;
  }
  showHintStep();
}

function stopHint() {
  $('#wilds').classList.remove('hint-deal');
  if (!wildArmed) markWildTargets(false);
  if (!hint) return;
  for (const t of hint.timers) clearTimeout(t);
  if (hint.layer) hint.layer.remove();
  hint = null;
  document.querySelectorAll('.hint-src').forEach((n) => n.classList.remove('hint-src'));
  document.querySelectorAll('.hint-dest').forEach((n) => n.classList.remove('hint-dest'));
  const stock = $('#stock');
  if (stock) stock.classList.remove('hint-deal');
  if (game) renderDock();
}

/** Where the top of a dropped card would come to rest inside a column. */
function landingTop(colIndex) {
  const col = game.state.columns[colIndex];
  if (!col.length) return 0;
  const nodes = document.querySelectorAll(`.card[data-col="${colIndex}"]`);
  const last = nodes[nodes.length - 1];
  if (!last) return 0;
  return parseFloat(last.style.top || 0) + (col[col.length - 1].faceUp ? offsets.up : offsets.down);
}

function showHintStep() {
  if (!hint) return;
  const move = hint.moves[hint.index];
  renderBoard();
  renderDock();

  const run = game.takeRun(move.from);
  const board = $('#board');
  const src = move.from.zone === 'reserve'
    ? document.querySelector(`.cell[data-cell="${move.from.index}"]`)
    : document.querySelector(
      `.card[data-col="${move.from.index}"][data-idx="${game.state.columns[move.from.index].length - move.from.count}"]`);
  const destEl = move.to.zone === 'reserve'
    ? document.querySelector(`.cell[data-cell="${move.to.index}"]`)
    : document.querySelector(`.col[data-col="${move.to.index}"]`);
  if (!src || !destEl || !board) return;

  const from = src.getBoundingClientRect();
  const to = destEl.getBoundingClientRect();
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  const gap = h * (document.body.classList.contains('compact-cards') ? 0.36 : 0.30);
  const landing = move.to.zone === 'reserve' ? to.top : to.top + landingTop(move.to.index);

  const layer = el('div', 'hint-layer');
  const nodes = run.map((card, i) => {
    const n = cardEl(card);
    n.style.left = from.left + 'px';
    n.style.top = from.top + i * gap + 'px';
    layer.appendChild(n);
    return n;
  });
  document.body.appendChild(layer);
  hint.layer = layer;

  // Two frames, so the browser paints the start before it animates away.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    nodes.forEach((n, i) => {
      n.style.left = to.left + 'px';
      n.style.top = landing + i * gap + 'px';
    });
  }));

  hint.timers.push(setTimeout(() => {
    if (!hint) return;
    layer.remove();
    hint.layer = null;
    hint.index = (hint.index + 1) % hint.moves.length;
    showHintStep();
  }, 1000));
}

/**
 * Any real action dismisses the carousel. This runs in the capture phase, so
 * it must not re-render the board -- the pointerdown still has to reach the
 * card element it was aimed at.
 */
function cancelHint(ev) {
  if (!hint) return;
  if (ev && ev.target.closest && ev.target.closest('#btn-hint')) return;
  stopHint();
}

// ----------------------------------------------------------------- input

function cardRef(node) {
  return { col: Number(node.dataset.col), idx: Number(node.dataset.idx) };
}

function onPointerDown(ev) {
  if (!game || game.state.phase !== 'play') return;
  // A second finger is not a second drag.
  if (ev.isPrimary === false) return;
  endStrayDrag();
  if (wildArmed) {
    const target = ev.target.closest('.col');
    if (target) { spendWild(Number(target.dataset.col)); return; }
    wildArmed = false;
    markWildTargets(false);
    render();
    return;
  }
  const cellEl = ev.target.closest('.cell');
  if (cellEl) return onCellTap(Number(cellEl.dataset.cell));

  const node = ev.target.closest('.card');
  if (!node) return;
  const { col, idx } = cardRef(node);
  const column = game.state.columns[col];
  const card = column[idx];
  if (!card.faceUp) return;

  const count = column.length - idx;
  drag = {
    zone: 'col', index: col, count, active: false,
    startX: ev.clientX, startY: ev.clientY, node, idx,
    grabbable: game.canGrab(col, count),
    touch: ev.pointerType === 'touch',
  };
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp, { once: true });
  window.addEventListener('pointercancel', onPointerCancel, { once: true });
}

function onPointerMove(ev) {
  if (!drag) return;
  const dx = ev.clientX - drag.startX;
  const dy = ev.clientY - drag.startY;
  if (!drag.active) {
    if (Math.hypot(dx, dy) < (drag.touch ? 10 : 7) || !drag.grabbable) return;
    startDrag(ev);
  }
  positionDrag(ev);
}

function startDrag(ev) {
  const col = game.state.columns[drag.index];
  const run = col.slice(col.length - drag.count);
  drag.active = true;
  drag.run = run;
  const rect = drag.node.getBoundingClientRect();
  drag.dx = ev.clientX - rect.left;
  drag.dy = ev.clientY - rect.top + (drag.touch ? TOUCH_LIFT : 0);
  const layer = el('div', 'drag-layer');
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  drag.stackGap = h * (document.body.classList.contains('compact-cards') ? 0.36 : 0.30);
  run.forEach((card, i) => {
    const n = cardEl(card);
    n.style.top = i * drag.stackGap + 'px';
    layer.appendChild(n);
  });
  drag.layer = layer;
  document.body.appendChild(layer);
  renderBoard();
  markTargets(run, true);
}

function positionDrag(ev) {
  if (!drag.active) return;
  for (const n of drag.layer.children) {
    n.style.left = ev.clientX - drag.dx + 'px';
  }
  [...drag.layer.children].forEach((n, i) => {
    n.style.top = ev.clientY - drag.dy + i * drag.stackGap + 'px';
  });
}

/**
 * Drop any drag still standing and take its cards off the screen.
 *
 * There is one drag at a time, but nothing used to enforce it: a second finger
 * landing on a card overwrote the drag in flight, and the layer holding the
 * first one's cards was left in the document with no reference to it. Being
 * pointer-events: none, it could not even be dismissed by touching it -- a
 * card frozen over the board for the rest of the run.
 */
function endStrayDrag() {
  if (drag) { window.removeEventListener('pointermove', onPointerMove); drag = null; }
  if (wildDrag) { window.removeEventListener('pointermove', onWildPointerMove); wildDrag = null; }
  clearDragLayers();
}

/** Take down every floating card layer. Only one can be wanted at a time. */
function clearDragLayers() {
  document.querySelectorAll('.drag-layer').forEach((n) => n.remove());
}

function onPointerCancel() {
  window.removeEventListener('pointermove', onPointerMove);
  if (drag && drag.active) drag.layer.remove();
  drag = null;
  afterAction();
}

function onPointerUp(ev) {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointercancel', onPointerCancel);
  if (!drag) return;
  const d = drag;
  drag = null;
  if (d.active) {
    d.layer.remove();
    const to = dropTargetAt(ev, d.touch);
    const from = { zone: 'col', index: d.index, count: d.count };
    const played = to && !(to.zone === 'col' && to.index === d.index) && attempt(from, to);
    // A refused drop still has to put the board back: the lifted cards were
    // taken out of the drawing when the drag began.
    if (!played) afterAction();
    return;
  }
  onCardTap(d);
}

/**
 * A tap is not a selection: it plays the card straight to wherever it builds
 * the longest sequence. Drag when you want a say in the matter.
 */
function onCardTap(d) {
  if (!d.grabbable) return nudge(d.node);
  const from = { zone: 'col', index: d.index, count: d.count };
  const target = game.bestTargetFor(from);
  if (target === null) return nudge(d.node);
  attempt(from, { zone: 'col', index: target }, { animate: true });
}

function onCellTap(index) {
  const card = game.state.reserve[index];
  if (!card) return;
  const from = { zone: 'reserve', index };
  const target = game.bestTargetFor(from);
  if (target !== null) attempt(from, { zone: 'col', index: target }, { animate: true });
}

// -------------------------------------------------------------- overlays

function overlay(html) {
  const o = $('#overlay');
  o.innerHTML = '';
  o.appendChild(html);
  // Pinned in the corner of every screen, so "am I on a stale cached page?"
  // is always answerable without opening devtools.
  o.appendChild(el('div', 'build-tag', `build ${buildTag()}`));
  o.hidden = false;
}

function closeOverlay() { $('#overlay').hidden = true; }

function rulesHtml() {
  return `<details class="rules-toggle"${isNarrow() ? '' : ' open'}>
    <summary>How to play</summary>
    <div class="rules">
      <h3>The board</h3>
      <ul>
        <li>Build <b>down by rank</b>; suit does not matter.</li>
        <li>Cards you cannot lift are <b>dimmed</b>.</li>
        <li>Lift a group only if it is a <b>descending run</b>.</li>
        <li><b>Tap a card</b> and it flies to wherever it builds the longest run. Drag it if you
        want somewhere else.</li>
        <li>An empty column takes anything. The stock deals to every column, empty ones included.</li>
      </ul>
      <h3>Ranking up</h3>
      <ul>
        <li>A complete <b>K→A run</b> is a <b>rune</b>. It binds itself and drops into the core.</li>
        <li>A rank ends when the <b>whole board</b> is gone. Then you <b>rank up</b>, pick a boon,
        and start fresh.</li>
        <li>Every rank deals <b>one more sequence than the last</b>. That is what the boons are for.</li>
        <li>Three undos per rank. The run ends only when nothing leads anywhere — splits, reserve
        slots and wildcards included. If a line exists, the hint finds it.</li>
      </ul>
      <h3>Boons &amp; keys</h3>
      <ul>
        <li><b>Wildcards</b> (✦) are held, not dealt. Drop one on a column and it becomes the card
        that belongs there — one below what it lands on, or a King in an empty column. Nothing
        goes below an Ace.</li>
        <li>It then <b>deletes</b> a copy of whatever it mimics, so the board stays clearable.</li>
        <li>A <b>reserve slot</b> holds one card off the board. Tap it to send it back.</li>
        <li><b>Space</b> deals · <b>U</b> or <b>Ctrl/⌘+Z</b> undoes · <b>H</b> shows hints · <b>Esc</b> stops them.</li>
        <li>Stuck? <b>Hint</b> walks every move, best first. Anything you do stops it.</li>
      </ul>
    </div>
  </details>`;
}

/**
 * The one thing there is to buy. Absent entirely where nothing can be sold --
 * the web build draws no shop, no ads and no mention of either.
 */
function supportRow() {
  if (!adsReady()) return null;
  const box = el('div', 'support');
  if (adsPremium()) {
    box.appendChild(el('p', 'fine', 'Ad-free — thanks.'));
    return box;
  }
  const buy = el('button', '', 'Remove ads');
  buy.onclick = async () => {
    buy.disabled = true;
    const ok = await buyPremium();
    buy.disabled = false;
    toast(ok ? 'Ad-free — thanks' : 'Purchase not completed');
    if (ok) pauseScreen();
  };
  const restore = el('button', 'quiet', 'Restore');
  restore.style.marginLeft = '8px';
  restore.onclick = async () => {
    const ok = await restorePremium();
    toast(ok ? 'Purchase restored' : 'Nothing to restore');
    if (ok) pauseScreen();
  };
  box.append(buy, restore);
  box.appendChild(el('p', 'fine', 'One payment, no more breaks between runs.'));
  return box;
}

/**
 * The result as something pasteable. Copying is offered but the text is shown
 * either way: a clipboard write can be refused, and a share you cannot read is
 * no share at all.
 */
async function copyResult(text, node) {
  let ok = false;
  try {
    await navigator.clipboard.writeText(text);
    ok = true;
  } catch (_) {
    // Blocked, or no clipboard at all: select it instead, so the player can
    // copy it by hand rather than being told it failed.
    try {
      const range = document.createRange();
      range.selectNodeContents(node);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    } catch (__) { /* nothing more to try */ }
  }
  toast(ok ? 'Copied' : 'Select and copy');
}

function shareBlock(text) {
  const box = el('div', 'share');
  const pre = el('pre', 'share-text', text.replace(/</g, '&lt;'));
  box.appendChild(pre);
  const copy = el('button', '', 'Copy result');
  copy.onclick = () => copyResult(text, pre);
  box.appendChild(copy);
  return box;
}

function recordsScreen() {
  const runs = readRuns(webStore);
  const sum = summarise(runs);
  const daily = readDaily(webStore);

  const p = el('div', 'panel');
  // The record book is a list, and a list is what a phone held sideways has
  // least room for: it loses the big sigil rather than the runs.
  if (!isNarrow()) p.appendChild(el('div', 'mark-big', '❖'));
  p.appendChild(el('h2', '', 'Records'));

  if (!runs.length) {
    p.appendChild(el('p', 'lead', 'Nothing yet. Finish a run and it lands here.'));
  } else {
    const tally = el('div', 'tally');
    const stat = (n, k) => {
      const d = el('div');
      d.appendChild(el('div', 'n', String(n)));
      d.appendChild(el('div', 'k', k));
      return d;
    };
    tally.appendChild(stat(sum.played, 'Runs'));
    tally.appendChild(stat(sum.won, 'Immortal'));
    tally.appendChild(stat(sum.runes, 'Runes'));
    tally.appendChild(stat(sum.best, 'Best'));
    p.appendChild(tally);

    const rows = Object.entries(DIFFICULTIES)
      .filter(([key]) => sum.byDifficulty[key])
      .map(([key, d]) => {
        const r = sum.byDifficulty[key];
        return `<tr><td>${d.name}</td><td>${r.played}</td>`
          + `<td>${r.bestRank ? RANKS[r.bestRank - 1].name : '—'}</td><td>${r.bestScore}</td></tr>`;
      }).join('');
    p.insertAdjacentHTML('beforeend',
      `<table class="records"><tr><th></th><th>Runs</th><th>Best rank</th><th>Best score</th></tr>${rows}</table>`);
  }

  if (daily.streak || daily.best) {
    p.appendChild(el('p', '', `Daily streak <b style="color:var(--gold)">${daily.streak}</b>`
      + ` · longest <b style="color:var(--gold)">${daily.best}</b>`));
  }

  const recent = runs.slice(0, isNarrow() ? 4 : 8).map((r) => `<tr><td>${r.daily ? dayLabel(r.daily) : r.day.slice(5)}`
    + `${r.daily ? ' <span class="tag">daily</span>' : ''}</td>`
    + `<td>${DIFFICULTIES[r.difficulty] ? DIFFICULTIES[r.difficulty].name : r.difficulty}</td>`
    + `<td>${r.won ? 'Immortal' : r.rankName}</td><td>${r.score}</td></tr>`).join('');
  if (recent) {
    // The one list here that grows without bound gets to scroll rather than
    // push the panel off a phone held sideways.
    p.insertAdjacentHTML('beforeend',
      `<h3>Recent</h3><div class="scroll-list"><table class="records">${recent}</table></div>`);
  }

  const back = el('button', 'big', 'Back');
  back.style.marginTop = '12px';
  back.onclick = titleScreen;
  p.appendChild(back);
  overlay(p);
}

function pauseScreen() {
  const p = el('div', 'panel');
  p.appendChild(el('div', 'mark-big', '❖'));
  p.appendChild(el('h2', '', 'Paused'));
  p.appendChild(el('p', '', 'No rush.'));
  p.appendChild(el('p', '', `Seed <b style="color:var(--gold)">${game.seed}</b>`
    + ` · ${DIFFICULTIES[game.difficulty].name} · build ${buildTag()}`));
  const held = boonSummary(game.state.boons);
  if (!held.length) {
    p.appendChild(el('p', '', 'None yet — clear a board to earn one.'));
  } else {
    p.appendChild(el('p', '', 'Boons held: ' + held
      .map((u) => `<b style="color:var(--gold)">${u.sigil} ${u.name} ×${u.count}</b>`).join(' · ')));
  }
  const row = el('div');
  const resume = el('button', 'big', 'Resume');
  resume.onclick = () => { closeOverlay(); render(); };
  const quit = el('button', '', 'Quit this run');
  quit.style.marginLeft = '10px';
  quit.onclick = () => { titleScreen(); };
  row.append(resume, quit);
  p.appendChild(row);
  const audio = el('button', soundOn() ? '' : 'quiet', soundOn() ? '🔊 Sound on' : '🔇 Sound off');
  audio.style.marginTop = '12px';
  audio.onclick = () => { setSoundOn(!soundOn()); playSound('move'); pauseScreen(); };
  p.appendChild(el('div', '', '')).appendChild(audio);
  const shop = supportRow();
  if (shop) p.appendChild(shop);
  p.insertAdjacentHTML('beforeend', rulesHtml());
  overlay(p);
}

/** One line about the daily: the streak, or how today went if it is done. */
function dailyLine() {
  const daily = readDaily(webStore);
  const today = daily.results[dayKey()];
  const bits = [];
  if (today) {
    bits.push(`Today: <b style="color:var(--gold)">${today.won ? 'Immortal' : today.rankName}</b>`
      + ` · ${today.runes} rune${today.runes === 1 ? '' : 's'}`);
  }
  if (daily.streak) bits.push(`streak <b style="color:var(--gold)">${daily.streak}</b>`);
  // Nothing to report on a first visit, and a line saying so is a line wasted.
  return bits.length ? `<p class="fine">${bits.join(' · ')}</p>` : '';
}

function titleScreen() {
  const best = Number(localStorage.getItem(BEST_KEY) || 0);
  const p = el('div', 'panel');
  p.innerHTML = `
    <div class="mark-big">✧</div>
    <h1>ASCENDANT</h1>
    <p class="lead">Spider solitaire, run by run. Clear the board to rank up — and each rank
    deals one more sequence than the last. Boons are how you keep up.</p>
    ${best ? `<p>Best run so far: <b style="color:var(--gold)">${best}</b></p>` : ''}
    <div class="setup">
      <div class="field"><label>Seed</label><input id="seed-input" placeholder="random" /></div>
      <div class="field"><label>Difficulty</label>
        <select id="diff-input">
          <option value="novice">Novice — 5 sequences to open</option>
          <option value="adept" selected>Adept — 6 to open, the one to play</option>
          <option value="immortal">Merciless — 8 sequences to open</option>
        </select>
      </div>
    </div>
    <div class="row-2">
      <button class="big" id="btn-begin">Start a run</button>
      <button id="btn-daily">${playedToday(webStore) ? "Today again" : "Today's board"}</button>
      <button id="btn-records">Records</button>
    </div>
    ${dailyLine()}
    <div id="resume-wrap"></div>
    ${rulesHtml()}`;
  overlay(p);
  // Only offer to resume a save the current rules can actually honour; an
  // unreadable one is cleared rather than left behind a dead button.
  const restored = loadSaved();
  if (restored) {
    const wrap = $('#resume-wrap');
    const b = el('button', '', `Resume — ${RANKS[restored.state.rank - 1].name}, `
      + `${restored.state.runes}/${restored.state.required} bound`);
    b.style.marginTop = '12px';
    b.onclick = () => {
      game = restored;
      closeOverlay();
      render();
      checkPhase();
    };
    wrap.appendChild(b);
  }
  $('#btn-begin').onclick = () => {
    const seed = $('#seed-input').value.trim() || randomSeed();
    start(seed, $('#diff-input').value);
  };
  $('#btn-daily').onclick = startDaily;
  $('#btn-records').onclick = recordsScreen;
  $('#seed-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#btn-begin').click(); });
}

function breakthroughScreen() {
  const s = game.state;
  const next = RANKS[s.rank];
  const p = el('div', 'panel');
  p.appendChild(el('div', 'mark-big', RANKS[s.rank - 1].mark));
  p.appendChild(el('h1', '', 'RANK UP'));
  p.appendChild(el('p', 'lead',
    `${RANKS[s.rank - 1].name} done. <b style="color:var(--gold)">${next.name}</b> next: `
    + `<b style="color:var(--gold)">${game.rankConfig(s.rank + 1).required} sequences</b>.`));
  p.appendChild(el('p', '', 'Pick one, for the rest of the run.'));
  const offer = el('div', 'offer');
  s.offer.forEach((boon, i) => {
    const b = el('div', 'boon');
    b.innerHTML = `<div class="sigil">${boon.sigil}</div>
      <div class="path">${boon.each}</div>
      <div class="name">${boon.name}</div>
      <div class="desc">${boon.desc}</div>
      <div class="tier">${boon.held ? `YOU HOLD ${boon.held} — THIS MAKES ${boon.next}` : 'YOUR FIRST'}</div>`;
    b.onclick = () => {
      game.chooseBoon(i);
      closeOverlay();
      render();
      checkPhase();
    };
    offer.appendChild(b);
  });
  p.appendChild(offer);
  overlay(p);
}

function endScreen(won) {
  const s = game.state;
  const score = game.score();
  const best = Number(localStorage.getItem(BEST_KEY) || 0);
  const beaten = score > best;
  if (beaten) localStorage.setItem(BEST_KEY, String(score));
  localStorage.removeItem(SAVE_KEY);
  const result = fileRun(won);
  playSound(won ? 'seal' : 'over');

  const p = el('div', 'panel');
  p.appendChild(el('div', 'mark-big', won ? TRANSCENDENCE.mark : '✧'));
  p.appendChild(el('h1', '', won ? 'IMMORTALITY' : 'RUN OVER'));
  p.appendChild(el('p', 'lead', won
    ? 'All six ranks. Turns out you were meant for it.'
    : `You made it to <b style="color:var(--gold)">${RANKS[s.rank - 1].name}</b>. `
      + "That's decent — but not everyone's meant for immortality."));

  const tally = el('div', 'tally');
  const stat = (n, k) => {
    const d = el('div');
    d.appendChild(el('div', 'n', String(n)));
    d.appendChild(el('div', 'k', k));
    return d;
  };
  tally.appendChild(stat(RANKS[s.rank - 1].name, 'Got to'));
  tally.appendChild(stat(s.totalRunes, 'Runes'));
  tally.appendChild(stat(s.moves, 'Moves'));
  tally.appendChild(stat(score, 'Score'));
  p.appendChild(tally);

  const held = boonSummary(s.boons);
  if (held.length) {
    p.appendChild(el('p', '', 'Boons held: '
      + held.map((u) => `${u.name} ×${u.count}`).join(' · ')));
  }
  if (beaten && score > 0) p.appendChild(el('p', 'fine', 'A personal best.'));
  p.appendChild(el('p', '', dailyRun
    ? `Daily <b style="color:var(--gold)">${dayLabel(dailyRun)}</b> · ${DIFFICULTIES[game.difficulty].name}`
    : `Seed <b style="color:var(--gold)">${game.seed}</b> · ${DIFFICULTIES[game.difficulty].name}`));
  const card = result ? shareText(result, RANKS.length) : null;
  if (card && !isNarrow()) p.appendChild(shareBlock(card));
  else if (card) p.appendChild(el('p', 'pips', card.split('\n')[1]));

  // The run is over, so a break is due if the count says so. It runs on the
  // way out, never over the tally the player is still reading.
  const leave = (go) => async () => {
    await lossBreak();
    go();
  };

  if (!won && game.canReprieve() && canReward('reprieve')) {
    const wind = el('button', 'big earn', `▶ ${REWARDS.reprieve.label}`);
    wind.onclick = async () => {
      wind.disabled = true;
      const earned = await playReward('reprieve');
      if (!earned) { wind.disabled = false; toast('Nothing earned'); return; }
      game.reprieve();
      shownPhase = 'play';
      closeOverlay();
      render();
      save();
      toast('A wildcard and an undo');
    };
    const windRow = el('div');
    windRow.style.margin = '14px 0 2px';
    windRow.appendChild(wind);
    p.appendChild(windRow);
    p.appendChild(el('p', 'fine', REWARDS.reprieve.blurb));
  }

  const again = el('button', 'big', 'Go again');
  again.style.marginRight = '10px';
  again.onclick = leave(() => start(randomSeed(), game.difficulty));
  const retry = el('button', '', 'Same seed');
  retry.onclick = leave(() => start(game.seed, game.difficulty));
  const menu = el('button', '', 'Main menu');
  menu.style.marginLeft = '10px';
  menu.onclick = leave(titleScreen);
  const row = el('div');
  row.style.marginTop = '10px';
  row.append(again, retry, menu);
  if (card && isNarrow()) {
    const copy = el('button', '', 'Copy');
    copy.style.marginLeft = '10px';
    copy.onclick = () => copyResult(card, p.querySelector('.pips'));
    row.appendChild(copy);
  }
  p.appendChild(row);
  overlay(p);
}

/**
 * Panels wait for the burst. Seeing the core change is the reward for clearing
 * a rank; covering it with an overlay would throw that away.
 */
function checkPhase() {
  const phase = game.state.phase;
  const fresh = phase !== shownPhase;
  shownPhase = phase;

  if (phase === 'breakthrough') {
    if (!fresh) return breakthroughScreen();
    coreBurst(coreColour(game.state.rank + 1));
    setTimeout(() => {
      if (game && game.state.phase === 'breakthrough') breakthroughScreen();
    }, BURST_MS - 150);
  } else if (phase === 'ascended') {
    if (!fresh) return endScreen(true);
    coreBurst(TRANSCENDENT);
    setTimeout(() => {
      if (game && game.state.phase === 'ascended') endScreen(true);
    }, BURST_MS - 150);
  } else if (phase === 'failed') {
    endScreen(false);
  }
}

// ------------------------------------------------------------------ setup

/** The stored run, or null if there isn't one the current rules can honour. */
function loadSaved() {
  let raw = null;
  try { raw = localStorage.getItem(SAVE_KEY); } catch (_) { return null; }
  if (!raw) return null;
  const restored = deserialize(raw);
  if (!restored) {
    try { localStorage.removeItem(SAVE_KEY); } catch (_) { /* ignore */ }
    return null;
  }
  return restored;
}

// ads.js takes any get/set pair; in the browser that is localStorage, and a
// native wrapper hands in its own key-value store instead.
const webStore = {
  get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (_) { /* private browsing */ } },
};

function save() {
  try {
    if (game.state.phase === 'play' || game.state.phase === 'breakthrough') {
      localStorage.setItem(SAVE_KEY, serialize(game));
    }
  } catch (_) { /* private browsing */ }
}

function start(seed, difficulty, { daily = null } = {}) {
  stopHint();
  shownPhase = 'play';
  wildArmed = false;
  dailyRun = daily;
  filed = false;
  game = new Game({ seed, difficulty });
  closeOverlay();
  render();
}

/** Everyone gets the same board today. Adept, so the results compare. */
function startDaily() {
  start(dailySeed(), 'adept', { daily: dayKey() });
}

/** What a finished run leaves behind. */
function fileRun(won) {
  if (filed) return null;
  filed = true;
  const s = game.state;
  const result = {
    day: dayKey(),
    daily: dailyRun,
    seed: game.seed,
    difficulty: game.difficulty,
    rank: s.rank,
    rankName: RANKS[s.rank - 1].name,
    runes: s.totalRunes,
    moves: s.moves,
    score: game.score(),
    won,
  };
  addRun(webStore, result);
  if (dailyRun) noteDaily(webStore, result, dailyRun);
  return result;
}

function bindChrome() {
  $('#stock').addEventListener('click', doDeal);
  $('#btn-deal').addEventListener('click', doDeal);
  $('#btn-paths').addEventListener('click', () => { stopHint(); pauseScreen(); });
  $('#btn-undo').addEventListener('click', async () => {
    if (!game) return;
    if (game.state.undosLeft <= 0) {
      if (!game.undoStack.length || !game.canGrantUndo() || !canReward('undo')) return;
      if (!(await playReward('undo'))) { toast('No undo earned'); return; }
      game.grantUndo();
    }
    if (game.undo()) { playSound('lift'); afterAction(); }
  });
  $('#btn-menu').addEventListener('click', () => {
    stopHint();
    if (!game) titleScreen();
    else pauseScreen();
  });
  $('#btn-hint').addEventListener('click', () => { if (hint) stopHint(); else startHint(); });
  $('#wilds').addEventListener('pointerdown', onWildPointerDown);
  $('#board').addEventListener('pointerdown', onPointerDown);
  $('#cells').addEventListener('pointerdown', onPointerDown);
  // Anything the player actually does dismisses a running hint.
  document.addEventListener('pointerdown', cancelHint, true);
  const relayout = () => {
    if (!game) return;
    if ($('#overlay').hidden) render();
    else { renderBoard(); renderCore(); }
  };
  window.addEventListener('resize', relayout);
  window.addEventListener('orientationchange', () => setTimeout(relayout, 120));
  window.addEventListener('keydown', (e) => {
    if (!game || game.state.phase !== 'play') return;
    if (e.key === 'Escape') {
      stopHint(); wildArmed = false; markTargets(null, false); markWildTargets(false); render();
    }
    if (e.key === 'h') { e.preventDefault(); if (hint) stopHint(); else startHint(); return; }
    cancelHint();
    if ((e.key === 'z' && (e.metaKey || e.ctrlKey)) || e.key === 'u') {
      e.preventDefault();
      if (game.undo()) afterAction();
    }
    if (e.key === ' ' || e.key === 'd') { e.preventDefault(); doDeal(); }
  });
}

export function boot() {
  soundSetup(webStore);
  bindChrome();
  titleScreen();
  // Handle for the console and for browser-driven tests.
  window.Ascendant = {
    get game() { return game; },
    start,
    render,
    checkPhase,
    startDaily,
    recordsScreen,
    /** A native wrapper supplies real haptics; the web makes do with vibrate. */
    setBuzzer,
    ads: { ready: adsReady, isPremium: adsPremium, canReward, lossBreak },
    /**
     * Attach a host's ad and purchase bridge, then redraw what it unlocks.
     * A native wrapper passes its own store too, so a purchase outlives the
     * web cache; on the web it is localStorage.
     */
    async attachAds(provider, store = webStore) {
      await adsInit({ provider, store });
      if (game && $('#overlay').hidden) render();
      return adsReady();
    },
  };
  // A native wrapper installs its bridge on the window before the page boots;
  // on the web there is nothing to find, and every ad path stays shut.
  window.Ascendant.attachAds(window.AscendantAds || null);
}
