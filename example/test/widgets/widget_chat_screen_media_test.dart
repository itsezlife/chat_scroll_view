/// The chat screen's media wiring: the per-chat media state above the
/// list (spoilers hide again when the chat is opened again) and the viewer
/// a tap on a picture opens under a chrome text root.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_media_messages.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat_list/view/chat_list_screen.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_ui/mpx_ui.dart' show MediaViewer;

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

final class _Source extends ChatDataSource {
  _Source(List<IChatMessage> messages) {
    messages.forEach(upsertMessage);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

_Source _chat() => _Source([
  for (final (id, template) in [
    DemoMediaMessage(
      parts: [
        (descriptor: DemoPhotos.lagoon.descriptor, kind: null, spoiler: true),
      ],
    ),
    DemoMediaMessage(
      parts: [
        (descriptor: DemoPhotos.harbour.descriptor, kind: null, spoiler: false),
      ],
    ),
  ].indexed)
    template.toMessage(id: id, sender: 'Alice', time: DateTime.utc(2026)),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late FakeSoftKeyboard keyboard;

  setUp(() => keyboard = FakeSoftKeyboard());
  tearDown(() => keyboard.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openChat(WidgetTester tester) async {
    await tester.tap(find.byKey(ChatListScreen.tileKey(0)));
    await settle(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(500, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        start: DemoStart.chatList,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async => _chat(),
      ),
    );
    await tester.pump();
    await openChat(tester);
  }

  const spoiler = MediaItemId('0.0');
  const photo = MediaItemId('1.0');
  Finder cellOf(MediaItemId id) => find.byKey(ValueKey(id));

  MessageMediaState stateOf(WidgetTester tester) =>
      MessageMediaStateScope.of(tester.element(cellOf(photo)));

  testWidgets('a revealed spoiler is hidden again when the chat is opened '
      'again', (tester) async {
    await pumpApp(tester);
    expect(cellOf(spoiler), findsOneWidget);
    expect(stateOf(tester).isSpoilerRevealed(spoiler), isFalse);

    await tester.tap(cellOf(spoiler));
    await settle(tester);
    expect(stateOf(tester).isSpoilerRevealed(spoiler), isTrue);

    Navigator.of(tester.element(find.byType(ChatScrollView))).pop();
    await settle(tester);
    expect(find.byType(ChatScrollView), findsNothing);
    await openChat(tester);

    expect(stateOf(tester).isSpoilerRevealed(spoiler), isFalse);
  });

  testWidgets('a tap on a picture opens the viewer on it, under a chrome text '
      'root', (tester) async {
    await pumpApp(tester);

    await tester.tapAt(
      tester.getRect(cellOf(photo)).topLeft + const Offset(10, 10),
    );
    await settle(tester);

    final viewer = find.byType(MediaViewer);
    expect(viewer, findsOneWidget);
    expect(tester.widget<MediaViewer>(viewer).initialIndex, 0);
    expect(
      find.ancestor(of: viewer, matching: find.byType(ChromeTextRoot)),
      findsWidgets,
    );
    expect(tester.widget<MediaViewer>(viewer).source.count, 1);
  });
}
