import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show ChannelController, InternalChannelController;
import 'package:path/path.dart' as p;
import 'open_typora_server.dart';

/// One browser environment per application. Individual documents own their
/// WebViews, but must not destroy an environment still used by another section.
class EditorRuntime {
  static Future<WebViewEnvironment?>? _environment;

  static Future<WebViewEnvironment?> environment() =>
      _environment ??= _createEnvironment().catchError((Object error) {
        _environment = null;
        throw error;
      });

  static Future<void> prewarm() async {
    // Warm the shared environment and assets. Windows 0.6.0 does not transfer
    // headlessWebViewId into its native texture: using it leaves a blank visible
    // browser while JavaScript still addresses the hidden browser. AppShell's
    // mounted notebook prepares its real view while the home page is visible.
    await Future.wait([
      environment().then<void>((_) {}).catchError((Object _) {}),
      OpenTyporaServer.prewarm().catchError((Object _) {}),
    ]);
  }

  static Future<WebViewEnvironment?> _createEnvironment() async {
    if (!Platform.isWindows) return null;
    if (await WebViewEnvironment.getAvailableVersion() == null) {
      throw StateError('Microsoft Edge WebView2 Runtime is required');
    }
    final profile = Directory(
      p.join(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
        'SpringNote',
        'editor-webview',
      ),
    );
    await profile.create(recursive: true);
    final environment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: profile.path),
    );
    // Pinned Windows plugin 0.6.0 binds the factory ID instead of the instance ID.
    final channel = environment.platform as ChannelController;
    final handler = channel.handler;
    channel.disposeChannel();
    channel.channel = MethodChannel(
      'com.pichillilorenzo/flutter_webview_environment_${environment.id}',
    );
    channel.handler = handler;
    channel.initMethodCallHandler();
    return environment;
  }
}
