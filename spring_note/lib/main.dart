import 'dart:async';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/editor/editor_runtime.dart';
import 'core/services/desktop_window_controller.dart';
import 'core/services/indexed_note_service.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(EditorRuntime.prewarm());
  await DesktopWindowController.initializeAndShow();
  await RustLib.init();
  runApp(const SpringNoteApp(noteService: IndexedNoteService()));
}
