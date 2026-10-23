# SpringNote 实时 Markdown 编辑核心

这个导出包提供可嵌入浏览器或 WebView 的 Markdown 实时编辑核心，以及对应的可修改源代码。实现来自当前项目已经引入的 Open Typora 0.13.4（MIT，commit `6c80997cbc1d98dc6a38adf38ea6839490d59801`），新增的宿主接口遵循 SpringNote 的 AGPL-3.0-only 许可证。第三方许可证见 `web/THIRD_PARTY_NOTICES.txt`。

## 在当前项目中使用

笔记页与工作计划页通过 `PlanMarkdownEditor` → `OpenTyporaEditor` 使用完整编辑器。独立导出入口与项目中的 `MarkdownEditor.tsx` 共同使用 `src/live-markdown-engine.ts`，共享富文本实例管理、组合输入保护和宿主选区同步。继续使用这个组件即可保留源码模式、工具栏、搜索替换、图片存储和 Flutter 文档会话同步。其可调用形式为：

```dart
OpenTyporaEditor(
  controller: markdownController,
  onChanged: saveMarkdown,
  imageBasePath: documentImageDirectory,
  expand: true,
)
```

新导出的核心入口在 `source/src/live-markdown-core.ts`，适合需要更小接入界面的新 WebView 或网页编辑区域。它复用同一套 `MarkdownDocument`、`RichEditor` 和块渲染模块，不需要 React、Flutter 或 Electron 对象才能运行。

## 直接使用构建产物

把整个 `web/` 目录放到 HTTP 静态资源服务中，用浏览器打开 `index.html`。必须保留动态加载的 JS 文件、字体和 CSS；不要只复制主 JS。示例页包含可编辑正文和同步显示的源文本。

不要直接双击 `file://` 下的 HTML，ES module 和动态加载资源需要 HTTP 来源。在 SpringNote 中可以使用现有的 loopback 资源服务器；接入完整编辑界面时沿用原来的资产目录。

```html
<link rel="stylesheet" href="./web/live-markdown.css">
<div id="editor" style="height: 440px"></div>
<script type="module">
  import { createLiveMarkdownEditor } from './web/live-markdown.js';

  const editor = createLiveMarkdownEditor(document.querySelector('#editor'), {
    markdown: '# 标题\n\n开始写作',
    onChange({ markdown }) {
      // 在宿主侧安排自动保存。保存完成无需重新创建编辑器。
      console.log(markdown);
    },
    onLink(url) {
      // 由宿主校验并打开外部链接或应用内文档。
      console.log(url);
    },
    onImage(file) {
      // 由宿主保存图片，再调用 editor.insert(...) 写入 Markdown 引用。
      console.log(file.name);
    },
  });

  editor.select({ anchor: 2, head: 4 });
  editor.wrap('**');
  // 页面/文档卸载时调用 editor.destroy()。
</script>
```

CSS 包含上游的页面级样式；嵌入已有网页时建议放在独立 iframe 或 WebView 中，避免与宿主样式冲突。

## API

| 方法 | 作用 |
| --- | --- |
| `snapshot()` | 返回 Markdown、选区、组合输入状态及撤销/重做可用状态 |
| `setMarkdown(text, selection?)` | 宿主替换内容，保留为一个可撤销操作；不回调 `onChange`，返回 `applied`、`unchanged` 或 `deferred` |
| `select({anchor, head})` | 设置选区；组合输入期间返回 `false` |
| `insert(text)` | 在当前位置插入 Markdown |
| `wrap(before, after = before)` | 给选区添加标记，例如 `wrap('**')` |
| `command(action, args?)` | 调用上游块命令，如 `heading-2`、`unordered-list`、`task-list`、`quote`、`table`、`math-block` |
| `undo()` / `redo()` | 使用编辑器统一历史 |
| `setReadOnly(value)` | 控制用户编辑；宿主仍可同步内容 |
| `focus()` | 聚焦并恢复光标 |
| `destroy()` | 移除本实例 DOM、监听器、浮层与代码块子编辑器，可重复调用 |

`onChange` 和 `onSelection` 接收相同快照结构。所有选区都是 **LF 归一化 Markdown 中的 UTF-16 偏移**，包含隐藏的语法字符。它们与 DOM 文本偏移、Unicode 码点数量不同。初始文本的 CRLF/LF 风格会保留。

`setMarkdown` 收到当前已保存文本的回声时不重建 DOM。IME 组合期间收到不同正文，会缓存最后一份显式宿主更新，在组合结束后应用；这是宿主最终内容优先策略，不是协同编辑合并协议。跨进程异步保存仍应使用现有 `OpenTyporaSession` 的文档 ID、revision 和 sequence 检查。

本入口提供富文本编辑核心。源码模式、完整工具栏和查找替换由现有 `MarkdownEditor.tsx` / Flutter 界面提供。核心入口拒绝初始或宿主传入超过 300,000 UTF-16 单元的正文；大文档应进入完整编辑器的源码模式。未对长文档持续输入做性能保证。

图片回调和链接回调默认不执行宿主操作。相对图片沿用项目现有的 `media/<编码后的原始引用>` 路由，宿主负责提供该路由及目录访问范围。这个接口没有文件系统、自动保存、跨文档冲突处理或远程图片上传功能。

## 从源代码构建和验证

使用 Node 24 或更新版本，在导出包的 `source/` 下运行：

```sh
npm ci
npm run build:core
npx playwright install chromium
npm run test:core
```

输出在 `dist-core/`。当前仓库中 `npm run export:core` 会重新构建并在项目 `.toolchains/exports/` 下生成带时间戳的目录和压缩包。`manifest.json` 列出导出文件的 SHA-256。导出脚本使用 Windows 内置 ZIP 工具，其他平台使用 tar。

`flutter/lib/core/editor/` 保存当前项目的宿主适配参考。它依赖 SpringNote 已有的图片、链接服务及 pubspec 配置；集成到其他 Flutter 项目时应实现这些服务，不能只复制这几个 Dart 文件就认为接入完成。

## 验证覆盖

浏览器测试覆盖连续输入与未改动块复用、保存回声、CRLF 和选区映射、格式操作、宿主更新撤销、Chromium IME 组合事件、组合期间延迟同步、只读、销毁后重新挂载、表格、公式和 Mermaid。

项目集成测试还覆盖源码和代码块中的中文候选输入不触发保存、组合输入一次撤销、跨模式保留重做分支、反向跨段选区、混合换行与 emoji 偏移、组合期间工具栏保护。Flutter 测试验证月度计划分区更新保留相邻分区的选区，以及保存回调内同步修改正文时推进 revision。原生 Windows 测试通过笔记和计划共用的 `PlanMarkdownEditor` 验证 WebView 挂载、中文插入、保存回声后的撤销重做和宿主更新。

这些自动化测试使用 Chromium 的 IME 接口，并不等同于对所有 Windows 输入法和 macOS WKWebView 的人工验证。具体分析与版本证据见 `source/docs/typora-1.7.6-analysis.zh-CN.md`。
