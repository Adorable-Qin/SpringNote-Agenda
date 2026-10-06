import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/core/services/project_deadline_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/weekly_report_picker.dart';
import 'package:spring_note/features/plans/work_plans_page.dart';

LocalDataState stateFor(String root) => LocalDataState(
  dataDirectory: root,
  configPath: p.join(root, 'config.json'),
  dailyNotesDirectory: p.join(root, 'notes', 'daily'),
  weeklyNotesDirectory: p.join(root, 'notes', 'weekly'),
  monthlyNotesDirectory: p.join(root, 'notes', 'monthly'),
  config: AppConfig.defaults(),
);

void main() {
  test(
    'work cycle defaults and survives config round trip and unrelated changes',
    () {
      expect(AppConfig.fromJson({}).workReportCycle, WorkReportCycle.weekly);
      expect(
        AppConfig.fromJson({'workReportCycle': 'unknown'}).workReportCycle,
        WorkReportCycle.weekly,
      );
      final config = AppConfig.defaults().copyWith(
        workReportCycle: WorkReportCycle.biweekly,
      );
      expect(
        AppConfig.fromJson(
          config.toJson(),
        ).copyWith(fontScale: 110).workReportCycle,
        WorkReportCycle.biweekly,
      );
    },
  );

  test(
    'merge preserves both reports across year boundary and existing edited output',
    () async {
      final temp = await Directory.systemTemp.createTemp('spring_note_merge_');
      addTearDown(() => temp.delete(recursive: true));
      final state = stateFor(temp.path);
      const service = NoteService();
      final sources = <NoteFile>[];
      for (final date in [DateTime(2025, 12, 22), DateTime(2025, 12, 29)]) {
        final note = await service.ensureCurrentMarkdownFile(
          directoryPath: state.weeklyNotesDirectory,
          kind: NoteKind.weekly,
          now: date,
        );
        await service.writeMarkdown(
          note.path,
          '# ${note.title}\n\n## Progress\n- ${date.day} complete\n\n```python\n# keep this comment\n```',
        );
        sources.add(note);
      }
      final result = await service.mergeWeeklyReports(
        directoryPath: state.directoryFor(NoteKind.biweekly),
        sources: sources.reversed.toList(),
      );
      expect(result.name, '2025-W52_2026-W01.md');
      final content = await service.readMarkdown(result.path);
      expect(content, contains('22 complete'));
      expect(content, contains('29 complete'));
      expect(content, contains('### Progress'));
      expect(content, contains('```python\n# keep this comment\n```'));
      expect(
        await service.readMarkdown(sources.first.path),
        contains('## Progress'),
      );
      await service.writeMarkdown(result.path, '# Edited report');
      final repeated = await service.mergeWeeklyReports(
        directoryPath: state.directoryFor(NoteKind.biweekly),
        sources: sources,
      );
      expect(await service.readMarkdown(repeated.path), '# Edited report');
      await expectLater(
        service.mergeWeeklyReports(
          directoryPath: state.directoryFor(NoteKind.biweekly),
          sources: [sources.first, sources.first],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'deletion waits for queued saves and does not recreate an empty notebook',
    () async {
      final temp = await Directory.systemTemp.createTemp('spring_note_delete_');
      addTearDown(() => temp.delete(recursive: true));
      final state = stateFor(temp.path);
      const service = NoteService();
      final note = await service.ensureCurrentMarkdownFile(
        directoryPath: state.dailyNotesDirectory,
        kind: NoteKind.daily,
        now: DateTime(2026, 10, 6),
      );
      final saving = service.writeMarkdown(note.path, '# Latest edit');
      final deleting = service.deleteMarkdown(note);
      await Future.wait([saving, deleting]);
      expect(await File(note.path).exists(), isFalse);
      expect(
        await service.listMarkdownFiles(
          directoryPath: state.dailyNotesDirectory,
          kind: NoteKind.daily,
        ),
        isEmpty,
      );
    },
  );

  test(
    'weekly and monthly plans enter calendar and edits and completion persist',
    () async {
      final temp = await Directory.systemTemp.createTemp('spring_note_plans_');
      addTearDown(() => temp.delete(recursive: true));
      final state = stateFor(temp.path);
      const service = NoteService();
      const calendar = ProjectDeadlineService();
      final weekly = await service.ensureCurrentMarkdownFile(
        directoryPath: state.directoryFor(NoteKind.weeklyPlan),
        kind: NoteKind.weeklyPlan,
        now: DateTime(2026, 10, 6),
      );
      final monthly = await service.ensureCurrentMarkdownFile(
        directoryPath: state.directoryFor(NoteKind.monthlyPlan),
        kind: NoteKind.monthlyPlan,
        now: DateTime(2026, 10, 6),
      );
      await service.writeMarkdown(
        weekly.path,
        '# Week\n- [ ] 10月9日完成方案\n- Due: 2026-10-10 Review\n- 2026-02-30 invalid',
      );
      await service.writeMarkdown(
        monthly.path,
        '# 2026-10\n## 本月度工作总结\n总结\n## 下月度工作计划\n- 截止：2026-11-05 交付',
      );
      var deadlines = await calendar.listDeadlines(state);
      expect(deadlines, hasLength(3));
      expect(deadlines.first.dueDate, DateTime(2026, 10, 9));
      await calendar.setCompleted(deadlines.first, completed: true);
      deadlines = await calendar.listDeadlines(state);
      expect(deadlines.first.isCompleted, isTrue);
      final completedContent = await service.readMarkdown(weekly.path);
      await service.writeMarkdown(
        weekly.path,
        completedContent.replaceAll('10月9日', '10月12日'),
      );
      deadlines = await calendar.listDeadlines(state);
      expect(deadlines.any((d) => d.dueDate == DateTime(2026, 10, 9)), isFalse);
      expect(
        deadlines.any(
          (d) => d.dueDate == DateTime(2026, 10, 12) && d.isCompleted,
        ),
        isTrue,
      );
    },
  );

  test(
    'startup generation respects deleted reports until explicitly recreated',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_deleted_report_',
      );
      addTearDown(() => temp.delete(recursive: true));
      const service = NoteService();
      final directory = stateFor(temp.path).weeklyNotesDirectory;
      final note = await service.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: NoteKind.weekly,
        now: DateTime(2026, 9, 1),
      );
      await service.deleteMarkdown(note);
      expect(
        await service.writeGeneratedReport(note.path, '# Generated\n\nBody'),
        isFalse,
      );
      expect(await File(note.path).exists(), isFalse);
      await service.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: NoteKind.weekly,
        now: DateTime(2026, 9, 1),
      );
      expect(await File('${note.path}.deleted').exists(), isFalse);
      await service.writeMarkdown(note.path, '# Edited\n\nKeep my edit');
      expect(
        await service.writeGeneratedReport(note.path, '# Generated\n\nBody'),
        isFalse,
      );
      expect(await service.readMarkdown(note.path), contains('Keep my edit'));
    },
  );

  testWidgets('weekly picker requires exactly two reports', (tester) async {
    final notes = List.generate(
      3,
      (index) => NoteFile(
        path: '/weekly/$index.md',
        name: '$index.md',
        title: 'Week $index',
        modifiedAt: DateTime(2026),
        kind: NoteKind.weekly,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeeklyReportPicker(notes: notes, english: true)),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Week 0'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Week 1'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Week 2'),
          )
          .onChanged,
      isNull,
    );
  });

  testWidgets('plans show archived months beside an editable weekly board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _PlanMemoryService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkPlansPage(
          localDataState: stateFor('/plans'),
          noteService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('月度计划'), findsOneWidget);
    expect(find.text('周计划板'), findsOneWidget);
    expect(find.text('2026-10'), findsOneWidget);
    expect(find.text('2026-09'), findsOneWidget);
    final weeklyEditor = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller!.text.contains('Weekly task'),
    );
    await tester.enterText(weeklyEditor, '# Week\n- 2026-10-12 Edited task');
    await tester.pumpAndSettle();
    expect(service.saved, contains('Edited task'));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(700, 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _PlanMemoryService extends NoteService {
  String saved = '';
  @override
  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  }) async => [
    for (final name
        in kind == NoteKind.monthlyPlan ? ['2026-10', '2026-09'] : ['2026-W41'])
      NoteFile(
        path: '$directoryPath/$name.md',
        name: '$name.md',
        title: name,
        modifiedAt: DateTime(2026),
        kind: kind,
      ),
  ];
  @override
  Future<String> readMarkdown(String path) async => path.contains('weekly_plan')
      ? '# Week\nWeekly task'
      : '# Month\n## 本月度工作总结\nSummary\n## 下月度工作计划\nPlan';
  @override
  Future<void> writeMarkdown(String path, String content) async {
    saved = content;
  }
}
