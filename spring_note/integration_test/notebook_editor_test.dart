import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:spring_note/core/editor/editor_runtime.dart';
import 'package:spring_note/core/editor/open_typora_editor.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/notes_page.dart';
import 'package:spring_note/features/plans/work_plans_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notebook and plans paint and edit their visible native views', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 900));
    final directory = await Directory.systemTemp.createTemp('notebook_editor_');
    final state = LocalDataState(
      dataDirectory: directory.path,
      configPath: p.join(directory.path, 'config.json'),
      dailyNotesDirectory: p.join(directory.path, 'notes', 'daily'),
      weeklyNotesDirectory: p.join(directory.path, 'notes', 'weekly'),
      monthlyNotesDirectory: p.join(directory.path, 'notes', 'monthly'),
      config: AppConfig.defaults().copyWith(language: 'zh'),
    );
    final first = File(p.join(state.dailyNotesDirectory, '2026-10-22.md'));
    final second = File(p.join(state.dailyNotesDirectory, '2026-10-21.md'));
    final plan = File(
      p.join(state.directoryFor(NoteKind.weeklyPlan), '2026-W43.md'),
    );
    await first.parent.create(recursive: true);
    await plan.parent.create(recursive: true);
    await first.writeAsString('# 第一篇笔记\n\n正文');
    await second.writeAsString('# 第二篇笔记\n\n独立内容');
    await plan.writeAsString('# 工作计划\n\n计划正文');
    final views = <InAppWebViewController>{};
    OpenTyporaEditor.debugOnReady = views.add;
    var section = 0;
    late StateSetter navigate;
    final captureKey = GlobalKey();

    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../.toolchains/typora-release/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    Future<void> waitFor(bool Function() condition) async {
      for (var frame = 0; frame < 400 && !condition(); frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(condition(), isTrue);
    }

    Future<dynamic> js(InAppWebViewController view, String source) async =>
        tester.runAsync(() => view.evaluateJavascript(source: source));

    Future<InAppWebViewController> viewWith(String text) async {
      for (final view in views) {
        if ((await js(
          view,
          'springNoteEditor.snapshot().text',
        )).toString().contains(text)) {
          return view;
        }
      }
      throw StateError('No editor for $text');
    }

    void expectVisibleView(InAppWebViewController view) {
      final texture = tester.widget<Texture>(find.byType(Texture));
      // JavaScript can succeed against a headless browser while the on-screen
      // texture is a different, blank WebView. Check the native identity too.
      expect(
        view.getViewId(),
        texture.textureId,
        reason: 'Editing commands must target the WebView painted on screen',
      );
      expect(
        tester.getSize(find.byType(InAppWebView)).height,
        greaterThan(300),
      );
    }

    Future<void> clickCommand(
      InAppWebViewController view,
      String command,
    ) async {
      final position =
          await js(view, '''(() => {
        const button = document.querySelector('[data-action="$command"]');
        const rect = button.getBoundingClientRect();
        return {x: rect.x + rect.width / 2, y: rect.y + rect.height / 2};
      })()''')
              as Map;
      final origin = tester.getTopLeft(find.byType(InAppWebView));
      await tester.tapAt(
        origin +
            Offset(
              (position['x'] as num).toDouble(),
              (position['y'] as num).toDouble(),
            ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    try {
      await tester.runAsync(EditorRuntime.prewarm);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              navigate = setState;
              // Match AppShell: notebook starts mounted behind the home page.
              return RepaintBoundary(
                key: captureKey,
                child: Scaffold(
                  body: IndexedStack(
                    index: section,
                    children: [
                      const Center(child: Text('首页')),
                      NotesPage(localDataState: state),
                      WorkPlansPage(localDataState: state),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await waitFor(() => views.length >= 2);
      navigate(() => section = 1);
      await tester.pump();
      final notebook = await viewWith('第一篇笔记');
      expectVisibleView(notebook);
      await capture('notebook-fixed');
      expect(
        await js(
          notebook,
          "document.querySelectorAll('#editor-toolbar button').length",
        ),
        8,
      );
      await clickCommand(notebook, 'source');
      expect(await js(notebook, 'editor.sourceView.inSourceMode'), isTrue);
      await js(
        notebook,
        "editor.sourceView.cm.setCursor({line:2,ch:2}); editor.sourceView.cm.replaceSelection('中文输入');",
      );
      await tester.runAsync(
        () => notebook.callAsyncJavaScript(
          functionBody: 'return await springNoteEditor.commit();',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(await first.readAsString(), '# 第一篇笔记\n\n正文中文输入');
      await clickCommand(notebook, 'undo');
      expect(
        await js(notebook, 'springNoteEditor.snapshot().text'),
        '# 第一篇笔记\n\n正文',
      );
      await clickCommand(notebook, 'redo');
      expect(
        await js(notebook, 'springNoteEditor.snapshot().text'),
        '# 第一篇笔记\n\n正文中文输入',
      );

      await tester.tap(find.text('第二篇笔记'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        await js(notebook, 'springNoteEditor.snapshot().text'),
        '# 第二篇笔记\n\n独立内容',
      );
      expectVisibleView(notebook);
      await clickCommand(notebook, 'undo');
      expect(
        await js(notebook, 'springNoteEditor.snapshot().text'),
        '# 第二篇笔记\n\n独立内容',
      );

      navigate(() => section = 2);
      await tester.pump();
      await waitFor(() => views.length >= 2);
      final planning = await viewWith('计划正文');
      expectVisibleView(planning);
      await clickCommand(planning, 'source');
      expect(await js(planning, 'editor.sourceView.inSourceMode'), isTrue);
      await js(
        planning,
        "editor.sourceView.cm.setCursor({line:2,ch:4}); editor.sourceView.cm.replaceSelection('已编辑');",
      );
      await tester.runAsync(
        () => planning.callAsyncJavaScript(
          functionBody: 'return await springNoteEditor.commit();',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(await plan.readAsString(), contains('计划正文已编辑'));
      await capture('plans-fixed');

      navigate(() => section = 1);
      await tester.pump();
      await tester.tap(find.text('第一篇笔记'));
      await tester.pump(const Duration(milliseconds: 600));
      expectVisibleView(notebook);
      expect(
        await js(notebook, 'springNoteEditor.snapshot().text'),
        '# 第一篇笔记\n\n正文中文输入',
      );
      expect(tester.takeException(), isNull);
    } finally {
      OpenTyporaEditor.debugOnReady = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await directory.delete(recursive: true);
    }
  });
}
