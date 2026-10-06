import 'dart:convert';
import 'dart:io';

import '../models/structured_work_note.dart';
import '../models/structured_note_section_config.dart';
import 'mock_ai_service.dart';

class HomeOverviewService {
  const HomeOverviewService();

  /// Derive the cards from the current diary, including edits and deletions.
  StructuredWorkNote fromDailyMarkdown(
    String markdown, {
    List<StructuredNoteSectionConfig> sectionConfigs =
        StructuredNoteSectionConfig.defaults,
  }) {
    final titles = <String, String>{
      for (final section in [
        ...StructuredNoteSectionConfig.defaults,
        ...StructuredNoteSectionConfig.defaultsFor('en'),
        ...sectionConfigs,
      ])
        section.title.toLowerCase(): section.id,
    };
    final items = <String, Set<String>>{
      for (final id in StructuredNoteSectionIds.values) id: <String>{},
    };
    final freeText = <String>[];
    final rawText = <String>[];
    String? sectionId;
    var sectionDepth = 0;
    var inRawInput = false;
    var hasSections = false;
    String? fence;
    for (final line in markdown.split('\n')) {
      var text = line.trim();
      final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(text);
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (fence == null) {
          fence = marker;
        } else if (marker[0] == fence[0] && marker.length >= fence.length) {
          fence = null;
        }
        continue;
      }
      if (fence != null) continue;
      final heading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$').firstMatch(text);
      if (heading != null) {
        final title = heading
            .group(2)!
            .replaceAll(RegExp(r'[*_`]+'), '')
            .replaceFirst(RegExp(r'[:：]$'), '')
            .trim()
            .toLowerCase();
        final depth = heading.group(1)!.length;
        final matchedId = titles[title];
        if (matchedId != null) {
          sectionId = matchedId;
          sectionDepth = depth;
          inRawInput = false;
          hasSections = true;
        } else if (title == '原始记录' || title == 'raw input') {
          sectionId = null;
          sectionDepth = depth;
          inRawInput = true;
        } else if (depth <= sectionDepth || sectionDepth == 0) {
          sectionId = null;
          inRawInput = false;
        }
        continue;
      }
      text = text
          .replaceFirst(RegExp(r'^(?:[-*+] |\d+[.)] )'), '')
          .replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '')
          .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
          .replaceAll(RegExp(r'[*`]+'), '')
          .trim();
      if (text.isEmpty ||
          RegExp(r'^[-=_]+$').hasMatch(text) ||
          const {
            '暂无',
            '无',
            'none',
            'n/a',
            '暂无。',
          }.contains(text.toLowerCase())) {
        continue;
      }
      if (sectionId != null) {
        items[sectionId]!.add(text);
      } else if (inRawInput) {
        rawText.add(text);
      } else {
        freeText.add(text);
      }
    }
    // Quick captures store raw input alongside the corresponding sections.
    if (!hasSections) freeText.addAll(rawText);
    final classified = const MockAiService().structureWorkNote(
      freeText.join('\n'),
      sectionConfigs: sectionConfigs,
    );
    return StructuredWorkNote(
      rawInput: markdown,
      sections: [
        for (final id in StructuredNoteSectionIds.values)
          StructuredWorkNoteSection(
            id: id,
            items: {...items[id]!, ...classified.itemsFor(id)}.toList(),
          ),
      ],
    );
  }

  Future<StructuredWorkNote> readOverview({
    required String appDataDir,
    required DateTime date,
  }) async {
    final file = File(overviewPath(appDataDir, date));
    if (!await file.exists()) {
      return _empty;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return _empty;
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return _empty;
    }

    final sections = decoded['schemaVersion'] == 2
        ? _readSections(decoded['sections'])
        : _readLegacySections(decoded);
    return StructuredWorkNote(
      rawInput: decoded['rawInput'] as String? ?? '',
      sections: sections,
    );
  }

  Future<StructuredWorkNote> mergeAndSaveOverview({
    required String appDataDir,
    required DateTime date,
    required StructuredWorkNote current,
    required StructuredWorkNote incoming,
  }) async {
    final merged = incoming.mergeWithOlder(current);
    await writeOverview(appDataDir: appDataDir, date: date, overview: merged);
    return merged;
  }

  Future<void> writeOverview({
    required String appDataDir,
    required DateTime date,
    required StructuredWorkNote overview,
  }) async {
    final file = File(overviewPath(appDataDir, date));
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert({
        'date': _formatDate(date),
        'updatedAt': DateTime.now().toIso8601String(),
        'schemaVersion': 2,
        'rawInput': overview.rawInput,
        'sections': [
          for (final id in StructuredNoteSectionIds.values) {'id': id, 'items': overview.itemsFor(id)},
        ],
      })}\n',
    );
  }

  String overviewPath(String appDataDir, DateTime date) {
    final separator = Platform.pathSeparator;
    final root = appDataDir.endsWith(separator)
        ? appDataDir.substring(0, appDataDir.length - 1)
        : appDataDir;
    return [
      root,
      'overview',
      'daily',
      '${_formatDate(date)}.json',
    ].join(separator);
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<StructuredWorkNoteSection> _readSections(Object? value) {
    final itemsById = <String, List<String>>{};
    if (value is List) {
      for (final section in value.whereType<Map>()) {
        final id = section['id'];
        if (id is String && StructuredNoteSectionIds.values.contains(id)) {
          itemsById[id] = _readStringList(section['items']);
        }
      }
    }
    return [
      for (final id in StructuredNoteSectionIds.values)
        StructuredWorkNoteSection(id: id, items: itemsById[id] ?? const []),
    ];
  }

  List<StructuredWorkNoteSection> _readLegacySections(Map decoded) {
    return [
      StructuredWorkNoteSection(
        id: StructuredNoteSectionIds.a,
        items: _readStringList(decoded['completed']),
      ),
      StructuredWorkNoteSection(
        id: StructuredNoteSectionIds.b,
        items: _readStringList(decoded['issues']),
      ),
      StructuredWorkNoteSection(
        id: StructuredNoteSectionIds.c,
        items: _readStringList(decoded['plans']),
      ),
    ];
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static const _empty = StructuredWorkNote.empty;
}
