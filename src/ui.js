// Board rendering and input. Everything here talks to the engine; no rules live
// in this file.

import { Game, REALMS, ASCENSION, DIFFICULTIES, serialize, deserialize } from './engine.js';
import { SUITS, SUIT_GLYPH, SUIT_NAME, RANK_LABEL } from './cards.js';
import { PATH_BY_KEY } from './paths.js';
import { randomSeed } from './rng.js';

// Replaced with a content hash by build.js; stays "dev" when running from src.
const BUILD = '__BUILD__';
const buildTag = () => (BUILD.startsWith('__') ? 'dev' : BUILD);

const SAVE_KEY = 'nine-meridians/run';
const BEST_KEY = 'nine-meridians/best';

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
let armed = null;            // 'void' | 'transmute' | 'awaken'
let pendingTransmute = null;
let drag = null;
let hint = null;             // {moves, index, timers, layer}
let offsets = { up: 0, down: 0 };

// How far above the fingertip a dragged stack floats, so it stays visible.
const TOUCH_LIFT = 38;

// ------------------------------------------------------------------ cards

function cardEl(card) {
  const n = el('div', 'card ' + (card.faceUp ? 'up' : 'down'));
  if (card.faceUp) {
    if (card.wild) {
      n.classList.add('wild');
      n.innerHTML = '<span class="corner">☯</span><span class="center">☯</span>';
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
  if (card.wild) return '<span style="color:var(--gold)">☯</span>';
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
  renderHud();
  renderBoard();
  renderDock();
  save();
}

function renderHud() {
  const s = game.state;
  const realm = REALMS[s.realm - 1];
  $('#realm-seal').textContent = realm.hanzi;
  $('#realm-name').textContent = realm.name;
  $('#realm-sub').textContent = `Realm ${s.realm} of ${REALMS.length}`;

  const pips = $('#pips');
  pips.innerHTML = '';
  // Nine pips crowd a phone; the count beside them says the same thing.
  if (!isNarrow()) {
    for (let i = 0; i < s.required; i++) {
      pips.appendChild(el('div', 'pip' + (i < s.meridians ? ' on' : '')));
    }
  }
  $('#meridian-label').textContent = `${s.meridians}/${s.required} meridians`;

  const chips = $('#boon-chips');
  chips.innerHTML = '';
  const taken = Object.entries(s.boons);
  // On a phone a row of full boon names costs more screen than it is worth;
  // collapse to a tap that opens the same list in the pause panel.
  if (isNarrow() && taken.length + (s.fortune ? 1 : 0) > 1) {
    const chip = el('span', 'chip', `☯ <b>${taken.length + (s.fortune ? 1 : 0)} boons</b>`);
    chip.style.cursor = 'pointer';
    chip.onclick = pauseScreen;
    chips.appendChild(chip);
  } else {
    for (const [key, tier] of taken) {
      const path = PATH_BY_KEY[key];
      chips.appendChild(el('span', 'chip', `${path.hanzi} <b>${path.tiers[tier - 1].name}</b>`));
    }
    if (s.fortune) chips.appendChild(el('span', 'chip', `天緣 <b>Fortune ×${s.fortune}</b>`));
  }

  renderStock();

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

  chargeButton('#btn-void', 'void', s.charges.voidStep, 'Void Step');
  chargeButton('#btn-transmute', 'transmute', s.charges.transmute, 'Transmute');
  chargeButton('#btn-awaken', 'awaken', s.charges.awaken, 'Awaken');
}

/**
 * One card back per remaining deal. The fan is the count: how many rows the
 * heavens still owe you is something you read off the board, not a number.
 */
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

function chargeButton(sel, mode, count, label) {
  const b = $(sel);
  b.hidden = count === 0 && armed !== mode;
  b.disabled = count === 0;
  b.classList.toggle('armed', armed === mode);
  b.innerHTML = `${label} <span class="count">${count}</span>`;
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
    status.appendChild(el('span', 'warn', '⚠ No moves left — undo, spend a technique, or abandon the climb.'));
  } else {
    status.appendChild(el('span', '', s.log[0] || ''));
  }
  $('#seed-tag').textContent = `${game.seed} · ${DIFFICULTIES[game.difficulty].name} · ${buildTag()}`;

  const undo = $('#btn-undo');
  undo.disabled = s.undosLeft <= 0 || !game.undoStack.length;
  undo.innerHTML = `↺ Undo <span class="count">${s.undosLeft}</span>`;
  const hintBtn = $('#btn-hint');
  hintBtn.disabled = s.phase !== 'play';
  hintBtn.classList.toggle('armed', !!hint);
}

// ------------------------------------------------------------- highlights

function markTargets(run, on) {
  document.querySelectorAll('.col').forEach((colEl) => {
    colEl.classList.remove('drop-ok', 'drop-forced');
    if (!on) return;
    const i = Number(colEl.dataset.col);
    if (drag && drag.zone === 'col' && drag.index === i) return;
    if (armed === 'void' && game.canDrop(run, { zone: 'col', index: i }, { force: true })) {
      colEl.classList.add('drop-forced');
    } else if (game.canDrop(run, { zone: 'col', index: i })) {
      colEl.classList.add('drop-ok');
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
 * transition carry it home. Cards sealed into a meridian are simply gone and
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
function attempt(from, to, { animate = false } = {}) {
  const force = armed === 'void';
  const before = game.state.totalMeridians;
  const positions = animate ? snapshotPositions() : null;
  const ok = game.move(from, to, { force });
  if (ok) {
    if (force) armed = null;
    if (game.state.totalMeridians > before) toast('Meridian sealed');
    afterAction();
    if (positions) flyFrom(positions);
  }
  return ok;
}

function afterAction() {
  stopHint();
  markTargets(null, false);
  render();
  checkPhase();
}

function toast(text) {
  const t = el('div', 'toast', text);
  Object.assign(t.style, {
    position: 'fixed', left: '50%', top: '22%', transform: 'translateX(-50%)',
    padding: '12px 26px', border: '1px solid var(--gold)', borderRadius: '6px',
    background: 'rgba(10,16,21,.94)', color: 'var(--gold)', zIndex: 70,
    letterSpacing: '.18em', textTransform: 'uppercase', fontSize: '13px',
    boxShadow: '0 0 30px rgba(227,184,105,.3)', pointerEvents: 'none',
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
  if (hint.kind === 'over') return 'No moves and nothing to deal — the run is over';
  const what = hint.kind === 'empty' ? 'Only empty-column moves' : 'Showing hint';
  return `${what} ${hint.index + 1}/${hint.moves.length}`;
}

function startHint() {
  stopHint();
  if (!game || game.state.phase !== 'play') return;
  const s = game.suggest();
  hint = { kind: s.kind, moves: s.moves, index: 0, timers: [], layer: null };
  renderHud();
  renderDock();
  if (!hint.moves.length) {
    // Nothing to draw a ghost for: the advice is the stock pile, or nothing.
    hint.timers.push(setTimeout(() => { stopHint(); render(); }, 2600));
    return;
  }
  showHintStep();
}

function stopHint() {
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
  const destCol = document.querySelector(`.col[data-col="${move.to.index}"]`);
  if (!src || !destCol || !board) return;

  const from = src.getBoundingClientRect();
  const to = destCol.getBoundingClientRect();
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  const gap = h * (document.body.classList.contains('compact-cards') ? 0.36 : 0.30);
  const landing = to.top + landingTop(move.to.index);

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
  const cellEl = ev.target.closest('.cell');
  if (cellEl) return onCellTap(Number(cellEl.dataset.cell));

  const node = ev.target.closest('.card');
  if (!node) return;
  const { col, idx } = cardRef(node);
  const column = game.state.columns[col];
  const card = column[idx];
  if (!card.faceUp) return;

  if (armed === 'transmute') return openSuitPicker({ zone: 'col', index: col, cardIndex: idx });
  if (armed === 'awaken') {
    if (game.awaken({ zone: 'col', index: col, cardIndex: idx })) { armed = null; toast('Talisman awakened'); afterAction(); }
    return;
  }

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
    const under = document.elementFromPoint(ev.clientX, ev.clientY - (d.touch ? TOUCH_LIFT : 0));
    const cell = under && under.closest('.cell');
    const colEl = under && under.closest('.col');
    if (cell) attempt({ zone: 'col', index: d.index, count: d.count }, { zone: 'reserve', index: Number(cell.dataset.cell) });
    else if (colEl && Number(colEl.dataset.col) !== d.index) {
      attempt({ zone: 'col', index: d.index, count: d.count }, { zone: 'col', index: Number(colEl.dataset.col) });
    } else afterAction();
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
  if (armed === 'transmute' && card) return openSuitPicker({ zone: 'reserve', index });
  if (armed === 'awaken' && card) {
    if (game.awaken({ zone: 'reserve', index })) { armed = null; afterAction(); }
    return;
  }
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

function openSuitPicker(ref) {
  pendingTransmute = ref;
  const p = el('div', 'panel');
  p.appendChild(el('h2', '', 'Transmutation'));
  p.appendChild(el('p', '', 'Reforge this card into another dao.'));
  const row = el('div', 'suit-picker');
  for (const suit of SUITS) {
    const b = el('button', '', `${SUIT_GLYPH[suit]}<br><span style="font-size:10px;letter-spacing:.1em">${SUIT_NAME[suit]}</span>`);
    b.style.color = suit === 'heart' || suit === 'diamond' ? 'var(--cinnabar)' : 'var(--paper)';
    b.onclick = () => {
      closeOverlay();
      if (game.transmute(pendingTransmute, suit)) { armed = null; toast('Reforged'); }
      pendingTransmute = null;
      afterAction();
    };
    row.appendChild(b);
  }
  p.appendChild(row);
  const cancel = el('button', '', 'Cancel');
  cancel.onclick = () => { closeOverlay(); pendingTransmute = null; armed = null; render(); };
  p.appendChild(cancel);
  overlay(p);
}

function rulesHtml() {
  return `<details class="rules-toggle"${isNarrow() ? '' : ' open'}>
    <summary>How to play</summary>
    <div class="rules">
      <h3>The Tableau</h3>
      <ul>
        <li>Build <b>down by rank</b> onto any card — suit does not matter while stacking.</li>
        <li>Cards that cannot be lifted yet are <b>dimmed</b>; free the run below them first.</li>
        <li>Lift a group only when it is a <b>descending run of one suit</b>.</li>
        <li><b>Tap or click a card</b> and it flies to whichever column builds the
        longest sequence. Drag it instead when you want a different column.</li>
        <li>An empty column accepts anything, and the stock deals one card to every column, empty ones included.</li>
      </ul>
      <h3>Cultivation</h3>
      <ul>
        <li>A complete <b>K→A run of one suit</b> is a <b>meridian</b>. It seals itself and leaves the column.</li>
        <li>A realm is a <b>whole game</b>: it ends when every card has been sealed away. Only then do you
        <b>break through</b>, choose a boon, and face a fresh tableau.</li>
        <li>Every realm deals <b>one more sequence than the last</b>, and all of them must go. The paths you
        walk are what close that gap.</li>
        <li>Three undos per realm. If the tableau locks up and the stock is spent, the climb ends.</li>
      </ul>
      <h3>Techniques &amp; Keys</h3>
      <ul>
        <li><b>Talismans</b> (☯) stand in for any rank and suit, in a stack or inside a sealed meridian.</li>
        <li><b>Void Step</b>, <b>Transmute</b> and <b>Awaken</b> are charges: arm the button, then click a card.</li>
        <li><b>Space</b> deals · <b>U</b> or <b>Ctrl/⌘+Z</b> undoes · <b>H</b> shows hints · <b>Esc</b> stops them.</li>
        <li>Stuck? <b>Hint</b> walks every move the position offers, one a
        second, showing where each one lands — best first. Anything you do
        stops it.</li>
      </ul>
    </div>
  </details>`;
}

function pauseScreen() {
  const p = el('div', 'panel');
  p.appendChild(el('div', 'hanzi-big', '靜坐'));
  p.appendChild(el('h2', '', 'Meditation'));
  p.appendChild(el('p', '', 'The climb waits.'));
  p.appendChild(el('p', '', `Seed <b style="color:var(--gold)">${game.seed}</b>`
    + ` · ${DIFFICULTIES[game.difficulty].name} · build ${buildTag()}`));
  const taken = Object.entries(game.state.boons);
  if (taken.length || game.state.fortune) {
    const list = taken
      .map(([k, t]) => `<b style="color:var(--gold)">${PATH_BY_KEY[k].hanzi} ${PATH_BY_KEY[k].tiers[t - 1].name}</b>`)
      .concat(game.state.fortune ? [`<b style="color:var(--gold)">天緣 Fortune ×${game.state.fortune}</b>`] : []);
    p.appendChild(el('p', '', 'Boons held: ' + list.join(' · ')));
  }
  const row = el('div');
  const resume = el('button', 'big', 'Resume');
  resume.onclick = () => { closeOverlay(); render(); };
  const quit = el('button', '', 'Abandon this climb');
  quit.style.marginLeft = '10px';
  quit.onclick = () => { titleScreen(); };
  row.append(resume, quit);
  p.appendChild(row);
  p.insertAdjacentHTML('beforeend', rulesHtml());
  overlay(p);
}

function titleScreen() {
  const best = Number(localStorage.getItem(BEST_KEY) || 0);
  const p = el('div', 'panel');
  p.innerHTML = `
    <div class="hanzi-big">九脈</div>
    <h1>NINE MERIDIANS</h1>
    <p class="lead">A cultivation roguelike played in Spider solitaire. A realm is a whole
    game: clear every K→A sequence on the board and you break through — but the next realm
    deals one more sequence than the last, and all of them must go.</p>
    ${best ? `<p>Highest cultivation attained: <b style="color:var(--gold)">${best}</b></p>` : ''}
    <div class="setup">
      <div class="field"><label>Seed</label><input id="seed-input" placeholder="random" /></div>
      <div class="field"><label>Difficulty</label>
        <select id="diff-input">
          <option value="novice">Novice — few suits, wide margins</option>
          <option value="adept" selected>Adept — the intended climb</option>
          <option value="immortal">Immortal — four suits, thin decks</option>
        </select>
      </div>
    </div>
    <button class="big" id="btn-begin">Begin Cultivation</button>
    <div id="resume-wrap"></div>
    ${rulesHtml()}`;
  overlay(p);
  // Only offer to resume a save the current rules can actually honour; an
  // unreadable one is cleared rather than left behind a dead button.
  const restored = loadSaved();
  if (restored) {
    const wrap = $('#resume-wrap');
    const b = el('button', '', `Resume — ${REALMS[restored.state.realm - 1].name}, `
      + `${restored.state.meridians}/${restored.state.required} sealed`);
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
  $('#seed-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#btn-begin').click(); });
}

function breakthroughScreen() {
  const s = game.state;
  const next = REALMS[s.realm];
  const p = el('div', 'panel');
  p.appendChild(el('div', 'hanzi-big', REALMS[s.realm - 1].hanzi));
  p.appendChild(el('h1', '', 'BREAKTHROUGH'));
  p.appendChild(el('p', 'lead',
    `${REALMS[s.realm - 1].name} is cleared. Ahead lies <b style="color:var(--gold)">${next.name}</b>, `
    + `a board of <b style="color:var(--gold)">${game.realmConfig(s.realm + 1).required} sequences</b>, all of which must go.`));
  p.appendChild(el('p', '', 'Choose the dao you will walk. The choice is permanent.'));
  const offer = el('div', 'offer');
  s.offer.forEach((boon, i) => {
    const b = el('div', 'boon');
    b.innerHTML = `<div class="hanzi">${boon.hanzi}</div>
      <div class="path">${boon.path}</div>
      <div class="name">${boon.name}</div>
      <div class="desc">${boon.desc}</div>
      ${boon.type === 'path' ? `<div class="tier">TIER ${boon.tier} OF 3</div>` : ''}`;
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
  if (score > best) localStorage.setItem(BEST_KEY, String(score));
  localStorage.removeItem(SAVE_KEY);

  const p = el('div', 'panel');
  p.appendChild(el('div', 'hanzi-big', won ? ASCENSION.hanzi : '塵歸'));
  p.appendChild(el('h1', '', won ? 'ASCENSION' : 'THE DAO CLOSES'));
  p.appendChild(el('p', 'lead', won
    ? 'Six realms sealed. You step past the mortal ceiling and are not seen again.'
    : `Your qi scattered in ${REALMS[s.realm - 1].name}. The mountain keeps its silence.`));

  const tally = el('div', 'tally');
  const stat = (n, k) => {
    const d = el('div');
    d.appendChild(el('div', 'n', String(n)));
    d.appendChild(el('div', 'k', k));
    return d;
  };
  tally.appendChild(stat(s.realm, 'Realm reached'));
  tally.appendChild(stat(s.totalMeridians, 'Meridians sealed'));
  tally.appendChild(stat(s.moves, 'Moves'));
  tally.appendChild(stat(score, 'Cultivation'));
  p.appendChild(tally);

  if (Object.keys(s.boons).length) {
    p.appendChild(el('p', '', 'Paths walked: ' + Object.entries(s.boons)
      .map(([k, t]) => `${PATH_BY_KEY[k].name} ${'I'.repeat(t)}`).join(' · ')));
  }
  p.appendChild(el('p', '', `Seed <b style="color:var(--gold)">${game.seed}</b> · ${DIFFICULTIES[game.difficulty].name}`));

  const again = el('button', 'big', 'Climb again');
  again.style.marginRight = '10px';
  again.onclick = () => start(randomSeed(), game.difficulty);
  const retry = el('button', '', 'Retry this seed');
  retry.onclick = () => start(game.seed, game.difficulty);
  const menu = el('button', '', 'Main menu');
  menu.style.marginLeft = '10px';
  menu.onclick = titleScreen;
  const row = el('div');
  row.style.marginTop = '10px';
  row.append(again, retry, menu);
  p.appendChild(row);
  overlay(p);
}

function checkPhase() {
  const phase = game.state.phase;
  if (phase === 'breakthrough') breakthroughScreen();
  else if (phase === 'ascended') endScreen(true);
  else if (phase === 'failed') endScreen(false);
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

function save() {
  try {
    if (game.state.phase === 'play' || game.state.phase === 'breakthrough') {
      localStorage.setItem(SAVE_KEY, serialize(game));
    }
  } catch (_) { /* private browsing */ }
}

function start(seed, difficulty) {
  stopHint();
  game = new Game({ seed, difficulty });
  armed = null;
  closeOverlay();
  render();
}

function bindChrome() {
  $('#stock').addEventListener('click', () => {
    if (game && game.deal()) afterAction();
  });
  $('#btn-undo').addEventListener('click', () => {
    if (game && game.undo()) { armed = null; afterAction(); }
  });
  for (const [sel, mode] of [['#btn-void', 'void'], ['#btn-transmute', 'transmute'], ['#btn-awaken', 'awaken']]) {
    $(sel).addEventListener('click', () => {
      stopHint();
      armed = armed === mode ? null : mode;
      render();
    });
  }
  $('#btn-menu').addEventListener('click', () => {
    stopHint();
    if (!game) titleScreen();
    else pauseScreen();
  });
  $('#btn-hint').addEventListener('click', () => { if (hint) stopHint(); else startHint(); });
  $('#board').addEventListener('pointerdown', onPointerDown);
  $('#cells').addEventListener('pointerdown', onPointerDown);
  // Anything the player actually does dismisses a running hint.
  document.addEventListener('pointerdown', cancelHint, true);
  const relayout = () => { if (game && $('#overlay').hidden) render(); else if (game) renderBoard(); };
  window.addEventListener('resize', relayout);
  window.addEventListener('orientationchange', () => setTimeout(relayout, 120));
  window.addEventListener('keydown', (e) => {
    if (!game || game.state.phase !== 'play') return;
    if (e.key === 'Escape') { stopHint(); armed = null; markTargets(null, false); render(); }
    if (e.key === 'h') { e.preventDefault(); if (hint) stopHint(); else startHint(); return; }
    cancelHint();
    if ((e.key === 'z' && (e.metaKey || e.ctrlKey)) || e.key === 'u') {
      e.preventDefault();
      if (game.undo()) afterAction();
    }
    if (e.key === ' ' || e.key === 'd') { e.preventDefault(); if (game.deal()) afterAction(); }
  });
}

export function boot() {
  bindChrome();
  titleScreen();
  // Handle for the console and for browser-driven tests.
  window.NineMeridians = {
    get game() { return game; },
    start,
    render,
    checkPhase,
  };
}
