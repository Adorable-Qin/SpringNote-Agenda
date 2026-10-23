import { MarkdownDocument, type SelectionBookmark } from '../vendor/open-typora/src/editor/model';
import { RichEditor, type RichCallbacks } from '../vendor/open-typora/src/editor/RichEditor';

/** Shared editing lifecycle for the standalone core and the Flutter editor. */
export class LiveMarkdownEngine {
  readonly rich: RichEditor;
  private disposed = false;

  constructor(readonly root: HTMLElement, readonly model: MarkdownDocument,
    documentId: string, callbacks: RichCallbacks) {
    root.dataset.editorCore = 'springnote-live-markdown';
    this.rich = new RichEditor(root, model, documentId, {
      ...callbacks,
      // CodeMirror changes its model during composition. Those provisional
      // characters must not escape into autosave or native selection reports.
      change: () => { if (!this.disposed && !this.rich?.composing) callbacks.change(); },
      cursor: (line, column) => { if (!this.disposed && !this.rich?.composing) callbacks.cursor(line, column); },
      compositionFinished: () => { if (!this.disposed) callbacks.compositionFinished(); },
    });
  }

  syncFromHost(content: string, selection: SelectionBookmark, render = true) {
    if (this.disposed || this.rich.composing) return false;
    const text = content.replace(/\r\n/g, '\n');
    const clamp = (n: number) => Number.isFinite(n) ? Math.max(0, Math.min(Math.trunc(n), text.length)) : 0;
    const next = { anchor: clamp(selection.anchor), head: clamp(selection.head) };
    const changed = text !== this.model.text;
    if (!changed && next.anchor === this.model.selection.anchor && next.head === this.model.selection.head) return false;
    this.rich.releaseFence();
    this.model.closeGroup();
    if (changed) this.model.replace(0, this.model.text.length, text, 'host-command', next);
    this.model.selection = next;
    if (render) this.rich.select(next, false);
    return changed;
  }

  destroy() {
    if (this.disposed) return;
    this.disposed = true;
    this.rich.destroy();
    delete this.root.dataset.editorCore;
  }
}
