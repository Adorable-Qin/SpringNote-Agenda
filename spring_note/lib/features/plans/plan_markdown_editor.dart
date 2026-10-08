import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
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
  final _sourceInput = TextEditingController();
  late String _documentText;
  final _focus = FocusNode();
  final _regionFocus = FocusNode();
  final _sourceFocus = FocusNode();
  final _toolbarPortal = OverlayPortalController();
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
    _documentText = widget.controller.text;
    _sourceInput.text = _documentText;
    _focus.onKeyEvent = _handleBlockKey;
    widget.controller.addListener(_externalChange);
  }

  @override
  void didUpdateWidget(covariant PlanMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalChange);
      widget.controller.addListener(_externalChange);
      _documentText = widget.controller.text;
      _sourceInput.text = _documentText;
      _start = null;
      _undo.clear();
      _redo.clear();
    }
  }

  void _externalChange() {
    if (_writing || !mounted || widget.controller.text == _documentText) return;
    setState(() {
      _documentText = widget.controller.text;
      _sourceInput.text = _documentText;
      _start = null;
      _undo.clear();
      _redo.clear();
    });
  }

  void _editingChanged(bool focused) {
    if (!mounted) return;
    if (focused && !_editing) return;
    if (focused) {
      _toolbarPortal.show();
    } else {
      _toolbarPortal.hide();
    }
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
    _sourceInput.dispose();
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
    _documentText = value;
    if (_sourceInput.text != value) _sourceInput.text = value;
    widget.controller.text = value;
    _writing = false;
    widget.onChanged(value);
    setState(() {});
  }

  void _activate(PlanMarkdownBlock block, {TextPosition? position}) {
    _toolbarPortal.show();
    setState(() {
      _editing = true;
      _start = block.start;
      _end = block.end;
      _prefix = block.prefix;
      _input.value = TextEditingValue(
        text: block.body,
        selection: TextSelection.collapsed(
          offset: position?.offset ?? block.body.length,
          affinity: position?.affinity ?? TextAffinity.downstream,
        ),
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

  KeyEventResult _handleBlockKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return _moveHorizontallyBetweenBlocks(event);
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return _moveBetweenBlocks(event);
    }
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        _start == null ||
        _input.text.isNotEmpty ||
        !_input.selection.isCollapsed ||
        _input.selection.baseOffset != 0 ||
        (_input.value.composing.isValid &&
            !_input.value.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    final source = widget.controller.text;
    final previous = parsePlanMarkdown(source.substring(0, _start!)).lastOrNull;
    if (previous == null) {
      if (_prefix.isEmpty) return KeyEventResult.ignored;
      _prefix = '';
      _edit('');
    } else {
      // Remove the empty block and its preceding separator, leaving the next
      // block's separator and all other source content intact.
      _publish(source.replaceRange(previous.end, _end, ''));
      _activate(previous);
    }
    return KeyEventResult.handled;
  }

  RenderEditable? _activeRenderEditable() {
    RenderEditable? result;
    void visit(RenderObject object) {
      if (object is RenderEditable) {
        result = object;
      } else if (result == null) {
        object.visitChildren(visit);
      }
    }

    final root = _activeBlockKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  KeyEventResult _moveHorizontallyBetweenBlocks(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final selection = _input.selection;
    if (event is KeyUpEvent ||
        _start == null ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        !selection.isValid ||
        !selection.isCollapsed ||
        (_input.value.composing.isValid &&
            !_input.value.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    final left = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (selection.extentOffset != (left ? 0 : _input.text.length)) {
      return KeyEventResult.ignored;
    }
    final blocks = _blocks;
    final index = blocks.indexWhere((block) => block.start == _start);
    final next = index + (left ? -1 : 1);
    if (index < 0 || next < 0 || next >= blocks.length) {
      return KeyEventResult.ignored;
    }
    final target = blocks[next];
    _activate(
      target,
      position: TextPosition(offset: left ? target.body.length : 0),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _start != target.start || !_focus.hasFocus) return;
      final render = _activeRenderEditable();
      render?.showOnScreen(
        rect: render.getLocalRectForCaret(_input.selection.extent),
      );
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _moveBetweenBlocks(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final selection = _input.selection;
    if (event is KeyUpEvent ||
        _start == null ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        !selection.isValid ||
        !selection.isCollapsed ||
        (_input.value.composing.isValid &&
            !_input.value.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    final render = _activeRenderEditable();
    if (render == null) return KeyEventResult.ignored;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final caret = render.getLocalRectForCaret(selection.extent);
    final edge = render.getLocalRectForCaret(
      TextPosition(offset: up ? 0 : _input.text.length),
    );
    // Use visual lines, including soft wrapping, rather than source newlines.
    if ((caret.top - edge.top).abs() > 0.5) return KeyEventResult.ignored;
    final blocks = _blocks;
    final index = blocks.indexWhere((block) => block.start == _start);
    final next = index + (up ? -1 : 1);
    if (index < 0 || next < 0 || next >= blocks.length) {
      return KeyEventResult.ignored;
    }
    final target = blocks[next];
    final position = _targetCaret(target, render, caret.left, up);
    // Publish text and selection together, before the target's first paint.
    _activate(target, position: position);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _start != target.start || !_focus.hasFocus) return;
      final destination = _activeRenderEditable();
      if (destination == null) return;
      destination.showOnScreen(
        rect: destination.getLocalRectForCaret(_input.selection.extent),
      );
    });
    return KeyEventResult.handled;
  }

  TextPosition _targetCaret(
    PlanMarkdownBlock block,
    RenderEditable render,
    double x,
    bool up,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double markerWidth(String prefix) {
      if (RegExp(r'^ {0,3}[-+*] \[[ xX]\] ').hasMatch(prefix)) return 30;
      if (!RegExp(r'^ {0,3}(?:[-+*]|\d+[.)]) ').hasMatch(prefix)) return 0;
      final marker = TextPainter(
        text: TextSpan(
          text: prefix.trim().contains(RegExp(r'\d')) ? prefix.trim() : '•',
          style: DefaultTextStyle.of(context).style,
        ),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final width = marker.width + 10;
      marker.dispose();
      return width;
    }

    final style =
        render.text?.style?.merge(_editStyle(context, prefix: block.prefix)) ??
        _editStyle(context, prefix: block.prefix);
    final painter =
        TextPainter(
          text:
              MarkdownEditorHighlightSpanBuilder(
                context,
                includeBottomSpacer: false,
              ).buildTextEditingValue(
                TextEditingValue(text: block.body),
                textStyle: style,
                withComposing: false,
              ),
          textDirection: direction,
          textScaler: scaler,
          textAlign: render.textAlign,
          textWidthBasis: render.textWidthBasis,
          strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
        )..layout(
          maxWidth:
              (render.size.width +
                      markerWidth(_prefix) -
                      markerWidth(block.prefix) -
                      render.cursorWidth)
                  .clamp(1, double.infinity),
        );
    final lines = painter.computeLineMetrics();
    final line = up ? lines.lastOrNull : lines.firstOrNull;
    final position = line == null
        ? const TextPosition(offset: 0)
        : painter.getPositionForOffset(
            Offset(x, line.baseline - line.ascent / 2),
          );
    painter.dispose();
    return position;
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

  TextStyle _editStyle(BuildContext context, {String? prefix}) {
    final level = RegExp(
      r'^ {0,3}(#{1,6}) ',
    ).firstMatch(prefix ?? _prefix)?[1]?.length;
    final base = TextStyle(
      color: AppTheme.colors(context).text,
      fontSize: 14,
      fontWeight: FontWeight.w400,
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

  List<Widget> _selectableBlocks() {
    final blocks = _blocks;
    final active = blocks.indexWhere((block) => block.start == _start);
    Widget reading(Iterable<PlanMarkdownBlock> items) => SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map(_block).toList(),
      ),
    );
    if (active < 0) return [reading(blocks)];
    return [
      if (active > 0) reading(blocks.take(active)),
      _block(blocks[active]),
      if (active + 1 < blocks.length) reading(blocks.skip(active + 1)),
    ];
  }

  Widget _floatingToolbar(
    BuildContext overlayContext,
    OverlayChildLayoutInfo info,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final editor = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    var visible = Offset.zero & info.overlaySize;
    context.visitAncestorElements((element) {
      final render = element.findRenderObject();
      if (render is RenderAbstractViewport && render is RenderBox) {
        final box = render as RenderBox;
        if (!box.hasSize) return true;
        visible = visible.intersect(
          MatrixUtils.transformRect(
            render.getTransformTo(overlay),
            Offset.zero & box.size,
          ),
        );
      }
      return true;
    });
    if (!_editing ||
        visible.isEmpty ||
        editor.bottom <= visible.top + 48 ||
        editor.top >= visible.bottom - 48) {
      return const SizedBox.shrink();
    }
    final top = editor.top
        .clamp(visible.top, visible.bottom)
        .clamp(double.negativeInfinity, editor.bottom - 48);
    return Positioned(
      left: editor.left,
      top: top,
      width: editor.width,
      height: 48,
      child: TapRegion(
        groupId: _regionFocus,
        child: TextFieldTapRegion(
          child: Material(
            color: AppTheme.colors(context).surface,
            elevation: top > editor.top ? 2 : 0,
            child: _toolbar(),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final english = widget.english;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        key: const ValueKey('plan-editor-toolbar'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              textStyle: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(decoration: TextDecoration.none),
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
            icon: Icon(_source ? Icons.edit_note : Icons.code, size: 18),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    return TapRegion(
      groupId: _regionFocus,
      onTapOutside: (_) => _regionFocus.unfocus(),
      child: Focus(
        focusNode: _regionFocus,
        onFocusChange: _editingChanged,
        child: TextFieldTapRegion(
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _toolbarPortal,
            overlayChildBuilder: _floatingToolbar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editing) const SizedBox(height: 48),
                if (_editing) const SizedBox(height: 8),
                if (_source)
                  TextField(
                    key: const ValueKey('plan-source-editor'),
                    controller: _sourceInput,
                    focusNode: _sourceFocus,
                    minLines: 9,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    onChanged: _publish,
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
                  ..._selectableBlocks(),
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
