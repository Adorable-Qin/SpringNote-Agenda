import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/spring_markdown.dart';
import '../../core/widgets/markdown_editor_highlight.dart';
import '../../core/widgets/spring_tree.dart';
import 'plan_markdown_document.dart';

/// A source-preserving live editor. Complex Markdown stays editable as a source
/// block instead of being round-tripped through a lossy rich-text document.
class PlanMarkdownEditor extends StatefulWidget {
  const PlanMarkdownEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.imageBasePath,
    this.english = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String imageBasePath;
  final bool english;

  @override
  State<PlanMarkdownEditor> createState() => _PlanMarkdownEditorState();
}

class _PlanMarkdownEditorState extends State<PlanMarkdownEditor> {
  final _input = _PlanBlockController();
  final _focus = FocusNode();
  final _regionFocus = FocusNode();
  final _sourceFocus = FocusNode();
  bool _editing = false;
  final _activeBlockKey = GlobalKey();
  final _undo = <String>[];
  final _redo = <String>[];
  int? _start;
  int _end = 0;
  String _prefix = '';
  bool _source = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_externalChange);
  }

  @override
  void didUpdateWidget(covariant PlanMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalChange);
      widget.controller.addListener(_externalChange);
      _start = null;
      _undo.clear();
      _redo.clear();
    }
  }

  void _externalChange() {
    if (_writing || !mounted) return;
    setState(() {
      _start = null;
      _undo.clear();
      _redo.clear();
    });
  }

  void _editingChanged(bool focused) {
    if (!mounted) return;
    setState(() {
      _editing = focused;
      if (!focused) {
        _start = null;
        _source = false;
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    _focus.dispose();
    _regionFocus.dispose();
    _sourceFocus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _publish(String value, {bool remember = true}) {
    if (value == widget.controller.text) return;
    if (remember) {
      _undo.add(widget.controller.text);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _writing = true;
    widget.controller.text = value;
    _writing = false;
    widget.onChanged(value);
    setState(() {});
  }

  void _activate(PlanMarkdownBlock block) {
    setState(() {
      _editing = true;
      _start = block.start;
      _end = block.end;
      _prefix = block.prefix;
      _input.value = TextEditingValue(
        text: block.body,
        selection: TextSelection.collapsed(offset: block.body.length),
      );
    });
    _focus.requestFocus();
  }

  void _edit(String value) {
    if (_start == null) return;
    final replacement = '$_prefix$value';
    final next = widget.controller.text.replaceRange(
      _start!,
      _end,
      replacement,
    );
    _end = _start! + replacement.length;
    _publish(next);
  }

  void _typed(String value) {
    if (_start == null) return;
    final composing = _input.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _edit(value);
      return;
    }
    final oldBody = widget.controller.text.substring(
      _start! + _prefix.length,
      _end,
    );
    if (value == '$oldBody\n' &&
        _input.selection.isCollapsed &&
        _input.selection.extentOffset == value.length) {
      var nextPrefix = '';
      if (RegExp(r'^ {0,3}[-+*] ').hasMatch(_prefix)) {
        nextPrefix = _prefix.replaceAll('[x]', '[ ]').replaceAll('[X]', '[ ]');
      }
      final ordered = RegExp(r'^( *)(\d+)([.)] )$').firstMatch(_prefix);
      if (ordered != null) {
        nextPrefix = '${ordered[1]}${int.parse(ordered[2]!) + 1}${ordered[3]}';
      }
      // Enter on an empty list item exits the list.
      if (oldBody.isEmpty) {
        _prefix = '';
        _input.clear();
        _edit('');
        return;
      }
      final separator = nextPrefix.isEmpty ? '\n\n' : '\n';
      final replacement = '$_prefix$oldBody$separator$nextPrefix';
      final next = widget.controller.text.replaceRange(
        _start!,
        _end,
        replacement,
      );
      final nextStart = _start! + replacement.length - nextPrefix.length;
      _end = _start! + replacement.length;
      _publish(next);
      _activate(PlanMarkdownBlock(nextStart, _end, nextPrefix));
      return;
    }
    if (!value.contains('\n')) {
      final combined = '$_prefix$value';
      final parsed = PlanMarkdownBlock(0, combined.length, combined);
      if (parsed.prefix != _prefix && parsed.prefix.isNotEmpty) {
        final delta = parsed.prefix.length - _prefix.length;
        final selection = _input.selection;
        _prefix = parsed.prefix;
        value = parsed.body;
        _input.value = TextEditingValue(
          text: value,
          selection: TextSelection(
            baseOffset: (selection.baseOffset - delta).clamp(0, value.length),
            extentOffset: (selection.extentOffset - delta).clamp(
              0,
              value.length,
            ),
          ),
        );
      }
    }
    _edit(value);
  }

  void _append() {
    final text = widget.controller.text;
    final separator = text.isEmpty || text.endsWith('\n\n')
        ? ''
        : text.endsWith('\n')
        ? '\n'
        : '\n\n';
    _publish('$text$separator');
    _activate(
      PlanMarkdownBlock(
        widget.controller.text.length,
        widget.controller.text.length,
        '',
      ),
    );
  }

  void _changePrefix(String prefix) {
    if (_start == null) _append();
    setState(() => _prefix = prefix);
    _edit(_input.text);
    _focus.requestFocus();
  }

  void _wrap(String marker) {
    if (_start == null) _append();
    final selection = _input.selection;
    final start = selection.isValid ? selection.start : _input.text.length;
    final end = selection.isValid ? selection.end : start;
    final text = _input.text;
    _input.value = TextEditingValue(
      text: text.replaceRange(
        start,
        end,
        '$marker${text.substring(start, end)}$marker',
      ),
      selection: TextSelection(
        baseOffset: start + marker.length,
        extentOffset: end + marker.length,
      ),
    );
    _edit(_input.text);
    _focus.requestFocus();
  }

  void _history(bool redo) {
    final from = redo ? _redo : _undo;
    if (from.isEmpty) return;
    (redo ? _undo : _redo).add(widget.controller.text);
    _start = null;
    _regionFocus.requestFocus();
    _publish(from.removeLast(), remember: false);
  }

  List<PlanMarkdownBlock> get _blocks {
    final text = widget.controller.text;
    if (_start == null) return parsePlanMarkdown(text);
    return [
      ...parsePlanMarkdown(text.substring(0, _start!)),
      PlanMarkdownBlock(_start!, _end, text.substring(_start!, _end)),
      ...parsePlanMarkdown(text.substring(_end), offset: _end),
    ];
  }

  TextStyle _editStyle(BuildContext context) {
    final level = RegExp(r'^ {0,3}(#{1,6}) ').firstMatch(_prefix)?[1]?.length;
    final base = TextStyle(
      color: AppTheme.colors(context).text,
      fontSize: 14,
      height: 1.55,
    );
    return level == null
        ? base
        : base.copyWith(
            fontSize: <double>[28, 24, 20, 18, 16, 14][level - 1],
            fontWeight: FontWeight.w700,
          );
  }

  Widget _render(String markdown) => GptMarkdownTheme(
    gptThemeData: springMarkdownThemeData(
      context,
      GptMarkdownTheme.of(context),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: springMarkdownTextColor(context),
      ),
      child: GptMarkdown(
        prepareSpringMarkdownText(markdown),
        style: TextStyle(
          fontSize: 14,
          height: 1.55,
          color: springMarkdownTextColor(context),
        ),
        checkboxBuilder: springMarkdownCheckboxBuilder,
        inlineCodeBuilder: springMarkdownInlineCodeBuilder,
        blockQuoteBuilder: springMarkdownBlockQuoteBuilder,
        hrBuilder: springMarkdownHrBuilder,
        unOrderedListBuilder: springMarkdownUnorderedListBuilder,
        codeBuilder: buildSpringCodeBlock,
        latexBuilder: springMarkdownLatexBuilder,
        useDollarSignsForLatex: true,
        imageBuilder: (context, url, width, height) => SpringMarkdownImage(
          url: url,
          width: width,
          height: height,
          localImageBasePaths: [widget.imageBasePath],
        ),
      ),
    ),
  );

  Widget _block(PlanMarkdownBlock block) {
    final active = block.start == _start;
    final task = block.isTask;
    Widget child;
    if (active) {
      // Preserve the platform input connection when moving to another block or
      // changing between a task row and a plain paragraph.
      child = KeyedSubtree(
        key: _activeBlockKey,
        child: TextField(
          key: const ValueKey('plan-active-block'),
          controller: _input,
          focusNode: _focus,
          maxLines: null,
          minLines: 1,
          style: _editStyle(context),
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
          onChanged: _typed,
        ),
      );
      if (!task && RegExp(r'^ {0,3}(?:[-+*]|\d+[.)]) ').hasMatch(_prefix)) {
        child = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 10),
              child: Text(
                _prefix.trim().contains(RegExp(r'\d')) ? _prefix.trim() : '•',
              ),
            ),
            Expanded(child: child),
          ],
        );
      }
    } else {
      child = MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _activate(block),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: IgnorePointer(
              child: _render(task ? block.body : block.source),
            ),
          ),
        ),
      );
    }
    if (task) {
      child = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: Checkbox(
              value: block.checked,
              onChanged: (value) {
                final updated = block.source.replaceFirst(
                  RegExp(r'\[[ xX]\]'),
                  value! ? '[x]' : '[ ]',
                );
                if (active) {
                  _prefix = PlanMarkdownBlock(
                    0,
                    updated.length,
                    updated,
                  ).prefix;
                }
                _publish(
                  widget.controller.text.replaceRange(
                    block.start,
                    block.end,
                    updated,
                  ),
                );
              },
            ),
          ),
          Expanded(child: child),
        ],
      );
    }
    return Container(
      key: ValueKey('plan-block-${block.start}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: active
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AppTheme.colors(context).border,
                  width: 2,
                ),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    return TapRegion(
      onTapOutside: (_) => _regionFocus.unfocus(),
      child: Focus(
        focusNode: _regionFocus,
        onFocusChange: _editingChanged,
        child: TextFieldTapRegion(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing)
                Wrap(
                  key: const ValueKey('plan-editor-toolbar'),
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(decoration: TextDecoration.none),
                      ),
                      key: const ValueKey('plan-editor-mode'),
                      onPressed: () {
                        _regionFocus.requestFocus();
                        setState(() {
                          _source = !_source;
                          _start = null;
                        });
                        if (_source) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _source) _sourceFocus.requestFocus();
                          });
                        }
                      },
                      icon: Icon(
                        _source ? Icons.edit_note : Icons.code,
                        size: 18,
                      ),
                      label: Text(
                        _source
                            ? (english ? 'Live edit' : '实时编辑')
                            : (english ? 'Source' : '源码'),
                      ),
                    ),
                    if (!_source) ...[
                      IconButton(
                        tooltip: english ? 'Heading' : '标题',
                        onPressed: () => _changePrefix('## '),
                        icon: const Icon(Icons.title, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Bold' : '加粗',
                        onPressed: () => _wrap('**'),
                        icon: const Icon(Icons.format_bold, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Italic' : '斜体',
                        onPressed: () => _wrap('*'),
                        icon: const Icon(Icons.format_italic, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'List' : '列表',
                        onPressed: () => _changePrefix('- '),
                        icon: const Icon(Icons.format_list_bulleted, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Task' : '待办',
                        onPressed: () => _changePrefix('- [ ] '),
                        icon: const Icon(Icons.check_box_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Paragraph' : '正文',
                        onPressed: () => _changePrefix(''),
                        icon: const Icon(Icons.notes, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Undo' : '撤销',
                        onPressed: _undo.isEmpty ? null : () => _history(false),
                        icon: const Icon(Icons.undo, size: 18),
                      ),
                      IconButton(
                        tooltip: english ? 'Redo' : '重做',
                        onPressed: _redo.isEmpty ? null : () => _history(true),
                        icon: const Icon(Icons.redo, size: 18),
                      ),
                    ],
                  ],
                ),
              if (_editing) const SizedBox(height: 8),
              if (_source)
                TextField(
                  key: const ValueKey('plan-source-editor'),
                  controller: widget.controller,
                  focusNode: _sourceFocus,
                  minLines: 9,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  onChanged: widget.onChanged,
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                )
              else ...[
                ..._blocks.map(_block),
                if (_editing || widget.controller.text.trim().isEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(decoration: TextDecoration.none),
                    ),
                    key: const ValueKey('plan-add-paragraph'),
                    onPressed: _append,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(english ? 'Add paragraph' : '添加段落'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBlockController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return MarkdownEditorHighlightSpanBuilder(
      context,
      includeBottomSpacer: false,
    ).buildTextEditingValue(
      value,
      textStyle: style,
      withComposing: withComposing,
    );
  }
}
