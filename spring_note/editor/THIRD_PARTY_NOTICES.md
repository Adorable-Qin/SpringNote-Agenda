# 第三方来源

此个人工程的实时编辑引擎来自用户提供的 `typora-setup-x64-1.7.6.exe`。Typora 编辑引擎与随安装包提供的资源保留其原始权利归属；本工程的开源许可证不替代这些文件的许可。

- 原始文件：`resources/appsrc/window/frame.js`
- 版本：1.7.6
- 原始 SHA-256：`3a1a1294d840ac7d5fff820426ec272b3cce80ab025c0d925a737775a9ba59ae`
- 原始协议：`vendor/typora-engine/LICENSE.md`，以及资源清单 `assets/typora_editor/manifest.json` 中的 `Typora-License-Agreement.md`。
- 适配：增加 SpringNote 启动入口、暴露 SourceView 坐标映射；编辑算法保留原实现。宿主调用坐标映射时复制 CodeMirror 光标对象，避免同步过程修改实时光标。

构建同时保留依赖资源自带的版权和许可证。文件扁平化只用于 Flutter 资源打包，原相对路径、大小和摘要保存在 manifest 中，可校验及追溯。

前期 Open Typora 原型的来源与 MIT 许可证见 `vendor/open-typora/LICENSE`。
