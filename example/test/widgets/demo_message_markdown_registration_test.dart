import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'DemoMessageBubble registers the message Markdown instance without re-parsing',
    (tester) async {
      final parsed = Markdown.fromString('hello **world**');
      final message = UserChatMessage.preParsed(
        id: 42,
        sender: 'alice',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        body: parsed,
      );
      final selection = ChatSelectionController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: DemoMessageBubble(
                  message: message,
                  selection: selection,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final registered = selection.bodyOf(42);
      expect(registered, isNotNull);
      expect(
        identical(registered, parsed),
        isTrue,
        reason:
            'Registration must reuse the host pre-parsed Markdown; '
            'fromString in the widget would allocate a new instance.',
      );
    },
  );
}
