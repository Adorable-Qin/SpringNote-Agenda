import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spring_note/core/editor/open_typora_server.dart';

class _Assets extends CachingAssetBundle {
  final reads = <String, int>{};
  @override
  Future<ByteData> load(String key) async {
    reads[key] = (reads[key] ?? 0) + 1;
    if (key == 'assets/typora_editor/manifest.json') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 1,
              'engine': 'typora-1.7.6',
              'files': {
                'index.html': {'asset': '000000000000000000000001.html'},
                'lib.asar/modes.js': {'asset': '000000000000000000000002.js'},
              },
            }),
          ),
        ),
      );
    }
    if (key == 'assets/typora_editor/000000000000000000000002.js') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode('/* modes */')),
      );
    }
    if (key != 'assets/typora_editor/000000000000000000000001.html') {
      throw StateError('missing');
    }
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode('<html>editor</html>')),
    );
  }
}

void main() {
  test(
    'local renderer serves nested assets and rejects escaped paths',
    () async {
      final root = await Directory.systemTemp.createTemp('typora_lab_server_');
      final assets = await Directory(p.join(root.path, 'web')).create();
      await File(
        p.join(assets.path, 'index.html'),
      ).writeAsString('<html>local</html>');
      await Directory(
        p.join(assets.path, 'lib.asar', 'codemirror'),
      ).create(recursive: true);
      await File(
        p.join(assets.path, 'lib.asar', 'codemirror', 'mode.js'),
      ).writeAsString('/* modes */');
      await File(p.join(root.path, 'private.js')).writeAsString('private');
      final server = OpenTyporaServer(
        token: 'secret',
        imageBasePath: root.path,
        localAssetPath: assets.path,
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await root.delete(recursive: true);
      });
      await server.start();
      expect(server.uri.query, 'native');
      Future<HttpClientResponse> get(String path) async =>
          (await client.getUrl(server.uri.resolve(path))).close();
      final index = await get('index.html');
      expect(index.statusCode, 200);
      expect(
        index.headers.value('Content-Security-Policy'),
        contains("connect-src 'self'"),
      );
      await index.drain<void>();
      final mode = await get('lib/codemirror/mode.js');
      expect(mode.statusCode, 200);
      expect(mode.headers.contentType?.mimeType, 'text/javascript');
      expect(await mode.transform(utf8.decoder).join(), '/* modes */');
      for (final path in [
        '../private.js',
        '%2e%2e%5cprivate.js',
        '/wrong/index.html',
        'missing.js',
      ]) {
        final response = await get(path);
        expect(response.statusCode, 404);
        await response.drain<void>();
      }
    },
  );
  test(
    'serves only scoped assets and images with token, rejects traversal',
    () async {
      final root = await Directory.systemTemp.createTemp('editor_server_');
      final base = await Directory(
        p.join(root.path, 'notes', 'daily'),
      ).create(recursive: true);
      final images = await Directory(
        p.join(root.path, 'notes', 'images'),
      ).create();
      final image = await File(
        p.join(images.path, 'a b.png'),
      ).writeAsBytes([1, 2, 3]);
      final outside = await File(
        p.join(root.path, 'private.png'),
      ).writeAsBytes([9]);
      final server = OpenTyporaServer(
        token: 'test-secret',
        imageBasePath: base.path,
        bundle: _Assets(),
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await root.delete(recursive: true);
      });
      await server.start();
      Future<HttpClientResponse> get(Uri uri) async =>
          (await client.getUrl(uri)).close();
      final response = await get(server.uri);
      expect(response.statusCode, 200);
      expect(
        await response.transform(utf8.decoder).join(),
        '<html>editor</html>',
      );
      final denied = await get(server.uri.replace(path: '/wrong/index.html'));
      expect(denied.statusCode, 404);
      await denied.drain<void>();
      final mode = await get(server.uri.resolve('lib/modes.js'));
      expect(mode.statusCode, 200);
      expect(mode.headers.contentType?.mimeType, 'text/javascript');
      expect(await mode.transform(utf8.decoder).join(), '/* modes */');
      final unmapped = await get(
        server.uri.resolve('000000000000000000000002.js'),
      );
      expect(unmapped.statusCode, 404);
      await unmapped.drain<void>();
      expect(
        (await server.resolveImage('../images/a%20b.png'))?.path,
        await image.resolveSymbolicLinks(),
      );
      expect(await server.resolveImage(outside.path), isNull);
      expect(await server.resolveImage('../../private.png'), isNull);
      expect(await server.resolveImage('../images/config.json'), isNull);
      final media = await get(
        server.uri.resolve(
          'media/test-secret/${Uri.encodeComponent('../images/a%20b.png')}',
        ),
      );
      expect(media.statusCode, 200);
      expect(media.headers.contentType?.mimeType, 'image/png');
      expect(
        await media.fold<List<int>>([], (data, chunk) => data..addAll(chunk)),
        [1, 2, 3],
      );
      server.bindDocument('another-document', base.path);
      final stale = await get(
        server.uri.resolve(
          'media/test-secret/${Uri.encodeComponent('../images/a%20b.png')}',
        ),
      );
      expect(stale.statusCode, 404);
      await stale.drain<void>();
      final current = await get(
        server.mediaBase.resolve(Uri.encodeComponent('../images/a%20b.png')),
      );
      expect(current.statusCode, 200);
      await current.drain<void>();
    },
  );
  test(
    'concurrent surfaces share immutable resources after one surface closes',
    () async {
      final assets = _Assets();
      final first = OpenTyporaServer(
        token: 'first',
        imageBasePath: '.',
        bundle: assets,
      );
      final second = OpenTyporaServer(
        token: 'second',
        imageBasePath: '.',
        bundle: assets,
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await first.close();
        await second.close();
      });
      await Future.wait([first.start(), second.start()]);
      Future<void> read(OpenTyporaServer server) async {
        final response = await (await client.getUrl(server.uri)).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      }

      await Future.wait([read(first), read(second)]);
      await first.close();
      await read(second);
      expect(assets.reads['assets/typora_editor/manifest.json'], 1);
      expect(
        assets.reads['assets/typora_editor/000000000000000000000001.html'],
        1,
      );
    },
  );
}
