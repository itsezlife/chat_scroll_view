/// The chat screen over the showcase conversation: what the host does with
/// the interactions the inline layer reports, and the large-emoji setting.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

/// Global point over rendered-text `[from, to)` of block 0 of [messageId].
Offset _pointOn(
  ChatSelectionController selection,
  int messageId,
  int from,
  int to,
) {
  final surface = selection.surfaceFor(messageId)!;
  final boxes = surface.localBoxesForRange(0, from, to);
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late GeneratedChatDataSource source;
  late FakeSoftKeyboard keyboard;

  setUp(() {
    keyboard = FakeSoftKeyboard();
    source = GeneratedChatDataSource(
      messageCount: ShowcaseBodies.all.length,
      style: GeneratedMessageStyle.showcase,
    );
  });
  tearDown(() => keyboard.dispose());

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void screenTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  // A tall window, so that every message of the showcase is mounted.
  Future<ChatSelectionController> openChat(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(500, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async => source,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return tester
        .widget<ChatScrollView>(find.byType(ChatScrollView))
        .selectionController!;
  }

  Future<void> tapAndRead(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('the host handles', () {
    screenTest('a mention, a username and a hashtag', (tester) async {
      final selection = await openChat(tester);

      // Message 8: "Thanks @Ann and bob, see #release for notes".
      await tapAndRead(tester, _pointOn(selection, 8, 7, 11));
      expect(find.text('User Profile: @Ann (id 42)'), findsOneWidget);

      await tapAndRead(tester, _pointOn(selection, 8, 16, 19));
      expect(find.text('Resolving username: bob'), findsOneWidget);

      await tapAndRead(tester, _pointOn(selection, 8, 26, 34));
      expect(find.text('Search: #release'), findsOneWidget);
    });

    screenTest('an inline custom emoji', (tester) async {
      final selection = await openChat(tester);

      // Message 0: the first custom emoji follows "Launch day ".
      await tapAndRead(tester, _pointOn(selection, 0, 11, 12));

      expect(find.textContaining('Emoji pack of document:'), findsOneWidget);
    });

    screenTest('the sticker of an emoji-only message', (tester) async {
      await openChat(tester);

      // Message 10 is a lone thumbs-up.
      final sticker = find.byWidgetPredicate(
        (widget) =>
            widget is ChatEmojiBody &&
            widget.messageId == 10 &&
            widget.sticker != null,
      );
      expect(sticker, findsOneWidget);
      await tapAndRead(tester, tester.getCenter(sticker));

      expect(find.text('Sticker pack of unicode:1F44D'), findsOneWidget);
    });

    screenTest('a spoiler: a tap reveals it, with no host action', (
      tester,
    ) async {
      final selection = await openChat(tester);
      expect(selection.spoilers.isRevealed(6), isFalse);

      // Message 6: "The answer is forty-two and nothing else".
      await tapAndRead(tester, _pointOn(selection, 6, 14, 23));

      expect(selection.spoilers.isRevealed(6), isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the large-emoji setting', () {
    screenTest('turns the emoji-only bodies on and off, and is kept', (
      tester,
    ) async {
      await openChat(tester);
      expect(find.byType(ChatEmojiBody), findsNWidgets(6));

      await tester.tap(find.byTooltip('Large emoji: on'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ChatEmojiBody), findsNothing);
      expect(services.largeEmoji.enabled.value, isFalse);

      await tester.tap(find.byTooltip('Large emoji: off'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ChatEmojiBody), findsNWidgets(6));
    });
  });
}
