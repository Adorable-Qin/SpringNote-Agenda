import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/note_external_update.dart';
import '../../core/models/note_file.dart';
import '../../core/services/note_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../l10n/l10n.dart';

class WorkPlansPage extends StatefulWidget {
  const WorkPlansPage({
    super.key,
    required this.localDataState,
    this.noteService = const NoteService(),
    this.externalNoteUpdate,
    this.onNoteSaved,
  });

  final LocalDataState localDataState;
  final NoteService noteService;
  final ValueListenable<NoteExternalUpdate?>? externalNoteUpdate;
  final ValueChanged<NoteFile>? onNoteSaved;

  @override
  State<WorkPlansPage> createState() => _WorkPlansPageState();
}

class _WorkPlansPageState extends State<WorkPlansPage> {
  List<NoteFile> _months = [];
  List<NoteFile> _weeks = [];
  final Map<String, String> _contents = {};
  String? _selectedWeek;
  String? _error;
  bool _loading = true;
  bool _creating = false;
  bool _notifyingSave = false;
  int _generation = 0;

  bool get _english => currentAppLanguage(context) == 'en';

  @override
  void initState() {
    super.initState();
    widget.externalNoteUpdate?.addListener(_externalChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkPlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalNoteUpdate != widget.externalNoteUpdate) {
      oldWidget.externalNoteUpdate?.removeListener(_externalChanged);
      widget.externalNoteUpdate?.addListener(_externalChanged);
    }
    if (oldWidget.localDataState.dataDirectory !=
        widget.localDataState.dataDirectory) {
      _selectedWeek = null;
      _contents.clear();
      setState(() {
        _months = [];
        _weeks = [];
        _loading = true;
      });
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.externalNoteUpdate?.removeListener(_externalChanged);
    super.dispose();
  }

  void _externalChanged() {
    if (_notifyingSave) return;
    final kind = widget.externalNoteUpdate?.value?.kind;
    if (kind == NoteKind.monthlyPlan || kind == NoteKind.weeklyPlan) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final state = widget.localDataState;
    try {
      final months = await widget.noteService.listMarkdownFiles(
        directoryPath: state.directoryFor(NoteKind.monthlyPlan),
        kind: NoteKind.monthlyPlan,
      );
      final weeks = await widget.noteService.listMarkdownFiles(
        directoryPath: state.directoryFor(NoteKind.weeklyPlan),
        kind: NoteKind.weeklyPlan,
      );
      final contents = <String, String>{};
      for (final note in [...months, ...weeks]) {
        contents[note.path] = await widget.noteService.readMarkdown(note.path);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _months = months;
        _weeks = weeks;
        _contents
          ..clear()
          ..addAll(contents);
        if (!weeks.any((note) => note.path == _selectedWeek)) {
          _selectedWeek = weeks.firstOrNull?.path;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _create(NoteKind kind) async {
    final state = widget.localDataState;
    final english = _english;
    setState(() => _creating = true);
    try {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: english
            ? 'Choose a date in the plan period'
            : '选择计划所属月份或周的日期',
      );
      if (date == null ||
          !mounted ||
          state.dataDirectory != widget.localDataState.dataDirectory) {
        return;
      }
      final note = await widget.noteService.ensureCurrentMarkdownFile(
        directoryPath: state.directoryFor(kind),
        kind: kind,
        now: date,
      );
      final original = await widget.noteService.readMarkdown(note.path);
      // Only seed a newly-created, empty template; preserve existing plans.
      if (original.trim() == '# ${note.title}') {
        final template = kind == NoteKind.monthlyPlan
            ? '# ${note.title}\n\n## ${english ? 'This month’s summary' : '本月度工作总结'}\n\n\n## ${english ? 'Next month’s plan' : '下月度工作计划'}\n\n'
            : '# ${note.title}\n\n';
        await widget.noteService.writeMarkdown(note.path, template);
      }
      if (!mounted ||
          state.dataDirectory != widget.localDataState.dataDirectory) {
        return;
      }
      if (kind == NoteKind.weeklyPlan) _selectedWeek = note.path;
      widget.onNoteSaved?.call(note);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpringNotePageScaffold(
      title: _english ? 'Work plans' : '工作计划',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: _english ? 'Refresh' : '刷新',
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${_english ? 'Could not load plans' : '计划操作失败'}：$_error',
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 760) {
                          return ListView(
                            children: [
                              SizedBox(height: 520, child: _monthlyColumn()),
                              const SizedBox(height: 20),
                              SizedBox(height: 520, child: _weeklyBoard()),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _monthlyColumn()),
                            const SizedBox(width: 24),
                            Expanded(flex: 5, child: _weeklyBoard()),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _heading(String title, NoteKind kind) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      TextButton.icon(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(decoration: TextDecoration.none),
        ),
        onPressed: _creating ? null : () => _create(kind),
        icon: const Icon(Icons.add, size: 18),
        label: Text(_english ? 'New' : '新建'),
      ),
    ],
  );

  Widget _monthlyColumn() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(_english ? 'Monthly plans' : '月度计划', NoteKind.monthlyPlan),
      Text(
        _english
            ? 'All monthly summaries and next-month plans'
            : '按月归档 · 本月总结与下月计划',
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _months.isEmpty
            ? Center(
                child: Text(
                  _english
                      ? 'Create your first monthly plan.'
                      : '新建一份月度计划，开始记录本月总结与下月计划。',
                ),
              )
            : ListView.builder(
                itemCount: _months.length,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _card(_months[index]),
                ),
              ),
      ),
    ],
  );

  Widget _weeklyBoard() {
    final selected = _weeks
        .where((note) => note.path == _selectedWeek)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(_english ? 'Weekly plan board' : '周计划板', NoteKind.weeklyPlan),
        Text(
          _english
              ? 'Dated tasks appear in the calendar automatically.'
              : '写下带日期的事项，自动进入项目日历。',
        ),
        const SizedBox(height: 12),
        if (_weeks.isNotEmpty)
          DropdownButton<String>(
            value: _selectedWeek,
            isExpanded: true,
            items: [
              for (final note in _weeks)
                DropdownMenuItem(
                  value: note.path,
                  child: Text(note.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (path) => setState(() => _selectedWeek = path),
          ),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text(
                    _english
                        ? 'Create a weekly plan to start.'
                        : '新建周计划，随时补充和调整本周工作。',
                  ),
                )
              : SingleChildScrollView(child: _card(selected, pinned: true)),
        ),
      ],
    );
  }

  Widget _card(NoteFile note, {bool pinned = false}) {
    final dataDirectory = widget.localDataState.dataDirectory;
    return _PlanCard(
      key: ValueKey(note.path),
      note: note,
      content: _contents[note.path] ?? '',
      noteService: widget.noteService,
      english: _english,
      pinned: pinned,
      onSaved: (updated) {
        if (!mounted || dataDirectory != widget.localDataState.dataDirectory) {
          return;
        }
        _notifyingSave = true;
        try {
          widget.onNoteSaved?.call(updated);
        } finally {
          _notifyingSave = false;
        }
      },
    );
  }
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    super.key,
    required this.note,
    required this.content,
    required this.noteService,
    required this.english,
    required this.pinned,
    required this.onSaved,
  });
  final NoteFile note;
  final String content;
  final NoteService noteService;
  final bool english;
  final bool pinned;
  final ValueChanged<NoteFile> onSaved;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _controller = TextEditingController(
    text: widget.content,
  );
  int _revision = 0;
  bool _saving = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _PlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving &&
        _error == null &&
        oldWidget.content != widget.content &&
        _controller.text != widget.content) {
      _controller.value = TextEditingValue(
        text: widget.content,
        selection: TextSelection.collapsed(
          offset: _controller.selection.baseOffset.clamp(
            0,
            widget.content.length,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String content) async {
    final revision = ++_revision;
    final service = widget.noteService;
    final note = widget.note;
    final onSaved = widget.onSaved;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await service.writeMarkdown(note.path, content);
      if (revision != _revision) return;
      if (mounted) setState(() => _saving = false);
      onSaved(service.describeMarkdown(note: note, content: content));
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppTheme.colors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: widget.pinned ? colors.surfaceMuted : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.pinned)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.push_pin_outlined, size: 18),
                ),
              Expanded(
                child: Text(
                  widget.note.name.replaceFirst('.md', ''),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                _saving
                    ? (widget.english ? 'Saving…' : '保存中…')
                    : _error != null
                    ? (widget.english ? 'Save failed' : '保存失败')
                    : (widget.english ? 'Saved' : '已保存'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: widget.pinned ? 16 : 9,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            onChanged: _save,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: widget.english
                  ? '- [ ] Task — Due: 2026-10-09'
                  : '- [ ] 完成方案，截止：2026-10-09',
            ),
          ),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: () => _save(_controller.text),
                  child: Text(widget.english ? 'Retry' : '重试'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
