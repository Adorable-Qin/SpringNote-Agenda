import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/plans/plan_markdown_document.dart';
import 'package:spring_note/features/plans/plan_markdown_editor.dart';

void main() {
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
      await tester.enterText(field, '- [ ] 第一项');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '第一项');
      await tester.enterText(field, '第一项\n');
      await tester.pump();
      expect(controller.text, '- [ ] 第一项\n- [ ] ');
      await tester.enterText(field, '\n');
      await tester.pump();
      expect(controller.text, '- [ ] 第一项\n');
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
