import 'package:flutter/material.dart';
import '../../core/editor/open_typora_editor.dart';

/// Shared live Markdown surface for notebook documents and plan sections.
class PlanMarkdownEditor extends StatelessWidget {
  static Future<void> flush(TextEditingController controller) =>
      OpenTyporaEditor.flushController(controller);
  const PlanMarkdownEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.imageBasePath,
    this.documentId,
    this.english = false,
    this.readOnly = false,
    this.expand = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String imageBasePath;
  final Object? documentId;
  final bool english;
  final bool readOnly;
  final bool expand;
  @override
  Widget build(BuildContext context) => OpenTyporaEditor(
    controller: controller,
    onChanged: onChanged,
    imageBasePath: imageBasePath,
    documentId: documentId,
    english: english,
    readOnly: readOnly,
    expand: expand,
  );
}
