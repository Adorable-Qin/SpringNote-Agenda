import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/editor/open_typora_editor.dart';
import 'package:spring_note/features/plans/plan_markdown_document.dart';
import 'package:spring_note/features/plans/monthly_plan_editor.dart';
import 'helpers/open_typora_surface.dart';

void main() {
  setUp(() {
    OpenTyporaEditor.debugSurfaceBuilder = (_, session) =>
        TestEditorSurface(session: session);
  });
  tearDown(() {
    OpenTyporaEditor.debugSurfaceBuilder = null;
  });
  testWidgets(
    'monthly sections preserve headings and sibling content through browser saves',
    (tester) async {
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
      final summary = find.descendant(
        of: find.byKey(const ValueKey('monthly-summary')),
        matching: find.byType(TestEditorSurface),
      );
      final session = tester.widget<TestEditorSurface>(summary).session;
      expect(session.controller.text, '\n\n完成方案\n\n');
      sendEditorChange(session, '完成修订');
      await tester.pump();
      expect(saved, contains('## 本月度工作总结\n\n完成修订\n\n## 下月度工作计划'));
      expect(saved, contains('- [ ] 截止：2026-11-05 交付'));
      expect(tester.widget<TestEditorSurface>(summary).session, same(session));
      session.controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      final selectedValue = session.controller.value;
      final revision = session.revision;
      controller.text = controller.text.replaceFirst('- [ ]', '- [x]');
      await tester.pump();
      expect(session.controller.value, selectedValue);
      expect(session.revision, revision);
      expect(tester.widget<TestEditorSurface>(summary).session, same(session));
      controller.text = '# 2026-10\n\n旧版自由正文';
      await tester.pump();
      expect(
        tester.widget<TestEditorSurface>(summary).session.controller.text,
        '旧版自由正文',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  test(
    'plan section parser preserves CRLF, blank lines, tables and fenced source',
    () {
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
    },
  );
}
