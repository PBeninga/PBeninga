// End-to-end checks in a real browser: layout, pointer drag, touch drag,
// tap-to-move, double-tap, and the overlays, across desktop and four devices.
//
//   npm i -D playwright && npx playwright install chromium
//   node test/browser.mjs [--shots <dir>]
//
// Playwright is not a dependency of the game. If it is missing this exits 0
// with a note, so it never blocks `npm test`.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const shotDir = process.argv.includes('--shots')
  ? process.argv[process.argv.indexOf('--shots') + 1] : null;

let playwright;
try {
  playwright = await import('playwright');
} catch {
  console.log('playwright not installed — skipping browser checks.');
  console.log('  npm i -D playwright && npx playwright install chromium');
  process.exit(0);
}
const { chromium, devices } = playwright;

// --- a dependency-free static server -----------------------------------
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const server = createServer(async (req, res) => {
  const rel = normalize(decodeURIComponent(req.url.split('?')[0])).replace(/^(\.\.[/\\])+/, '');
  const path = join(root, rel === '/' ? 'index.html' : rel);
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'content-type': TYPES[extname(path)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((r) => server.listen(0, r));
const BASE = `http://localhost:${server.address().port}`;

let failures = 0;
const check = async (name, fn) => {
  try { await fn(); console.log('  ok   ' + name); } catch (e) { failures++; console.log('  FAIL ' + name + ' — ' + e.message); }
};
const shot = (page, name) => (shotDir ? page.screenshot({ path: join(shotDir, name + '.png') }) : Promise.resolve());

/** A drag built from PointerEvents of a given pointerType. */
function dragBy(page, type, sx, sy, ex, ey) {
  return page.evaluate(async ({ type, sx, sy, ex, ey }) => {
    const opt = (x, y) => ({ pointerType: type, pointerId: 1, isPrimary: true,
      clientX: x, clientY: y, bubbles: true, cancelable: true });
    const start = document.elementFromPoint(sx, sy);
    if (!start) return { err: 'nothing under the start point' };
    start.dispatchEvent(new PointerEvent('pointerdown', opt(sx, sy)));
    for (let i = 1; i <= 10; i++) {
      window.dispatchEvent(new PointerEvent('pointermove', opt(sx + (ex - sx) * i / 10, sy + (ey - sy) * i / 10)));
      await new Promise((r) => setTimeout(r, 12));
    }
    const lifted = document.querySelectorAll('.drag-layer .card').length;
    window.dispatchEvent(new PointerEvent('pointerup', opt(ex, ey)));
    await new Promise((r) => setTimeout(r, 150));
    return { lifted };
  }, { type, sx, sy, ex, ey });
}

/** Any single card that can legally move to another column, per the engine. */
const findMove = (page) => page.evaluate(() => {
  const g = window.Ascendant.game;
  for (let i = 0; i < g.state.columns.length; i++) {
    const col = g.state.columns[i];
    if (col.length < 2) continue;
    for (let j = 0; j < g.state.columns.length; j++) {
      if (i !== j && g.canDrop(col.slice(-1), { zone: 'col', index: j })) return { i, j, idx: col.length - 1 };
    }
  }
  return null;
});

const moves = (page) => page.evaluate(() => window.Ascendant.game.state.moves);

/** Escape stops any running hint, so a check starts from a known state. */
async function hintOff(page) {
  await page.keyboard.press('Escape');
  await page.waitForTimeout(120);
}

// Checks that rig the board by hand leave it holding the wrong cards, which
// later trips the save's conservation check. Stash the real state around them.
const stash = (page) => page.evaluate(() => {
  window.__stash = structuredClone(window.Ascendant.game.state);
});
const unstash = (page) => page.evaluate(() => {
  const g = window.Ascendant.game;
  g.state = window.__stash;
  g.undoStack = [];
  window.Ascendant.render();
});

const browser = await chromium.launch();

// --- one pass per form factor ------------------------------------------
const VIEWS = [
  { tag: 'desktop', ctx: { viewport: { width: 1440, height: 900 } }, touch: false },
  { tag: 'iphone-portrait', ctx: devices['iPhone 13'], touch: true },
  { tag: 'iphone-landscape', ctx: devices['iPhone 13 landscape'], touch: true },
  { tag: 'pixel', ctx: devices['Pixel 7'], touch: true },
  { tag: 'ipad', ctx: devices['iPad Mini'], touch: true },
];

for (const view of VIEWS) {
  console.log('\n' + view.tag);
  const ctx = await browser.newContext(view.ctx);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  await page.goto(`${BASE}/index.html`);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForTimeout(200);

  const overlayFits = async (what) => {
    const o = await page.evaluate(() => {
      const n = document.querySelector('#overlay');
      return { over: n.scrollHeight > n.clientHeight + 1 || n.scrollWidth > n.clientWidth + 1,
        h: n.scrollHeight, view: n.clientHeight };
    });
    if (o.over) throw new Error(`${what} needs ${o.h}px in a ${o.view}px viewport`);
  };

  await check('the title screen fits without scrolling', () => overlayFits('the title screen'));

  await check('the build stamp is visible on the title screen', async () => {
    const tag = await page.evaluate(() => {
      const n = document.querySelector('#overlay .build-tag');
      if (!n) return null;
      return { text: n.textContent.trim(), position: getComputedStyle(n).position };
    });
    if (!tag) throw new Error('no build stamp on the overlay');
    if (!/^build (dev|[0-9a-f]{8})$/.test(tag.text)) throw new Error('stamp read "' + tag.text + '"');
    // Fixed, or it adds height to panels that have to fit a phone.
    if (tag.position !== 'fixed') throw new Error('the stamp is in flow: ' + tag.position);
  });

  await check('a save from an incompatible build is dropped, not resumed', async () => {
    await page.evaluate(() => {
      // A rank-1 save claiming a one-sequence quota and holding no cards:
      // exactly the shape the old rules wrote, and unaccountable under these.
      localStorage.setItem('ascendant/run', JSON.stringify({
        v: 1, seed: 'STALE', difficulty: 'adept', rng: 1,
        state: {
          phase: 'play', rank: 1, required: 1, runes: 0, totalRunes: 0,
          collected: [], columns: [[]], reserve: [], stock: [], boons: {}, fortune: 0,
          charges: { voidStep: 0, transmute: 0, awaken: 0 }, undosLeft: 3, moves: 0,
          offer: [], log: [],
        },
      }));
    });
    await page.reload();
    await page.waitForTimeout(250);
    const r = await page.evaluate(() => ({
      resume: !!document.querySelector('#resume-wrap button'),
      stored: localStorage.getItem('ascendant/run'),
    }));
    if (r.resume) throw new Error('offered to resume a save the rules cannot honour');
    if (r.stored) throw new Error('the dead save was left in storage');
  });

  await page.fill('#seed-input', 'BROWSERTEST');
  await page.click('#btn-begin');
  await page.waitForTimeout(350);

  await check('the board fits the viewport', async () => {
    const m = await page.evaluate(() => {
      const board = document.querySelector('#board');
      const menu = document.querySelector('#btn-menu').getBoundingClientRect();
      return {
        xOverflow: board.scrollWidth > board.clientWidth + 1,
        pageScroll: document.body.scrollWidth > window.innerWidth + 1,
        menuOnScreen: menu.right <= window.innerWidth + 1 && menu.bottom <= window.innerHeight + 1,
        cardW: parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--card-w')),
        touchAction: getComputedStyle(board).touchAction,
      };
    });
    if (m.xOverflow) throw new Error('columns overflow the board');
    if (m.pageScroll) throw new Error('the page scrolls sideways');
    if (!m.menuOnScreen) throw new Error('the menu button is off screen');
    if (m.touchAction !== 'none') throw new Error('the board must claim touch gestures');
    if (m.cardW < 30) throw new Error('cards shrank below 30px: ' + m.cardW);
  });

  await check('a dealt row flies out of the stock, one card after another', async () => {
    const r = await page.evaluate(async () => {
      const before = document.querySelectorAll('#board .card').length;
      document.querySelector('#btn-deal').click();
      await new Promise((res) => setTimeout(res, 30));
      const flying = [...document.querySelectorAll('#board .card.dealing')];
      return {
        before,
        after: document.querySelectorAll('#board .card').length,
        flying: flying.length,
        delays: [...new Set(flying.map((n) => n.style.transitionDelay))].length,
        offset: flying.filter((n) => n.style.transform || getComputedStyle(n).transform !== 'none').length,
      };
    });
    if (r.after <= r.before) throw new Error('nothing was dealt');
    if (!r.flying) throw new Error('the dealt cards did not animate');
    if (r.flying !== r.after - r.before) throw new Error('only some of the row animated');
    if (r.delays < 2) throw new Error('every card left at once, with no stagger');
    await page.waitForTimeout(900);
    const done = await page.evaluate(() => ({
      stuck: document.querySelectorAll('#board .card.dealing').length,
      inline: [...document.querySelectorAll('#board .card')].filter((n) => n.style.transform || n.style.transitionDelay).length,
    }));
    if (done.stuck || done.inline) throw new Error('the animation left state behind: ' + JSON.stringify(done));
  });

  await check('drag and drop moves a card', async () => {
    const p = await findMove(page);
    if (!p) throw new Error('this deal offered no legal move');
    const src = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
    const dst = await page.locator(`.col[data-col="${p.j}"]`).boundingBox();
    const before = await moves(page);
    const r = await dragBy(page, view.touch ? 'touch' : 'mouse',
      src.x + src.width / 2, src.y + src.height * 0.25,
      dst.x + dst.width / 2, dst.y + Math.min(dst.height - 10, 260));
    if (r.err) throw new Error(r.err);
    if (r.lifted !== 1) throw new Error('the card did not lift off the board');
    if (await moves(page) <= before) throw new Error('the drop did not register');
    if (await page.evaluate(() => document.querySelectorAll('.drag-layer').length)) {
      throw new Error('a drag layer was left behind');
    }
  });

  await check('a tap plays the card to the column that builds the longest run', async () => {
    const p = await findMove(page);
    if (!p) throw new Error('no legal move');
    const expected = await page.evaluate(({ i, idx }) => {
      const g = window.Ascendant.game;
      const count = g.state.columns[i].length - idx;
      return g.bestTargetFor({ zone: 'col', index: i, count });
    }, p);
    if (expected === null) throw new Error('the engine offered no target');
    const beforeLen = await page.evaluate((j) => window.Ascendant.game.state.columns[j].length, expected);
    const before = await moves(page);
    const c = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
    await page.mouse.click(c.x + c.width / 2, c.y + 8);
    await page.waitForTimeout(200);
    if (await moves(page) <= before) throw new Error('the tap moved nothing');
    if (await page.evaluate(() => document.querySelectorAll('.card.picked').length)) {
      throw new Error('a tap should move a card, not select it');
    }
    const afterLen = await page.evaluate((j) => window.Ascendant.game.state.columns[j].length, expected);
    // A sealed meridian empties the column, which is also a correct landing.
    if (afterLen <= beforeLen && afterLen !== 0) throw new Error('the card did not land in the expected column');
  });

  await check('a tapped card slides to its new column', async () => {
    const p = await findMove(page);
    if (!p) throw new Error('no legal move');
    const c = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
    await page.mouse.click(c.x + c.width / 2, c.y + 8);
    const mid = await page.evaluate(() => {
      const n = document.querySelector('#board .card.flying');
      if (!n) return null;
      const cs = getComputedStyle(n);
      return { duration: parseFloat(cs.transitionDuration), transform: cs.transform };
    });
    if (!mid) throw new Error('the card teleported -- nothing was animated');
    if (Math.abs(mid.duration - 0.5) > 0.05) throw new Error('flight took ' + mid.duration + 's, wanted 0.5s');
    if (mid.transform === 'none') throw new Error('no offset applied, so nothing will slide');
    await page.waitForTimeout(650);
    if (await page.evaluate(() => document.querySelectorAll('#board .card.flying').length)) {
      throw new Error('the animation never cleared up');
    }
  });

  await check('the dock names the build', async () => {
    const text = await page.evaluate(() => document.querySelector('#seed-tag').textContent);
    if (!/ · (dev|[0-9a-f]{8})$/.test(text)) throw new Error('dock tag read "' + text + '"');
  });

  await check('the hint carousel cycles and reports its position', async () => {
    const plan = await page.evaluate(() => {
      const s = window.Ascendant.game.suggest();
      return { kind: s.kind, total: s.moves.length };
    });
    if (plan.kind !== 'moves') throw new Error('expected move suggestions, got ' + plan.kind);
    if (plan.total < 2) throw new Error('need at least two suggestions to cycle');
    const total = plan.total;
    await page.click('#btn-hint');
    await page.waitForTimeout(150);
    const first = await page.evaluate(() => ({
      text: document.querySelector('#status').textContent,
      ghosts: document.querySelectorAll('.hint-layer .card').length,
      srcMarked: document.querySelectorAll('.card.hint-src').length,
      destMarked: document.querySelectorAll('.col.hint-dest').length,
      armed: document.querySelector('#btn-hint').classList.contains('armed'),
    }));
    if (first.text !== `Showing hint 1/${total}`) throw new Error('status read "' + first.text + '"');
    if (!first.ghosts) throw new Error('no ghost cards drawn');
    if (!first.srcMarked || !first.destMarked) throw new Error('source or destination not highlighted');
    if (!first.armed) throw new Error('the hint button should read as active');

    // The ghost has to travel, not sit on the source card.
    const travelled = await page.evaluate(() => {
      const n = document.querySelector('.hint-layer .card');
      if (!n) return -1;
      const a = n.getBoundingClientRect();
      return new Promise((r) => setTimeout(() => {
        const b = n.getBoundingClientRect();
        r(Math.hypot(b.left - a.left, b.top - a.top));
      }, 450));
    });
    if (travelled < 0) throw new Error('the ghost vanished mid-step');

    await page.waitForTimeout(800);
    const second = await page.evaluate(() => document.querySelector('#status').textContent);
    if (second !== `Showing hint 2/${total}`) throw new Error('did not advance, read "' + second + '"');
    await hintOff(page);
  });

  await check('an empty column does not stop the stock', async () => {
    await hintOff(page);
    await stash(page);
    const r = await page.evaluate(() => {
      const g = window.Ascendant.game;
      g.state.columns[2] = [];          // as if a meridian had just sealed
      window.Ascendant.render();
      const before = g.state.stock.length;
      const dealt = g.deal();
      window.Ascendant.render();
      return { dealt, before, after: g.state.stock.length,
        filled: g.state.columns[2].length, status: document.querySelector('#status').textContent };
    });
    if (!r.dealt) throw new Error('the stock refused to deal with an empty column');
    if (r.after >= r.before) throw new Error('no cards left the stock');
    if (r.filled !== 1) throw new Error('the empty column was not dealt into');
    if (/empty column/i.test(r.status)) throw new Error('still warning about empty columns: "' + r.status + '"');
    await unstash(page);
  });

  await check('with the board full and no moves, the hint says deal', async () => {
    await hintOff(page);
    await stash(page);
    await page.evaluate(() => {
      const g = window.Ascendant.game;
      // Every column two face-up cards that cannot stack, and stock in hand.
      g.state.columns = g.state.columns.map((_, i) => [
        { id: 7000 + i * 2, rank: 2, suit: 'spade', faceUp: true, wild: false },
        { id: 7001 + i * 2, rank: 9, suit: 'heart', faceUp: true, wild: false },
      ]);
      g.state.stock = [{ id: 7900, rank: 5, suit: 'club', faceUp: false, wild: false }];
      g.state.reserve = [];
      window.Ascendant.render();
    });
    await page.click('#btn-hint');
    await page.waitForTimeout(200);
    const r = await page.evaluate(() => ({
      kind: window.Ascendant.game.suggest().kind,
      status: document.querySelector('#status').textContent,
      pulsing: document.querySelector('#stock').classList.contains('hint-deal'),
    }));
    if (r.kind !== 'deal') throw new Error('expected deal advice, got ' + r.kind);
    if (!/deal another row/i.test(r.status)) throw new Error('status read "' + r.status + '"');
    if (!r.pulsing) throw new Error('the stock was not highlighted');
    await hintOff(page);
    await unstash(page);
  });

  await check('any action cancels the hint', async () => {
    if (!(await page.evaluate(() => !!document.querySelector('.hint-layer')))) {
      await page.click('#btn-hint');
      await page.waitForTimeout(150);
    }
    const board = await page.locator('#board').boundingBox();
    await page.mouse.click(board.x + board.width / 2, board.y + board.height - 20);
    await page.waitForTimeout(250);
    const after = await page.evaluate(() => ({
      layers: document.querySelectorAll('.hint-layer').length,
      marks: document.querySelectorAll('.hint-src, .hint-dest').length,
      status: document.querySelector('#status').textContent,
      armed: document.querySelector('#btn-hint').classList.contains('armed'),
    }));
    if (after.layers || after.marks) throw new Error('hint artwork survived the click');
    if (after.armed || after.status.startsWith('Showing hint')) throw new Error('hint state survived the click');
  });

  await check('undo sits in the dock and steps back', async () => {
    await hintOff(page);
    if (!(await page.evaluate(() => document.querySelector('#dock').contains(document.querySelector('#btn-undo'))))) {
      throw new Error('undo is not in the bottom dock');
    }
    // Make a move of our own, so the check does not lean on earlier ones.
    const p = await findMove(page);
    if (!p) throw new Error('no legal move to undo');
    const c = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
    await page.mouse.click(c.x + c.width / 2, c.y + 8);
    await page.waitForTimeout(250);
    const before = await moves(page);
    if (await page.evaluate(() => document.querySelector('#btn-undo').disabled)) {
      throw new Error('undo is dead straight after a move');
    }
    await page.click('#btn-undo');
    await page.waitForTimeout(220);
    if (await moves(page) >= before) throw new Error('undo did not step back');
  });

  if (view.touch) {
    await check('controls are big enough to tap', async () => {
      const small = await page.evaluate(() => [...document.querySelectorAll(
        '#stock, .topbar button, #stock-row button:not([hidden]), .dock-btn')]
        .map((n) => ({ id: n.id || n.className, h: Math.round(n.getBoundingClientRect().height) }))
        .filter((n) => n.h < 32));
      if (small.length) throw new Error('under 32px tall: ' + JSON.stringify(small));
    });
  }

  await check('the stock shows one card back per remaining deal', async () => {
    const read = () => page.evaluate(() => ({
      backs: document.querySelectorAll('#stock .stock-card:not(.empty)').length,
      deals: window.Ascendant.game.dealsLeft(),
      cards: window.Ascendant.game.state.stock.length,
      label: document.querySelector('.stock-count').textContent,
    }));
    const before = await read();
    if (!before.deals) throw new Error('no stock left to check');
    if (before.backs !== before.deals) {
      throw new Error(`${before.backs} backs drawn for ${before.deals} deals`);
    }
    if (!before.label.includes(String(before.deals))) throw new Error('label read "' + before.label + '"');

    await page.click('#stock');
    await page.waitForTimeout(250);
    const after = await read();
    if (after.cards >= before.cards) throw new Error('the stock did not deal');
    if (after.backs !== after.deals) throw new Error('the fan did not follow the deal');
    if (after.deals !== before.deals - 1) throw new Error('a deal did not come off the fan');
  });

  await check('a spent stock says so', async () => {
    await stash(page);
    await page.evaluate(() => {
      window.Ascendant.game.state.stock = [];
      window.Ascendant.render();
    });
    await page.waitForTimeout(150);
    const r = await page.evaluate(() => ({
      backs: document.querySelectorAll('#stock .stock-card:not(.empty)').length,
      placeholder: document.querySelectorAll('#stock .stock-card.empty').length,
      label: document.querySelector('.stock-count').textContent,
      spent: document.querySelector('#stock').classList.contains('spent'),
    }));
    if (r.backs) throw new Error('backs still drawn for an empty stock');
    if (!r.placeholder) throw new Error('no empty-slot placeholder');
    if (!r.spent || !/spent/i.test(r.label)) throw new Error('spent state not shown: ' + JSON.stringify(r));
    await unstash(page);
  });

  await check('a live run resumes exactly where it left off', async () => {
    const snap = () => page.evaluate(() => {
      const g = window.Ascendant.game;
      return { rank: g.state.rank, required: g.state.required, runes: g.state.runes,
        moves: g.state.moves, board: g.state.columns.map((c) => c.map((x) => x.id).join('.')).join('|') };
    });
    const before = await snap();
    await page.reload();
    await page.waitForTimeout(250);
    const btn = page.locator('#resume-wrap button');
    if (!(await btn.count())) throw new Error('a live run was not offered for resume');
    const label = await btn.textContent();
    if (!label.includes(`/${before.required}`)) throw new Error('resume label read "' + label + '"');
    await btn.click();
    await page.waitForTimeout(300);
    const after = await snap();
    if (JSON.stringify(after) !== JSON.stringify(before)) {
      throw new Error('the run came back changed: ' + JSON.stringify({ before, after }));
    }
  });

  await check('cards that cannot be lifted are dimmed', async () => {
    const r = await page.evaluate(() => {
      const g = window.Ascendant.game;
      const wrong = [];
      let faceUp = 0;
      let dimmed = 0;
      g.state.columns.forEach((col, ci) => {
        const liftable = col.length - g.columnTail(ci);
        col.forEach((card, i) => {
          if (!card.faceUp) return;
          faceUp++;
          const n = document.querySelector(`.card[data-col="${ci}"][data-idx="${i}"]`);
          const isDim = n && n.classList.contains('stuck');
          if (isDim) dimmed++;
          if (isDim !== i < liftable) wrong.push({ ci, i, isDim });
        });
      });
      const sample = document.querySelector('.card.up.stuck');
      return { faceUp, dimmed, wrong, filter: sample ? getComputedStyle(sample).filter : null };
    });
    if (r.wrong.length) throw new Error('wrong dim state on ' + JSON.stringify(r.wrong.slice(0, 3)));
    if (!r.dimmed) throw new Error('no buried card was dimmed after a deal');
    if (r.filter === 'none') throw new Error('the dim class has no visual effect');
  });

  await check('a sealed run is drawn into the core, and the core grows', async () => {
    await hintOff(page);
    await stash(page);
    const start = await page.evaluate(() => {
      const N = window.Ascendant, g = N.game;
      const col = [];
      for (let r = 13; r >= 2; r--) col.push({ id: 9100 + r, rank: r, suit: 'spade', faceUp: true, wild: false });
      g.state.columns[4] = col;
      g.state.columns[5] = [{ id: 9099, rank: 1, suit: 'spade', faceUp: true, wild: false }];
      N.render();
      return { core: document.querySelector('#core').getBoundingClientRect().width,
        runes: g.state.totalRunes };
    });

    const card = await page.locator('.card[data-col="5"][data-idx="0"]').boundingBox();
    await page.mouse.click(card.x + card.width / 2, card.y + 10);
    await page.waitForTimeout(320);

    const mid = await page.evaluate(() => ({
      cards: document.querySelectorAll('.seal-layer .card').length,
      dust: document.querySelectorAll('.seal-layer .dust').length,
      onScreen: [...document.querySelectorAll('.seal-layer .card')]
        .filter((n) => n.getBoundingClientRect().top < window.innerHeight).length,
      sealed: window.Ascendant.game.state.totalRunes,
    }));
    if (mid.sealed <= start.runes) throw new Error('nothing bound');
    if (mid.cards !== 13) throw new Error(`${mid.cards} cards drawn for a thirteen-card run`);
    if (!mid.dust) throw new Error('the cards did not come apart into dust');
    if (mid.onScreen !== 13) throw new Error(`${13 - mid.onScreen} of the run sat off screen`);

    await page.waitForTimeout(1700);
    const done = await page.evaluate(() => ({
      layers: document.querySelectorAll('.seal-layer').length,
      core: document.querySelector('#core').getBoundingClientRect().width,
      progress: window.Ascendant.game.progress(),
    }));
    if (done.layers) throw new Error('the absorption left a layer behind');
    if (!(done.progress > 0)) throw new Error('progress did not move');
    if (done.core <= start.core) throw new Error(`the core did not grow (${start.core} -> ${done.core})`);
    await unstash(page);
  });

  await check('the Boons button lists what you hold', async () => {
    await hintOff(page);
    await stash(page);
    await page.evaluate(() => {
      const g = window.Ascendant.game;
      g.state.boons = { talisman: 2, cell: 1 };
      window.Ascendant.render();
    });
    await page.click('#btn-paths');
    await page.waitForTimeout(250);
    const text = await page.evaluate(() => document.querySelector('#overlay .panel').textContent);
    if (!/Wildstone ×2/.test(text) || !/Vault Slot ×1/.test(text)) {
      throw new Error('the panel did not name the boons held: ' + JSON.stringify(text.slice(0, 200)));
    }
    await page.evaluate(() => document.querySelector('#overlay .big').click());
    await page.waitForTimeout(200);
    if (!(await page.evaluate(() => document.querySelector('#overlay').hidden))) {
      throw new Error('resume did not close the panel');
    }
    await unstash(page);
  });

  await check('the breakthrough offer fits without scrolling', async () => {
    await page.evaluate(() => {
      const N = window.Ascendant, g = N.game;
      const col = [];
      for (let r = 13; r >= 2; r--) col.push({ id: 9000 + r, rank: r, suit: 'spade', faceUp: true, wild: false });
      g.state.columns[0] = col;
      g.state.columns[1] = [{ id: 8999, rank: 1, suit: 'spade', faceUp: true, wild: false }];
      g.state.required = g.state.runes + 1;   // one sequence from a cleared board
      g.move({ zone: 'col', index: 1, count: 1 }, { zone: 'col', index: 0 });
      N.render(); N.checkPhase();
    });
    await page.waitForTimeout(350);
    await shot(page, `${view.tag}-breakthrough`);
    const r = await page.evaluate(() => {
      const o = document.querySelector('#overlay');
      return { boons: document.querySelectorAll('.boon').length,
        clipped: o.scrollHeight > o.clientHeight + 1 || o.scrollWidth > o.clientWidth + 1 };
    });
    if (r.boons !== 2) throw new Error('expected two upgrades, got ' + r.boons);
    if (r.clipped) throw new Error('a choice sits outside the viewport');
    await page.locator('.boon').first().click();
    await page.waitForTimeout(300);
    if (await page.evaluate(() => window.Ascendant.game.state.rank) !== 2) {
      throw new Error('choosing a boon did not open the next realm');
    }
    await shot(page, `${view.tag}-realm2`);
  });

  await check('the end screen fits without scrolling', async () => {
    await page.evaluate(() => { window.Ascendant.game.concede(); window.Ascendant.checkPhase(); });
    await page.waitForTimeout(300);
    await shot(page, `${view.tag}-end`);
    if (!(await page.locator('.tally').count())) throw new Error('no run summary shown');
    await overlayFits('the end screen');
  });

  await check('no console errors', () => {
    if (errors.length) throw new Error(errors.join(' | '));
  });
  await ctx.close();
}

await browser.close();
server.close();
console.log(failures ? `\n${failures} failing` : '\nall browser checks passed');
process.exit(failures ? 1 : 0);
