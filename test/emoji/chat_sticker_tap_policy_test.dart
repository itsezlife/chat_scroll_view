import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

// The drawn sticker, 100 square, in a message cell that is wider than it.
const _sticker = Rect.fromLTWH(100, 100, 100, 100);
const _onIt = Offset(150, 150);
const _besideIt = Offset(205, 150); // 5 px outside, still in the cell
const _farOutside = Offset(400, 400);

void main() {
  group('ChatStickerTapPolicy', () {
    for (final (name, policy) in [
      ('mobile', const ChatStickerTapPolicy.mobile()),
      ('desktop', const ChatStickerTapPolicy.desktop()),
    ]) {
      group(name, () {
        test('hits the drawn sticker and nothing beside it', () {
          expect(policy.hits(_sticker, _onIt), isTrue);
          expect(policy.hits(_sticker, _besideIt), isFalse);
          expect(policy.hits(_sticker, _farOutside), isFalse);
        });

        test('the default replay tap slop is zero: the edge is the edge', () {
          expect(policy.replayTapSlop, 0);
          expect(policy.hits(_sticker, const Offset(100, 100)), isTrue);
          expect(policy.hits(_sticker, const Offset(99.9, 150)), isFalse);
        });

        test('a tap replays', () {
          expect(policy.replaysOn(ChatInlineGesture.tap), isTrue);
        });

        test('a replay tap slop outsets the hit area on every side', () {
          final slop = switch (policy) {
            ChatStickerTapPolicy$Mobile() => const ChatStickerTapPolicy.mobile(
              replayTapSlop: 8,
            ),
            ChatStickerTapPolicy$Desktop() =>
              const ChatStickerTapPolicy.desktop(replayTapSlop: 8),
          };

          expect(slop.replayTapSlop, 8);
          expect(slop.hits(_sticker, _besideIt), isTrue);
          expect(slop.hits(_sticker, const Offset(95, 95)), isTrue);
          expect(slop.hits(_sticker, const Offset(209, 150)), isFalse);
          expect(slop.hits(_sticker, _farOutside), isFalse);
        });
      });
    }

    test('mobile replays on a long press: the menu opens over a sticker '
        'that restarts', () {
      expect(
        const ChatStickerTapPolicy.mobile().replaysOn(
          ChatInlineGesture.longPress,
        ),
        isTrue,
      );
    });

    test('mobile can follow the reference that does not restart on a long '
        'press', () {
      expect(
        const ChatStickerTapPolicy.mobile(
          replaysOnLongPress: false,
        ).replaysOn(ChatInlineGesture.longPress),
        isFalse,
      );
    });

    test('desktop has no long press to replay on', () {
      expect(
        const ChatStickerTapPolicy.desktop().replaysOn(
          ChatInlineGesture.longPress,
        ),
        isFalse,
      );
    });

    test('follows the selection policy', () {
      expect(
        ChatStickerTapPolicy.of(const ChatSelectionPolicy.mobile()),
        isA<ChatStickerTapPolicy$Mobile>(),
      );
      expect(
        ChatStickerTapPolicy.of(
          const ChatSelectionPolicy.desktop(),
          replayTapSlop: 4,
        ),
        isA<ChatStickerTapPolicy$Desktop>().having(
          (p) => p.replayTapSlop,
          'replayTapSlop',
          4,
        ),
      );
    });

    test('a negative slop is rejected', () {
      expect(
        () => ChatStickerTapPolicy.mobile(replayTapSlop: -1),
        throwsAssertionError,
      );
    });
  });
}
