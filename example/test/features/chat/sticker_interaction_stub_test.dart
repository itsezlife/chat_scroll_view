/// The example's stand-in for the peer broadcast of a direct-tap sticker
/// interaction: it batches the taps the viewport reports and says what it
/// would send. Time, randomness and the timer are injected, so the debounce
/// and the offsets are checked without waiting.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_interaction_stub.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _thumb = ContentKey.unicode('\u{1F44D}');
const _heart = ContentKey.unicode('\u{2764}');
const _custom = ContentKey.document('5368');

ChatStickerActivated _tap(
  int messageId,
  int atMs, {
  ContentKey content = _thumb,
  ChatInlineGesture gesture = ChatInlineGesture.tap,
}) => ChatStickerActivated(
  messageId: messageId,
  content: content,
  gesture: gesture,
  stickerRect: const Rect.fromLTWH(10, 10, 100, 100),
  tapTime: Duration(milliseconds: atMs),
);

/// Picks the index it was told to, so the test names it.
final class _Random implements Random {
  _Random(this.picks);

  final List<int> picks;

  @override
  int nextInt(int max) => picks.removeAt(0) % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  late List<StickerBroadcast> sent;

  StickerInteractionStub stub({
    List<int> picks = const [0, 1, 2, 0, 1, 2, 0, 1, 2],
    int Function(ContentKey)? animationCount,
    bool Function()? canInteract,
  }) {
    final result = StickerInteractionStub(
      onBroadcast: sent.add,
      random: _Random([...picks]),
      animationCount:
          animationCount ?? (key) => key is ContentKey$Unicode ? 3 : 0,
      canInteract: canInteract ?? () => true,
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() => sent = []);

  Map<String, Object?> json(StickerBroadcast b) =>
      jsonDecode(b.interaction) as Map<String, Object?>;

  group('the host-owned values', () {
    test('a send debounce of 500 ms and a window of 1.0 s: the Android '
        'rhythm inside the window Desktop accepts', () {
      expect(
        StickerInteractionStub.debounce,
        const Duration(milliseconds: 500),
      );
      expect(StickerInteractionStub.window, const Duration(seconds: 1));
    });
  });

  group('one tap', () {
    testWidgets('is sent 500 ms after it, as the wire shape says', (
      tester,
    ) async {
      final s = stub(picks: [1]);

      s.onActivated(_tap(7, 1000));
      await tester.pump(const Duration(milliseconds: 499));
      expect(sent, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));

      final b = sent.single;
      expect(b.messageId, 7);
      expect(b.emoticon, '\u{1F44D}');
      expect(b.interaction, '{"v":1,"a":[{"i":2,"t":0.0}]}');
    });

    testWidgets('a long press is no interaction', (tester) async {
      final s = stub();

      s.onActivated(_tap(7, 1000, gesture: ChatInlineGesture.longPress));
      await tester.pump(const Duration(seconds: 2));

      expect(sent, isEmpty);
    });

    testWidgets('an emoji with no effect is not handled, and not sent', (
      tester,
    ) async {
      final s = stub();

      expect(s.onActivated(_tap(7, 1000, content: _custom)), isFalse);
      await tester.pump(const Duration(seconds: 2));

      expect(sent, isEmpty);
    });

    testWidgets('a tap that was handled says so', (tester) async {
      final s = stub();

      expect(s.onActivated(_tap(7, 1000)), isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a chat that cannot interact sends nothing (a group, Saved '
        'Messages, a secret chat)', (tester) async {
      final s = stub(canInteract: () => false);

      expect(s.onActivated(_tap(7, 1000)), isFalse);
      await tester.pump(const Duration(seconds: 2));

      expect(sent, isEmpty);
    });
  });

  group('a run of taps on one message', () {
    testWidgets('is one batch, offsets in seconds from the first tap', (
      tester,
    ) async {
      final s = stub(picks: [0, 2, 1]);

      s.onActivated(_tap(7, 1000));
      await tester.pump(const Duration(milliseconds: 300));
      s.onActivated(_tap(7, 1300));
      await tester.pump(const Duration(milliseconds: 250));
      s.onActivated(_tap(7, 1550));
      await tester.pump(const Duration(milliseconds: 500));

      expect(sent, hasLength(1));
      expect(json(sent.single)['a'], [
        {'i': 1, 't': 0.0},
        {'i': 3, 't': 0.3},
        {'i': 2, 't': 0.55},
      ]);
    });

    testWidgets('each tap re-arms the debounce', (tester) async {
      final s = stub();

      s.onActivated(_tap(7, 0));
      await tester.pump(const Duration(milliseconds: 400));
      s.onActivated(_tap(7, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sent, isEmpty, reason: '500 ms since the last tap has not passed');
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, hasLength(1));
    });

    testWidgets('is flushed at 1.0 s after its first tap however fast the '
        'taps keep coming: every offset stays within [0, 1] for Desktop', (
      tester,
    ) async {
      final s = stub();

      for (var t = 0; t <= 900; t += 300) {
        s.onActivated(_tap(7, t));
        await tester.pump(const Duration(milliseconds: 300));
      }
      // Taps at 0, 300, 600, 900 ms; the window closed at 1000 ms.
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, hasLength(1));
      final offsets = [
        for (final a in json(sent.single)['a']! as List) (a as Map)['t'],
      ];
      expect(offsets, [0.0, 0.3, 0.6, 0.9]);
    });

    testWidgets('a tap after the window starts a batch of its own', (
      tester,
    ) async {
      final s = stub();

      for (var t = 0; t <= 1200; t += 300) {
        s.onActivated(_tap(7, t));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(seconds: 1));

      expect(sent, hasLength(2));
      expect(
        [for (final a in json(sent.first)['a']! as List) (a as Map)['t']],
        [0.0, 0.3, 0.6, 0.9],
      );
      expect(
        [for (final a in json(sent.last)['a']! as List) (a as Map)['t']],
        [0.0],
      );
    });

    testWidgets('offsets strictly increase: a tap at the same time as the '
        'last is not added', (tester) async {
      final s = stub();

      s.onActivated(_tap(7, 1000));
      s.onActivated(_tap(7, 1000));
      await tester.pump(const Duration(seconds: 1));

      expect(json(sent.single)['a'], hasLength(1));
    });
  });

  group('taps on different messages', () {
    testWidgets('a tap on another message sends the pending batch at once', (
      tester,
    ) async {
      final s = stub();

      s.onActivated(_tap(7, 0));
      await tester.pump(const Duration(milliseconds: 100));
      s.onActivated(_tap(8, 100, content: _heart));

      expect(sent.map((b) => b.messageId), [7]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(sent.map((b) => b.messageId), [7, 8]);
      expect(sent.last.emoticon, '\u{2764}');
    });
  });

  group('dispose', () {
    testWidgets('drops a pending batch: nothing is sent after it', (
      tester,
    ) async {
      final s = stub();
      s.onActivated(_tap(7, 0));

      s.dispose();
      await tester.pump(const Duration(seconds: 2));

      expect(sent, isEmpty);
    });
  });

  test('a broadcast prints what it would send', () {
    const b = StickerBroadcast(
      messageId: 7,
      emoticon: '\u{1F44D}',
      interaction: '{"v":1,"a":[{"i":1,"t":0.0}]}',
    );

    expect(b.toString(), contains('msg_id: 7'));
    expect(b.toString(), contains('{"v":1,"a":[{"i":1,"t":0.0}]}'));
  });
}
