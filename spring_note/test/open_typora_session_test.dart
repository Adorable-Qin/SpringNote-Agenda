import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/editor/open_typora_session.dart';

void main() {
  test('synchronous host edits inside save callbacks advance the revision', () {
    final controller = TextEditingController(text: '正文');
    final session = OpenTyporaSession(
      controller: controller,
      onChanged: (text) {
        controller.value = TextEditingValue(
          text: '$text\n',
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
    );
    addTearDown(() {
      session.dispose();
      controller.dispose();
    });
    final message = {
      ...session.snapshot,
      'type': 'change',
      'sequence': 1,
      'text': '中文',
      'anchor': 2,
      'head': 2,
    };
    expect(session.accept(message), isTrue);
    expect(controller.text, '中文\n');
    expect(session.revision, 1);
    expect(session.accept({...message, 'sequence': 2}), isFalse);
    expect(controller.text, '中文\n');
  });
  test(
    'autosave echoes and selection reports preserve revision and save only changes',
    () {
      final controller = TextEditingController(text: '正文');
      final saved = <String>[];
      final session = OpenTyporaSession(
        controller: controller,
        onChanged: saved.add,
      );
      addTearDown(() {
        session.dispose();
        controller.dispose();
      });
      var notifications = 0;
      session.addListener(() => notifications++);
      Map<String, dynamic> message(String text, int sequence) => {
        ...session.snapshot,
        'type': 'change',
        'sequence': sequence,
        'text': text,
        'anchor': text.length,
        'head': text.length,
      };
      expect(session.accept(message('正文中文', 1)), isTrue);
      controller.value = controller.value.copyWith(text: '正文中文');
      expect(session.revision, 0);
      expect(notifications, 0);
      expect(
        session.accept({
          ...message('正文中文', 2),
          'type': 'selection',
          'anchor': 0,
        }),
        isTrue,
      );
      expect(saved, ['正文中文']);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(session.accept(message('obsolete', 1)), isFalse);
      controller.text = '外部更新';
      expect(session.revision, 1);
      expect(notifications, 1);
      expect(session.accept({...message('过期输入', 3), 'revision': 0}), isFalse);
      expect(controller.text, '外部更新');
    },
  );
  test('document identity, readonly and offsets are enforced', () {
    final controller = TextEditingController(text: 'a\r\n😀');
    final session = OpenTyporaSession(
      controller: controller,
      onChanged: (_) {},
    );
    addTearDown(() {
      session.dispose();
      controller.dispose();
    });
    final message = {
      ...session.snapshot,
      'type': 'change',
      'sequence': 1,
      'text': 'x',
      'anchor': 1,
      'head': 1,
    };
    expect(session.accept({...message, 'id': 'old-document'}), isFalse);
    expect(session.accept({...message, 'head': 10}), isFalse);
    session.configure(readOnly: true, dark: false, english: false);
    expect(session.accept(message), isFalse);
    expect(controller.text, 'a\r\n😀');
    expect(
      session.accept({
        ...session.snapshot,
        'type': 'selection',
        'sequence': 2,
        'anchor': 3,
        'head': 5,
      }),
      isTrue,
    );
  });
}
