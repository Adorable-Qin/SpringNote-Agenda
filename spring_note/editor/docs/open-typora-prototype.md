# SpringNote embedded editor

For a reusable DOM API, build and export with `npm run export:core`. See
[the core integration guide](docs/reusable-core.zh-CN.md) and
[the Typora 1.7.6 implementation study](docs/typora-1.7.6-analysis.zh-CN.md).
Run `npm run test:core` to verify the separately bundled core.

The live editor in notebooks and work plans embeds the actual Open Typora editor
modules in a Flutter InAppWebView. SpringNote's `TextEditingController` and existing
note services continue to own Markdown persistence, autosave and calendar updates.

## Pinned sources

- SpringNote baseline: 1.0.16, including the autosave/history fix in `5fb2e7f`,
  and release metadata at `6d8f57e`.
- Open Typora: [0.13.4, commit 6c80997cbc1d98dc6a38adf38ea6839490d59801](https://github.com/AniChikage/open-typora/tree/6c80997cbc1d98dc6a38adf38ea6839490d59801), MIT.
- `vendor/open-typora/src/editor` contains the upstream document model,
  RichEditor, MarkdownEditor, CodeMirror integration, clipboard, rendering,
  formatting commands, table editing, MathJax and Mermaid modules.
- Upstream notices are retained in `vendor/open-typora/LICENSE`. The build also
  emits third-party dependency notices into the distributed Flutter assets.

## Host integration

`src/main.tsx` mounts the upstream React component. `src/host.ts` supplies the
Flutter image and link adapters. The desktop app serves packaged assets over an
ephemeral loopback port with a per-editor random path. Only scoped local images
are readable. The document travels through the WebView bridge and stays out of
HTTP requests and browser storage. A CSP restricts scripts to bundled resources.

`src/live-markdown-engine.ts` owns the shared rich editor lifecycle and native
content/selection synchronization. Both `live-markdown-core.ts` and the production
`MarkdownEditor.tsx` instantiate this engine. Notes and plan sections reach it
through `PlanMarkdownEditor` → `OpenTyporaEditor` → `src/main.tsx`.

The bridge identifies each document session and numbers native revisions and
browser events. It rejects stale events and ignores autosave echoes. Composition
is left in the upstream editor until committed. Source and rich modes share the
upstream history. Native same-document insertions enter that history as commands.
Changing documents disposes the old editor; saving does not recreate it.
Rich text, fenced code and source mode publish only committed IME text. Each
composition is one undo step. Mode switches retain individual edits and redo
branches; Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y use that same history. Toolbar mutations
are blocked during composition, and mode switches apply after it ends. UTF-16 offsets are mapped across actual CRLF pairs,
including documents with mixed line endings and emoji.

Monthly plans compare each incoming section with its last serialized value.
Updating a sibling section leaves the active editor and selection intact, even
when saving previously added Markdown separator blank lines. Synchronous host
edits inside save callbacks receive a new native revision.

Notebook surfaces fill the available panel. Plan sections use a 440 px scrolling
surface. Windows uses WebView2, macOS uses WKWebView. If the runtime cannot start,
the app shows the error and an editable source fallback. Windows requires the
Microsoft Edge WebView2 Runtime. Linux currently uses the source fallback.

The Windows platform dependency is pinned to 0.6.0. A narrow adapter corrects
its environment instance channel after creation (the upstream factory binds the
static factory ID). This lets the plugin's normal disposal release the native
environment and its Dart handler. Recheck this adapter when upgrading the plugin.

## Local upstream patches

Keep these small changes when refreshing the pinned source:

1. `MarkdownEditor.tsx`: expose source selection and native synchronization on
   its handle, preserving history and allowing host changes while read-only.
2. `markdown.ts` / `htmlResources.ts`: route local media to the document server.
3. `mathEngine.ts`: adjust the bundled font import path for the vendored layout.
4. `richRender.ts`: retain trailing whitespace removed by markdown-it, so the
   DOM has a caret position after a space typed at the end of a paragraph.
5. `MarkdownEditor.tsx` / `RichEditor.ts`: use the shared engine, suppress
   provisional composition callbacks, keep one history across source/live modes,
   guard commands during IME input, and support Windows Ctrl+Y redo.

The host stylesheet preserves whitespace in editable leaves and adapts the
toolbar, typography and dark theme. File move/delete/upload actions from the
upstream desktop shell are hidden; image alt text, dimensions and URL editing
remain available.

## Build and test

Use Node 24 or later, then run from this directory:

```sh
npm ci
npm run build
npx playwright install chromium
npm test
npm run test:core
```

Commit the generated `../assets/open_typora/` files with source changes. Flutter
builds use those assets directly and require no Node installation or internet
access at runtime. The fixed dependency graph is in `package-lock.json`.

From `spring_note`, run Flutter tests and the optional native smoke test:

```sh
flutter test
flutter test integration_test/open_typora_editor_test.dart -d windows
flutter build windows --release
```

Windows compilation requires NuGet on PATH for the WebView2 SDK. Use a short
checkout/build path if MSBuild reports its 260-character path limit. macOS release
sandboxing permits the local asset server with the network server entitlement.

To run the native test alongside a running SpringNote instance, configure the
Windows CMake build directory with `-DSPRINGNOTE_TEST_INSTANCE=ON`. This gives the
test its own single-instance mutex and window title. Restore the option to `OFF`
before building the application for distribution.
