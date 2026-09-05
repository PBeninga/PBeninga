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
  const g = window.NineMeridians.game;
  for (let i = 0; i < g.state.columns.length; i++) {
    const col = g.state.columns[i];
    if (col.length < 2) continue;
    for (let j = 0; j < g.state.columns.length; j++) {
      if (i !== j && g.canDrop(col.slice(-1), { zone: 'col', index: j })) return { i, j, idx: col.length - 1 };
    }
  }
  return null;
});

const moves = (page) => page.evaluate(() => window.NineMeridians.game.state.moves);

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

  await check('tap to pick up, tap to place', async () => {
    const p = await findMove(page);
    if (!p) throw new Error('no legal move');
    const before = await moves(page);
    const c = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
    await page.mouse.click(c.x + c.width / 2, c.y + 8);
    await page.waitForTimeout(120);
    if (!(await page.evaluate(() => document.querySelectorAll('.card.picked').length))) {
      throw new Error('the tap did not select anything');
    }
    const d = await page.locator(`.col[data-col="${p.j}"]`).boundingBox();
    await page.mouse.click(d.x + d.width / 2, d.y + Math.min(d.height - 10, 260));
    await page.waitForTimeout(180);
    if (await moves(page) <= before) throw new Error('the second tap did not place the card');
  });

  if (view.touch) {
    await check('double-tap sends a card home', async () => {
      const p = await findMove(page);
      if (!p) throw new Error('no legal move');
      const before = await moves(page);
      const c = await page.locator(`.card[data-col="${p.i}"][data-idx="${p.idx}"]`).boundingBox();
      const [x, y] = [c.x + c.width / 2, c.y + 8];
      await page.touchscreen.tap(x, y);
      await page.waitForTimeout(70);
      await page.touchscreen.tap(x, y);
      await page.waitForTimeout(220);
      if (await moves(page) <= before) throw new Error('double-tap moved nothing');
    });

    await check('controls are big enough to tap', async () => {
      const small = await page.evaluate(() => [...document.querySelectorAll('#stock, .hud button:not([hidden])')]
        .map((n) => ({ id: n.id || n.className, h: Math.round(n.getBoundingClientRect().height) }))
        .filter((n) => n.h < 32));
      if (small.length) throw new Error('under 32px tall: ' + JSON.stringify(small));
    });
  }

  await check('the stock deals a row', async () => {
    const before = await page.evaluate(() => window.NineMeridians.game.state.stock.length);
    await page.click('#stock');
    await page.waitForTimeout(220);
    if (await page.evaluate(() => window.NineMeridians.game.state.stock.length) >= before) {
      throw new Error('the stock did not deal');
    }
  });

  await check('the breakthrough offer fits without scrolling', async () => {
    await page.evaluate(() => {
      const N = window.NineMeridians, g = N.game;
      const col = [];
      for (let r = 13; r >= 2; r--) col.push({ id: 9000 + r, rank: r, suit: 'spade', faceUp: true, wild: false });
      g.state.columns[0] = col;
      g.state.columns[1] = [{ id: 8999, rank: 1, suit: 'spade', faceUp: true, wild: false }];
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
    if (r.boons !== 3) throw new Error('expected three boons, got ' + r.boons);
    if (r.clipped) throw new Error('a choice sits outside the viewport');
    await page.locator('.boon').first().click();
    await page.waitForTimeout(300);
    if (await page.evaluate(() => window.NineMeridians.game.state.realm) !== 2) {
      throw new Error('choosing a boon did not open the next realm');
    }
    await shot(page, `${view.tag}-realm2`);
  });

  await check('the end screen fits without scrolling', async () => {
    await page.evaluate(() => { window.NineMeridians.game.concede(); window.NineMeridians.checkPhase(); });
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
