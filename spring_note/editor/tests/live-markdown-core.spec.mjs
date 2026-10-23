import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { chromium } from 'playwright';

let server, browser, origin;
before(async () => {
  const root = resolve('dist-core');
  await mkdir('test-results', { recursive: true });
  server = createServer(async (req, res) => {
    try {
      const path = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
      if (!path.startsWith(root + sep) && path !== root) { res.writeHead(404).end(); return; }
      const file = path === root ? resolve(root, 'index.html') : path;
      res.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' })[extname(file)] || 'application/octet-stream');
      res.end(await readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true });
});
after(async () => { await browser?.close(); if (server) await new Promise(resolve => server.close(resolve)); });

async function open(markdown, options = {}) {
  const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(origin);
  await page.waitForFunction(() => window.editor);
  await page.evaluate(async ({ markdown, options }) => {
    window.editor.destroy();
    const { createLiveMarkdownEditor } = await import('/live-markdown.js');
    window.createEditor = createLiveMarkdownEditor;
    window.changes = [];
    window.editor = createLiveMarkdownEditor(document.querySelector('#editor'), {
      markdown, ...options, onChange: value => {
        window.changes.push(value);
        document.querySelector('#source').textContent = value.markdown;
      },
    });
    document.querySelector('#source').textContent = markdown;
  }, { markdown, options });
  page.errors = errors;
  return page;
}
const text = page => page.evaluate(() => window.editor.snapshot().markdown);

test('core edits Markdown with stable unaffected blocks and history through save echoes', async () => {
  const page = await open('# title\n\nbody');
  await page.evaluate(() => { window.heading = document.querySelector('.rich-document').firstElementChild; });
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' abc');
  assert.equal(await text(page), '# title\n\nbody abc');
  assert.equal(await page.evaluate(() => window.heading === document.querySelector('.rich-document').firstElementChild), true);
  assert.equal(await page.evaluate(() => window.editor.setMarkdown(window.editor.snapshot().markdown)), 'unchanged');
  await page.keyboard.type(' def');
  assert.equal(await text(page), '# title\n\nbody abc def');
  await page.evaluate(() => window.editor.undo());
  assert.equal(await text(page), '# title\n\nbody');
  await page.evaluate(() => window.editor.redo());
  assert.equal(await text(page), '# title\n\nbody abc def');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('formatting uses LF offsets, preserves CRLF and host updates are undoable without change echoes', async () => {
  const page = await open('one\r\n\r\ntwo');
  await page.evaluate(() => { window.editor.select({ anchor: 0, head: 3 }); window.editor.wrap('**'); });
  assert.equal(await text(page), '**one**\r\n\r\ntwo');
  const changes = await page.evaluate(() => window.changes.length);
  await page.evaluate(() => window.editor.setMarkdown('host\r\n\r\ntext', { anchor: 4, head: 4 }));
  assert.equal(await text(page), 'host\r\n\r\ntext');
  assert.equal(await page.evaluate(() => window.changes.length), changes);
  await page.evaluate(() => window.editor.undo());
  assert.equal(await text(page), '**one**\r\n\r\ntwo');
  await page.close();
});

test('IME composition survives a save echo and commits as one undo step', async () => {
  const page = await open('开始');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
  assert.equal(await page.evaluate(() => window.editor.snapshot().composing), true);
  assert.equal(await page.evaluate(() => window.editor.setMarkdown('开始', { anchor: 0, head: 0 })), 'unchanged');
  await client.send('Input.insertText', { text: '中文' });
  await page.waitForFunction(() => !window.editor.snapshot().composing);
  assert.equal(await text(page), '开始中文');
  await page.evaluate(() => window.editor.undo());
  assert.equal(await text(page), '开始');
  await page.close();
});

test('host updates wait for composition and keep the composed edit in history', async () => {
  const page = await open('开始');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
  assert.equal(await page.evaluate(() => window.editor.setMarkdown('宿主更新')), 'deferred');
  await client.send('Input.insertText', { text: '中文' });
  await page.waitForFunction(() => window.editor.snapshot().markdown === '宿主更新');
  await page.evaluate(() => window.editor.undo());
  assert.equal(await text(page), '开始中文');
  await page.close();
});

test('read-only blocks local edits, allows host updates, and destroy supports a clean remount', async () => {
  const page = await open('locked', { readOnly: true });
  assert.equal(await page.locator('.rich-document').getAttribute('contenteditable'), 'false');
  assert.equal(await page.evaluate(() => window.editor.insert('x')), false);
  await page.evaluate(() => window.editor.setMarkdown('updated'));
  assert.equal(await text(page), 'updated');
  await page.evaluate(() => {
    window.editor.destroy(); window.editor.destroy();
    window.editor = window.createEditor(document.querySelector('#editor'), { markdown: 'new' });
    window.editor.focus();
  });
  await page.keyboard.press('Control+End');
  await page.keyboard.type('!');
  assert.equal(await text(page), 'new!');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('core renders tables, math and diagrams and produces a visual example', async () => {
  const page = await open('# 实时编辑\n\n正文 **加粗** 和 *斜体*\n\n- [ ] 中文输入\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$$\nx^2 + y^2\n$$\n\n```mermaid\ngraph LR\nA-->B\n```');
  await page.waitForFunction(() => document.querySelector('.mathjax-node svg'));
  await page.waitForFunction(() => document.querySelector('.mermaid-block svg'));
  assert.equal(await page.locator('.rich-document table').count(), 1);
  assert.deepEqual(page.errors, []);
  await page.screenshot({ path: 'test-results/live-markdown-core.png', fullPage: true });
  await page.close();
});
