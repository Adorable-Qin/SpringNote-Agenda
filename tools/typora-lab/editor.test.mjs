import { test, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { resolve, dirname, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '../../spring_note/editor/node_modules/playwright/index.mjs';

let browser, server, origin, page, errors;
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const root = resolve(repository, 'spring_note/assets/typora_editor');
const manifest = JSON.parse(await readFile(resolve(root, 'manifest.json'), 'utf8'));
before(async () => {
  server = createServer(async (req, res) => {
    try {
      const path = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/lib\//, '/lib.asar/').slice(1) || 'index.html';
      const asset = manifest.files[path]?.asset;
      if (!asset) { res.writeHead(404).end(); return; }
      const file = resolve(root, asset);
      if (!file.startsWith(root + sep)) { res.writeHead(403).end(); return; }
      res.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' })[extname(file)] || 'application/octet-stream');
      res.end(await readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true });
});
after(async () => { await browser?.close(); await new Promise(r => server.close(r)); });
beforeEach(async () => {
  page = await browser.newPage(); errors = [];
  page.on('pageerror', e => errors.push(e.stack));
  page.on('console', m => { if (/sendError|Error:/.test(m.text())) errors.push(m.text()); });
  await page.route('**/*', route => route.request().url().startsWith(origin) ? route.continue() : route.abort());
});
afterEach(async () => { await page.close(); assert.deepEqual(errors, []); });
async function boot(text, anchor = text.length, head = anchor) {
  await page.addInitScript(initial => {
    window.testNativeFile = window.File;
    window.host = { id: 'test', revision: 0, readOnly: false, dark: false, ...initial };
    window.messages = [];
    window.flutter_inappwebview = { callHandler: async (_, message) => {
      messages.push(message);
      if (message.type === 'ready') return structuredClone(host);
      if (message.type === 'image') return '../images/paste.png';
      if (message.type === 'change' || message.type === 'selection') {
        assertMessage(message);
        Object.assign(host, { text: message.text, anchor: message.anchor, head: message.head });
        setTimeout(() => springNoteEditor.receive({ ...host }), 0);
      }
      return true;
    }};
    function assertMessage(m) {
      if (m.revision !== host.revision || m.id !== host.id || m.anchor < 0 || m.head < 0 || m.anchor > m.text.length || m.head > m.text.length) throw Error('Invalid bridge snapshot');
    }
  }, { text, anchor, head });
  await page.goto(origin + '/?native');
  await page.waitForFunction(() => !!window.springNoteEditor || window.bootError);
  assert.equal(await page.evaluate(() => window.bootError), undefined);
  await page.locator('#write').focus();
}
const settle = () => page.waitForTimeout(500);
const snapshot = () => page.evaluate(() => springNoteEditor.snapshot());
const changes = () => page.evaluate(() => messages.filter(m => m.type === 'change'));

test('original renderer: typing, autosave echo, caret, undo and redo', async () => {
  await boot('中文正文');
  await page.keyboard.type(' ABC'); await settle();
  const typed = await snapshot(); assert.equal(typed.text.trim(), '中文正文 ABC');
  assert.equal(typed.id, 'test');
  assert.equal(typed.selection.head, 8);
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '中文正文');
  await page.keyboard.press('Control+y'); await settle();
  assert.equal((await snapshot()).text.trim(), '中文正文 ABC');
  assert.ok((await changes()).length >= 3);
});
test('original formatting shortcuts: bold, heading, quote and code block', async () => {
  await boot('正文');
  await page.keyboard.press('Control+a'); await page.keyboard.press('Control+b'); await settle();
  assert.match((await snapshot()).text, /\*\*正文\*\*/);
  await page.keyboard.press('ArrowRight'); await page.keyboard.press('Control+2'); await settle();
  assert.match((await snapshot()).text, /^## /);
  await page.keyboard.press('Control+0'); await page.keyboard.press('Control+Shift+q'); await settle();
  assert.match((await snapshot()).text, /^> /);
  await page.keyboard.press('Control+z'); await settle();
  await page.keyboard.press('Control+Shift+k'); await settle();
  assert.match((await snapshot()).text, /```/);
});
test('source mode edits and round trip retain text and undo', async () => {
  await boot('正文');
  await page.keyboard.press('Control+/'); await settle();
  assert.equal(await page.evaluate(() => editor.sourceView.inSourceMode), true);
  await page.keyboard.press('Control+End'); await page.keyboard.type(' SOURCE'); await settle();
  assert.match((await snapshot()).text, /正文 SOURCE/);
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '正文');
  await page.keyboard.press('Control+y'); await settle();
  assert.match((await snapshot()).text, /SOURCE/);
  await page.keyboard.press('Control+/'); await settle();
  assert.equal(await page.evaluate(() => editor.sourceView.inSourceMode), false);
  assert.match((await snapshot()).text, /SOURCE/);
});
test('rich IME commits once and does not publish preedit or lose echo', async () => {
  await boot('开始');
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.imeSetComposition', { text: 'zhong', selectionStart: 5, selectionEnd: 5 });
  await settle(); assert.equal((await changes()).length, 0);
  await page.evaluate(() => springNoteEditor.receive({ ...host, dark: true }));
  await cdp.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
  await cdp.send('Input.insertText', { text: '中文' }); await settle();
  assert.equal((await snapshot()).text.trim(), '开始中文');
  assert.equal((await changes()).length, 1);
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始');
  await page.keyboard.press('Control+y'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始中文');
});
test('source IME preserves candidate text until commit', async () => {
  await boot('开始'); await page.keyboard.press('Control+/'); await settle();
  await page.keyboard.press('Control+End');
  const cdp = await page.context().newCDPSession(page);
  const before = (await changes()).length;
  await cdp.send('Input.imeSetComposition', { text: 'nihao', selectionStart: 5, selectionEnd: 5 });
  await settle(); assert.equal((await changes()).length, before);
  await cdp.send('Input.insertText', { text: '你好' }); await settle();
  assert.equal((await snapshot()).text.trim(), '开始你好');
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始');
});
test('external updates, reverse selection and UTF-16 offsets', async () => {
  const text = '开始😀中文\r\n\r\n第二段';
  await boot(text, 6, 2);
  assert.deepEqual((await snapshot()).selection, { anchor: 6, head: 2 });
  assert.equal(await page.evaluate(() => getSelection().toString()), '😀中文');
  await page.evaluate(() => { Object.assign(host, { revision: 1, text: '外部更新', anchor: 2, head: 2 }); springNoteEditor.receive({ ...host }); });
  await settle(); assert.equal((await snapshot()).text, '外部更新');
  await page.keyboard.insertText('插入'); await settle();
  assert.equal((await snapshot()).text.trim(), '外部插入更新');
});
test('read only mode rejects text commands', async () => {
  await boot('只读正文');
  await page.evaluate(() => springNoteEditor.receive({ ...host, readOnly: true }));
  await page.keyboard.type('bad'); await page.keyboard.press('Control+2'); await settle();
  assert.equal((await snapshot()).text, '只读正文');
});
test('code block IME, repeated snapshots and caret remain stable', async () => {
  await boot('```js\n开始\n```', 10);
  await page.locator('#write .CodeMirror').click();
  await page.keyboard.press('Control+End');
  for (let i = 0; i < 8; i++) await snapshot();
  const cdp = await page.context().newCDPSession(page);
  const before = (await changes()).length;
  await cdp.send('Input.imeSetComposition', { text: 'zhongwen', selectionStart: 8, selectionEnd: 8 });
  await settle(); assert.equal((await changes()).length, before);
  await cdp.send('Input.insertText', { text: '中文' }); await settle();
  assert.match((await snapshot()).text, /开始中文/);
  for (let i = 0; i < 8; i++) await snapshot();
  await page.keyboard.type('!'); await settle();
  assert.match((await snapshot()).text, /开始中文!/);
  await page.keyboard.press('Control+z'); await settle();
  assert.doesNotMatch((await snapshot()).text, /!/);
});
test('original paste handler and undo accept multiline Chinese text', async () => {
  await boot('开始');
  await page.evaluate(() => {
    const data = new DataTransfer(); data.setData('text/plain', '粘贴第一行\n粘贴第二行');
    document.activeElement.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data }));
  }); await settle();
  assert.match((await snapshot()).text, /粘贴第一行/);
  assert.match((await snapshot()).text, /粘贴第二行/);
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始');
});
test('list continuation, indentation and search shortcuts', async () => {
  await boot('- 第一项');
  await page.keyboard.press('End'); await page.keyboard.press('Enter'); await page.keyboard.insertText('第二项'); await settle();
  assert.match((await snapshot()).text, /[-*] 第一项\r?\n[-*] 第二项/);
  await page.keyboard.press('Tab'); await settle();
  assert.match((await snapshot()).text, /\n +[-*] 第二项/);
  await page.keyboard.press('Shift+Tab'); await settle();
  assert.match((await snapshot()).text, /\n[-*] 第二项/);
  await page.keyboard.press('Control+f'); await settle();
  assert.equal(await page.evaluate(() => editor.searchPanel.isOpen()), true);
  await page.keyboard.press('Escape');
});
test('multiline reverse selection retains source offsets through save echoes', async () => {
  await boot('开始😀中文\r\n\r\n第二段', 12, 2);
  const before = await snapshot();
  assert.deepEqual(before.selection, { anchor: 12, head: 2 });
  await settle();
  assert.deepEqual((await snapshot()).selection, before.selection);
  await page.keyboard.insertText('替换'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始替换段');
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '开始😀中文\r\n\r\n第二段');
});
test('document image URLs retain Markdown paths and pasted images use host storage', async () => {
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=';
  await page.route('**/media/**', route => route.fulfill({ contentType: 'image/png', body: Buffer.from(png, 'base64') }));
  await boot('![图片](../images/test.png)\n\n正文');
  await settle();
  assert.equal(await page.locator('#write img').first().evaluate(img => img.naturalWidth), 1);
  assert.match((await snapshot()).text, /\.\.\/images\/test\.png/);
  await page.keyboard.press('Control+End');
  await page.evaluate(png => {
    const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
    const data = new DataTransfer(); data.items.add(new testNativeFile([bytes], 'paste.png', { type: 'image/png' }));
    document.activeElement.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data }));
  }, png); await settle();
  assert.match((await snapshot()).text, /\.\.\/images\/paste\.png/);
  assert.equal(await page.evaluate(() => messages.filter(m => m.type === 'image').length), 1);
  await page.keyboard.press('Control+z'); await settle();
  assert.doesNotMatch((await snapshot()).text, /paste\.png/);
});
test('icon toolbar formats the selection without losing focus and toggles source', async () => {
  await boot('选择这段');
  assert.equal(await page.locator('#editor-toolbar button').count(), 8);
  assert.equal(await page.locator('#editor-toolbar button svg').count(), 8);
  assert.equal(await page.locator('#editor-toolbar button').allTextContents().then(text => text.join('')), '');
  assert.equal(await page.locator('#editor-toolbar span').count(), 0);
  await page.keyboard.press('Control+a');
  await page.getByRole('button', { name: '加粗', exact: true }).click(); await settle();
  assert.match((await snapshot()).text, /\*\*选择这段\*\*/);
  await page.getByRole('button', { name: '撤销', exact: true }).click(); await settle();
  assert.equal((await snapshot()).text.trim(), '选择这段');
  const source = page.getByRole('button', { name: '源码模式', exact: true });
  assert.equal(await source.getAttribute('title'), '源码模式 (Ctrl+/)');
  await source.click(); await settle();
  assert.equal(await source.getAttribute('aria-pressed'), 'true');
  await page.setViewportSize({ width: 360, height: 600 });
  assert.equal(await page.evaluate(() => document.querySelector('#editor-toolbar').scrollWidth <= 360), true);
});

test('document switches reuse the renderer and isolate source and rich history', async () => {
  await boot('第一篇');
  await page.keyboard.type(' A'); await settle();
  await page.evaluate(() => { window.originalEditor = editor; });
  for (const [index, text] of ['第二篇', '第三篇', '第四篇'].entries()) {
    await page.keyboard.press('Control+/'); await settle();
    await page.evaluate(async ({ index, text }) => {
      host = { ...host, id: `document-${index}`, revision: 0, text, anchor: text.length, head: text.length };
      const id = await springNoteEditor.openDocument({ ...host }, index + 1);
      if (id !== host.id || editor !== originalEditor) throw new Error('Editor was recreated');
    }, { index, text });
    await page.keyboard.press('Control+z'); await settle();
    assert.equal((await snapshot()).text.trim(), text);
    await page.keyboard.type(' 新'); await settle();
    assert.equal((await snapshot()).text.trim(), text + ' 新');
    await page.keyboard.press('Control+z'); await settle();
    assert.equal((await snapshot()).text.trim(), text);
    await page.keyboard.press('Control+y'); await settle();
    assert.equal((await snapshot()).text.trim(), text + ' 新');
  }
  assert.equal(await page.evaluate(() => performance.getEntriesByType('navigation').length), 1);
});

test('document switch waits for composition and rejects stale navigation', async () => {
  await boot('原文');
  const session = await page.context().newCDPSession(page);
  await session.send('Input.imeSetComposition', { text: 'zhong', selectionStart: 5, selectionEnd: 5 });
  await page.evaluate(() => {
    window.switchDone = false;
    const next = { ...host, id: 'next', revision: 0, text: '下一篇', anchor: 3, head: 3 };
    springNoteEditor.openDocument(next, 1).then(() => { host = next; switchDone = true; });
  });
  assert.equal(await page.evaluate(() => switchDone), false);
  await session.send('Input.insertText', { text: '中' });
  await page.waitForFunction(() => switchDone);
  await settle();
  assert.equal((await snapshot()).text.trim(), '下一篇');
  assert.equal(await page.evaluate(() => springNoteEditor.openDocument({ ...host, text: '过期' }, 1)), null);
  await page.keyboard.type(' ABC'); await settle();
  assert.equal((await snapshot()).text.trim(), '下一篇 ABC');
});

test('SpringNote chrome and theme contain no upstream desktop controls', async () => {
  await boot('# 工作笔记\n\n中文实时编辑，支持 **加粗**、撤销与重做。\n\n- [ ] 今天的工作计划');
  assert.equal(await page.title(), 'SpringNote');
  assert.doesNotMatch(await page.locator('body').innerText(), /typora/i);
  await page.setViewportSize({ width: 900, height: 640 });
  const captures = resolve(repository, '.toolchains/typora-release');
  await mkdir(captures, { recursive: true });
  await page.screenshot({ path: resolve(captures, 'editor-light.png') });
  await page.evaluate(() => springNoteEditor.receive({ ...host, dark: true }));
  assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
  assert.equal(await page.locator('body').evaluate(body => getComputedStyle(body).backgroundColor), 'rgb(34, 34, 34)');
  assert.equal(await page.locator('content').evaluate(body => getComputedStyle(body).backgroundColor), 'rgb(34, 34, 34)');
  await page.screenshot({ path: resolve(captures, 'editor-dark.png') });
});

test('navigation commit waits for the final Chinese input and host acknowledgement', async () => {
  await boot('正文');
  await page.evaluate(async () => {
    document.execCommand('insertText', false, '末尾');
    await springNoteEditor.commit();
    if (host.text.trim() !== '正文末尾') throw new Error('Final input was not saved');
  });
  const session = await page.context().newCDPSession(page);
  await session.send('Input.imeSetComposition', { text: 'zhong', selectionStart: 5, selectionEnd: 5 });
  await page.evaluate(() => { window.committed = false; springNoteEditor.commit().then(() => { committed = true; }); });
  assert.equal(await page.evaluate(() => committed), false);
  await session.send('Input.insertText', { text: '中' });
  await page.waitForFunction(() => committed);
  assert.equal(await page.evaluate(() => host.text.trim()), '正文末尾中');
  await page.keyboard.press('Control+z'); await settle();
  assert.equal((await snapshot()).text.trim(), '正文末尾');
});
