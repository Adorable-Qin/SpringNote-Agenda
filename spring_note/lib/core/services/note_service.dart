import 'dart:io';

import '../models/note_file.dart';
import 'note_storage_coordinator.dart';

class NoteService {
  const NoteService();

  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.md'),
        )
        .cast<File>()
        .toList();

    final noteFiles = <NoteFile>[];
    for (final file in files) {
      final stat = await file.stat();
      final content = await readMarkdown(file.path);
      final name = _fileName(file.path);
      noteFiles.add(
        NoteFile(
          path: file.path,
          name: name,
          title: _titleFromContent(content, name),
          modifiedAt: stat.modified,
          kind: kind,
          preview: _previewFromContent(content),
          searchText: _searchTextFromContent(content),
        ),
      );
    }

    noteFiles.sort((a, b) => b.name.compareTo(a.name));
    return noteFiles;
  }

  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  }) async {
    final date = now ?? DateTime.now();
    final name = switch (kind) {
      NoteKind.daily => _formatDate(date),
      NoteKind.weekly || NoteKind.weeklyPlan => _formatIsoWeek(date),
      NoteKind.biweekly => throw ArgumentError('Select two weekly reports'),
      NoteKind.monthly || NoteKind.monthlyPlan =>
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}',
    };
    final path = _join(directoryPath, '$name.md');
    final title = '$name ${kind.suffix}';

    await ensureMarkdownFile(path, defaultContent: '# $title\n\n');
    final stat = await File(path).stat();
    final content = await readMarkdown(path);

    return NoteFile(
      path: path,
      name: '$name.md',
      title: _titleFromContent(content, '$name.md'),
      modifiedAt: stat.modified,
      kind: kind,
      preview: _previewFromContent(content),
      searchText: _searchTextFromContent(content),
    );
  }

  Future<String> readMarkdown(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> deleteMarkdown(NoteFile note) async {
    await NoteStorageCoordinator.runForManagedNotePath(note.path, () async {
      final file = File(note.path);
      if (await file.exists()) {
        if (note.kind == NoteKind.weekly || note.kind == NoteKind.monthly) {
          await File('${note.path}.deleted').writeAsString('');
        }
        await file.delete();
      }
    });
    await refreshMarkdownIndex(
      directoryPath: File(note.path).parent.path,
      kind: note.kind,
    );
  }

  /// Keeps the two source reports intact and never overwrites an edited merge.
  Future<NoteFile> mergeWeeklyReports({
    required String directoryPath,
    required List<NoteFile> sources,
    required Future<String?> Function(String sourceMarkdown, String periodLabel)
    generate,
    bool english = false,
  }) async {
    if (sources.length != 2 ||
        sources.any((n) => n.kind != NoteKind.weekly) ||
        sources[0].path == sources[1].path ||
        sources[0].name == sources[1].name) {
      throw ArgumentError('Select two distinct weekly reports');
    }
    final sorted = [...sources]..sort((a, b) => a.name.compareTo(b.name));
    final stems = sorted
        .map((n) => n.name.replaceFirst(RegExp(r'\.md$'), ''))
        .toList();
    if (stems.any((s) => !RegExp(r'^\d{4}-W\d{2}$').hasMatch(s))) {
      throw ArgumentError('Weekly reports must have ISO week filenames');
    }
    final name = '${stems[0]}_${stems[1]}';
    final path = _join(directoryPath, '$name.md');
    final title = '$name ${english ? 'Biweekly report' : '双周报'}';
    await NoteStorageCoordinator.runForManagedNotePath(path, () async {
      final file = File(path);
      if (!await file.exists()) {
        final sections = <String>[];
        for (final source in sorted) {
          sections.add(
            '## ${source.name}\n\n${await readMarkdown(source.path)}',
          );
        }
        final generated = await generate(sections.join('\n\n'), name);
        final body = (generated ?? '')
            .trim()
            .replaceFirst(RegExp(r'^# [^\n]*(?:\n|$)'), '')
            .trim();
        if (body.isEmpty) {
          throw StateError(
            english
                ? 'AI could not generate the biweekly report. Check the intelligent-generation model and try again.'
                : 'AI 未能生成双周报，请检查智能生成模型配置后重试。',
          );
        }
        await file.parent.create(recursive: true);
        await file.writeAsString('# $title\n\n$body\n');
      }
    });
    await indexMarkdownFile(
      directoryPath: directoryPath,
      kind: NoteKind.biweekly,
      notePath: path,
    );
    return describeMarkdown(
      note: NoteFile(
        path: path,
        name: '$name.md',
        title: title,
        modifiedAt: DateTime.now(),
        kind: NoteKind.biweekly,
      ),
      content: await readMarkdown(path),
    );
  }

  Future<void> writeMarkdown(String path, String content) async {
    await NoteStorageCoordinator.runForManagedNotePath(path, () async {
      final file = File(path);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(content);
      final deletionMarker = File('$path.deleted');
      if (await deletionMarker.exists()) await deletionMarker.delete();
    });
  }

  /// Startup generation must not bring back a manually deleted report, or
  /// overwrite a report edited while the model was producing its response.
  Future<bool> writeGeneratedReport(String path, String content) {
    return NoteStorageCoordinator.runForManagedNotePath(path, () async {
      if (await File('$path.deleted').exists()) return false;
      final file = File(path);
      if (await file.exists()) {
        final lines = (await file.readAsString()).split(RegExp(r'\r?\n'));
        if (lines.any(
          (line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'),
        )) {
          return false;
        }
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return true;
    });
  }

  Future<bool> refreshMarkdownIndex({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    return false;
  }

  Future<void> indexMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    required String notePath,
  }) async {}

  NoteFile describeMarkdown({
    required NoteFile note,
    required String content,
    DateTime? modifiedAt,
  }) {
    return NoteFile(
      path: note.path,
      name: note.name,
      title: _titleFromContent(content, note.name),
      modifiedAt: modifiedAt ?? DateTime.now(),
      kind: note.kind,
      preview: _previewFromContent(content),
      searchText: _searchTextFromContent(content),
    );
  }

  Future<List<NoteFile>> searchMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
    required String query,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.runes.length < 2) {
      return const [];
    }

    final notes = await listMarkdownFiles(
      directoryPath: directoryPath,
      kind: kind,
    );
    final results = <NoteFile>[];
    for (final note in notes) {
      final content = await readMarkdown(note.path);
      if (content.toLowerCase().contains(normalizedQuery) ||
          note.name.toLowerCase().contains(normalizedQuery) ||
          note.title.toLowerCase().contains(normalizedQuery)) {
        results.add(note);
      }
    }
    return results;
  }

  Future<File> ensureMarkdownFile(
    String path, {
    String defaultContent = '',
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      await writeMarkdown(path, defaultContent);
    }
    return file;
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  String _titleFromContent(String content, String fallbackName) {
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
      if (trimmed.isNotEmpty) {
        return trimmed.length > 28 ? '${trimmed.substring(0, 28)}...' : trimmed;
      }
    }
    return fallbackName.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
  }

  String _previewFromContent(String content) {
    final text = _bodyTextFromContent(content, skipFirstLine: true);
    if (text.length <= 72) {
      return text;
    }
    return '${text.substring(0, 72)}...';
  }

  String _searchTextFromContent(String content) {
    return _bodyTextFromContent(content);
  }

  String _bodyTextFromContent(String content, {bool skipFirstLine = false}) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''))
        .where((line) => line.isNotEmpty)
        .toList();
    return (skipFirstLine ? lines.skip(1) : lines).join(' ');
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _isoWeekNumber(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final first = _startOfWeek(DateTime(isoYear, 1, 4));
    return (start.difference(first).inDays ~/ 7) + 1;
  }

  String _formatIsoWeek(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final week = _isoWeekNumber(date);
    return '${isoYear.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }
}
