import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { MarkdownEditor, type EditorHandle } from '../vendor/open-typora/src/editor/MarkdownEditor';
import { defaultPreferences } from '../vendor/open-typora/src/preferences';
import { setMarkdownOptions } from '../vendor/open-typora/src/editor/markdown';
import type { DocumentRecord } from '../vendor/open-typora/src/types';
import { request } from './host';
import { normalizedOffset, serializedOffset } from './markdown-offsets';
import '../vendor/open-typora/src/styles.css';
import '../vendor/open-typora/src/features.css';
import '../vendor/open-typora/src/extensions.css';
import './style.css';

type Snapshot = { id: string; revision: number; text: string; anchor: number; head: number; readOnly: boolean; dark: boolean; english: boolean };
const preferences = { ...defaultPreferences, spellcheck: false, imageAutoUpload: false };
setMarkdownOptions(preferences);

function App({ initial }: { initial: Snapshot }) {
  const editor = useRef<EditorHandle>(null);
  const current = useRef(initial), sequence = useRef(0), applying = useRef(false);
  const pending = useRef<Snapshot | null>(null);
  const [options, setOptions] = useState(initial);
  const [rendered, setRendered] = useState(true);
  const [error, setError] = useState('');
  const [history, setHistory] = useState({ undo: false, redo: false });
  const [record, setRecord] = useState<DocumentRecord>({ id: initial.id, name: 'SpringNote.md', content: initial.text, savedContent: initial.text, diskHash: null, path: null, lineEnding: initial.text.includes('\r\n') ? '\r\n' : '\n' });
  const report = (changed = false) => {
    if (applying.current || !editor.current || editor.current.composing()) return;
    const text = editor.current.markdown(), selection = editor.current.selection();
    if (changed) current.current = { ...current.current, text };
    void request({ type: changed ? 'change' : 'selection', id: current.current.id, revision: current.current.revision, sequence: ++sequence.current, text,
      anchor: serializedOffset(text, selection.anchor), head: serializedOffset(text, selection.head) }).catch(e => setError(e.message));
  };
  function receive(snapshot: Snapshot) {
    if (snapshot.id !== current.current.id || snapshot.revision < Math.max(current.current.revision, pending.current?.revision ?? 0)) return;
    setOptions(snapshot);
    // Only a new native revision can change content or selection. A same-revision
    // acknowledgement may arrive after the browser has already accepted input.
    if (snapshot.revision === current.current.revision) return;
    // A delayed save acknowledgement must never replace an in-progress IME
    // composition or move its caret back to the pre-composition bookmark.
    if (snapshot.text === current.current.text && editor.current?.composing()) {
      current.current = snapshot;
      setOptions(snapshot);
      return;
    }
    if (editor.current?.composing()) { pending.current = snapshot; return; }
    applying.current = true;
    current.current = snapshot;
    setOptions(snapshot);
    editor.current?.syncFromHost(snapshot.text, { anchor: normalizedOffset(snapshot.text, snapshot.anchor), head: normalizedOffset(snapshot.text, snapshot.head) });
    setRecord(previous => previous.content === snapshot.text ? previous : ({ ...previous, content: snapshot.text }));
    applying.current = false;
  }
  useEffect(() => {
    (window as any).springNoteEditor = { receive, snapshot: () => ({ text: editor.current?.markdown(), selection: editor.current?.selection(), composing: editor.current?.composing() }) };
    (window as any).desktop = { historyState: async (undo: boolean, redo: boolean) => setHistory({ undo, redo }) };
    applying.current = true;
    editor.current?.syncFromHost(initial.text, { anchor: normalizedOffset(initial.text, initial.anchor), head: normalizedOffset(initial.text, initial.head) });
    applying.current = false;
    void request({ type: 'mounted' });
    return () => { delete (window as any).springNoteEditor; delete (window as any).desktop; };
  }, []);
  useEffect(() => { document.documentElement.dataset.appearance = options.dark ? 'dark' : 'light'; document.documentElement.lang = options.english ? 'en' : 'zh-CN'; }, [options.dark, options.english]);
  const label = (zh: string, en: string) => options.english ? en : zh;
  const button = (text: string, title: string, run: () => void, disabled = options.readOnly) => <button type="button" title={title} aria-label={title} disabled={disabled} onMouseDown={e => e.preventDefault()} onClick={run}>{text}</button>;
  const command = (action: string) => () => editor.current?.command(action);
  return <main className="embedded-editor">
    <nav className="embed-toolbar" aria-label={label('编辑工具栏', 'Editor toolbar')}>
      {button('↶', label('撤销', 'Undo'), () => editor.current?.undo(), options.readOnly || !history.undo)}
      {button('↷', label('重做', 'Redo'), () => editor.current?.redo(), options.readOnly || !history.redo)}
      <span className="toolbar-divider" />
      {button('B', label('加粗', 'Bold'), () => editor.current?.wrap('**', '**'))}
      {button('I', label('斜体', 'Italic'), () => editor.current?.wrap('*', '*'))}
      {button('H₂', label('标题', 'Heading'), command('heading-2'), options.readOnly || !rendered)}
      {button('☑', label('任务列表', 'Task list'), command('task-list'), options.readOnly || !rendered)}
      {button('•', label('无序列表', 'Bullet list'), command('unordered-list'), options.readOnly || !rendered)}
      {button('❞', label('引用', 'Quote'), command('quote'), options.readOnly || !rendered)}
      {button('</>', label('代码块', 'Code block'), () => editor.current?.codeBlock(), options.readOnly || !rendered)}
      {button('▦', label('表格', 'Table'), command('table'), options.readOnly || !rendered)}
      {button('∑', label('公式', 'Math'), command('math-block'), options.readOnly || !rendered)}
      {button('⌕', label('查找替换', 'Find and replace'), () => editor.current?.find(), false)}
      <span className="toolbar-space" />
      <button type="button" className="mode-button" aria-pressed={!rendered} onMouseDown={e => e.preventDefault()} onClick={() => setRendered(value => !value)}>{rendered ? label('源码', 'Source') : label('实时编辑', 'Live')}</button>
    </nav>
    {error && <div role="alert" className="embed-error">{error}<button onClick={() => setError('')}>×</button></div>}
    <MarkdownEditor ref={editor} document={record} rendered={rendered} preferences={preferences} readOnly={options.readOnly}
      onChange={content => { setRecord(previous => ({ ...previous, content })); report(true); }}
      onCursor={() => report()} onError={setError}
      onCompositionEnd={() => { if (pending.current) { const next = pending.current; pending.current = null; receive(next); } }} />
  </main>;
}

let started = false;
async function start() {
  if (started || !(window as any).flutter_inappwebview?.callHandler) return;
  started = true;
  try { createRoot(document.getElementById('root')!).render(<App initial={await request({ type: 'ready' })} />); }
  catch (error) { document.getElementById('root')!.textContent = String(error); }
}
window.addEventListener('flutterInAppWebViewPlatformReady', start);
void start();
