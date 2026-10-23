import 'package:flutter/widgets.dart';
import 'package:spring_note/core/editor/open_typora_session.dart';

// Native widgets are unavailable in flutter_test. Browser behavior is covered
// by editor/tests; this surface exercises the production Dart document bridge.
class TestEditorSurface extends StatelessWidget {
  const TestEditorSurface({super.key, required this.session});
  final OpenTyporaSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.controller,
    builder: (_, _) => Text(session.controller.text),
  );
}

int _sequence = 0;
void sendEditorChange(OpenTyporaSession session, String text) {
  session.accept({
    ...session.snapshot,
    'type': 'change',
    'sequence': ++_sequence,
    'text': text,
    'anchor': text.length,
    'head': text.length,
  });
}
