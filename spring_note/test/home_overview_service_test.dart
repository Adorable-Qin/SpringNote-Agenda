import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/models/structured_note_section_config.dart';
import 'package:spring_note/core/services/home_overview_service.dart';

void main() {
  test('diary sections exclude raw copies, placeholders and fenced code', () {
    const service = HomeOverviewService();
    final note = service.fromDailyMarkdown('''
# 2026-10-06 日报
## 10:00 随手记录
### 原始记录
修好了首页，明天上线
### 完成事项
- [x] **修好了首页**
- 修好了首页
### 问题记录
- 暂无
### 明日计划
1. 上线
```dart
## 完成事项
not a task
```
''');
    expect(note.itemsFor(StructuredNoteSectionIds.a), ['修好了首页']);
    expect(note.itemsFor(StructuredNoteSectionIds.b), isEmpty);
    expect(note.itemsFor(StructuredNoteSectionIds.c), ['上线']);
    final edited = service.fromDailyMarkdown('## 完成事项\n- 新事项');
    expect(edited.itemsFor(StructuredNoteSectionIds.a), ['新事项']);
    expect(service.fromDailyMarkdown('').isEmpty, isTrue);
    expect(service.fromDailyMarkdown('# 日报\n## 完成事项\n- 暂无').isEmpty, isTrue);
  });

  test('diary supports custom headings and classifies free text', () {
    const service = HomeOverviewService();
    final note = service.fromDailyMarkdown(
      '已完成开发\n问题：连接失败\n明天测试\n## 今日进展\n- 合并代码',
      sectionConfigs: [
        StructuredNoteSectionConfig.defaults[0].copyWith(title: '今日进展'),
        ...StructuredNoteSectionConfig.defaults.skip(1),
      ],
    );
    expect(note.itemsFor(StructuredNoteSectionIds.a), ['合并代码', '已完成开发']);
    expect(note.itemsFor(StructuredNoteSectionIds.b), ['问题：连接失败']);
    expect(note.itemsFor(StructuredNoteSectionIds.c), ['明天测试']);
    final english = service.fromDailyMarkdown(
      '## Done\n- Shipped\n## Issues\n- None\n## Next plans\n- Test',
    );
    expect(english.itemsFor(StructuredNoteSectionIds.a), ['Shipped']);
    expect(english.itemsFor(StructuredNoteSectionIds.b), isEmpty);
    expect(english.itemsFor(StructuredNoteSectionIds.c), ['Test']);
  });

  test('home overview service persists daily overview json', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_overview_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = HomeOverviewService();
    final date = DateTime(2026, 6, 18, 10, 30);
    final overview = await service.mergeAndSaveOverview(
      appDataDir: temp.path,
      date: date,
      current: const StructuredWorkNote(
        rawInput: 'old',
        sections: [
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.a,
            items: ['旧完成'],
          ),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.b, items: []),
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.c,
            items: ['旧计划'],
          ),
        ],
      ),
      incoming: const StructuredWorkNote(
        rawInput: 'new',
        sections: [
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.a,
            items: ['新完成'],
          ),
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.b,
            items: ['新问题'],
          ),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.c, items: []),
        ],
      ),
    );

    expect(overview.itemsFor(StructuredNoteSectionIds.a), ['新完成', '旧完成']);
    expect(overview.itemsFor(StructuredNoteSectionIds.b), ['新问题']);
    expect(overview.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);

    final path = service.overviewPath(temp.path, date);
    expect(path, endsWith('${Platform.pathSeparator}2026-06-18.json'));
    expect(await File(path).exists(), isTrue);
    final savedJson = jsonDecode(await File(path).readAsString()) as Map;
    expect(savedJson['schemaVersion'], 2);
    expect(savedJson['completed'], isNull);
    expect(savedJson['issues'], isNull);
    expect(savedJson['plans'], isNull);
    expect(savedJson['sections'], hasLength(3));

    final reloaded = await service.readOverview(
      appDataDir: temp.path,
      date: date,
    );
    expect(reloaded.rawInput, 'new');
    expect(reloaded.itemsFor(StructuredNoteSectionIds.a), ['新完成', '旧完成']);
    expect(reloaded.itemsFor(StructuredNoteSectionIds.b), ['新问题']);
    expect(reloaded.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);
  });

  test('home overview service reads legacy daily overview json', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_legacy_overview_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = HomeOverviewService();
    final date = DateTime(2026, 6, 19);
    final file = File(service.overviewPath(temp.path, date));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'date': '2026-06-19',
        'rawInput': 'legacy',
        'completed': ['旧完成'],
        'issues': ['旧问题'],
        'plans': ['旧计划'],
      }),
    );

    final overview = await service.readOverview(
      appDataDir: temp.path,
      date: date,
    );
    expect(overview.rawInput, 'legacy');
    expect(overview.itemsFor(StructuredNoteSectionIds.a), ['旧完成']);
    expect(overview.itemsFor(StructuredNoteSectionIds.b), ['旧问题']);
    expect(overview.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);
  });
}
