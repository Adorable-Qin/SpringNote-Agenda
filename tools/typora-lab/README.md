# Typora 1.7.6 本地测试

双击本目录的 `start.cmd` 启动 SpringNote 测试实例。此启动器用于独立资源调试。日常程序直接加载 Flutter 内置资源，工程接入与重建方式见 `spring_note/editor/README.md`。

测试程序在 `.toolchains/typora-lab/app`；编辑器资源在 `.toolchains/typora-lab/web`；测试笔记和设置在 `.toolchains/typora-lab/profile/Roaming/SpringNote`。启动器为测试实例设置独立的数据、WebView 配置目录和窗口互斥名称，可与现有程序同时运行。在测试实例中新建笔记，或复制需要测试的 Markdown 内容。

## 原版代码与宿主适配

来源是用户提供的 `typora-setup-x64-1.7.6.exe`。使用其中 `resources/appsrc/window/frame.js` 的 Editor、NodeMap、Brush、Selection、UndoManager、Stylize、SourceView、CodeMirror 模块，以及原版主题、代码语言模式和 MathJax。源 renderer SHA-256：

```
3a1a1294d840ac7d5fff820426ec272b3cce80ab025c0d925a737775a9ba59ae
```

`prepare.mjs` 校验这个摘要，保留原版编辑算法，增加宿主启动入口并暴露 SourceView 内部位置映射。`spring_note/editor/runtime/host.js` 负责 Flutter 消息、保存与选区同步、快捷键绑定、图片存取和主题。原版映射方法会修改 CodeMirror 返回的光标对象，因此宿主调用时复制该对象，避免反复同步改变编辑光标。

中文组合输入期间暂缓模型同步和外部内容应用；提交后恢复同步。保存回声不会重建文档或清除历史；真正的外部修改使用原版 `File.reloadContent`。富文本、源码、代码块中的编辑和撤销由原版组件处理。图片保留 Markdown 相对路径，通过 SpringNote 的文档作用域 HTTP 服务读取。

调试资源与程序放在 Git 忽略的 `.toolchains` 中。正式资源由 `bundle.mjs` 写入 `spring_note/assets/typora_editor/`，并由 `verify-bundle.mjs` 校验。本目录保存导入、打包脚本及浏览器测试。该测试入口使用 `SPRINGNOTE_TYPORA_LAB_DIR` 环境变量加载本地资源。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 撤销 / 重做 | Ctrl+Z / Ctrl+Y、Ctrl+Shift+Z |
| 加粗 / 斜体 / 下划线 | Ctrl+B / Ctrl+I / Ctrl+U |
| 1–6 级标题 / 正文 | Ctrl+1…6 / Ctrl+0 |
| 代码块 / 引用 | Ctrl+Shift+K / Ctrl+Shift+Q |
| 无序列表 / 任务列表 | Ctrl+Shift+L / Ctrl+Shift+M |
| 行内代码 | Ctrl+Shift+` |
| 源码模式 / 查找 | Ctrl+/ / Ctrl+F |
| 列表续行 / 缩进 / 退缩进 | Enter / Tab / Shift+Tab |
| 立即同步 | Ctrl+S |

## 重建与验证

在仓库根目录运行：

```powershell
node tools/typora-lab/bundle.mjs
$env:PLAYWRIGHT_BROWSERS_PATH = (Resolve-Path .toolchains/playwright).Path
node --test tools/typora-lab/editor.test.mjs
```

准备脚本使用本地已有的 `.toolchains/typora-research/1.7.6/app/resources` 和本目录的 `module-index.json`，也接受资源目录作为第一个参数。静态模块索引由 `tools/inspect_typora.mjs` 生成。

原生测试位于 `spring_note/integration_test/typora_lab_test.dart`。设置 `SPRINGNOTE_TYPORA_LAB_DIR` 为上述 `web` 的绝对路径后，运行 `flutter test integration_test/typora_lab_test.dart -d windows`。Windows Release 构建输出复制到 `.toolchains/typora-lab/app`，复制时排除用户配置文件 `data-directory.json`，使启动器使用独立测试数据目录。当前交付的测试配置已启用笔记实时编辑。

自动化覆盖 Chromium 的 IME 组合事件、正文和代码块光标、反向跨段落选区、格式命令、列表、粘贴、图片、保存回声和撤销重做。原生 WebView 测试覆盖加载、实际桥接保存、外部更新和源码切换。微软拼音、搜狗等系统输入法的候选窗交互仍需在此测试程序中实测。这个版本包含嵌入式编辑区域；Typora 的完整桌面菜单、文件管理和发布功能不属于宿主接口。
