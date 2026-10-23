import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Document boundary between Flutter and the embedded editor. Autosave echoes
/// never advance the revision or recreate browser history.
class OpenTyporaSession extends ChangeNotifier {
  OpenTyporaSession({required this.controller, required this.onChanged})
    : id = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      _value = controller.value {
    controller.addListener(_externalChange);
  }

  final TextEditingController controller;
  ValueChanged<String> onChanged;
  final String id;
  int revision = 0;
  int _sequence = 0;
  bool _writing = false;
  bool _disposed = false;
  TextEditingValue _value;
  bool readOnly = false;
  bool dark = false;
  bool english = false;
  Map<String, String> colors = const {};

  Map<String, Object> get snapshot => {
    'id': id,
    'revision': revision,
    'text': controller.text,
    'anchor': controller.selection.isValid
        ? controller.selection.baseOffset
        : 0,
    'head': controller.selection.isValid
        ? controller.selection.extentOffset
        : 0,
    'readOnly': readOnly,
    'dark': dark,
    'english': english,
    'colors': colors,
  };
  void configure({
    required bool readOnly,
    required bool dark,
    required bool english,
    Map<String, String> colors = const {},
  }) {
    if (this.readOnly == readOnly &&
        this.dark == dark &&
        this.english == english &&
        mapEquals(this.colors, colors)) {
      return;
    }
    this.readOnly = readOnly;
    this.dark = dark;
    this.english = english;
    this.colors = colors;
    notifyListeners();
  }

  void _externalChange() {
    if (_writing || _disposed || controller.value == _value) return;
    final value = controller.value;
    final changed =
        value.text != _value.text || value.selection != _value.selection;
    _value = value;
    if (changed) {
      revision++;
      notifyListeners();
    }
  }

  bool accept(Map<String, dynamic> message) {
    if (_disposed || message['id'] != id || message['revision'] != revision) {
      return false;
    }
    final sequence = message['sequence'],
        text = message['text'],
        anchor = message['anchor'],
        head = message['head'];
    if (sequence is! int ||
        sequence <= _sequence ||
        text is! String ||
        anchor is! int ||
        head is! int ||
        anchor < 0 ||
        head < 0 ||
        anchor > text.length ||
        head > text.length) {
      return false;
    }
    final changed = text != controller.text;
    if (changed && (readOnly || message['type'] != 'change')) return false;
    _sequence = sequence;
    _writing = true;
    try {
      _value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: anchor, extentOffset: head),
      );
      controller.value = _value;
      if (changed) onChanged(text);
    } finally {
      _writing = false;
      // A controller listener or onChanged may synchronously apply a host edit.
      // Publish it after the browser write rather than losing its revision.
      _externalChange();
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_externalChange);
    super.dispose();
  }
}
