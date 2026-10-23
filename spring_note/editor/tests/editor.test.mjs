import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import { chromium } from 'playwright';

let server, browser, origin;
before(async () => {
  const root = resolve('../assets/open_typora');
  server = createServer(async (req, res) => {
    try {
      const name = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
      if (!/^[\w.-]+$/.test(name)) { res.writeHead(404).end(); return; }
      res.setHeader('Content-Type', ({ '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' })[extname(name)] || 'application/octet-stream');
      res.end(await readFile(resolve(root, name)));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true });
});
after(async () => { await browser?.close(); await new Promise(resolve => server?.close(resolve)); });

async function open(text, options = {}) {
  const page = await browser.newPage({ viewport: { width: 1050, height: 720 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(({ text, options }) => {
    window.messages = [];
    window.initial = { id: 'test-document', revision: 0, text, anchor: text.length, head: text.length, readOnly: false, dark: false, english: false, ...options };
    window.flutter_inappwebview = { callHandler: async (_, message) => {
      window.messages.push(message);
      if (message.type === 'ready') return window.initial;
      if (message.type === 'image') return 'images/pasted.png';
      return true;
    } };
  }, { text, options });
  await page.goto(origin);
  await page.waitForFunction(() => window.messages.some(m => m.type === 'mounted'));
  page.errors = errors;
  return page;
}
const markdown = page => page.evaluate(() => window.springNoteEditor.snapshot().text);
async function receive(page, patch) {
  await page.evaluate(patch => window.springNoteEditor.receive({ ...window.initial, ...patch }), patch);
}

test('real editor types continuously, keeps DOM/caret and undo through autosave echoes', async () => {
  const page = await open('# 标题\n\n正文');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' ABC');
  assert.equal(await markdown(page), '# 标题\n\n正文 ABC');
  await page.evaluate(() => { window.savedNode = document.querySelector('.rich-document'); });
  const text = await markdown(page);
  await receive(page, { text, anchor: text.length, head: text.length });
  await page.keyboard.type(' DEF');
  assert.equal(await markdown(page), '# 标题\n\n正文 ABC DEF');
  assert.equal(await page.evaluate(() => window.savedNode === document.querySelector('.rich-document')), true);
  await page.keyboard.press('Control+z');
  assert.notEqual(await markdown(page), '# 标题\n\n正文 ABC DEF');
  await page.keyboard.press('Control+Shift+z');
  assert.equal(await markdown(page), '# 标题\n\n正文 ABC DEF');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('source and rich modes preserve CRLF, YAML, tables, code and unknown HTML', async () => {
  const source = '---\r\ntitle: Test\r\n---\r\n\r\n# 标题\r\n\r\n| A | B |\r\n|---|---|\r\n| 1 | 2 |\r\n\r\n```js\r\nconst x = 1;\r\n```\r\n\r\n<details><summary>更多</summary>原文</details>\r\n';
  const page = await open(source);
  await page.getByRole('button', { name: '源码', exact: true }).click();
  await page.locator('.source-surface .cm-content').waitFor({ state: 'visible' });
  assert.equal(await markdown(page), source);
  await page.getByRole('button', { name: '实时编辑', exact: true }).click();
  assert.equal(await markdown(page), source);
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('upstream formatting, task commands, table insertion and source undo operate on markdown', async () => {
  const page = await open('待办');
  await receive(page, { revision: 1, anchor: 0, head: 2 });
  await page.getByRole('button', { name: '加粗', exact: true }).click();
  assert.equal(await markdown(page), '**待办**');
  await page.getByRole('button', { name: '撤销', exact: true }).click();
  assert.equal(await markdown(page), '待办');
  await page.getByRole('button', { name: '任务列表', exact: true }).click();
  assert.match(await markdown(page), /- \[ \] 待办/);
  await page.getByRole('button', { name: '表格', exact: true }).click();
  assert.match(await markdown(page), /\| --- \| --- \|/);
  await page.getByRole('button', { name: '源码', exact: true }).click();
  await page.locator('.source-surface .cm-content').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type('\nsource edit');
  assert.match(await markdown(page), /source edit$/);
  await page.getByRole('button', { name: '实时编辑', exact: true }).click();
  await page.keyboard.press('Control+z');
  assert.doesNotMatch(await markdown(page), /source edit/);
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('composition survives save echoes and commits one undoable edit', async () => {
  const page = await open('开始');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
  await receive(page, { text: '开始', anchor: 2, head: 2 });
  await client.send('Input.insertText', { text: '中文' });
  await page.waitForTimeout(100);
  assert.equal(await markdown(page), '开始中文');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), '开始');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('read-only, local images, formula and Mermaid rendering', async () => {
  const page = await open('# 只读\n\n![图片](../images/a%20b.png)\n\n$$\nx^2 + y^2\n$$\n\n```mermaid\ngraph LR\nA-->B\n```', { readOnly: true });
  assert.equal(await page.locator('.rich-document').getAttribute('contenteditable'), 'false');
  const source = await markdown(page);
  assert.match(await page.locator('img').getAttribute('src'), /\/media\/\.\.%2Fimages%2Fa%2520b.png$/);
  await page.waitForFunction(() => document.querySelector('.mathjax-node svg'));
  await page.waitForFunction(() => document.querySelector('.mermaid-block svg'));
  assert.equal(await markdown(page), source);
  assert.deepEqual(page.errors, []);
  await page.screenshot({ path: 'test-results/editor.png' });
  await page.close();
});

test('held deletion crosses headings and lists while preserving the editor instance', async () => {
  const page = await open('# abc\n\n- def\n- ghi');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  for (let i = 0; i < 30; i++) await page.keyboard.press('Backspace');
  assert.equal(await markdown(page), '');
  await page.keyboard.type('new text');
  assert.equal(await markdown(page), 'new text');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('a delayed same-revision acknowledgement cannot overwrite newer browser text', async () => {
  const page = await open('original');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' edit');
  await receive(page, { text: 'original', anchor: 0, head: 0, dark: true });
  await page.keyboard.type(' more');
  assert.equal(await markdown(page), 'original edit more');
  assert.equal(await page.locator('html').getAttribute('data-appearance'), 'dark');
  await page.close();
});

test('image paste uses the native storage adapter and preserves the relative path', async () => {
  const page = await open('图片：');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  await page.evaluate(() => {
    const data = new DataTransfer();
    data.items.add(new File([new Uint8Array([137,80,78,71])], 'pasted.png', { type: 'image/png' }));
    document.querySelector('.rich-document').dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  });
  await page.waitForFunction(() => window.springNoteEditor.snapshot().text.includes('images/pasted.png'));
  assert.match(await markdown(page), /!\[.*\]\(images\/pasted.png\)/);
  assert.equal(await page.evaluate(() => window.messages.filter(m => m.type === 'image').length), 1);
  await page.close();
});

test('closed ATX heading markers stay intact when editing their text', async () => {
  const page = await open('# Heading #  \n\nbody');
  await receive(page, { revision: 1, anchor: 9, head: 9 });
  await page.keyboard.type('!');
  assert.equal(await markdown(page), '# Heading! #  \n\nbody');
  await page.close();
});

test('native changes apply in read-only mode, obsolete revisions do not replace content', async () => {
  const page = await open('before', { readOnly: true });
  await receive(page, { revision: 2, text: 'external', anchor: 8, head: 8, readOnly: true });
  assert.equal(await markdown(page), 'external');
  await receive(page, { revision: 1, text: 'stale', anchor: 0, head: 0 });
  assert.equal(await markdown(page), 'external');
  await receive(page, { revision: 3, text: 'external', anchor: 8, head: 8, readOnly: false });
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' edit');
  assert.equal(await markdown(page), 'external edit');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('embedded HTML cannot execute script or navigate the host', async () => {
  const page = await open('<img src="missing" onerror="window.compromised=true">\n\n<script>window.compromised=true</script>\n\n<iframe src="https://example.com"></iframe>');
  assert.equal(await page.evaluate(() => window.compromised), undefined);
  assert.equal(await page.locator('script:not([src])').count(), 0);
  assert.equal(await page.locator('[onerror]').count(), 0);
  await page.close();
});

for (const mode of ['source', 'code']) {
  test(`${mode}: intermediate IME text stays local and one undo restores the committed text`, async () => {
    const initial = mode === 'source' ? '开始' : '```text\n开始\n```';
    const page = await open(initial);
    if (mode === 'source') await page.getByRole('button', { name: '源码', exact: true }).click();
    else {
      await receive(page, { revision: 1, anchor: 10, head: 10 });
      await page.locator('.rich-document [data-fence]').click();
    }
    await page.locator('.cm-content:visible').click();
    await page.keyboard.press('Control+End');
    await page.evaluate(() => { window.messages = []; });
    const client = await page.context().newCDPSession(page);
    await client.send('Input.imeSetComposition', { text: 'zhong', selectionStart: 5, selectionEnd: 5 });
    await client.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
    assert.equal(await page.evaluate(() => window.springNoteEditor.snapshot().composing), true);
    assert.deepEqual(await page.evaluate(() => window.messages.filter(m => ['change', 'selection'].includes(m.type))), []);
    await client.send('Input.insertText', { text: '中文' });
    await page.waitForFunction(() => !window.springNoteEditor.snapshot().composing);
    assert.match(await markdown(page), /中文/);
    assert.equal(await page.evaluate(() => window.messages.filter(m => m.type === 'change').length), 1);
    await page.keyboard.press('Control+z');
    assert.equal(await markdown(page), initial);
    await page.keyboard.press('Control+y');
    assert.match(await markdown(page), /中文/);
    assert.deepEqual(page.errors, []);
    await page.close();
  });
}

test('source and rich mode share granular history and a redo branch across mode switches', async () => {
  const page = await open('base');
  await page.getByRole('button', { name: '源码', exact: true }).click();
  await page.locator('.source-surface .cm-content').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' first');
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.type(' second');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), 'base first');
  await page.getByRole('button', { name: '实时编辑', exact: true }).click();
  await page.keyboard.press('Control+y');
  assert.equal(await markdown(page), 'base first second');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), 'base first');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), 'base');
  await page.getByRole('button', { name: '源码', exact: true }).click();
  await page.keyboard.press('Control+y');
  assert.equal(await markdown(page), 'base first');
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('IME replacing a reversed cross-paragraph selection restores text and caret on undo', async () => {
  const initial = '中文中文\n\n中文中文';
  const page = await open(initial);
  await receive(page, { revision: 1, anchor: 8, head: 2 });
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '候选', selectionStart: 2, selectionEnd: 2 });
  await client.send('Input.insertText', { text: '替换' });
  await page.waitForFunction(() => !window.springNoteEditor.snapshot().composing);
  assert.equal(await markdown(page), '中文替换中文');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), initial);
  assert.deepEqual(await page.evaluate(() => window.springNoteEditor.snapshot().selection), { anchor: 8, head: 2 });
  await page.close();
});

test('new revision save echo during IME preserves the composing caret and reports the new revision', async () => {
  const page = await open('中文开头，中文结尾');
  await receive(page, { revision: 1, anchor: 5, head: 5 });
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '中间', selectionStart: 2, selectionEnd: 2 });
  await receive(page, { revision: 2, text: '中文开头，中文结尾', anchor: 0, head: 0, dark: true });
  await client.send('Input.insertText', { text: '中间' });
  await page.waitForFunction(() => !window.springNoteEditor.snapshot().composing);
  await page.keyboard.type('!');
  assert.equal(await markdown(page), '中文开头，中间!中文结尾');
  assert.equal(await page.evaluate(() => window.messages.filter(m => m.type === 'change').at(-1).revision), 2);
  await page.close();
});

test('mixed line endings and surrogate pairs preserve native selection offsets', async () => {
  const initial = 'a\r\n😀\nb';
  const page = await open(initial);
  await receive(page, { revision: 1, anchor: 6, head: 6 });
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowRight');
  await page.waitForFunction(() => window.messages.filter(m => m.type === 'selection').at(-1)?.anchor === 6);
  assert.equal(await markdown(page), initial);
  const selection = await page.evaluate(() => window.messages.filter(m => m.type === 'selection').at(-1));
  assert.equal(selection.head, 6);
  await page.keyboard.type('!');
  assert.equal(await markdown(page), 'a\r\n😀\r\n!b');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), initial);
  assert.deepEqual(page.errors, []);
  await page.close();
});

test('formatting is blocked and mode switching is deferred until IME commits', async () => {
  const page = await open('开始');
  await page.locator('.rich-document').click();
  await page.keyboard.press('Control+End');
  const client = await page.context().newCDPSession(page);
  await client.send('Input.imeSetComposition', { text: '中文', selectionStart: 2, selectionEnd: 2 });
  await page.getByRole('button', { name: '加粗', exact: true }).evaluate(el => el.click());
  await page.getByRole('button', { name: '源码', exact: true }).evaluate(el => el.click());
  assert.equal(await page.locator('.rich-document').isVisible(), true);
  await client.send('Input.insertText', { text: '中文' });
  await page.waitForFunction(() => !window.springNoteEditor.snapshot().composing);
  assert.equal(await page.locator('.source-surface .cm-content').isVisible(), true);
  assert.equal(await markdown(page), '开始中文');
  await page.keyboard.press('Control+z');
  assert.equal(await markdown(page), '开始');
  assert.deepEqual(page.errors, []);
  await page.close();
});
