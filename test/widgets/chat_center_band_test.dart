import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

/// Preloaded `[0, count)` conversation for Center Band widget tests.
class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count) {
    if (count <= 0) return;
    upsertMessages(<IChatMessage>[
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

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    if (count <= 0) return const <IChatMessage>[];
    final lo = fromId.clamp(0, count - 1);
    final hi = toId.clamp(0, count - 1);
    return <IChatMessage>[
      for (var i = lo; i <= hi; i++)
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'content $i',
        ),
    ];
  }
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double Function(int id)? heightForId,
  double viewportHeight = 600,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: viewportHeight,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: 2000,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: heightForId?.call(id) ?? 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('ChatScrollController.centerBand', () {
    testWidgets('null before first layout; non-null after Message crosses mid-band', (
      tester,
    ) async {
      const count = 40;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      expect(controller.centerBand.value, isNull);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller),
      );
      await tester.pump();

      final band = controller.centerBand.value;
      expect(band, isNotNull);
      expect(band!.messageId, inInclusiveRange(0, count - 1));
      expect(band.offsetFromMessageTop, greaterThanOrEqualTo(0));
    });

    testWidgets('null when paint band has no Message intersection', (
      tester,
    ) async {
      // Full-height reserved insets collapse the paint band to zero height —
      // the ray has no Message rect to hit.
      const count = 20;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _PreloadedDataSource(count);
      final topPad = ValueNotifier<double>(300);
      final bottomPad = ValueNotifier<double>(300);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(topPad.dispose);
      addTearDown(bottomPad.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: ds,
                  controller: controller,
                  topPadding: topPad,
                  bottomPadding: bottomPad,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(
                        height: 60,
                        child: Text(
                          message == null ? 'shimmer-$id' : 'msg-$id',
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.centerBand.value, isNull);
    });

    testWidgets(
      'tall Message mid-bubble: offsetFromMessageTop reflects ray hit',
      (tester) async {
        const count = 8;
        const tallId = 4;
        const tallHeight = 800.0;
        const viewportHeight = 600.0;
        // Paint band is full viewport; ray at 300. Place tall top at y=0 so
        // the ray hits 300px into the bubble.
        final controller = ChatScrollController()..jumpTo(tallId);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            viewportHeight: viewportHeight,
            heightForId: (id) => id == tallId ? tallHeight : 60,
          ),
        );
        await tester.pump();

        final band = controller.centerBand.value;
        expect(band, isNotNull);
        expect(band!.messageId, tallId);
        expect(band.offsetFromMessageTop, closeTo(300, 2));
      },
    );

    testWidgets(
      'mixed heights: geometric center Message, not id midpoint',
      (tester) async {
        const count = 80;
        const tallId = 40;
        const tallHeight = 400.0;
        const shortHeight = 40.0;
        const viewportHeight = 600.0;
        // Tall row at band top: ray at 300 is inside tallId. Visible shorts
        // below push lastId well past tallId, so (firstId+lastId)/2 ≠ tallId.
        final controller = ChatScrollController()..jumpTo(tallId);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            viewportHeight: viewportHeight,
            heightForId: (id) => id == tallId ? tallHeight : shortHeight,
          ),
        );
        await tester.pump();

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        final idMidpoint = ((range!.firstId + range.lastId) / 2).round();
        expect(
          idMidpoint,
          isNot(tallId),
          reason: 'fixture must make id-midpoint differ from geometric hit',
        );

        final band = controller.centerBand.value;
        expect(band, isNotNull);
        expect(band!.messageId, tallId);
        expect(band.offsetFromMessageTop, closeTo(300, 2));
      },
    );

    testWidgets(
      'centerBand listener may call setState — deferred past layout',
      (tester) async {
        const count = 24;
        final controller = ChatScrollController();
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _CenterBandListenerProbe(
                controller: controller,
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: ChatScrollView(
                    dataSource: ds,
                    controller: controller,
                    messageBuilder:
                        (context, id, message, status, runLayout) => SizedBox(
                          height: 60,
                          child: Text(
                            message == null ? 'shimmer-$id' : 'msg-$id',
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              'External centerBand listener must be free to call setState '
              'without an explicit post-frame trampoline.',
        );
        expect(controller.centerBand.value, isNotNull);
      },
    );

    testWidgets(
      'Tier-1 animate refreshes centerBand without ChatViewportScrolled',
      (tester) async {
        // Silent Tier-1 frames (animate delta is not user-driven) must still
        // push centerBand — same publish path that runs after Anchor origin
        // renormalize without a scroll event.
        const count = 64;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await tester.pump();

        final before = controller.centerBand.value;
        expect(before, isNotNull);

        final scrolled = <ChatViewportScrolled>[];
        controller.addScrollListener((event) {
          if (event case final ChatViewportScrolled e) {
            scrolled.add(e);
          }
        });

        final animating = controller.animateTo(20, highlight: false);
        await tester.pumpAndSettle();
        await animating;

        expect(
          scrolled,
          isEmpty,
          reason: 'close-path animate must not emit ChatViewportScrolled',
        );
        final after = controller.centerBand.value;
        expect(after, isNotNull);
        expect(
          after!.messageId,
          isNot(before!.messageId),
          reason: 'centerBand must refresh on silent Tier-1 frames',
        );
      },
    );

    test('post-dispose centerBand push is a silent no-op', () {
      final controller = ChatScrollController();
      controller.dispose();
      expect(
        () => controller.centerBand = const ChatCenterBand(
          messageId: 1,
          offsetFromMessageTop: 12,
        ),
        returnsNormally,
      );
      expect(controller.centerBand.value, isNull);
    });

    test('ChatCenterBand equality is value-based', () {
      const a = ChatCenterBand(messageId: 7, offsetFromMessageTop: 12.5);
      const b = ChatCenterBand(messageId: 7, offsetFromMessageTop: 12.5);
      const c = ChatCenterBand(messageId: 8, offsetFromMessageTop: 12.5);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ChatScrollController.jumpToCenterBand', () {
    testWidgets(
      'places center-band ray at message top + offsetFromMessageTop',
      (tester) async {
        const count = 8;
        const tallId = 4;
        const tallHeight = 800.0;
        const viewportHeight = 600.0;
        const targetOffset = 300.0;
        final controller = ChatScrollController()..jumpTo(0);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            viewportHeight: viewportHeight,
            heightForId: (id) => id == tallId ? tallHeight : 60,
          ),
        );
        await tester.pump();

        controller.jumpToCenterBand(tallId, targetOffset);
        await tester.pumpAndSettle();

        final band = controller.centerBand.value;
        expect(band, isNotNull);
        expect(band!.messageId, tallId);
        expect(band.offsetFromMessageTop, closeTo(targetOffset, 2));
      },
    );

    testWidgets(
      'round-trip: observe → leave → apply restores within tolerance '
      '(tall mid-bubble)',
      (tester) async {
        const count = 80;
        const tallId = 40;
        const tallHeight = 800.0;
        const viewportHeight = 600.0;
        final controller = ChatScrollController()..jumpTo(tallId);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            viewportHeight: viewportHeight,
            heightForId: (id) => id == tallId ? tallHeight : 60,
          ),
        );
        await tester.pump();

        final saved = controller.centerBand.value;
        expect(saved, isNotNull);
        expect(saved!.messageId, tallId);
        expect(saved.offsetFromMessageTop, closeTo(300, 2));

        controller.jumpTo(count - 1);
        await tester.pumpAndSettle();
        expect(
          controller.centerBand.value?.messageId,
          isNot(tallId),
          reason: 'must leave the tall mid-bubble before restore',
        );

        controller.jumpToCenterBand(
          saved.messageId,
          saved.offsetFromMessageTop,
        );
        await tester.pumpAndSettle();

        final restored = controller.centerBand.value;
        expect(restored, isNotNull);
        expect(restored!.messageId, saved.messageId);
        expect(
          restored.offsetFromMessageTop,
          closeTo(saved.offsetFromMessageTop, 2),
        );
      },
    );

    testWidgets(
      'absent target completes without assuming a visible row',
      (tester) async {
        const count = 20;
        // Past known newest — same clamp path as jumpTo (ADR 002 caution:
        // complete without error; do not assume a visible row at that id).
        const absentId = 1_000_001;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await tester.pump();

        expect(
          () => controller.jumpToCenterBand(absentId, 40),
          returnsNormally,
        );
        await tester.pumpAndSettle();

        expect(controller.centerBand.value?.messageId, isNot(absentId));
        expect(find.text('msg-$absentId'), findsNothing);
      },
    );

    testWidgets(
      'emits ChatProgrammaticJump like jumpTo',
      (tester) async {
        const count = 40;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await tester.pump();

        final jumps = <int>[];
        final events = <ChatScrollEvent>[];
        controller
          ..addJumpListener(jumps.add)
          ..addScrollListener(events.add);

        controller.jumpToCenterBand(10, 20);
        await tester.pump();

        expect(jumps, <int>[10]);
        expect(
          events.whereType<ChatProgrammaticJump>().map((e) => e.targetId),
          <int>[10],
        );
      },
    );

    test('post-dispose jumpToCenterBand is a silent no-op', () {
      final controller = ChatScrollController()..jumpTo(5);
      controller.dispose();
      expect(() => controller.jumpToCenterBand(5, 12), returnsNormally);
      expect(controller.anchorMessageId, 5);
    });
  });
}

class _CenterBandListenerProbe extends StatefulWidget {
  const _CenterBandListenerProbe({
    required this.controller,
    required this.child,
  });

  final ChatScrollController controller;
  final Widget child;

  @override
  State<_CenterBandListenerProbe> createState() =>
      _CenterBandListenerProbeState();
}

class _CenterBandListenerProbeState extends State<_CenterBandListenerProbe> {
  ChatCenterBand? _band;

  @override
  void initState() {
    super.initState();
    widget.controller.centerBand.addListener(_onChange);
  }

  void _onChange() {
    setState(() => _band = widget.controller.centerBand.value);
  }

  @override
  void dispose() {
    widget.controller.centerBand.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text('band: ${_band?.messageId}'),
      Expanded(child: widget.child),
    ],
  );
}
