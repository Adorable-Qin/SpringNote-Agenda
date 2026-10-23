# SpringNote 实时编辑器

笔记与工作计划统一使用 `PlanMarkdownEditor` → `OpenTyporaEditor` → `editor/runtime/host.js`。正式 Flutter 构建从 `assets/typora_editor/` 读取已打包资源，直接使用应用现有的数据目录、自动保存、图片存储与日历联动。

## 工程结构

- `runtime/host.js`：文档切换、组合输入、Markdown/UTF-16 选区同步、撤销重做、图标工具栏、快捷键和图片粘贴。
- `runtime/preload.js`：编辑引擎所需的浏览器宿主接口。
- `runtime/editor.css`：SpringNote 工具栏、排版和主题；颜色由 Flutter 主题传入。
- `runtime/view.html`：编辑页面与模板。`vendor/typora-engine/frame.js`：固定版本的编译后引擎代码；`scripts/renderer.mjs` 组装应用启动入口和选区映射访问器。
- `lib/core/editor/editor_runtime.dart`：应用级 WebView 环境与启动预热。
- `lib/core/editor/open_typora_server.dart`：共享只读资源缓存、随机会话路径及文档图片访问范围。
- `lib/core/editor/open_typora_session.dart`：文档编号、修订号和事件序列校验，连接 TextEditingController 与保存服务。

更换笔记时保留 WebView，通过显式文档边界重置正文、源码历史、选区和图片作用域。自动保存回声不会重建文档。组合输入期间不回写预编辑文本；文档切换会等组合结束，过期的文档消息与图片粘贴结果会被丢弃。外部修改仍进入当前文档的编辑历史。

Windows 的浏览器环境由应用持有，计划的多个编辑区共享它；关闭一个编辑区不会释放其他编辑区仍在使用的环境。只读资源只加载一次，缓存不包含笔记内容或图片。应用初始化时并行预热浏览器环境与资源；首页显示期间，已挂载的笔记本直接加载自己的可见 WebView，切到笔记本时复用同一实例。当前 Windows 插件不支持把无界面的 WebView 转移到画面中，因此不使用该转移接口。若用户立即打开编辑区，仍需等待尚未完成的启动部分。

笔记切换前等待当前编辑器提交并收到宿主确认，避免最后一次输入还在同步队列中。中文组合输入开始和结束时关闭前后输入的撤销合并分组。

## 引擎来源

当前个人版本使用用户提供的 Typora 1.7.6 安装包中编译后的 JavaScript 编辑引擎。它仍在内嵌 WebView 中执行。工程内维护的宿主代码负责产品界面、生命周期、存储与状态同步。原始来源、校验值与许可见 [第三方说明](THIRD_PARTY_NOTICES.md)。

前期 Open Typora / 可复用核心的独立源代码与构建入口保留在 `vendor/`、`src/` 和 `build:core`，说明见 [原型文档](docs/open-typora-prototype.md)。正式应用只声明当前编辑器资源目录。

## 构建与验证

在 `spring_note/editor` 执行：

```sh
npm ci
npm run build:runtime
npm run verify:runtime
npx playwright install chromium
npm run test:runtime
```

`build:runtime` 使用仓库内的引擎、模板和宿主源文件重建动态资源，保留资源清单中的静态文件。修改 runtime 或组装脚本后一并更新 `assets/typora_editor/`。`verify:runtime` 校验每个文件与源代码的对应摘要。Flutter、CI 和日常重建均不依赖外部安装包。

CI 和正式发布流程都会运行浏览器与 Flutter 回归测试。Windows 构建完成后还会校验实际输出目录中的编辑器资源，校验通过后才打包安装程序，确保更新包包含与源代码一致的编辑器。

重新导入原始静态资源时才需要执行 `node tools/typora-lab/bundle.mjs <resources目录>`。`prepare.mjs` 校验原始 renderer 的 SHA-256，`module-index.json` 提供固定模块位置。

在 `spring_note` 执行：

```sh
flutter analyze
flutter test
flutter test integration_test/open_typora_editor_test.dart -d windows
flutter test integration_test/editor_startup_test.dart -d windows
flutter test integration_test/notebook_editor_test.dart -d windows
flutter build windows --release
```

浏览器回归覆盖中文组合输入、代码块与源码模式、反向选区、快捷键、图片、保存回声、文档切换及撤销历史隔离。原生测试验证 WebView 桥接、连续切换耗时，以及从首页进入笔记本、笔记切换、计划编辑和返回笔记本的流程；同时校验编辑命令与可见纹理属于同一个原生实例，实际点击工具栏并验证文件保存。系统输入法候选窗口仍需使用实际输入法体验确认。

原生测试与日常程序同时运行时，给测试构建设置 `SPRINGNOTE_TEST_INSTANCE=ON`，并使用独立的 `LOCALAPPDATA`。构建日常版本前将该 CMake 选项恢复为 `OFF`。
