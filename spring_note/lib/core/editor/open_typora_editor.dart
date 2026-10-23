import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import '../services/external_link_service.dart';
import '../services/image_file_types.dart';
import '../services/pasted_image_service.dart';
import '../theme/app_theme.dart';
import 'editor_runtime.dart';
import 'open_typora_server.dart';
import 'open_typora_session.dart';

class OpenTyporaEditor extends StatefulWidget {
  static final _flushers = Expando<Future<void> Function()>();
  static Future<void> flushController(TextEditingController controller) async {
    await _flushers[controller]?.call();
  }

  const OpenTyporaEditor({
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
  @visibleForTesting
  static Widget Function(BuildContext, OpenTyporaSession)? debugSurfaceBuilder;
  @visibleForTesting
  static ValueChanged<InAppWebViewController>? debugOnReady;
  @override
  State<OpenTyporaEditor> createState() => _OpenTyporaEditorState();
}

class _OpenTyporaEditorState extends State<OpenTyporaEditor> {
  late OpenTyporaSession _session;
  @override
  void initState() {
    super.initState();
    _createSession();
  }

  void _createSession() {
    _session = OpenTyporaSession(
      controller: widget.controller,
      onChanged: widget.onChanged,
    );
  }

  @override
  void didUpdateWidget(covariant OpenTyporaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.imageBasePath != widget.imageBasePath ||
        oldWidget.documentId != widget.documentId) {
      _session.dispose();
      _createSession();
    }
    _session.onChanged = widget.onChanged;
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    String hex(Color value) =>
        '#${(value.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    _session.configure(
      readOnly: widget.readOnly,
      dark: Theme.of(context).brightness == Brightness.dark,
      english: widget.english,
      colors: {
        'surface': hex(colors.surface),
        'text': hex(colors.text),
        'muted': hex(colors.textMuted),
        'border': hex(colors.border),
        'hover': hex(colors.surfaceHover),
      },
    );
    final surface =
        OpenTyporaEditor.debugSurfaceBuilder?.call(context, _session) ??
        _WebEditor(session: _session, imageBasePath: widget.imageBasePath);
    return SizedBox(height: widget.expand ? null : 440, child: surface);
  }
}

class _WebEditor extends StatefulWidget {
  const _WebEditor({required this.session, required this.imageBasePath});
  final OpenTyporaSession session;
  final String imageBasePath;
  @override
  State<_WebEditor> createState() => _WebEditorState();
}

class _WebEditorState extends State<_WebEditor> {
  late OpenTyporaServer _server;
  InAppWebViewController? _web;
  WebViewEnvironment? _environment;
  bool _started = false, _ready = false, _fallback = false;
  bool _opening = false;
  int _navigation = 0;
  String? _error;
  Timer? _loadTimer;
  @override
  void initState() {
    super.initState();
    _server = OpenTyporaServer(
      token: widget.session.id,
      imageBasePath: widget.imageBasePath,
      localAssetPath: Platform.environment['SPRINGNOTE_TYPORA_LAB_DIR'],
    );
    widget.session.addListener(_sendSnapshot);
    OpenTyporaEditor._flushers[widget.session.controller] = _flush;
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (!(Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS)) {
        throw UnsupportedError('WebView is unavailable on this platform');
      }
      await Future.wait([
        EditorRuntime.environment().then((value) => _environment = value),
        _server.start(),
      ]);
      if (!mounted) {
        await _server.close();
        return;
      }
      setState(() => _started = true);
      _loadTimer = Timer(const Duration(seconds: 20), () {
        if (!_ready) _fail('Editor startup timed out');
      });
    } catch (error) {
      _fail(error.toString());
    }
  }

  Map<String, Object> get _snapshot => {
    ...widget.session.snapshot,
    'mediaBase': _server.mediaBase.toString(),
  };

  @override
  void didUpdateWidget(covariant _WebEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_sendSnapshot);
    _unregisterFlush(oldWidget.session.controller);
    widget.session.addListener(_sendSnapshot);
    OpenTyporaEditor._flushers[widget.session.controller] = _flush;
    _server.bindDocument(widget.session.id, widget.imageBasePath);
    if (_ready) unawaited(_openDocument());
  }

  Future<void> _flush() async {
    if (!_ready || _opening || _fallback || !mounted) return;
    final result = await _web?.callAsyncJavaScript(
      functionBody: 'return await window.springNoteEditor.commit();',
    );
    if (result?.error != null) throw StateError(result!.error.toString());
  }

  void _unregisterFlush(TextEditingController controller) {
    if (OpenTyporaEditor._flushers[controller] == _flush) {
      OpenTyporaEditor._flushers[controller] = null;
    }
  }

  Future<void> _openDocument() async {
    final generation = ++_navigation;
    _opening = true;
    try {
      final result = await _web?.callAsyncJavaScript(
        functionBody:
            'return await window.springNoteEditor.openDocument(snapshot, generation);',
        arguments: {'snapshot': _snapshot, 'generation': generation},
      );
      if (!mounted || generation != _navigation) return;
      if (result?.error != null) throw StateError(result!.error.toString());
      if (result?.value != widget.session.id) {
        throw StateError('Document switch did not complete');
      }
      _opening = false;
      _loadTimer?.cancel();
      if (!_ready) setState(() => _ready = true);
      _sendSnapshot();
      OpenTyporaEditor.debugOnReady?.call(_web!);
    } catch (error) {
      if (mounted && generation == _navigation) _fail(error.toString());
    }
  }

  void _fail(String error) {
    if (!mounted) return;
    _loadTimer?.cancel();
    setState(() {
      _error = error;
      _fallback = true;
    });
  }

  void _sendSnapshot() {
    if (!_ready || !mounted || _fallback || _opening) return;
    unawaited(
      _web
          ?.evaluateJavascript(
            source:
                'window.springNoteEditor?.receive(${jsonEncode(_snapshot)});',
          )
          .catchError((Object e) {
            _fail(e.toString());
            return null;
          }),
    );
  }

  Future<dynamic> _message(List<dynamic> args) async {
    if (!mounted || args.isEmpty || args.first is! Map) return null;
    final message = Map<String, dynamic>.from(args.first as Map);
    try {
      switch (message['type']) {
        case 'ready':
          return _snapshot;
        case 'mounted':
          _loadTimer?.cancel();
          setState(() => _ready = true);
          if (message['id'] == widget.session.id) {
            _sendSnapshot();
            OpenTyporaEditor.debugOnReady?.call(_web!);
          } else {
            unawaited(_openDocument());
          }
          return true;
        case 'change':
        case 'selection':
          return widget.session.accept(message);
        case 'image':
          if (message['id'] != widget.session.id) return null;
          if (widget.session.readOnly) throw StateError('Editor is read only');
          final name = message['name'] as String,
              data = message['data'] as String;
          final extension = allowedImageExtension(name);
          if (extension == null || data.length > 44 * 1024 * 1024) {
            throw ArgumentError('Unsupported image');
          }
          final notePath = p.join(widget.imageBasePath, 'editor.md');
          const images = PastedImageService();
          final saved = await images.saveImageBytesForNote(
            notePath: notePath,
            bytes: base64Decode(data),
            preferredName: name,
            extension: extension,
          );
          return images.markdownPathForNote(
            notePath: notePath,
            imagePath: saved.path,
          );
        case 'link':
          final uri = Uri.tryParse(message['url'] as String);
          if (uri == null ||
              !['https', 'http'].contains(uri.scheme) ||
              uri.host.isEmpty) {
            throw ArgumentError(
              widget.session.english
                  ? 'Only web links can be opened here.'
                  : '这里支持打开网页链接。',
            );
          }
          return await const ExternalLinkService().open(uri.toString());
      }
    } catch (error) {
      return {'error': error.toString()};
    }
    return null;
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    widget.session.removeListener(_sendSnapshot);
    _unregisterFlush(widget.session.controller);
    unawaited(_server.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return Column(
        children: [
          MaterialBanner(
            content: Text(
              widget.session.english
                  ? 'Live editor unavailable. Source editing is available.\n$_error'
                  : '实时编辑器暂不可用，可以继续编辑源码。\n$_error',
            ),
            actions: const [SizedBox.shrink()],
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('open-typora-source-fallback'),
              controller: widget.session.controller,
              readOnly: widget.session.readOnly,
              onChanged: widget.session.onChanged,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
            ),
          ),
        ],
      );
    }
    if (!_started) return const Center(child: CircularProgressIndicator());
    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: _environment,
          initialUrlRequest: URLRequest(url: WebUri(_server.uri.toString())),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            isInspectable: kDebugMode,
            useShouldOverrideUrlLoading: true,
            allowFileAccessFromFileURLs: false,
            allowUniversalAccessFromFileURLs: false,
            supportMultipleWindows: false,
          ),
          onWebViewCreated: (controller) {
            _web = controller;
            controller.addJavaScriptHandler(
              handlerName: 'springNote',
              callback: _message,
            );
          },
          shouldOverrideUrlLoading: (_, action) async =>
              action.request.url?.toString() == _server.uri.toString()
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL,
          onPermissionRequest: (_, request) async => PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.DENY,
          ),
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame == true) _fail(error.description);
          },
          onWebContentProcessDidTerminate: (_) =>
              _fail('Editor process stopped'),
        ),
        if (!_ready)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
