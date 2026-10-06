import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

import 'plan_markdown_document.dart';
import 'plan_markdown_editor.dart';

/// Keep document headings in storage for calendar/export compatibility, while
/// exposing only section bodies to the editor.
class MonthlyPlanEditor extends StatefulWidget {
  const MonthlyPlanEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.imageBasePath,
    required this.english,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String imageBasePath;
  final bool english;

  @override
  State<MonthlyPlanEditor> createState() => _MonthlyPlanEditorState();
}

class _MonthlyPlanEditorState extends State<MonthlyPlanEditor> {
  final _intro = TextEditingController();
  final _summary = TextEditingController();
  final _plan = TextEditingController();
  String _title = '';
  String _summaryHeading = '';
  String _planHeading = '';
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant MonthlyPlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_reload);
      widget.controller.addListener(_reload);
      _load();
    }
  }

  void _reload() {
    if (!_writing) setState(_load);
  }

  void _load() {
    final source = widget.controller.text;
    final blocks = parsePlanMarkdown(source);
    var start = 0;
    _title = '';
    if (blocks.isNotEmpty && blocks.first.source.startsWith('# ')) {
      start = blocks.length > 1 ? blocks[1].start : source.length;
      _title = source.substring(0, start);
    }
    final headings = blocks
        .where(
          (block) =>
              block.start >= start &&
              RegExp(
                r'^## (本月度?工作总结|下月度?工作计划|This month[’\x27]s summary|Next month[’\x27]s plan)\s*$',
              ).hasMatch(block.source),
        )
        .toList();
    _summaryHeading = '## 本月度工作总结\n\n';
    _planHeading = '## 下月度工作计划\n\n';
    _intro.text = '';
    _summary.text = '';
    _plan.text = '';
    if (headings.isEmpty) {
      // Older free-form plans remain fully editable as the summary.
      _summary.text = source.substring(start);
      return;
    }
    _intro.text = source.substring(start, headings.first.start);
    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final end = i + 1 < headings.length
          ? headings[i + 1].start
          : source.length;
      final isSummary =
          heading.source.contains('总结') || heading.source.contains('summary');
      final target = isSummary ? _summary : _plan;
      // Preserve repeated sections as editable content instead of dropping them.
      if (target.text.isNotEmpty) {
        target.text += source.substring(heading.start, end);
      } else {
        if (isSummary) {
          _summaryHeading = heading.source;
        } else {
          _planHeading = heading.source;
        }
        target.text = source.substring(heading.end, end);
      }
    }
  }

  String _join(String left, String right) {
    if (left.isEmpty || right.isEmpty) return '$left$right';
    return '$left${left.endsWith('\n') || right.startsWith('\n') ? '' : '\n\n'}$right';
  }

  void _save(String _) {
    var content = _join(_title, _intro.text);
    content = _join(content, _summaryHeading);
    content = _join(content, _summary.text);
    content = _join(content, _planHeading);
    content = _join(content, _plan.text);
    _writing = true;
    widget.controller.text = content;
    _writing = false;
    widget.onChanged(content);
  }

  Widget _section(String key, String title, TextEditingController controller) {
    final colors = AppTheme.colors(context);
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colors.divider),
          ),
          PlanMarkdownEditor(
            controller: controller,
            onChanged: _save,
            imageBasePath: widget.imageBasePath,
            english: widget.english,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_intro.text.trim().isNotEmpty) ...[
        _section(
          'monthly-intro',
          widget.english ? 'Additional notes' : '补充内容',
          _intro,
        ),
        const SizedBox(height: 16),
      ],
      _section(
        'monthly-summary',
        widget.english ? 'This month’s summary' : '本月度工作总结',
        _summary,
      ),
      const SizedBox(height: 16),
      _section(
        'monthly-plan',
        widget.english ? 'Next month’s plan' : '下月度工作计划',
        _plan,
      ),
    ],
  );

  @override
  void dispose() {
    widget.controller.removeListener(_reload);
    _intro.dispose();
    _summary.dispose();
    _plan.dispose();
    super.dispose();
  }
}
