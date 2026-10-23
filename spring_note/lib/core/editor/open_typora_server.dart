import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../services/image_file_types.dart';

/// Bundled code and document-scoped images, served on an ephemeral loopback port.
/// Every request requires the unguessable session path.
class OpenTyporaServer {
  OpenTyporaServer({
    required this.token,
    required this.imageBasePath,
    AssetBundle? bundle,
    this.localAssetPath,
  }) : _bundle = bundle ?? rootBundle,
       documentId = token;
  final String token;
  String imageBasePath;
  String documentId;
  final AssetBundle _bundle;
  final String? localAssetPath;
  String? _localRoot;
  HttpServer? _server;
  bool _closed = false;
  static final _bundles = Expando<_EditorAssets>();
  _EditorAssets get _assets => _bundles[_bundle] ??= _EditorAssets(_bundle);
  static Future<void> prewarm() async {
    final assets = _bundles[rootBundle] ??= _EditorAssets(rootBundle);
    await assets.manifest;
    await Future.wait(
      [
        'index.html',
        'renderer.js',
        'adapter.js',
        'preload.js',
        'editor.css',
      ].map(assets.read),
    );
  }

  Uri get mediaBase => uri.resolve('media/$documentId/');
  void bindDocument(String id, String basePath) {
    documentId = id;
    imageBasePath = basePath;
  }

  Uri get uri =>
      Uri.parse('http://127.0.0.1:${_server!.port}/$token/index.html?native');
  Future<void> start() async {
    if (localAssetPath != null) {
      _localRoot = await Directory(localAssetPath!).resolveSymbolicLinks();
      if (!await File(p.join(_localRoot!, 'index.html')).exists()) {
        throw StateError(
          'Local editor assets are missing; run tools/typora-lab/prepare.mjs',
        );
      }
    } else {
      await _assets.manifest;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen(_serve);
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      final parts = request.uri.pathSegments;
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      request.response.headers.set('Referrer-Policy', 'no-referrer');
      request.response.headers.set('Cache-Control', 'no-store');
      if (request.method != 'GET' || parts.length < 2 || parts.first != token) {
        request.response.statusCode = HttpStatus.notFound;
      } else if (parts.length == 4 &&
          parts[1] == 'media' &&
          parts[2] == documentId) {
        final imageDocument = documentId;
        final file = await resolveImage(parts[3]);
        if (file == null || imageDocument != documentId) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(
            'Content-Type',
            imageMimeTypeForExtension(p.extension(file.path)),
          );
          request.response.add(await file.readAsBytes());
        }
      } else {
        final relative = parts.skip(1).toList();
        final data = await _readAsset(relative);
        if (data == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(
            'Content-Type',
            _mimeType(relative.last),
          );
          request.response.headers.set(
            'Content-Security-Policy',
            "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-src 'none'",
          );
          request.response.add(data);
        }
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.notFound;
    } finally {
      await request.response.close();
    }
  }

  Future<Uint8List?> _readAsset(List<String> parts) async {
    if (parts.isEmpty ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains(RegExp(r'[\\/:\x00]')),
        )) {
      return null;
    }
    if (parts.first == 'lib') parts[0] = 'lib.asar';
    if (_localRoot != null) {
      final resolved = await File(
        p.joinAll([_localRoot!, ...parts]),
      ).resolveSymbolicLinks();
      if (!p.isWithin(_localRoot!, resolved)) return null;
      final file = File(resolved);
      if (await file.length() > 32 * 1024 * 1024) return null;
      return file.readAsBytes();
    }
    return _assets.read(parts.join('/'));
  }

  static String _mimeType(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.html' => 'text/html; charset=utf-8',
        '.js' => 'text/javascript; charset=utf-8',
        '.css' => 'text/css; charset=utf-8',
        '.json' => 'application/json; charset=utf-8',
        '.woff' => 'font/woff',
        '.woff2' => 'font/woff2',
        '.ttf' => 'font/ttf',
        '.otf' => 'font/otf',
        '.svg' => 'image/svg+xml',
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        _ => 'application/octet-stream',
      };

  Future<File?> resolveImage(String source) async {
    try {
      final decoded = Uri.decodeComponent(source),
          uri = Uri.tryParse(Uri.decodeComponent(source));
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : decoded;
      if (!hasAllowedImageExtension(path)) return null;
      final base = await Directory(imageBasePath).resolveSymbolicLinks();
      final candidate = File(p.isAbsolute(path) ? path : p.join(base, path));
      final resolved = await candidate.resolveSymbolicLinks();
      final shared = p.join(p.dirname(base), 'images');
      if (!p.isWithin(base, resolved) && !p.isWithin(shared, resolved)) {
        return null;
      }
      final file = File(resolved);
      if (await file.length() > 32 * 1024 * 1024) return null;
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    _server = null;
  }
}

/// Immutable packaged resources are shared across notes and plan sections.
/// Futures coalesce concurrent reads; user documents and images never enter it.
class _EditorAssets {
  _EditorAssets(this.bundle);
  final AssetBundle bundle;
  Future<Map<String, String>>? _manifest;
  final _bytes = <String, Future<Uint8List>>{};
  Future<Map<String, String>> get manifest =>
      _manifest ??= _loadManifest().catchError((Object error) {
        _manifest = null;
        throw error;
      });
  Future<Map<String, String>> _loadManifest() async {
    final data =
        jsonDecode(
              await bundle.loadString('assets/typora_editor/manifest.json'),
            )
            as Map<String, dynamic>;
    if (data['format'] != 1 || data['engine'] != 'typora-1.7.6') {
      throw const FormatException('Unsupported editor bundle');
    }
    final files = <String, String>{};
    for (final entry in (data['files'] as Map<String, dynamic>).entries) {
      final asset = (entry.value as Map<String, dynamic>)['asset'] as String;
      if (!RegExp(r'^[a-f0-9]{24}\.[a-z0-9]+$').hasMatch(asset)) {
        throw const FormatException('Invalid editor asset name');
      }
      files[entry.key] = asset;
    }
    if (!files.containsKey('index.html')) {
      throw const FormatException('Editor entry is missing');
    }
    return files;
  }

  Future<Uint8List?> read(String path) async {
    final asset = (await manifest)[path];
    if (asset == null) return null;
    return _bytes[asset] ??= bundle
        .load('assets/typora_editor/$asset')
        .then(
          (data) =>
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        )
        .catchError((Object error) {
          _bytes.remove(asset);
          throw error;
        });
  }
}
