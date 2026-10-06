import 'package:flutter/material.dart';
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

  testWidgets(
    'opening and mode switches do not rewrite Markdown; heading edits replace only their range',
    (tester) async {
      const original =
          '# 标题\r\n\r\n**粗体** 与 [链接](https://example.com)\r\n\r\n```dart\r\nprint(1);\r\n```\r\n';
      final controller = TextEditingController(text: original);
      var saves = 0;
      await pumpEditor(tester, controller, (_) => saves++);
      expect(saves, 0);
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
