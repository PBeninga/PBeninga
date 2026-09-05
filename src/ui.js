// Board rendering and input. Everything here talks to the engine; no rules live
// in this file.

import { Game, REALMS, ASCENSION, DIFFICULTIES, serialize, deserialize } from './engine.js';
import { SUITS, SUIT_GLYPH, SUIT_NAME, RANK_LABEL } from './cards.js';
import { PATH_BY_KEY } from './paths.js';
import { randomSeed } from './rng.js';

const SAVE_KEY = 'nine-meridians/run';
const BEST_KEY = 'nine-meridians/best';

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, html) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html !== undefined) n.innerHTML = html;
  return n;
};

let game = null;
let selection = null;        // {zone:'col'|'reserve', index, count}
let armed = null;            // 'void' | 'transmute' | 'awaken'
let pendingTransmute = null;
let drag = null;
let lastSeen = { meridians: 0 };

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
  const gap = (cols > 11 ? 6 : 9) - (narrow ? 4 : 0);
  const padX = narrow ? 12 : 32;
  const avail = board.clientWidth - padX - gap * (cols - 1);
  // Fit the width, but never let a card grow so tall that a column of five
  // cannot breathe.
  const byWidth = Math.floor(avail / cols);
  const byHeight = Math.floor((board.clientHeight - 20) * 0.34 / 1.4);
  const w = Math.max(narrow ? 32 : 40, Math.min(124, byWidth, byHeight));
  const h = Math.round(w * 1.4);
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
  return { w, h, boardH: board.clientHeight - 20 };
}

/** Stack offsets, squeezed uniformly so the tallest column still fits. */
function offsetsFor(columns, h, boardH) {
  const upGap = h * 0.30;
  const downGap = h * 0.15;
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
  renderTicker();
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
  for (let i = 0; i < s.required; i++) {
    pips.appendChild(el('div', 'pip' + (i < s.meridians ? ' on' : '')));
  }
  $('#meridian-label').textContent = `${s.meridians}/${s.required} meridians`;

  const chips = $('#boon-chips');
  chips.innerHTML = '';
  for (const [key, tier] of Object.entries(s.boons)) {
    const path = PATH_BY_KEY[key];
    chips.appendChild(el('span', 'chip',
      `${path.hanzi} <b>${path.tiers[tier - 1].name}</b>`));
  }
  if (s.fortune) chips.appendChild(el('span', 'chip', `天緣 <b>Fortune ×${s.fortune}</b>`));

  const stock = $('#stock');
  stock.textContent = s.stock.length;
  stock.classList.toggle('spent', s.stock.length === 0);
  stock.classList.toggle('blocked', s.stock.length > 0 && !game.canDeal());
  stock.title = s.stock.length === 0 ? 'The stock is spent.'
    : game.canDeal() ? 'Deal one card to every column.'
    : 'Fill every empty column before the heavens will deal again.';

  const cells = $('#cells');
  cells.innerHTML = '';
  $('#cells-wrap').hidden = s.reserve.length === 0;
  s.reserve.forEach((card, i) => {
    const c = el('div', 'cell' + (card ? ' filled' : ''));
    c.dataset.cell = i;
    if (card) c.appendChild(el('span', 'mini', miniLabel(card)));
    if (selection && selection.zone === 'reserve' && selection.index === i) {
      c.style.boxShadow = '0 0 0 2px var(--jade)';
    }
    cells.appendChild(c);
  });

  chargeButton('#btn-void', 'void', s.charges.voidStep, 'Void Step');
  chargeButton('#btn-transmute', 'transmute', s.charges.transmute, 'Transmute');
  chargeButton('#btn-awaken', 'awaken', s.charges.awaken, 'Awaken');

  const undo = $('#btn-undo');
  undo.disabled = s.undosLeft <= 0 || !game.undoStack.length;
  undo.innerHTML = `Undo <span class="count">${s.undosLeft}</span>`;
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
  const { h, boardH } = measure();
  const cols = game.state.columns;
  const off = offsetsFor(cols, h, boardH);

  board.innerHTML = '';
  cols.forEach((col, ci) => {
    const colEl = el('div', 'col' + (col.length ? '' : ' empty'));
    colEl.dataset.col = ci;
    let top = 0;
    col.forEach((card, i) => {
      const n = cardEl(card);
      n.style.top = Math.round(top) + 'px';
      n.dataset.col = ci;
      n.dataset.idx = i;
      if (isSelected(ci, i)) n.classList.add('picked');
      if (drag && drag.active && drag.zone === 'col' && drag.index === ci && i >= col.length - drag.count) {
        n.classList.add('ghost');
      }
      colEl.appendChild(n);
      if (i < col.length - 1) top += card.faceUp ? off.up : off.down;
    });
    board.appendChild(colEl);
  });
}

function isSelected(colIndex, cardIndex) {
  if (!selection || selection.zone !== 'col' || selection.index !== colIndex) return false;
  const col = game.state.columns[colIndex];
  return cardIndex >= col.length - selection.count;
}

function renderTicker() {
  const s = game.state;
  const t = $('#ticker');
  t.innerHTML = '';
  t.appendChild(el('span', '', s.log[0] || ''));
  if (game.isStagnant()) {
    t.appendChild(el('span', 'warn', '⚠ No moves remain in the tableau — undo, spend a technique, or abandon the climb.'));
  }
  const tag = el('span', '', `${game.seed} · ${DIFFICULTIES[game.difficulty].name}`);
  tag.id = 'seed-tag';
  tag.style.cssText = 'margin-left:auto;opacity:.6';
  t.appendChild(tag);
}

// ------------------------------------------------------------- highlights

function markTargets(run, on) {
  document.querySelectorAll('.col').forEach((colEl) => {
    colEl.classList.remove('drop-ok', 'drop-forced');
    if (!on) return;
    const i = Number(colEl.dataset.col);
    if (drag && drag.zone === 'col' && drag.index === i) return;
    if (selection && selection.zone === 'col' && selection.index === i) return;
    if (armed === 'void' && game.canDrop(run, { zone: 'col', index: i }, { force: true })) {
      colEl.classList.add('drop-forced');
    } else if (game.canDrop(run, { zone: 'col', index: i })) {
      colEl.classList.add('drop-ok');
    }
  });
}

// ------------------------------------------------------------- act on move

function attempt(from, to) {
  const force = armed === 'void';
  const before = game.state.totalMeridians;
  const ok = game.move(from, to, { force });
  if (ok) {
    if (force) armed = null;
    if (game.state.totalMeridians > before) toast('Meridian sealed');
    afterAction();
  }
  return ok;
}

function afterAction() {
  selection = null;
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

// ----------------------------------------------------------------- input

function cardRef(node) {
  return { col: Number(node.dataset.col), idx: Number(node.dataset.idx) };
}

function onPointerDown(ev) {
  if (!game || game.state.phase !== 'play') return;
  const cellEl = ev.target.closest('.cell');
  if (cellEl) return onCellTap(Number(cellEl.dataset.cell));

  const node = ev.target.closest('.card');
  if (!node) {
    const colEl = ev.target.closest('.col');
    if (colEl) onColumnTap(Number(colEl.dataset.col));
    return;
  }
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
  const grabbable = game.canGrab(col, count);

  drag = {
    zone: 'col', index: col, count, active: false,
    startX: ev.clientX, startY: ev.clientY, grabbable, node,
  };
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp, { once: true });
}

function onPointerMove(ev) {
  if (!drag) return;
  const dx = ev.clientX - drag.startX;
  const dy = ev.clientY - drag.startY;
  if (!drag.active) {
    if (Math.hypot(dx, dy) < 7 || !drag.grabbable) return;
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
  drag.dy = ev.clientY - rect.top;
  const layer = el('div', 'drag-layer');
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  run.forEach((card, i) => {
    const n = cardEl(card);
    n.style.top = i * h * 0.30 + 'px';
    layer.appendChild(n);
  });
  drag.layer = layer;
  document.body.appendChild(layer);
  selection = null;
  renderBoard();
  markTargets(run, true);
}

function positionDrag(ev) {
  if (!drag.active) return;
  for (const n of drag.layer.children) {
    n.style.left = ev.clientX - drag.dx + 'px';
  }
  const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-h'));
  [...drag.layer.children].forEach((n, i) => {
    n.style.top = ev.clientY - drag.dy + i * h * 0.30 + 'px';
  });
}

function onPointerUp(ev) {
  window.removeEventListener('pointermove', onPointerMove);
  if (!drag) return;
  const d = drag;
  if (d.active) {
    d.layer.remove();
    drag = null;
    const under = document.elementFromPoint(ev.clientX, ev.clientY);
    const cell = under && under.closest('.cell');
    const colEl = under && under.closest('.col');
    if (cell) attempt({ zone: 'col', index: d.index, count: d.count }, { zone: 'reserve', index: Number(cell.dataset.cell) });
    else if (colEl && Number(colEl.dataset.col) !== d.index) {
      attempt({ zone: 'col', index: d.index, count: d.count }, { zone: 'col', index: Number(colEl.dataset.col) });
    } else afterAction();
    return;
  }
  drag = null;
  onCardTap(d.index, d.count, d.grabbable);
}

function onCardTap(colIndex, count, grabbable) {
  if (selection && !(selection.zone === 'col' && selection.index === colIndex)) {
    if (attempt(selection, { zone: 'col', index: colIndex })) return;
  }
  if (selection && selection.zone === 'col' && selection.index === colIndex && selection.count === count) {
    selection = null;
  } else if (grabbable) {
    selection = { zone: 'col', index: colIndex, count };
  } else {
    selection = null;
  }
  const run = selection ? game.state.columns[colIndex].slice(-count) : null;
  render();
  markTargets(run, !!selection);
}

function onColumnTap(colIndex) {
  if (!selection) return;
  attempt(selection, { zone: 'col', index: colIndex });
}

function onCellTap(index) {
  const card = game.state.reserve[index];
  if (armed === 'transmute' && card) return openSuitPicker({ zone: 'reserve', index });
  if (armed === 'awaken' && card) {
    if (game.awaken({ zone: 'reserve', index })) { armed = null; afterAction(); }
    return;
  }
  if (selection) {
    if (selection.zone === 'reserve' && selection.index === index) { selection = null; return render(); }
    if (attempt(selection, { zone: 'reserve', index })) return;
  }
  if (card) {
    selection = { zone: 'reserve', index, count: 1 };
    render();
    markTargets([card], true);
  }
}

function onDoubleClick(ev) {
  if (!game || game.state.phase !== 'play' || armed) return;
  const node = ev.target.closest('.card');
  if (!node) return;
  const { col, idx } = cardRef(node);
  const column = game.state.columns[col];
  if (!column[idx] || !column[idx].faceUp) return;
  const count = column.length - idx;
  const target = game.autoTarget(col, count);
  if (target === null) return;
  selection = null;
  attempt({ zone: 'col', index: col, count }, { zone: 'col', index: target });
}

// -------------------------------------------------------------- overlays

function overlay(html) {
  const o = $('#overlay');
  o.innerHTML = '';
  o.appendChild(html);
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
  return `<div class="rules">
      <h3>The Tableau</h3>
      <ul>
        <li>Build <b>down by rank</b> onto any card — suit does not matter while stacking.</li>
        <li>Lift a group only when it is a <b>descending run of one suit</b>. Drag it, or tap to pick up and tap to place.</li>
        <li><b>Double-click</b> a card to send it to the best spot automatically.</li>
        <li>An empty column accepts anything. The stock deals one card to every column — but only when no column stands empty.</li>
      </ul>
      <h3>Cultivation</h3>
      <ul>
        <li>A complete <b>K→A run of one suit</b> is a <b>meridian</b>. It seals itself and leaves the column.</li>
        <li>Seal the realm's quota to <b>break through</b>: choose a boon, then face a fresh, larger tableau.</li>
        <li>Realm 1 asks for one meridian. Realm 6 asks for six. The paths you walk are what close that gap.</li>
        <li>Three undos per realm. If the tableau locks up and the stock is spent, the climb ends.</li>
      </ul>
      <h3>Techniques &amp; Keys</h3>
      <ul>
        <li><b>Talismans</b> (☯) stand in for any rank and suit, in a stack or inside a sealed meridian.</li>
        <li><b>Void Step</b>, <b>Transmute</b> and <b>Awaken</b> are charges: arm the button, then click a card.</li>
        <li><b>Space</b> deals · <b>U</b> or <b>Ctrl/⌘+Z</b> undoes · <b>Esc</b> clears a selection.</li>
      </ul>
    </div>`;
}

function pauseScreen() {
  const p = el('div', 'panel');
  p.appendChild(el('div', 'hanzi-big', '靜坐'));
  p.appendChild(el('h2', '', 'Meditation'));
  p.appendChild(el('p', '', 'The climb waits.'));
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
    <p class="lead">A cultivation roguelike played in Spider solitaire. Seal a full K→A
    sequence and you break through to the next realm — but each realm demands one more
    sequence than the last.</p>
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
  const saved = localStorage.getItem(SAVE_KEY);
  if (saved) {
    const wrap = $('#resume-wrap');
    const b = el('button', '', 'Resume the climb');
    b.style.marginTop = '12px';
    b.onclick = () => {
      const restored = deserialize(saved);
      if (!restored) return;
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
    `${REALMS[s.realm - 1].name} is complete. Ahead lies <b style="color:var(--gold)">${next.name}</b>, `
    + `which demands <b style="color:var(--gold)">${Math.max(1, s.realm + 1 - s.fortune)} meridians</b>.`));
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

function save() {
  try {
    if (game.state.phase === 'play' || game.state.phase === 'breakthrough') {
      localStorage.setItem(SAVE_KEY, serialize(game));
    }
  } catch (_) { /* private browsing */ }
}

function start(seed, difficulty) {
  game = new Game({ seed, difficulty });
  selection = null;
  armed = null;
  lastSeen.meridians = 0;
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
      armed = armed === mode ? null : mode;
      selection = null;
      render();
    });
  }
  $('#btn-menu').addEventListener('click', () => {
    if (!game) titleScreen();
    else pauseScreen();
  });
  $('#board').addEventListener('pointerdown', onPointerDown);
  $('#board').addEventListener('dblclick', onDoubleClick);
  $('#cells').addEventListener('pointerdown', onPointerDown);
  window.addEventListener('resize', () => { if (game) renderBoard(); });
  window.addEventListener('keydown', (e) => {
    if (!game || game.state.phase !== 'play') return;
    if (e.key === 'Escape') { selection = null; armed = null; markTargets(null, false); render(); }
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
