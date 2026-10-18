/// An emoji-only message gives up its selected look when selection ends.
///
/// The viewport keeps a row's `selectProgress` frozen when selection mode
/// closes (so the check rides the mode collapse instead of playing an unselect
/// animation); only `modeProgress` runs back to 0. A body that tints from
/// `selectProgress` alone therefore keeps the tint of the last message
/// unselected and of every message a `clear()` / Esc leaves behind. These
/// tests run the real `ChatScrollView` and watch the tint the desktop emoji
/// chrome paints (a `ColorFiltered` over the glyphs) through every way
/// selection can end.
///
/// The glyph recolour is the only selection paint an emoji-only body of the
/// demo owns (Android and iOS leave it to the viewport's row tint), so the
/// desktop emoji chrome stands for the body under both selection policies.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

/// One unicode emoji, which the host shows as a sticker.
final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);

/// Three unicode emoji: the text layout.
final _glyphs = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F525}')),
]);

const _first = 0;
const _second = 1;

/// How selection ends in each test: the controller call or the input that
/// reaches it.
enum _Exit { toggleLast, clear, escape }

class _Source extends ChatDataSource {
  _Source(int count) {
    upsertMessages([
      for (var i = 0; i < count; i++)
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'content $i',
        ),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetCacheScope scope;
  late ValueNotifier<LargeEmojiPolicy> largeEmoji;
  late ChatBodyHost host;
  late ChatSelectionController selection;
  late ChatScrollController scroll;

  tearDown(() {
    selection.dispose();
    scroll.dispose();
    largeEmoji.dispose();
    scope.dispose();
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    required ChatSelectionPolicy policy,
    required EmojiOnly emojiOnly,
  }) async {
    scope = AssetCacheScope(producer: FakeAssetProducer());
    largeEmoji = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    host = ChatBodyHost(assets: scope, policy: largeEmoji);
    selection = ChatSelectionController(policy: policy);
    scroll = ChatScrollController()..jumpTo(_second);
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatKeyboardShortcuts(
            controller: scroll,
            selectionController: selection,
            child: ChatScrollView(
              dataSource: _Source(2),
              controller: scroll,
              selectionController: selection,
              messageBuilder: (context, id, message, status, runLayout) =>
                  DemoEmojiMessage(
                    messageId: id,
                    emojiOnly: emojiOnly,
                    selection: selection,
                    host: host,
                    createdAt: DateTime(2026, 1, 1, 9, 5),
                    isOutgoing: false,
                    policy: const ChatEmojiPolicy.desktop(),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The recolour of the message with [id]: the filter over its glyphs.
  Finder tintOf(int id) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is DemoEmojiMessage && w.messageId == id,
    ),
    matching: find.byType(ColorFiltered),
  );

  // A real click on the message, the way the viewport's pointer sees it.
  Future<void> clickMessage(
    WidgetTester tester,
    int id, {
    required PointerDeviceKind kind,
  }) async {
    final row = find.byWidgetPredicate(
      (w) => w is DemoEmojiMessage && w.messageId == id,
    );
    // The blank end of the row, level with the body: a click on the sticker
    // itself is the sticker's own (desktop keeps it live during selection).
    final at = Offset(
      tester.view.physicalSize.width - 8,
      tester.getCenter(row).dy,
    );
    final gesture = await tester.startGesture(at, kind: kind);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> end(
    WidgetTester tester,
    _Exit how,
    PointerDeviceKind kind,
  ) async {
    switch (how) {
      case _Exit.toggleLast:
        await clickMessage(tester, _first, kind: kind);
      case _Exit.clear:
        selection.clear();
        await tester.pumpAndSettle();
      case _Exit.escape:
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
    }
  }

  for (final (name, policy, kind) in [
    (
      'desktop policy',
      const ChatSelectionPolicy.desktop(),
      PointerDeviceKind.mouse,
    ),
    (
      'mobile policy',
      const ChatSelectionPolicy.mobile(),
      PointerDeviceKind.touch,
    ),
  ]) {
    for (final (layout, emojiOnly) in [
      ('text layout', _glyphs),
      ('sticker layout', _sticker),
    ]) {
      group('$name, $layout', () {
        for (final how in _Exit.values) {
          testWidgets('drops the tint when selection ends by ${how.name}', (
            tester,
          ) async {
            await pumpChat(tester, policy: policy, emojiOnly: emojiOnly);
            expect(tintOf(_first), findsNothing);

            selection.startSelection(_first);
            await tester.pumpAndSettle();
            expect(selection.isSelected(_first), isTrue);
            expect(tintOf(_first), findsOneWidget, reason: 'selected tint');
            expect(tintOf(_second), findsNothing);

            await end(tester, how, kind);

            expect(selection.isSelectionMode, isFalse);
            expect(tintOf(_first), findsNothing, reason: 'stale tint');
          });
        }

        testWidgets('drops the tint of the last message unselected by hand '
            'while another was unselected before it', (tester) async {
          await pumpChat(tester, policy: policy, emojiOnly: emojiOnly);
          selection
            ..startSelection(_first)
            ..toggle(_second);
          await tester.pumpAndSettle();
          expect(tintOf(_first), findsOneWidget);
          expect(tintOf(_second), findsOneWidget);

          await clickMessage(tester, _second, kind: kind);
          expect(selection.isSelected(_second), isFalse);
          expect(tintOf(_second), findsNothing);
          expect(tintOf(_first), findsOneWidget, reason: 'still selected');

          await clickMessage(tester, _first, kind: kind);
          expect(selection.isSelectionMode, isFalse);
          expect(tintOf(_first), findsNothing, reason: 'the last one');
          expect(tintOf(_second), findsNothing);
        });
      });
    }
  }
}
