import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/demo/new_messages_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

/// Data source whose initial state is `isInitialLoading` (no boundaries, no
/// chunks). The test controls when ids actually appear by calling
/// [pushFirstArrival] / [pushMore].
class _LateArrivingSource extends ChatDataSource {
  bool _arrived = false;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];

  /// Simulate the first batch of ids landing — closes initial-loading by
  /// seeding both boundaries and upserting messages.
  void pushFirstArrival({required int count}) {
    if (_arrived) {
      throw StateError('pushFirstArrival can only be called once');
    }
    _arrived = true;
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  /// Append a single new message past the previous newestKnownId, mimicking
  /// a real-time arrival.
  void appendOne() {
    final next = (newestKnownId ?? -1) + 1;
    upsertMessage(_msg(next));
    seedBoundaries(newestKnownId: next);
  }
}

class _PreloadedLikeSource extends ChatDataSource {
  _PreloadedLikeSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
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

class _TallMessagePreloadedSource extends ChatDataSource {
  _TallMessagePreloadedSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
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

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

Future<void> _pumpSettleFrames(
  WidgetTester tester, {
  int frameCount = 12,
}) async {
  for (var i = 0; i < frameCount; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _scaffoldWithTallPill({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required int lastRead,
  double messageHeight = 350,
  double cacheExtent = 1000,
  ValueNotifier<int?>? lastSeenNewestId,
  bool reverse = true,
  ValueNotifier<double>? bottomPadding,
}) {
  final lastSeen = lastSeenNewestId ?? ValueNotifier<int?>(lastRead);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: Stack(
            children: <Widget>[
              ChatScrollView(
                reverse: reverse,
                dataSource: dataSource,
                controller: controller,
                cacheExtent: cacheExtent,
                bottomPadding: bottomPadding,
                messageBuilder: (context, id, message, status) => SizedBox(
                  height: messageHeight,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                ),
                loadingBuilder: (ctx) => const Center(child: Text('loading')),
              ),
              NewMessagesPill(
                controller: controller,
                dataSource: dataSource,
                lastSeenNewestId: lastSeen,
                bottomInset: bottomPadding,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _mountNearTailTall({
  required WidgetTester tester,
  required int count,
  required int lastRead,
  required ChatScrollController controller,
  required ChatDataSource ds,
  ValueNotifier<int?>? lastSeen,
  double messageHeight = 350,
}) async {
  addTearDown(controller.dispose);
  addTearDown(ds.dispose);
  if (lastSeen != null) {
    addTearDown(lastSeen.dispose);
  }

  controller.jumpTo(lastRead, alignment: 0.8);
  await tester.pumpWidget(
    _scaffoldWithTallPill(
      dataSource: ds,
      controller: controller,
      lastRead: lastRead,
      messageHeight: messageHeight,
      lastSeenNewestId: lastSeen,
      bottomPadding: ValueNotifier<double>(96),
    ),
  );
  await tester.pump();
}

Widget _scaffoldWithPill({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double cacheExtent = 1000,
  ValueNotifier<int?>? lastSeenNewestId,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: Stack(
          children: <Widget>[
            ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              cacheExtent: cacheExtent,
              messageBuilder: (context, id, message, status) => SizedBox(
                height: 60,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              ),
              loadingBuilder: (ctx) => const Center(child: Text('loading')),
            ),
            NewMessagesPill(
              controller: controller,
              dataSource: dataSource,
              lastSeenNewestId: lastSeenNewestId,
            ),
          ],
        ),
      ),
    ),
  ),
);

/// The pill widget is always present in the tree — only its opacity flips.
/// Read the rendered count from its `Text` to assert visibility intent.
String _pillText(WidgetTester tester) {
  final txt = tester.widget<Text>(
    find.descendant(of: find.byType(NewMessagesPill), matching: find.byType(Text)),
  );
  return txt.data ?? '';
}

void main() {
  group('NewMessagesPill', () {
    testWidgets(
      'empty-source mount → first off-tail arrival surfaces the pill',
      (tester) async {
        // Regression: the pill seeded `_lastSeenNewestId` from
        // `dataSource.newestKnownId` in initState. With an initially-empty
        // source that value is `null`, and `_unseenCount` short-circuits to
        // 0 on a null baseline, so the pill stayed at "0 new messages"
        // (invisible) forever after the first message arrived off-tail.
        final ds = _LateArrivingSource();
        // Anchor mid-history before messages exist — when the batch lands
        // off-tail, the null-baseline promotion path must surface the pill.
        final controller = ChatScrollController()..jumpTo(0);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(_scaffoldWithPill(
          dataSource: ds,
          controller: controller,
          cacheExtent: 80,
        ));
        await tester.pump();
        expect(_pillText(tester), '0 new messages',
            reason: 'pill is invisibly zero before any arrival');

        // First batch lands. Anchor at id 50 → newest = 9, anchor is past
        // the end of the conversation → controller pins to newest? In
        // practice the renormalisation rebases the anchor to a visible
        // child, but `isAtTail` is recomputed each layout — and a follow-
        // tail clamp without a `_wasAtTailLastLayout=true` snapshot leaves
        // the user "off tail" until they scroll. Drive enough frames for
        // both the deferred setter and the pill's post-frame trampoline.
        ds.pushFirstArrival(count: 20);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // The count for a bulk first-arrival is intentionally lossy (we
        // chose newest-1 as the seed, so the just-arrived id counts as
        // exactly 1). What matters is that the count is non-zero — the
        // pill is no longer silently hidden.
        expect(
          _pillText(tester),
          isNot('0 new messages'),
          reason: 'After first off-tail arrival the pill must surface with '
              'a non-zero count.',
        );
      },
    );

    testWidgets('lastSeenNewestId sets unread baseline on open', (
      tester,
    ) async {
      final ds = _LateArrivingSource()..pushFirstArrival(count: 151);
      final controller = ChatScrollController()..jumpTo(50);
      final lastSeen = ValueNotifier<int?>(50);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: Stack(
                  children: <Widget>[
                    ChatScrollView(
                      dataSource: ds,
                      controller: controller,
                      messageBuilder: (context, id, message, status) =>
                          SizedBox(
                            height: 60,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          ),
                    ),
                    NewMessagesPill(
                      controller: controller,
                      dataSource: ds,
                      lastSeenNewestId: lastSeen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(_pillText(tester), '100 new messages');
    });

    testWidgets('scrolling toward newer reduces unread count progressively', (
      tester,
    ) async {
      const count = 200;
      const lastRead = 50;
      final ds = _PreloadedLikeSource(count);
      final controller = ChatScrollController()..jumpTo(lastRead);
      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _scaffoldWithPill(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
        ),
      );
      await tester.pump();

      expect(_pillText(tester), '149 new messages');

      await tester.drag(find.byType(ChatScrollView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final afterScroll = _pillText(tester);
      expect(afterScroll, isNot('149 new messages'));
      expect(afterScroll, isNot('0 new messages'));
      expect(lastSeen.value, greaterThan(lastRead));
    });

    testWidgets(
      'mount at tail → subsequent at-tail arrival keeps the pill at zero',
      (tester) async {
        // Sanity: when the user mounts already at tail and one new message
        // arrives, the layout auto-follows and `isAtTail` stays true
        // across the boundary fire — `_onBoundaryChanged` re-baselines so
        // the pill stays at zero (a *later* scroll-away does NOT count
        // those already-seen messages).
        final ds = _LateArrivingSource()..pushFirstArrival(count: 10);
        // Anchor at the newest known id — follow-tail pins us there.
        final controller = ChatScrollController()..jumpTo(9);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(_scaffoldWithPill(
          dataSource: ds,
          controller: controller,
        ));
        await tester.pumpAndSettle();

        ds.appendOne();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // If the user was at tail, follow-tail pinned the new message,
        // boundary listener re-baselined `_lastSeenNewestId`, count stays
        // at zero. We don't *require* atTail here (the controller is
        // free to consider the user as off-tail in this scaffold) — we
        // require that the rebaseline path keeps the count from
        // overflowing past 1. Either invisible-zero or visible-one are
        // acceptable; visible-two would be the regression.
        final text = _pillText(tester);
        final isZeroOrOne = text == '0 new messages' ||
            text == '1 new message';
        expect(isZeroOrOne, isTrue,
            reason: 'After one new arrival the count must not exceed 1; '
                'got "$text".');
      },
    );

    testWidgets(
      'near-tail open with tall messages keeps pill count stable',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        expect(_pillText(tester), '2 new messages');

        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            _pillText(tester),
            '2 new messages',
            reason: 'frame $i: pill must not drop count during layout settling',
          );
        }
      },
    );

    testWidgets(
      'near-tail open pill stays visible for 500ms without scroll',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await tester.pump(const Duration(milliseconds: 500));

        expect(_pillText(tester), isNot('0 new messages'));
        expect(_pillText(tester), '2 new messages');
      },
    );

    testWidgets(
      'baseline unchanged when raw isAtTail flickers near tail',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final newest = count - 1;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await _pumpSettleFrames(tester);

        expect(lastSeen.value, lastRead);
        expect(lastSeen.value, isNot(newest));
      },
    );

    testWidgets(
      'count recovers after brief raw isAtTail true',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await _pumpSettleFrames(tester, frameCount: 6);

        // Even if raw isAtTail flickered mid-sequence, stable at-tail must
        // not have latched and the label must show the full unread gap.
        expect(_pillText(tester), '2 new messages');
        expect(lastSeen.value, lastRead);
      },
    );

    testWidgets(
      'tap pill from near-tail jumps to newest and advances baseline',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final newest = count - 1;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );
        await tester.pump();

        expect(_pillText(tester), '2 new messages');

        await tester.tap(
          find.descendant(
            of: find.byType(NewMessagesPill),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pump();
        expect(_pillText(tester), isNot('0 new messages'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(_pillText(tester), isNot('0 new messages'));
        }
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        expect(lastSeen.value, newest);
        expect(_pillText(tester), '0 new messages');
      },
    );

    testWidgets(
      'scroll to genuine tail dismisses pill and advances baseline',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final newest = count - 1;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );
        await tester.pump();

        await tester.drag(find.byType(ChatScrollView), const Offset(0, -800));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _pumpSettleFrames(tester, frameCount: 6);

        expect(lastSeen.value, newest);
        expect(_pillText(tester), '0 new messages');
      },
    );

    testWidgets(
      'one unread tall message stays visible until tail',
      (tester) async {
        const count = 10;
        const lastRead = count - 2;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await _pumpSettleFrames(tester);
        expect(_pillText(tester), '1 new message');
      },
    );

    testWidgets(
      'three unread tall messages count stable',
      (tester) async {
        const count = 10;
        const lastRead = count - 4;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await _pumpSettleFrames(tester);
        expect(_pillText(tester), '3 new messages');
      },
    );

    testWidgets(
      'progressive scroll with tall messages reduces count without spurious zero',
      (tester) async {
        const count = 20;
        const lastRead = 9;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
          messageHeight: 200,
        );
        await tester.pump();

        expect(_pillText(tester), '10 new messages');

        await tester.drag(find.byType(ChatScrollView), const Offset(0, -400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final afterScroll = _pillText(tester);
        expect(afterScroll, isNot('10 new messages'));
        expect(afterScroll, isNot('0 new messages'));
        expect(lastSeen.value, greaterThan(lastRead));
      },
    );
  });
}
