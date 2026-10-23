import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_note/core/editor/open_typora_editor.dart';
import 'package:spring_note/core/editor/editor_runtime.dart';
import 'package:spring_note/features/plans/plan_markdown_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native startup and consecutive document switches', (
    tester,
  ) async {
    final timings = <int>[];
    final controllers = <TextEditingController>[];
    InAppWebViewController? firstView;
    final directory = await Directory.systemTemp.createTemp('editor_startup_');
    try {
      final prewarm = Stopwatch()..start();
      await tester.runAsync(EditorRuntime.prewarm);
      debugPrint('EDITOR_BACKGROUND_PREWARM_MS ${prewarm.elapsedMilliseconds}');
      for (var index = 0; index < 6; index++) {
        final ready = Completer<InAppWebViewController>();
        OpenTyporaEditor.debugOnReady = (view) {
          if (!ready.isCompleted) ready.complete(view);
        };
        final controller = index < 4
            ? TextEditingController()
            : controllers.last;
        controller.text = '# 文档 $index\n\n中文输入与光标位置。';
        if (index < 4) controllers.add(controller);
        final watch = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlanMarkdownEditor(
                controller: controller,
                documentId: index,
                onChanged: (_) {},
                imageBasePath: directory.path,
                expand: true,
              ),
            ),
          ),
        );
        for (var frame = 0; frame < 300 && !ready.isCompleted; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          ready.isCompleted,
          isTrue,
          reason: 'Document $index did not become editable',
        );
        timings.add(watch.elapsedMilliseconds);
        debugPrint('EDITOR_DOCUMENT_${index}_MS ${timings.last}');
        final web = await ready.future;
        expect(
          web.getViewId(),
          tester.widget<Texture>(find.byType(Texture)).textureId,
          reason:
              'Startup must prepare the visible editor, not a hidden browser',
        );
        if (firstView == null) {
          firstView = web;
        } else {
          expect(web, same(firstView));
        }
        await tester.runAsync(() async {
          expect(
            await web.evaluateJavascript(
              source: 'springNoteEditor.snapshot().text',
            ),
            controller.text,
          );
          await web.evaluateJavascript(
            source: "springNoteEditor.command('undo')",
          );
          expect(
            await web.evaluateJavascript(
              source: 'springNoteEditor.snapshot().text',
            ),
            controller.text,
          );
          await web.evaluateJavascript(
            source: "springNoteEditor.command('source')",
          );
        });
      }
      debugPrint('EDITOR_STARTUP_MS ${jsonEncode(timings)}');
      await tester.runAsync(() async {
        final output = File(
          '../.toolchains/typora-release/startup-latest.json',
        );
        await output.parent.create(recursive: true);
        await output.writeAsString(jsonEncode({'milliseconds': timings}));
      });
    } finally {
      OpenTyporaEditor.debugOnReady = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      for (final controller in controllers) {
        controller.dispose();
      }
      await directory.delete(recursive: true);
    }
  });
}
