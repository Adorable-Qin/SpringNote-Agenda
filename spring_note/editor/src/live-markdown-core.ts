import { MarkdownDocument, type SelectionBookmark } from '../vendor/open-typora/src/editor/model';
import { LiveMarkdownEngine } from './live-markdown-engine';
import type { BlockArguments } from '../vendor/open-typora/src/editor/blockCommands';
import { setMarkdownOptions } from '../vendor/open-typora/src/editor/markdown';
import { defaultPreferences } from '../vendor/open-typora/src/preferences';
import '../vendor/open-typora/src/styles.css';
import '../vendor/open-typora/src/features.css';
import '../vendor/open-typora/src/extensions.css';
import './live-markdown-core.css';

// This entry uses the MIT Open Typora implementation vendored in this repository.
// All instances share the upstream parser's default syntax configuration.
setMarkdownOptions(defaultPreferences);

export interface LiveMarkdownSnapshot {
  markdown: string;
  /** UTF-16 offsets into LF-normalized Markdown, including hidden syntax. */
  selection: SelectionBookmark;
  composing: boolean;
  canUndo: boolean;
  canRedo: boolean;
}
export interface LiveMarkdownOptions {
  markdown?: string;
  readOnly?: boolean;
  label?: string;
  onChange?(snapshot: LiveMarkdownSnapshot): void;
  onSelection?(snapshot: LiveMarkdownSnapshot): void;
  /** The host owns link handling and image storage. */
  onLink?(url: string): void;
  onImage?(file: File): void;
}

/** One rich editor per container. Persistence remains the caller's responsibility. */
export function createLiveMarkdownEditor(container: HTMLElement, options: LiveMarkdownOptions = {}) {
  if (!container.isConnected) throw new Error('Attach the editor container before mounting.');
  if (container.childNodes.length) throw new Error('The editor container must be empty.');
  const initial = options.markdown ?? '';
  const validateSize = (text: string) => {
    if (text.length > 300_000) throw new RangeError('Use the full editor source mode for documents over 300,000 UTF-16 units.');
  };
  validateSize(initial);
  const documentId = `live-${crypto.randomUUID()}`;
  const model = new MarkdownDocument(initial, initial.includes('\r\n') ? '\r\n' : '\n');
  const surface = document.createElement('div');
  surface.className = 'sn-live-markdown document-editor';
  const root = document.createElement('div');
  root.className = 'rich-document';
  surface.append(root);
  container.append(surface);
  let disposed = false, readOnly = options.readOnly ?? false, applying = false;
  let pending: { markdown: string; selection?: SelectionBookmark } | null = null;
  const alive = () => { if (disposed) throw new Error('The editor has been destroyed.'); };
  const snapshot = (): LiveMarkdownSnapshot => {
    alive();
    return { markdown: model.toMarkdown(), selection: { ...model.selection },
      composing: rich.composing, canUndo: model.canUndo, canRedo: model.canRedo };
  };
  const engine = new LiveMarkdownEngine(root, model, documentId, {
    change: () => { if (!applying && !disposed) options.onChange?.(snapshot()); },
    cursor: () => { if (!applying && !disposed) options.onSelection?.(snapshot()); },
    image: file => options.onImage?.(file),
    link: url => options.onLink?.(url),
    compositionFinished: () => {
      if (pending && !disposed) {
        const next = pending;
        pending = null;
        setMarkdown(next.markdown, next.selection);
      }
    },
  });
  const rich = engine.rich;
  root.setAttribute('aria-label', options.label ?? 'Markdown 编辑器');
  const configure = () => rich.setOptions({ readOnly, spellcheck: false, tabSize: 2, typewriter: false, autoPair: false, emoji: true });
  configure();
  const clamp = (selection: SelectionBookmark) => {
    const offset = (n: number) => Number.isFinite(n) ? Math.max(0, Math.min(Math.trunc(n), model.text.length)) : 0;
    return { anchor: offset(selection.anchor), head: offset(selection.head) };
  };
  function setMarkdown(markdown: string, selection?: SelectionBookmark): 'applied' | 'unchanged' | 'deferred' {
    alive();
    validateSize(markdown);
    // Save acknowledgements must not disturb a composing DOM or its selection.
    if (markdown === model.toMarkdown() && (!selection || rich.composing)) return 'unchanged';
    if (rich.composing) {
      pending = { markdown, selection: selection && { ...selection } };
      return 'deferred';
    }
    applying = true;
    try {
      const next = markdown.replace(/\r\n/g, '\n');
      const changed = engine.syncFromHost(markdown, selection ?? { anchor: next.length, head: next.length });
      return changed ? 'applied' : 'unchanged';
    } finally { applying = false; }
  }
  const edit = (action: () => void) => {
    alive();
    if (readOnly || rich.composing) return false;
    action();
    return true;
  };
  return {
    snapshot,
    /** Host updates enter undo history; they do not emit onChange. Initial EOL style is retained. */
    setMarkdown,
    select(selection: SelectionBookmark) {
      alive();
      if (rich.composing) return false;
      rich.select(clamp(selection));
      return true;
    },
    insert(text: string) {
      return edit(() => { validateSize(model.text + text); rich.insert(text); });
    },
    command(action: string, args?: BlockArguments) { return edit(() => rich.command(action, args)); },
    wrap(before: string, after = before) { return edit(() => rich.wrap(before, after)); },
    undo() { return edit(() => rich.undo()); },
    redo() { return edit(() => rich.redo()); },
    setReadOnly(value: boolean) { alive(); readOnly = value; configure(); },
    focus() { alive(); root.focus({ preventScroll: true }); rich.restore(); },
    destroy() {
      if (disposed) return;
      disposed = true;
      pending = null;
      engine.destroy();
      surface.remove();
    },
  };
}
export type LiveMarkdownEditor = ReturnType<typeof createLiveMarkdownEditor>;
