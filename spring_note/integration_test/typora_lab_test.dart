import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_note/core/editor/open_typora_editor.dart';
import 'package:spring_note/features/plans/plan_markdown_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Typora 1.7.6 native host editing, saves, history and external update',
    (tester) async {
      expect(Platform.environment['SPRINGNOTE_TYPORA_LAB_DIR'], isNotEmpty);
      final ready = Completer<InAppWebViewController>();
      OpenTyporaEditor.debugOnReady = (view) {
        if (!ready.isCompleted) ready.complete(view);
      };
      final directory = await Directory.systemTemp.createTemp('typora_lab_');
      final controller = TextEditingController(text: '# Native test\n\n正文');
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanMarkdownEditor(
              controller: controller,
              onChanged: saved.add,
              imageBasePath: directory.path,
              expand: true,
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 300 && !ready.isCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        ready.isCompleted,
        isTrue,
        reason: 'Original renderer did not mount',
      );
      final web = await ready.future;
      await tester.runAsync(() async {
        Future<dynamic> js(String source) =>
            web.evaluateJavascript(source: source);
        Future<void> settle() =>
            Future<void>.delayed(const Duration(milliseconds: 400));
        expect(await js('document.title'), 'SpringNote');
        expect(await js('springNoteEditor.snapshot().text'), controller.text);
        await js(
          "editor.sourceView.gotoLine({line:2,ch:2,lineText:'正文',textBefore:'正文'}); editor.writingArea.focus(); document.execCommand('insertText',false,'中文 ABC');",
        );
        await settle();
        expect(controller.text.trim(), '# Native test\n\n正文中文 ABC');
        expect(saved.last, controller.text);
        await js("springNoteEditor.command('undo')");
        await settle();
        expect(controller.text.trim(), '# Native test\n\n正文');
        await js("springNoteEditor.command('redo')");
        await settle();
        expect(controller.text.trim(), '# Native test\n\n正文中文 ABC');
        controller.value = const TextEditingValue(
          text: '外部更新',
          selection: TextSelection.collapsed(offset: 2),
        );
        await settle();
        await js("document.execCommand('insertText',false,'插入')");
        await settle();
        expect(controller.text.trim(), '外部插入更新');
        await js("springNoteEditor.command('source')");
        await settle();
        expect(await js('editor.sourceView.inSourceMode'), true);
        await js("editor.sourceView.cm.replaceSelection('源码')");
        await settle();
        expect(controller.text, contains('源码'));
        await File('${directory.path}/image.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=',
          ),
        );
        controller.value = const TextEditingValue(
          text: '![图片](image.png)\n\n正文',
          selection: TextSelection.collapsed(offset: 0),
        );
        await settle();
        await js("springNoteEditor.command('source')");
        await settle();
        expect(
          await js("document.querySelector('#write img').naturalWidth"),
          1,
        );
        final image = await web.takeScreenshot();
        if (image != null) {
          final capture = File('../.toolchains/typora-lab/native.png');
          await capture.parent.create(recursive: true);
          await capture.writeAsBytes(image);
        }
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      OpenTyporaEditor.debugOnReady = null;
      controller.dispose();
      await directory.delete(recursive: true);
    },
  );
}
