import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { chromium } from '../../spring_note/editor/node_modules/playwright/index.mjs';
const root = resolve('.toolchains/typora-lab/web');
const server = createServer(async (req, res) => {
  try {
    const path = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/lib\//, '/lib.asar/'));
    if (path !== root && !path.startsWith(root + sep)) { res.writeHead(403).end(); return; }
    const file = path === root ? resolve(root, 'index.html') : path;
    res.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' })[extname(file)] || 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });
const errors = [], consoleMessages = [];
page.on('pageerror', e => errors.push(e.stack));
page.on('console', m => consoleMessages.push(m.text()));
page.on('response', r => { if (r.status() === 404) consoleMessages.push('404 ' + r.url()); });
await page.route('**/*', route => route.request().url().startsWith(origin) ? route.continue() : route.abort());
try {
  await page.goto(origin);
  await page.waitForTimeout(1200);
  if (await page.evaluate(() => !!window.springNoteEditor)) {
    await page.locator('#write').click();
    await page.keyboard.press('Control+End');
    await page.keyboard.type(' ABC');
    await page.waitForTimeout(300);
    consoleMessages.push('markdown after typing: ' + await page.evaluate(() => { editor.store(null, true); return editor.getMarkdown(); }));
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(300);
    consoleMessages.push('markdown after undo: ' + await page.evaluate(() => editor.getMarkdown()));
  }
  const state = await page.evaluate(() => ({ bootError: window.bootError, initialized: !!window.springNoteEditor, write: document.querySelector('#write')?.outerHTML.slice(0,2000), methods: window.editor ? Object.getOwnPropertyNames(Object.getPrototypeOf(editor)) : [] }));
  await writeFile('.toolchains/typora-lab/probe.json', JSON.stringify({ errors, consoleMessages, state }, null, 2));
  console.log(JSON.stringify({ errors, consoleMessages: consoleMessages.slice(-20), state }, null, 2));
  await page.screenshot({ path: '.toolchains/typora-lab/probe.png' });
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
