// Inlines the ES modules and stylesheet into a single self-contained page.
// No bundler: the modules are concatenated in dependency order with their
// import/export syntax stripped, which is enough for a project this size.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const MODULES = ['rng.js', 'cards.js', 'paths.js', 'engine.js', 'ads.js', 'sound.js', 'records.js', 'ui.js'];

function stripModuleSyntax(src) {
  return src
    .replace(/^import[\s\S]*?from\s*['"][^'"]*['"];\s*$/gm, '')  // import ... from '...'
    .replace(/^export\s*\{[^}]*\};\s*$/gm, '')                    // bare re-exports
    .replace(/^export\s+(?=(const|let|var|function|class|async))/gm, '');
}

const stripped = MODULES.map((name) =>
  [name, stripModuleSyntax(readFileSync(join(root, 'src', name), 'utf8')).trim()]);
checkNames(stripped);

const bundle = stripped
  .map(([name, src]) => `/* ---- src/${name} ---- */\n${src}\n`)
  .join('\n');
checkParses(bundle);

/**
 * The modules become one scope, so two of them declaring the same top-level
 * name is a syntax error in the shipped file and nowhere else -- the dev page
 * loads real modules, each with a scope of its own, and never notices. Say so
 * here, by name, rather than letting the browser report it as a blank page.
 */
function checkNames(sources) {
  const owner = new Map();
  const clashes = [];
  const DECL = /^(?:export\s+)?(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)/gm;
  for (const [name, src] of sources) {
    const seen = new Set();
    let m;
    DECL.lastIndex = 0;
    while ((m = DECL.exec(src))) seen.add(m[1]);
    for (const id of seen) {
      if (owner.has(id)) clashes.push(`${id} (${owner.get(id)} and ${name})`);
      else owner.set(id, name);
    }
  }
  if (clashes.length) {
    throw new Error('two modules declare the same top-level name:\n  ' + clashes.join('\n  '));
  }
}

/** And whatever the checks above miss, the parser will not. */
function checkParses(js) {
  try {
    new Function(js);
  } catch (e) {
    throw new Error(`the bundle does not parse: ${e.message}`);
  }
}

// A short content hash, so a player can see at a glance which build they have
// and whether a cached page is stale.
const css = readFileSync(join(root, 'src', 'style.css'), 'utf8');
const build = createHash('sha256').update(bundle).update(css).digest('hex').slice(0, 8);
const html = readFileSync(join(root, 'index.html'), 'utf8');

const body = html
  .replace(/^[\s\S]*?<body>\n?/, '')
  .replace(/<\/body>[\s\S]*$/, '')
  .replace(/<script type="module">[\s\S]*?<\/script>\s*/, '');

const script = `<script>\n${bundle.replace('__BUILD__', build)}\nboot();\n</script>\n`;
const style = `<style>\n${css}</style>\n`;
const title = (html.match(/<title>([^<]*)<\/title>/) || [, 'Nine Meridians'])[1];

mkdirSync(join(root, 'dist'), { recursive: true });

// Standalone page: open it straight from the filesystem.
writeFileSync(join(root, 'dist', 'index.html'), `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>${title}</title>
${style}</head>
<body>
${body}${script}</body>
</html>
`);

// The native wrapper's web root. Capacitor copies this directory into the app
// bundle, so the shipped game is the same single file the web gets.
mkdirSync(join(root, 'dist', 'www'), { recursive: true });
writeFileSync(join(root, 'dist', 'www', 'index.html'), readFileSync(join(root, 'dist', 'index.html'), 'utf8'));

// Body-only fragment, for hosts that supply their own document shell.
writeFileSync(join(root, 'dist', 'artifact.html'), `<title>${title}</title>\n${style}${body}${script}`);

const size = (p) => (readFileSync(join(root, 'dist', p), 'utf8').length / 1024).toFixed(1);
console.log(`build ${build}`);
console.log(`dist/index.html    ${size('index.html')} KB`);
console.log(`dist/artifact.html ${size('artifact.html')} KB`);
