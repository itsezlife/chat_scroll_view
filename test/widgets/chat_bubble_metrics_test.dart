import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_bubble_metrics.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_message_theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alone = MessageRunLayout(
    isFirstInSenderRun: true,
    isLastInSenderRun: true,
  );
  const first = MessageRunLayout(
    isFirstInSenderRun: true,
    isLastInSenderRun: false,
  );
  const middle = MessageRunLayout(
    isFirstInSenderRun: false,
    isLastInSenderRun: false,
  );
  const last = MessageRunLayout(
    isFirstInSenderRun: false,
    isLastInSenderRun: true,
  );

  group('ChatMessageThemeData bubble tokens', () {
    test('defaults match Telegram-aligned values', () {
      const theme = ChatMessageThemeData.fallback;
      expect(theme.bubbleRadius, 17);
      expect(theme.cornerNearCap, 6);
      expect(theme.nearRadius, 6);
      expect(theme.mediaRadiusInset, 2);
      expect(theme.mediaLargeRadius, 15);
      expect(theme.mediaNearCap, 3);
      expect(theme.mediaNearRadius, 3);
      expect(theme.extraTextX, 2);
      expect(
        theme.bubblePadding,
        const EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
      );
    });

    test('nearRadius and media radii clamp to bubbleRadius', () {
      const theme = ChatMessageThemeData(bubbleRadius: 4);
      expect(theme.nearRadius, 4);
      expect(theme.mediaLargeRadius, 2);
      expect(theme.mediaNearRadius, 2);
      expect(theme.extraTextX, 0);
    });

    test('extraTextX steps with bubbleRadius', () {
      expect(const ChatMessageThemeData(bubbleRadius: 10).extraTextX, 0);
      expect(const ChatMessageThemeData(bubbleRadius: 11).extraTextX, 1);
      expect(const ChatMessageThemeData(bubbleRadius: 14).extraTextX, 1);
      expect(const ChatMessageThemeData(bubbleRadius: 15).extraTextX, 2);
    });

    test('copyWith and lerp preserve bubble fields', () {
      const a = ChatMessageThemeData.fallback;
      final b = a.copyWith(bubbleRadius: 10, cornerNearCap: 4);
      expect(b.bubbleRadius, 10);
      expect(b.cornerNearCap, 4);
      expect(b.nearRadius, 4);

      final mid = a.lerp(b, 0.5);
      expect(mid.bubbleRadius, closeTo(13.5, 0.001));
      expect(mid.cornerNearCap, closeTo(5, 0.001));
    });
  });

  group('ChatBubbleMetrics.bubbleBorderRadius', () {
    const theme = ChatMessageThemeData.fallback;
    final large = Radius.circular(theme.bubbleRadius);
    final near = Radius.circular(theme.nearRadius);

    test('alone: all large', () {
      for (final outgoing in [false, true]) {
        final r = ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: outgoing,
          run: alone,
        );
        expect(r.topStart, large);
        expect(r.topEnd, large);
        expect(r.bottomStart, large);
        expect(r.bottomEnd, large);
      }
    });

    test('outgoing: outer end shrinks when pinned', () {
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: true,
          run: first,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: large,
          topEnd: large,
          bottomEnd: near,
        ),
      );
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: true,
          run: middle,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: large,
          topEnd: near,
          bottomEnd: near,
        ),
      );
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: true,
          run: last,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: large,
          topEnd: near,
          bottomEnd: large,
        ),
      );
    });

    test('incoming: outer start shrinks when pinned', () {
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: false,
          run: first,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: near,
          topEnd: large,
          bottomEnd: large,
        ),
      );
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: false,
          run: middle,
        ),
        BorderRadiusDirectional.only(
          topStart: near,
          bottomStart: near,
          topEnd: large,
          bottomEnd: large,
        ),
      );
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: theme,
          outgoing: false,
          run: last,
        ),
        BorderRadiusDirectional.only(
          topStart: near,
          bottomStart: large,
          topEnd: large,
          bottomEnd: large,
        ),
      );
    });

    test('bubbleRadius 4 collapses near to large', () {
      const small = ChatMessageThemeData(bubbleRadius: 4);
      const r = Radius.circular(4);
      expect(
        ChatBubbleMetrics.bubbleBorderRadius(
          theme: small,
          outgoing: true,
          run: middle,
        ),
        const BorderRadiusDirectional.only(
          topStart: r,
          bottomStart: r,
          topEnd: r,
          bottomEnd: r,
        ),
      );
    });
  });

  group('ChatBubbleMetrics.bubbleContentPadding', () {
    const theme = ChatMessageThemeData.fallback;

    test('symmetric horizontal inset (no Telegram tail-side +6)', () {
      expect(
        ChatBubbleMetrics.bubbleContentPadding(theme: theme),
        const EdgeInsetsDirectional.fromSTEB(13, 8, 13, 8),
      );
    });

    test('low bubbleRadius drops extraTextX', () {
      const low = ChatMessageThemeData(bubbleRadius: 10);
      expect(
        ChatBubbleMetrics.bubbleContentPadding(theme: low),
        const EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
      );
    });
  });

  group('ChatBubbleMetrics.mediaContentRadius', () {
    const theme = ChatMessageThemeData.fallback;
    final large = Radius.circular(theme.mediaLargeRadius);
    final near = Radius.circular(theme.mediaNearRadius);

    test('middle outgoing uses media near on outer end', () {
      expect(
        ChatBubbleMetrics.mediaContentRadius(
          theme: theme,
          outgoing: true,
          run: middle,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: large,
          topEnd: near,
          bottomEnd: near,
        ),
      );
    });

    test('alone uses media large on all corners', () {
      expect(
        ChatBubbleMetrics.mediaContentRadius(
          theme: theme,
          outgoing: false,
          run: alone,
        ),
        BorderRadiusDirectional.only(
          topStart: large,
          bottomStart: large,
          topEnd: large,
          bottomEnd: large,
        ),
      );
    });
  });
}
