// SpringNote document, selection, composition and command lifecycle.
(async () => {
  const bridge = () => window.flutter_inappwebview?.callHandler;
  const native = !!bridge() || new URLSearchParams(location.search).has('native');
  if (native && !bridge()) await new Promise(resolve => window.addEventListener('flutterInAppWebViewPlatformReady', resolve, { once: true }));
  const request = async message => {
    if (!bridge()) return null;
    const result = await window.flutter_inappwebview.callHandler('springNote', message);
    if (result?.error) throw new Error(result.error);
    return result;
  };
  let current = await request({ type: 'ready' }) || {
    id: 'preview', revision: 0, text: '# SpringNote\n\n在这里记录想法。',
    anchor: 0, head: 0, readOnly: false, dark: false,
  };
  const require = window.springNoteModules, File = window.File;
  delete window.springNoteModules;
  File.loadFile = async () => {};
  File.setTheme = () => {};
  File.isWin = true;
  require('5a');
  require('4c').init();
  const editor = window.editor, key = require('26');
  // Translate only the displayed resource URL. The Markdown keeps its original
  // relative image path and uses SpringNote's document-scoped image server.
  editor.imgEdit.getRealSrc = source => {
    if (!source || /^(https?:|data:|blob:)/i.test(source)) return source;
    if (source.startsWith('//')) return 'https:' + source;
    return new URL(encodeURIComponent(source), current.mediaBase || new URL('media/', location.href)).href;
  };
  let composing = false, applying = false, pending = null, pendingOpen = null, sequence = 0, timer;
  let navigation = 0;
  let publication = Promise.resolve(), commitWaiters = [];
  let lastModel = '', lastSelection = '', nativeSelection = [];
  const isComposing = () => composing || !!editor.isIME;
  function options(snapshot) {
    if (isComposing()) return;
    File.isLocked = !!snapshot.readOnly;
    editor.writingArea.contentEditable = snapshot.readOnly ? 'false' : 'true';
    editor.writingArea.spellcheck = false;
    if (editor.sourceView.cm) editor.sourceView.cm.setOption('readOnly', !!snapshot.readOnly);
    document.documentElement.dataset.theme = snapshot.dark ? 'dark' : 'light';
    document.documentElement.lang = snapshot.english ? 'en' : 'zh-CN';
    for (const [name, value] of Object.entries(snapshot.colors || {})) {
      if (/^#[\da-f]{6}$/i.test(value)) document.documentElement.style.setProperty(`--sn-${name}`, value);
    }
    updateToolbar();
  }
  function load(text) {
    File.decideLineEnding(text);
    editor.nodeMap.reset(); editor.reset(text); editor.undo.reset();
    File.bundle.savedContent = text; lastModel = editor.getMarkdown();
    editor.writingArea.classList.remove('ty-before-first-render');
  }
  function markdown() {
    const model = editor.getMarkdown();
    return model === lastModel ? current.text : model;
  }
  function linePosition(text, offset) {
    const before = text.slice(0, offset).replace(/\r\n/g, '\n');
    const line = before.split('\n').length - 1, ch = before.length - before.lastIndexOf('\n') - 1;
    const lineText = text.split(/\r?\n/)[line] || '';
    return { line, ch, lineText, textBefore: lineText.slice(0, ch) };
  }
  function offsetOf(text, pos) {
    if (!pos) return Math.min(current.head, text.length);
    const lines = text.split(/\r?\n/), line = Math.max(0, Math.min(pos.line, lines.length - 1));
    let ch = pos.ch;
    if (pos.afterIndent) ch = (/^((\s+)|([-+*]\s)|(\[( |x)\])|>|(\d+[.)]\s))+/i.exec(lines[line]) || [''])[0].length;
    if (ch === undefined) ch = pos.before ? lines[line].indexOf(pos.before) + pos.before.length : pos.beforeRegExp ? (new RegExp(pos.beforeRegExp).exec(lines[line])?.[0].length || 0) : 0;
    if (ch < 0) ch = lines[line].length;
    const end = Math.max(0, Math.min(ch, lines[line].length)), breaks = [...text.matchAll(/\r?\n/g)];
    return Math.min(text.length, line ? (breaks[line - 1]?.index ?? text.length) + (breaks[line - 1]?.[0].length ?? 0) + end : end);
  }
  function selection(text = markdown()) {
    if (editor.sourceView.inSourceMode) {
      const selected = editor.sourceView.cm.listSelections()[0];
      return { anchor: offsetOf(text, selected.anchor), head: offsetOf(text, selected.head) };
    }
    // CodeMirror owns its own selection; a DOM range would refer to stale rich
    // text. The language field has no body cursor, so retain the last position.
    if (document.activeElement?.classList.contains('ty-cm-lang-input')) {
      return { anchor: Math.min(current.anchor, text.length), head: Math.min(current.head, text.length) };
    }
    if (document.activeElement?.closest('.CodeMirror')) {
      const cm = document.activeElement.closest('.CodeMirror').CodeMirror;
      const range = cm.listSelections()[0];
      return { anchor: offsetOf(text, mapPosition(range.anchor)), head: offsetOf(text, mapPosition(range.head)) };
    }
    const original = editor.selection.getRangy();
    if (!original) return { anchor: Math.min(current.anchor, text.length), head: Math.min(current.head, text.length) };
    const focused = editor.focusCid, backward = original.isBackward;
    const point = start => {
      const range = original.cloneRange(); range.collapse(start);
      editor.selection.rangy.getSelection().setSingleRange(range);
      editor.focusCid = editor.getMarkElem(range.startContainer).attr('cid');
      return offsetOf(text, mapPosition());
    };
    try {
      const start = point(true), end = original.collapsed ? start : point(false);
      return backward ? { anchor: end, head: start } : { anchor: start, head: end };
    } finally {
      editor.selection.rangy.getSelection().setSingleRange(original, backward);
      editor.focusCid = focused;
    }
  }
  function mapPosition(cursor) {
    // The original one-shot source-mode mapper mutates the cursor object that
    // CodeMirror returns. Clone it for repeated host snapshots, or its Markdown
    // line number would be written back into CodeMirror's live selection.
    const prototype = window.CodeMirror.Doc.prototype, getCursor = prototype.getCursor;
    prototype.getCursor = function (...args) { return { ...(cursor || getCursor.apply(this, args)) }; };
    try { return editor.sourceView.getMarkdownPosition(); }
    finally { prototype.getCursor = getCursor; }
  }
  function select(text, anchor, head) {
    if (editor.sourceView.inSourceMode) {
      editor.sourceView.cm.setSelection(linePosition(text, anchor), linePosition(text, head)); return;
    }
    editor.sourceView.gotoLine(linePosition(text, anchor));
    const first = window.getSelection(), node = first?.anchorNode, offset = first?.anchorOffset;
    if (head !== anchor && node) {
      editor.sourceView.gotoLine(linePosition(text, head));
      const last = window.getSelection();
      if (last?.focusNode) last.setBaseAndExtent(node, offset, last.focusNode, last.focusOffset);
    }
  }
  function flush() {
    if (applying || isComposing()) return publication;
    if (!editor.sourceView.inSourceMode) editor.store(null, true);
    const text = markdown(), selected = selection(text), changed = text !== current.text;
    const selectedKey = JSON.stringify(selected);
    if (!changed && selectedKey === lastSelection) return publication;
    lastSelection = selectedKey; lastModel = editor.getMarkdown();
    current = { ...current, text, ...selected };
    return publication = request({ type: changed ? 'change' : 'selection', id: current.id, revision: current.revision,
      sequence: ++sequence, text, ...selected }).catch(showError);
  }
  function commit() {
    clearTimeout(timer);
    if (isComposing()) return new Promise(resolve => commitWaiters.push(resolve));
    return flush();
  }
  const schedule = () => { clearTimeout(timer); timer = setTimeout(flush, 20); };
  function receive(next) {
    if (next.id !== current.id || next.revision < Math.max(current.revision, pending?.revision ?? 0)) return;
    if (next.revision === current.revision) {
      current = { ...current, readOnly: next.readOnly, dark: next.dark, english: next.english, colors: next.colors };
      options(current); return;
    }
    if (isComposing()) {
      if (next.text === current.text) current = { ...current, revision: next.revision };
      else pending = next;
      return;
    }
    applying = true;
    try {
      if (next.text !== current.text) File.reloadContent(next.text, { skipChangeCount: true, delayRefresh: false });
      current = next; lastModel = editor.getMarkdown();
      select(next.text, next.anchor, next.head); options(next);
    } finally { applying = false; }
  }
  function replaceDocument(next) {
    clearTimeout(timer); pending = null;
    applying = true;
    try {
      const sourceMode = editor.sourceView.inSourceMode;
      if (sourceMode) File.toggleSourceMode();
      current = next; sequence = 0; lastSelection = ''; nativeSelection = [];
      if (editor.searchPanel.isOpen()) editor.searchPanel.closePanel(true);
      load(next.text);
      select(next.text, next.anchor, next.head);
      if (sourceMode) File.toggleSourceMode();
      editor.sourceView.cm?.clearHistory();
      options(next);
      document.querySelector('content').scrollTop = 0;
    } finally { applying = false; }
    return current.id;
  }
  function openDocument(next, generation) {
    if (generation <= navigation) return Promise.resolve(null);
    navigation = generation;
    if (pendingOpen) { pendingOpen.resolve(null); pendingOpen = null; }
    if (isComposing()) return new Promise((resolve, reject) => { pendingOpen = { next, resolve, reject }; });
    return Promise.resolve(replaceDocument(next));
  }
  const editableEvent = event => editor.writingArea.contains(event.target) || document.querySelector('#typora-source').contains(event.target);
  function closeHistoryGroup() {
    editor.undo.endSnap(true);
    const cm = editor.sourceView.inSourceMode ? editor.sourceView.cm : document.activeElement?.closest('.CodeMirror')?.CodeMirror;
    cm?.doc.changeGeneration(true);
  }
  document.addEventListener('compositionstart', event => {
    if (editableEvent(event)) { closeHistoryGroup(); composing = true; clearTimeout(timer); }
  }, true);
  document.addEventListener('compositionend', event => {
    if (!editableEvent(event)) return;
    setTimeout(async () => {
      composing = false;
      closeHistoryGroup();
      if (commitWaiters.length) {
        // Let the original rich/CodeMirror composition handlers finish first.
        await new Promise(resolve => setTimeout(resolve, 20));
        await flush();
        const waiters = commitWaiters; commitWaiters = [];
        waiters.forEach(resolve => resolve());
      }
      if (pendingOpen) {
        const { next, resolve, reject } = pendingOpen; pendingOpen = null;
        try { resolve(replaceDocument(next)); } catch (error) { reject(error); }
      }
      if (pending) { const next = pending; pending = null; receive(next); }
      options(current);
      schedule();
    }, 0);
  }, true);
  document.addEventListener('input', event => { if (editableEvent(event)) schedule(); });
  document.addEventListener('paste', event => {
    window.springNoteClipboardText = event.clipboardData?.getData('text/plain') || '';
    const images = [...(event.clipboardData?.files || [])].filter(file => file.type.startsWith('image/'));
    if (!images.length || !editableEvent(event)) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (!native || current.readOnly || isComposing()) return;
    const documentId = current.id;
    void (async () => {
      for (const file of images) {
        if (file.size > 32 * 1024 * 1024) throw new Error('图片不能超过 32 MB');
        const data = await new Promise((resolve, reject) => {
          const reader = new FileReader(); reader.onload = () => resolve(reader.result.split(',')[1]); reader.onerror = reject; reader.readAsDataURL(file);
        });
        if (current.id !== documentId) return;
        const path = await request({ type: 'image', id: documentId, name: file.name || 'paste.png', data });
        if (typeof path !== 'string' || current.readOnly || current.id !== documentId) return;
        if (editor.sourceView.inSourceMode) editor.sourceView.cm.replaceSelection(`![](${path})`);
        else editor.imgEdit.insertImageFromURL(path);
      }
      schedule();
    })().catch(showError);
  }, true);
  document.addEventListener('selectionchange', () => {
    const sel = window.getSelection(), next = [sel?.anchorNode, sel?.anchorOffset, sel?.focusNode, sel?.focusOffset];
    if (next.every((value, i) => value === nativeSelection[i])) return;
    nativeSelection = next;
    if (!applying && !isComposing() && (editor.writingArea.contains(document.activeElement) || editor.sourceView.inSourceMode)) schedule();
  });
  const changeCount = File.updateChangeCount;
  File.updateChangeCount = function (...args) { const result = changeCount.apply(this, args); if (!applying) schedule(); return result; };
  function command(action, value) {
    if (isComposing() || (current.readOnly && action !== 'source' && action !== 'find')) return;
    if (action === 'undo' || action === 'redo') ClientCommand[action]();
    if (action === 'inline') editor.stylize.toggleStyle(value);
    if (action === 'heading') editor.stylize.changeBlock(value ? `header${value}` : 'paragraph');
    if (action === 'code') editor.stylize.toggleFences();
    if (action === 'quote') editor.stylize.toggleIndent('blockquote');
    if (action === 'list') editor.stylize.toggleIndent(value);
    if (action === 'source') File.toggleSourceMode();
    if (action === 'find') editor.searchPanel.showPanel();
    updateToolbar();
    schedule();
  }
  for (const [shortcut, action, value] of [
    ['ctrl+z', 'undo'], ['ctrl+y', 'redo'], ['ctrl+shift+z', 'redo'],
    ['ctrl+b', 'inline', 'strong'], ['ctrl+i', 'inline', 'em'], ['ctrl+u', 'inline', 'underline'],
    ['ctrl+shift+k', 'code'], ['ctrl+shift+q', 'quote'], ['ctrl+shift+`', 'inline', 'code'],
    ['ctrl+shift+l', 'list', 'ul'], ['ctrl+shift+m', 'list', 'task'], ['ctrl+/', 'source'],
    ['ctrl+f', 'find'], ...Array.from({ length: 7 }, (_, n) => [`ctrl+${n}`, 'heading', n]),
  ]) {
    // Some browser-host commands are already registered by the original editor.
    // Replace that binding so one keypress runs exactly one command.
    key.unbind(shortcut, 'all');
    key(shortcut, () => { command(action, value); return false; });
  }
  key('ctrl+s', () => { flush(); return false; });
  const toolbar = document.createElement('nav'); toolbar.id = 'editor-toolbar';
  toolbar.setAttribute('role', 'toolbar');
  const controls = [
    ['撤销', 'Undo', 'Ctrl+Z', 'undo', null, 'M9 5 4 10l5 5M4 10h10a6 6 0 0 1 0 12', '0 0 24 26'],
    ['重做', 'Redo', 'Ctrl+Y', 'redo', null, 'm15 5 5 5-5 5m5-5H10a6 6 0 0 0 0 12', '0 0 24 26'],
    ['加粗', 'Bold', 'Ctrl+B', 'inline', 'strong', 'M7 12h6a4 4 0 0 0 0-8H7v16h7a4 4 0 0 0 0-8H7'],
    ['斜体', 'Italic', 'Ctrl+I', 'inline', 'em', 'M10 4h9M5 20h9M15 4 9 20'],
    ['二级标题', 'Heading 2', 'Ctrl+2', 'heading', 2, 'M4 5v14M14 5v14M4 12h10m4-1a2 2 0 0 1 4 0c0 2-4 3-4 5h4'],
    ['引用', 'Quote', 'Ctrl+Shift+Q', 'quote', null, 'M4 5h6v7H4V5Zm10 0h6v7h-6V5ZM10 12c0 4-2 6-6 7m16-7c0 4-2 6-6 7'],
    ['代码块', 'Code block', 'Ctrl+Shift+K', 'code', null, 'M9 8 5 12l4 4m6-8 4 4-4 4M3 3h18v18H3V3Z'],
    ['源码模式', 'Source mode', 'Ctrl+/', 'source', null, 'm7 7-5 5 5 5m10-10 5 5-5 5M14 4l-4 16'],
  ];
  for (const [label, english, shortcut, action, value, path, viewBox] of controls) {
    const button = document.createElement('button'); button.type = 'button';
    button.dataset.action = action;
    button.setAttribute('aria-keyshortcuts', shortcut.replace('Ctrl', 'Control'));
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', viewBox || '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    const shape = document.createElementNS(svg.namespaceURI, 'path'); shape.setAttribute('d', path); svg.append(shape);
    button.append(svg);
    button.addEventListener('mousedown', event => event.preventDefault());
    button.addEventListener('click', () => command(action, value)); toolbar.append(button);
  }
  function updateToolbar() {
    if (!toolbar) return;
    toolbar.setAttribute('aria-label', current.english ? 'Formatting' : '编辑工具栏');
    [...toolbar.querySelectorAll('button')].forEach((button, i) => {
      const [label, english, shortcut, action] = controls[i];
      const text = current.english ? english : label;
      button.setAttribute('aria-label', text); button.title = `${text} (${shortcut})`;
      button.disabled = !!current.readOnly && action !== 'source';
      if (action === 'source') button.setAttribute('aria-pressed', String(!!editor.sourceView.inSourceMode));
    });
  }
  document.body.append(toolbar);
  function showError(error) {
    console.error(error);
    let alert = document.querySelector('#editor-error');
    if (!alert) { alert = document.createElement('div'); alert.id = 'editor-error'; alert.setAttribute('role','alert'); document.body.append(alert); }
    alert.textContent = error.message || String(error);
  }
  load(current.text); options(current); select(current.text, current.anchor, current.head);
  window.springNoteEditor = { receive, openDocument, command, flush, commit, snapshot: () => ({ id: current.id, text: markdown(), selection: selection(), composing: isComposing() }) };
  window.JSBridge.showInBrowser = url => request({ type: 'link', url });
  window.addEventListener('pagehide', () => { clearTimeout(timer); if (!isComposing()) flush(); });
  window.addEventListener('blur', () => { if (!isComposing()) flush(); });
  await request({ type: 'mounted', id: current.id });
})().catch(error => { window.bootError = error.stack; console.error(error); });
