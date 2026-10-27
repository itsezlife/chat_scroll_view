import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _viewportWidth = 400.0;
const _viewportHeight = 400.0;
const _normalHeight = 60.0;
const _tallHeight = 900.0;
const _mediumTallHeight = 480.0;

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(Iterable<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isEmpty) return;
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
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

double _heightFor(
  int id, {
  required int tallId,
  double tallHeight = _tallHeight,
}) => id == tallId ? tallHeight : _normalHeight;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required int tallId,
  double tallHeight = _tallHeight,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: _viewportWidth,
        height: _viewportHeight,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          messageBuilder: (context, id, message, status, runLayout) {
            if (status.isAbsent) return const SizedBox.shrink();
            final h = _heightFor(id, tallId: tallId, tallHeight: tallHeight);
            return SizedBox(
              height: h,
              child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
            );
          },
        ),
      ),
    ),
  ),
);

Future<void> _pumpHarness(
  WidgetTester tester,
  ChatDataSource ds,
  ChatScrollController controller, {
  required int tallId,
  double tallHeight = _tallHeight,
}) async {
  await tester.pumpWidget(
    _harness(
      dataSource: ds,
      controller: controller,
      tallId: tallId,
      tallHeight: tallHeight,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _slowDrag(
  WidgetTester tester,
  Offset totalDelta, {
  int steps = 8,
}) async {
  final center = tester.getCenter(find.byType(ChatScrollView));
  final gesture = await tester.startGesture(center);
  final stepDelta = totalDelta / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(stepDelta);
    await tester.pump(const Duration(milliseconds: 32));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Scroll into the interior of a message taller than the viewport. Alignment
/// alone cannot move the anchor when `travel <= 0` — use programmatic scroll.
Future<void> _scrollIntoTallAnchor(
  ChatScrollController controller,
  WidgetTester tester, {
  required double delta,
}) async {
  controller.scrollBy(delta);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

({int id, double bottom, double gapToBottomEdge})? probeBottomBand(
  WidgetTester tester, {
  Iterable<int> ids = const [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
  ],
}) {
  final viewRect = tester.getRect(find.byType(ChatScrollView));
  final bottomEdge = viewRect.height;
  int? bestId;
  double? bestBottom;
  var bestGap = double.infinity;

  for (final id in ids) {
    final finder = find.text('msg-$id');
    if (finder.evaluate().isEmpty) continue;
    final msgRect = tester.getRect(finder);
    final top = msgRect.top - viewRect.top;
    final bottom = msgRect.bottom - viewRect.top;
    if (bottom <= 0 || top >= bottomEdge) continue;
    final gap = (bottom - bottomEdge).abs();
    if (gap < bestGap) {
      bestGap = gap;
      bestId = id;
      bestBottom = bottom;
    }
  }
  if (bestId == null || bestBottom == null) return null;
  return (id: bestId, bottom: bestBottom, gapToBottomEdge: bestGap);
}

void expectBandBottomStable(
  ({int id, double bottom, double gapToBottomEdge})? before,
  ({int id, double bottom, double gapToBottomEdge})? after, {
  double tolerance = 8.0,
}) {
  expect(before, isNotNull, reason: 'band before delete');
  expect(after, isNotNull, reason: 'band after delete');
  expect(
    (after!.gapToBottomEdge - before!.gapToBottomEdge).abs(),
    lessThanOrEqualTo(tolerance),
    reason: 'band gap to bottom edge should stay within $tolerance px',
  );
}

void expectAnchorNotJumpedToDistantId({
  required int beforeAnchorId,
  required int afterAnchorId,
  required int neighborId,
}) {
  expect(
    afterAnchorId,
    anyOf(
      equals(neighborId),
      equals(beforeAnchorId - 1),
      equals(beforeAnchorId + 1),
    ),
    reason:
        'anchor should stay on immediate present neighbor, not renormalize jump',
  );
  expect(afterAnchorId - neighborId, lessThan(2));
}

List<IChatMessage> _chain(int count) => [
  for (var i = 0; i < count; i++) _msg(i),
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('viewport-stable delete collapse', () {
    testWidgets('mid-scroll tall anchor delete preserves band bottom', (
      tester,
    ) async {
      const tallId = 1;
      final ds = _LoadedSource(_chain(5));
      final controller = ChatScrollController()..jumpTo(tallId, alignment: 0);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpHarness(tester, ds, controller, tallId: tallId);
      await _scrollIntoTallAnchor(controller, tester, delta: -350);
      expect(controller.anchorPixelOffset, lessThan(-50));

      final bandBefore = probeBottomBand(tester);
      expect(bandBefore, isNotNull);

      ds.removeMessages([tallId]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final bandAfter = probeBottomBand(tester);
      expectBandBottomStable(bandBefore, bandAfter);
      expectAnchorNotJumpedToDistantId(
        beforeAnchorId: tallId,
        afterAnchorId: controller.anchorMessageId,
        neighborId: tallId + 1,
      );
      expect(find.text('msg-$tallId'), findsNothing);
      expect(find.text('msg-${tallId + 1}'), findsOneWidget);
    });

    testWidgets('anchor after mid delete is next present neighbor only', (
      tester,
    ) async {
      const tallId = 1;
      final ds = _LoadedSource(_chain(6));
      final controller = ChatScrollController()..jumpTo(tallId, alignment: 0);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpHarness(tester, ds, controller, tallId: tallId);
      await _scrollIntoTallAnchor(controller, tester, delta: -350);

      ds.removeMessages([tallId]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.anchorMessageId, tallId + 1);
      expect(controller.anchorMessageId, isNot(greaterThan(tallId + 2)));
    });

    testWidgets('lower-interior tall anchor delete preserves band bottom', (
      tester,
    ) async {
      const tallId = 1;
      final ds = _LoadedSource(_chain(5));
      final controller = ChatScrollController()..jumpTo(tallId, alignment: 0);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpHarness(tester, ds, controller, tallId: tallId);
      await _scrollIntoTallAnchor(controller, tester, delta: -520);
      final bandBefore = probeBottomBand(tester);

      ds.removeMessages([tallId]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expectBandBottomStable(bandBefore, probeBottomBand(tester));
    });

    testWidgets(
      'top-of-tall anchor delete keeps zero anchor delta regression',
      (tester) async {
        const tallId = 1;
        final ds = _LoadedSource(_chain(5));
        final controller = ChatScrollController()..jumpTo(tallId, alignment: 0);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await _pumpHarness(tester, ds, controller, tallId: tallId);
        final anchorYBefore = controller.anchorPixelOffset;

        ds.removeMessages([tallId]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          (controller.anchorPixelOffset - anchorYBefore).abs(),
          lessThanOrEqualTo(0.5),
        );
        expect(controller.anchorMessageId, tallId + 1);
        expect(find.text('msg-${tallId + 1}'), findsOneWidget);
      },
    );

    testWidgets('tail-preempted mid-history delete does not pin to newest', (
      tester,
    ) async {
      const count = 20;
      const tallId = 10;
      const newest = count - 1;
      final ds = _LoadedSource(_chain(count));
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpHarness(tester, ds, controller, tallId: tallId);
      await _slowDrag(tester, const Offset(0, -280));

      controller.jumpTo(tallId, alignment: 0);
      await tester.pump();
      await _scrollIntoTallAnchor(controller, tester, delta: -350);

      final offsetBefore = controller.anchorPixelOffset;

      ds.removeMessages([tallId]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tail-pin guard: assert no full tail snap. Band-gap tolerance is relaxed
      // here — a short successor cannot preserve a below-edge gap left by a
      // tall deleted row in a small viewport.
      expect(controller.anchorMessageId, isNot(newest));
      expect(
        (controller.anchorPixelOffset - offsetBefore).abs(),
        lessThan(_tallHeight),
        reason: 'should not snap by a full tail-pin delta',
      );
      final bandAfter = probeBottomBand(
        tester,
        ids: Iterable.generate(count, (i) => i),
      );
      expect(
        bandAfter,
        isNotNull,
        reason: 'viewport should still show messages',
      );
    });

    testWidgets(
      'medium-tall anchor delete preserves band when anchor Y unchanged',
      (tester) async {
        const tallId = 1;
        final ds = _LoadedSource(_chain(5));
        final controller = ChatScrollController()..jumpTo(tallId, alignment: 0);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await _pumpHarness(
          tester,
          ds,
          controller,
          tallId: tallId,
          tallHeight: _mediumTallHeight,
        );
        await _scrollIntoTallAnchor(controller, tester, delta: -120);
        final bandBefore = probeBottomBand(tester);

        ds.removeMessages([tallId]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expectBandBottomStable(bandBefore, probeBottomBand(tester));
      },
    );
  });
}
