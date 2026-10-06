import 'package:flutter/material.dart';
import '../../core/models/note_file.dart';

class WeeklyReportPicker extends StatefulWidget {
  const WeeklyReportPicker({
    super.key,
    required this.notes,
    required this.english,
  });
  final List<NoteFile> notes;
  final bool english;

  @override
  State<WeeklyReportPicker> createState() => _WeeklyReportPickerState();
}

class _WeeklyReportPickerState extends State<WeeklyReportPicker> {
  final Set<NoteFile> _selected = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.english ? 'Select two weekly reports' : '选择两份周报'),
    content: SizedBox(
      width: 520,
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.english
                ? 'Selected ${_selected.length}/2. An existing merge will be opened without overwriting it.'
                : '已选 ${_selected.length}/2。若已有相同组合的双周报，将直接打开。',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.notes.length < 2
                ? Center(
                    child: Text(
                      widget.english
                          ? 'Create at least two weekly reports first.'
                          : '请先创建至少两份周报。',
                    ),
                  )
                : ListView(
                    children: [
                      for (final note in widget.notes)
                        CheckboxListTile(
                          title: Text(note.title),
                          subtitle: Text(note.name),
                          value: _selected.contains(note),
                          onChanged:
                              !_selected.contains(note) && _selected.length == 2
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(note);
                                  } else {
                                    _selected.remove(note);
                                  }
                                }),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.english ? 'Cancel' : '取消'),
      ),
      FilledButton(
        onPressed: _selected.length == 2
            ? () => Navigator.pop(context, _selected.toList())
            : null,
        child: Text(widget.english ? 'Merge' : '合并'),
      ),
    ],
  );
}
