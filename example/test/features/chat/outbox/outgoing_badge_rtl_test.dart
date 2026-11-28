/// The time pill and the error badge mirror with the chrome: the badge
/// sits after the time in a left-to-right chat and before it in a
/// right-to-left one.
library;

import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_error_badge.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = 'c1';

  Future<void> pumpFailed(WidgetTester tester, TextDirection direction) async {
    final server = DemoChatServer(peerDelay: Duration.zero);
    final demo = DemoOutbox(transfers: FakeOutboxTransfers(), server: server);
    addTearDown(demo.dispose);
    final source = GeneratedChatDataSource(messageCount: 0);
    final bound = demo.chat(chat);
    await bound.attach(source);
    server.script(chat, DemoServerScript.reject);
    final message = bound.sendText('failed')!;
    // The server answers on a timer.
    await tester.pump(const Duration(milliseconds: 50));
    expect(bound.isFailedAt(message.position), isTrue);
    final selection = ChatSelectionController();
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: DemoMessageBubble(
                  message: source.getMessage(message.position)!,
                  selection: selection,
                  outbox: bound,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets('the badge sits after the time in a ${direction.name} chat', (
      tester,
    ) async {
      await pumpFailed(tester, direction);

      final time = tester.getRect(find.byType(DemoMessageMeta));
      final badge = tester.getRect(find.byType(DemoErrorBadge));
      switch (direction) {
        case TextDirection.ltr:
          expect(badge.left, greaterThanOrEqualTo(time.right));
        case TextDirection.rtl:
          expect(badge.right, lessThanOrEqualTo(time.left));
      }
    });
  }
}
