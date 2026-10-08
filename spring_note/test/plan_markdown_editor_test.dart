import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/plans/plan_markdown_document.dart';
import 'package:spring_note/features/plans/plan_markdown_editor.dart';
import 'package:spring_note/features/plans/monthly_plan_editor.dart';

void main() {
  testWidgets('monthly titles stay outside both editable section bodies', (
    tester,
  ) async {
    const original =
        '# 2026-10\n\n## 本月度工作总结\n\n完成方案\n\n## 下月度工作计划\n\n- [ ] 截止：2026-11-05 交付\n';
    final controller = TextEditingController(text: original);
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthlyPlanEditor(
              controller: controller,
              onChanged: (value) => saved = value,
              imageBasePath: '.',
              english: false,
            ),
          ),
        ),
      ),
    );
    expect(saved, isNull);
    expect(controller.text, original);
    expect(find.text('本月度工作总结'), findsOneWidget);
    expect(find.text('下月度工作计划'), findsOneWidget);
    final summary = find.byKey(const ValueKey('monthly-summary'));
    final toolbar = find.byKey(const ValueKey('plan-editor-toolbar'));
    expect(toolbar, findsNothing);
    await tester.tap(find.text('完成方案', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.descendant(of: summary, matching: toolbar), findsOneWidget);
    await tester.tap(find.byTooltip('加粗'));
    await tester.pumpAndSettle();
    expect(toolbar, findsOneWidget);
    // Restore before checking exact preservation of existing section content.
    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: summary,
        matching: find.byKey(const ValueKey('plan-editor-mode')),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: summary,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, '\n\n完成方案\n\n');
    await tester.enterText(field, '完成修订');
    await tester.pump();
    expect(saved, contains('## 本月度工作总结\n\n完成修订\n\n## 下月度工作计划'));
    expect(saved, contains('- [ ] 截止：2026-11-05 交付'));
    final planBody = find.text('截止：2026-11-05 交付', findRichText: true);
    await tester.ensureVisible(planBody);
    await tester.tap(planBody);
    await tester.pumpAndSettle();
    expect(toolbar, findsOneWidget);
    expect(find.descendant(of: summary, matching: toolbar), findsNothing);
    expect(find.byKey(const ValueKey('plan-source-editor')), findsNothing);
    await tester.ensureVisible(find.text('完成修订', findRichText: true));
    await tester.tap(find.text('完成修订', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-editor-mode')));
    await tester.pumpAndSettle();
    controller.text = '# 2026-10\n\n旧版自由正文';
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '旧版自由正文');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  test('block ranges preserve CRLF, blank lines, tables and fenced source', () {
    const source =
        '# 标题\r\n\r\n\r\n- [ ] 截止：2026-10-14 交付\r\n\r\n```dart\r\n# not a heading\r\n\r\n```\r\n\r\n| A | B |\r\n|---|---|\r\n| 1 | 2 |\r\n';
    final blocks = parsePlanMarkdown(source);
    expect(blocks, hasLength(4));
    for (final block in blocks) {
      expect(source.substring(block.start, block.end), block.source);
    }
    expect(blocks[1].isTask, isTrue);
    expect(blocks[2].source, contains('# not a heading\r\n\r\n```'));
    expect(blocks[3].source, contains('| 1 | 2 |'));
  });

  Future<void> pumpEditor(
    WidgetTester tester,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 650,
              child: PlanMarkdownEditor(
                controller: controller,
                onChanged: onChanged,
                imageBasePath: '.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reading text can be drag-selected and copied without entering edit mode',
    (tester) async {
      final controller = TextEditingController(text: 'Alpha beta gamma delta');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var saves = 0;
      await pumpEditor(tester, controller, (_) => saves++);
      final rect = tester.getRect(
        find.text('Alpha beta gamma delta', findRichText: true),
      );
      final gesture = await tester.startGesture(
        Offset(rect.left + 1, rect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset(rect.left + 160, rect.center.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-active-block')), findsNothing);
      expect(find.byKey(const ValueKey('plan-editor-toolbar')), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, isNotNull);
      expect(copied, contains('Alpha'));
      expect(saves, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'active toolbar stays at viewport top while scrolling and remains usable',
    (tester) async {
      final controller = TextEditingController(
        text: List.generate(40, (i) => 'Paragraph $i').join('\n\n'),
      );
      await pumpEditor(tester, controller, (_) {});
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(350);
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('plan-editor-toolbar'));
      expect(toolbar, findsOneWidget);
      expect(tester.getTopLeft(toolbar).dy, closeTo(0, 1));
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      expect(controller.text, startsWith('Paragraph 0****'));
      expect(find.byKey(const ValueKey('plan-active-block')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(toolbar, findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'Enter keeps the input connection for consecutive paragraphs without tapping',
    (tester) async {
      final controller = TextEditingController(text: '第一段');
      await pumpEditor(tester, controller, (_) {});
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('plan-active-block'));
      final editable = tester.state(find.byType(EditableText));
      for (final text in ['第一段\n', '第二段', '第二段\n', '第三段']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        expect(tester.state(find.byType(EditableText)), same(editable));
      }
      expect(controller.text, '第一段\n\n第二段\n\n第三段');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final list in [false, true]) {
    testWidgets('left and right cross block edges immediately (list: $list)', (
      tester,
    ) async {
      final source = list ? '- [ ] abc\n- [ ] def' : 'abc\n\ndef';
      final controller = TextEditingController(text: source);
      var saves = 0;
      await pumpEditor(tester, controller, (_) => saves++);
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('plan-active-block'));
      final input = tester.widget<TextField>(field).controller!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(input.text, 'def');
      expect(input.selection.baseOffset, 0);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(input.text, 'abc');
      expect(input.selection.baseOffset, 3);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(input.text, 'abc');
      expect(input.selection.baseOffset, 2);
      input.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(input.text, 'abc');
      expect(input.selection.baseOffset, 0);
      expect(controller.text, source);
      expect(saves, 0);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    testWidgets(
      'arrow keys navigate adjacent blocks without editing source (list: $list)',
      (tester) async {
        final source = list
            ? '- [ ] abcdef\n- [ ] ghijkl\n- [ ] mnopqr'
            : 'abcdef\n\nghijkl\n\nmnopqr';
        final controller = TextEditingController(text: source);
        var saves = 0;
        await pumpEditor(tester, controller, (_) => saves++);
        await tester.tap(find.byKey(const ValueKey('plan-block-0')));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('plan-active-block'));
        final input = tester.widget<TextField>(field).controller!;
        input.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();
        for (final expected in ['ghijkl', 'mnopqr']) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          // Selection must already be correct before the next frame paints.
          expect(input.text, expected);
          expect(input.selection.baseOffset, 2);
          await tester.pumpAndSettle();
          expect(input.text, expected);
          expect(input.selection.baseOffset, 2);
          expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(input.text, 'ghijkl');
        expect(input.selection.baseOffset, 2);
        expect(controller.text, source);
        expect(saves, 0);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
    testWidgets(
      'Backspace removes an emptied block and resumes previous input (list: $list)',
      (tester) async {
        final source = list
            ? '- [ ] 第一项\r\n- [ ] 第二项\r\n- [ ] 第三项'
            : '第一段\n\n第二段';
        final controller = TextEditingController(text: source);
        await pumpEditor(tester, controller, (_) {});
        final start = source.indexOf(list ? '- [ ] 第二项' : '第二段');
        await tester.tap(find.byKey(ValueKey('plan-block-$start')));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('plan-active-block'));
        final editable = tester.state(find.byType(EditableText));
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          ),
        );
        await tester.pumpAndSettle();
        final emptied = controller.text;
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(controller.text, list ? '- [ ] 第一项\r\n- [ ] 第三项' : '第一段');
        final input = tester.widget<TextField>(field);
        expect(input.controller!.text, list ? '第一项' : '第一段');
        expect(input.controller!.selection.baseOffset, 3);
        expect(input.focusNode!.hasFocus, isTrue);
        expect(tester.state(find.byType(EditableText)), same(editable));
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: list ? '第一项继续' : '第一段继续',
            selection: const TextSelection.collapsed(offset: 5),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.text, contains('继续'));
        await tester.tap(find.byTooltip('撤销'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('撤销'));
        await tester.pumpAndSettle();
        expect(controller.text, emptied);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets('Down stays within wrapped text until its last visual line', (
    tester,
  ) async {
    final longText = List.filled(35, 'word').join(' ');
    final controller = TextEditingController(
      text: '$longText\n\nNext paragraph',
    );
    await pumpEditor(tester, controller, (_) {});
    await tester.tap(find.byKey(const ValueKey('plan-block-0')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('plan-active-block'));
    final input = tester.widget<TextField>(field).controller!;
    input.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(input.text, longText);
    expect(input.selection.baseOffset, greaterThan(2));
    input.selection = TextSelection.collapsed(offset: longText.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(input.text, 'Next paragraph');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'opening and mode switches do not rewrite Markdown; heading edits replace only their range',
    (tester) async {
      const original =
          '# 标题\r\n\r\n**粗体** 与 [链接](https://example.com)\r\n\r\n```dart\r\nprint(1);\r\n```\r\n';
      final controller = TextEditingController(text: original);
      var saves = 0;
      await pumpEditor(tester, controller, (_) => saves++);
      expect(saves, 0);
      expect(find.byKey(const ValueKey('plan-editor-toolbar')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-editor-mode')));
      await tester.pumpAndSettle();
      expect(controller.text, original);
      await tester.tap(find.byKey(const ValueKey('plan-editor-mode')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('plan-active-block'));
      expect(tester.widget<TextField>(field).controller!.text, '标题');
      await tester.enterText(field, '修改后的标题');
      await tester.pump();
      expect(controller.text, original.replaceFirst('标题', '修改后的标题'));
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(controller.text, original);
      await tester.tap(find.byTooltip('重做'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('# 修改后的标题'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('task checkboxes and source edits save to the same Markdown', (
    tester,
  ) async {
    final controller = TextEditingController(text: '- [ ] 截止：2026-10-14 交付\n');
    String? saved;
    await pumpEditor(tester, controller, (value) => saved = value);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(saved, '- [x] 截止：2026-10-14 交付\n');
    await tester.tap(find.text('截止：2026-10-14 交付', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-editor-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-source-editor')),
      '## 新计划\n\n保留原始格式',
    );
    await tester.pump();
    expect(saved, '## 新计划\n\n保留原始格式');
    await tester.tap(find.byKey(const ValueKey('plan-editor-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-block-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('plan-active-block')))
          .controller!
          .text,
      '新计划',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'typed Markdown turns into a task and Enter continues and exits the list',
    (tester) async {
      final controller = TextEditingController();
      await pumpEditor(tester, controller, (_) {});
      await tester.tap(find.byKey(const ValueKey('plan-add-paragraph')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('plan-active-block'));
      final inputState = tester.state(find.byType(EditableText));
      Future<void> type(String text) async {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.hasAnyClients, isTrue);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(tester.state(find.byType(EditableText)), same(inputState));
      }

      await type('- [ ] 第一项');
      expect(tester.widget<TextField>(field).controller!.text, '第一项');
      await type('第一项\n');
      expect(controller.text, '- [ ] 第一项\n- [ ] ');
      await type('\n');
      expect(controller.text, '- [ ] 第一项\n');
      await type('继续正文');
      expect(controller.text, '- [ ] 第一项\n继续正文');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'Chinese composing range survives live edits and external reload is shown',
    (tester) async {
      final controller = TextEditingController(text: '## 标题');
      await pumpEditor(tester, controller, (_) {});
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      const composing = TextEditingValue(
        text: '标题zhong',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 2, end: 7),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('plan-active-block')),
      );
      expect(field.controller!.value.composing, composing.composing);
      expect(controller.text, '## 标题zhong');
      controller.text = '# 从日历刷新';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-active-block')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plan-block-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('plan-active-block')))
            .controller!
            .text,
        '从日历刷新',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
