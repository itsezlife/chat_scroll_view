import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/navigation_placement.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count) {
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

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Newest chunk loaded; older ids stay cold until [loadTargetWindow].
class _GatedLazyTailDataSource extends ChatDataSource {
  _GatedLazyTailDataSource({
    required this.totalCount,
    required this.loadedFromId,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: totalCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = loadedFromId; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int totalCount;
  final int loadedFromId;

  void loadTargetWindow({required int aroundId, int radius = 32}) {
    final lo = (aroundId - radius).clamp(0, totalCount - 1);
    final hi = (aroundId + radius).clamp(0, totalCount - 1);
    for (var i = lo; i <= hi; i++) {
      upsertMessage(_msg(i));
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;
const _messageHeight = 60.0;

/// A reserved inset that never changes.
ValueListenable<double> _fixedInset(double value) =>
    AlwaysStoppedAnimation<double>(value);

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ValueListenable<double> bottomPadding = const AlwaysStoppedAnimation(0),
  ValueListenable<double> topPadding = const AlwaysStoppedAnimation(0),
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: _viewportWidth,
        height: _viewportHeight,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          bottomPadding: bottomPadding,
          topPadding: topPadding,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: _messageHeight,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

double _expectedAlignedTop({
  required double viewportHeight,
  required double bottomPadding,
  required double messageHeight,
  required double alignment,
  double topPadding = 0,
}) {
  final travel = viewportHeight - topPadding - bottomPadding - messageHeight;
  if (travel <= 0) return topPadding;
  return topPadding + alignment * travel;
}

/// Per-frame monotonicity tolerance (sub-pixel rounding on high-DPI).
const _monotonicityTolerance = 0.5;

/// Samples [controller.anchorPixelOffset] across close-path [animateTo] frames.
/// Sign convention: distance to [expectedEndOffset] must not increase between
/// consecutive samples (approaches destination monotonically).
Future<List<double>> sampleAnimateToOffsets(
  WidgetTester tester,
  ChatScrollController controller, {
  required int targetId,
  required Duration duration,
  required double alignment,
  int frameCount = 16,
}) async {
  final samples = <double>[];
  final future = controller.animateTo(
    targetId,
    duration: duration,
    alignment: alignment,
    highlight: false,
  );
  await tester.pump();
  for (var i = 0; i < frameCount; i++) {
    samples.add(controller.anchorPixelOffset);
    await tester.pump(const Duration(milliseconds: 16));
  }
  final remaining = (duration.inMilliseconds ~/ 16) + 4;
  for (var i = 0; i < remaining; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await future;
  samples.add(controller.anchorPixelOffset);
  return samples;
}

void expectMonotonicApproachTo({
  required List<double> samples,
  required double expectedEndOffset,
}) {
  expect(samples.length, greaterThan(1));
  for (var i = 1; i < samples.length; i++) {
    final prevDist = (samples[i - 1] - expectedEndOffset).abs();
    final currDist = (samples[i] - expectedEndOffset).abs();
    expect(
      currDist,
      lessThanOrEqualTo(prevDist + _monotonicityTolerance),
      reason:
          'frame $i: offset ${samples[i]} moved away from end '
          '$expectedEndOffset (prev=${samples[i - 1]})',
    );
  }
}

void main() {
  group('navigation alignment', () {
    testWidgets('jumpTo alignment 0 keeps message top at viewport top', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, 50);
      expect(controller.anchorPixelOffset, closeTo(0, 1));
    });

    testWidgets('jumpTo alignment 0.5 centers message in scroll band', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorMessageId, 50);
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0.5 respects bottom inset', (tester) async {
      const count = 100;
      const bottomPadding = 96.0;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          bottomPadding: _fixedInset(bottomPadding),
        ),
      );
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: bottomPadding,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0.5 respects top inset', (tester) async {
      const count = 100;
      const topPadding = 56.0;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          topPadding: _fixedInset(topPadding),
        ),
      );
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        topPadding: topPadding,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0.5 respects top and bottom inset', (
      tester,
    ) async {
      const count = 100;
      const topPadding = 56.0;
      const bottomPadding = 96.0;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          topPadding: _fixedInset(topPadding),
          bottomPadding: _fixedInset(bottomPadding),
        ),
      );
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0 places message below top inset', (
      tester,
    ) async {
      const count = 100;
      const topPadding = 48.0;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50, alignment: 0);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          topPadding: _fixedInset(topPadding),
        ),
      );
      await tester.pump();

      expect(controller.anchorPixelOffset, closeTo(topPadding, 1));
    });

    testWidgets('jumpTo alignment 0.5 near oldest clamps via oldest pin', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(0, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, 0);
      expect(controller.anchorPixelOffset, closeTo(0, 1));
    });

    testWidgets('jumpTo newest ignores alignment in favor of tail pin', (
      tester,
    ) async {
      const count = 100;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(newest, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          bottomPadding: _fixedInset(96),
        ),
      );
      await tester.pump();

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('animateTo alignment 0.5 settles at centered offset', (
      tester,
    ) async {
      const count = 256;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      const targetId = 120;
      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await future;

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorMessageId, targetId);
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('animateTo alignment 0.5 scroll up moves monotonically', (
      tester,
    ) async {
      const count = 256;
      const targetId = 120;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final expectedEnd = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      final samples = await sampleAnimateToOffsets(
        tester,
        controller,
        targetId: targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
      );
      expectMonotonicApproachTo(
        samples: samples,
        expectedEndOffset: expectedEnd,
      );
      expect(controller.anchorMessageId, targetId);
      expect(controller.anchorPixelOffset, closeTo(expectedEnd, 1));
      expect(
        controller.navigationPlacement,
        const AlignmentPlacement(
          messageId: targetId,
          alignment: 0.5,
          isHeld: true,
        ),
      );
    });

    testWidgets('animateTo alignment 0 scroll up moves monotonically', (
      tester,
    ) async {
      const count = 256;
      const targetId = 120;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      const expectedEnd = 0.0;
      final samples = await sampleAnimateToOffsets(
        tester,
        controller,
        targetId: targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 0,
      );
      expectMonotonicApproachTo(
        samples: samples,
        expectedEndOffset: expectedEnd,
      );
      expect(controller.anchorPixelOffset, closeTo(expectedEnd, 1));
    });

    testWidgets('animateTo alignment 1.0 scroll up moves monotonically', (
      tester,
    ) async {
      const count = 256;
      const targetId = 120;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final expectedEnd = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 1,
      );
      final samples = await sampleAnimateToOffsets(
        tester,
        controller,
        targetId: targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 1,
      );
      expectMonotonicApproachTo(
        samples: samples,
        expectedEndOffset: expectedEnd,
      );
      expect(controller.anchorPixelOffset, closeTo(expectedEnd, 1));
    });

    testWidgets('animateTo newest scroll down moves monotonically', (
      tester,
    ) async {
      const count = 256;
      const startId = 80;
      const targetId = 200;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(startId);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final expectedEnd = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      final samples = await sampleAnimateToOffsets(
        tester,
        controller,
        targetId: targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
      );
      expectMonotonicApproachTo(
        samples: samples,
        expectedEndOffset: expectedEnd,
      );
      expect(controller.anchorMessageId, targetId);
      expect(controller.anchorPixelOffset, closeTo(expectedEnd, 1));
    });

    testWidgets('animateTo survives layout during animation', (tester) async {
      const count = 512;
      const targetId = 40;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count - 20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final expectedEnd = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      final samples = await sampleAnimateToOffsets(
        tester,
        controller,
        targetId: targetId,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
        frameCount: 24,
      );
      expectMonotonicApproachTo(
        samples: samples,
        expectedEndOffset: expectedEnd,
      );
      expect(controller.anchorMessageId, targetId);
    });

    testWidgets('animateTo alignment 0.5 applies after load-gate readiness', (
      tester,
    ) async {
      const total = 200;
      const loadedFrom = 192;
      const target = 50;
      const loadedHeight = 200.0;
      final controller = ChatScrollController()..jumpTo(total - 1);
      final ds = _GatedLazyTailDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _viewportWidth,
                height: _viewportHeight,
                child: ChatScrollView(
                  reverse: true,
                  dataSource: ds,
                  controller: controller,
                  cacheExtent: 2000,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(
                        height: message == null ? 40.0 : loadedHeight,
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
      await tester.pump(const Duration(milliseconds: 200));

      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        alignment: 0.5,
        highlight: false,
      );
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        controller.navigationPlacement,
        const AlignmentPlacement(messageId: target, alignment: 0.5),
      );
      expect(controller.anchorMessageId, isNot(target));

      ds.loadTargetWindow(aroundId: target);
      await tester.pump();
      var done = false;
      unawaited(future.whenComplete(() => done = true));
      for (var i = 0; i < 400 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: 'animateTo did not finish after readiness');
      await future;
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Load-gate contract: land on the real destination row, not a shimmer.
      // Exact band Y after tall settle may still correct on a later layout;
      // issue 01 only requires no shimmer-stitch completion.
      expect(find.text('msg-$target'), findsOneWidget);
      expect(find.text('shimmer-$target'), findsNothing);
      expect(controller.anchorMessageId, target);
    });
  });

  group('alignment hold', () {
    const count = 100;
    const grownTopInset = 56.0;

    late _PreloadedDataSource ds;
    late ChatScrollController controller;
    late ValueNotifier<double> topInset;
    late ValueNotifier<double> bottomInset;

    setUp(() {
      ds = _PreloadedDataSource(count);
      controller = ChatScrollController();
      topInset = ValueNotifier<double>(0);
      bottomInset = ValueNotifier<double>(0);
    });

    tearDown(() {
      controller.dispose();
      ds.dispose();
      topInset.dispose();
      bottomInset.dispose();
    });

    Future<void> mount(WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          topPadding: topInset,
          bottomPadding: bottomInset,
        ),
      );
      await tester.pump();
    }

    double rowTop(WidgetTester tester, int id) =>
        tester.getTopLeft(find.text('msg-$id')).dy -
        tester.getTopLeft(find.byType(ChatScrollView)).dy;

    double rowBottom(WidgetTester tester, int id) =>
        tester.getBottomLeft(find.text('msg-$id')).dy -
        tester.getTopLeft(find.byType(ChatScrollView)).dy;

    Future<void> growTopInset(WidgetTester tester) async {
      topInset.value = grownTopInset;
      await tester.pump();
    }

    testWidgets('a top inset change re-applies alignment 0 to the target', (
      tester,
    ) async {
      controller.jumpTo(50);
      await mount(tester);
      expect(rowTop(tester, 50), 0);

      await growTopInset(tester);

      expect(rowTop(tester, 50), grownTopInset);
    });

    testWidgets('a top inset change re-applies a fractional alignment', (
      tester,
    ) async {
      controller.jumpTo(50, alignment: 0.5);
      await mount(tester);

      await growTopInset(tester);

      expect(
        rowTop(tester, 50),
        _expectedAlignedTop(
          viewportHeight: _viewportHeight,
          topPadding: grownTopInset,
          bottomPadding: 0,
          messageHeight: _messageHeight,
          alignment: 0.5,
        ),
      );
    });

    testWidgets('the hold survives unrelated layouts until a trigger', (
      tester,
    ) async {
      controller.jumpTo(50);
      await mount(tester);
      await tester.pump(const Duration(seconds: 1));

      await growTopInset(tester);
      topInset.value = 24;
      await tester.pump();

      expect(rowTop(tester, 50), 24);
    });

    testWidgets('a drag releases the hold', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      final top = rowTop(tester, 50);

      await growTopInset(tester);

      expect(rowTop(tester, 50), top);
    });

    testWidgets('a fling releases the hold', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 120),
        1000,
      );
      await tester.pumpAndSettle();
      final anchorId = controller.anchorMessageId;
      final top = rowTop(tester, anchorId);

      await growTopInset(tester);

      expect(rowTop(tester, anchorId), top);
    });

    testWidgets('a wheel scroll releases the hold', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(ChatScrollView));
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pump();
      final top = rowTop(tester, 50);
      expect(top, isNot(0));

      await growTopInset(tester);

      expect(rowTop(tester, 50), top);
    });

    testWidgets('scrollBy releases the hold', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      controller.scrollBy(30);
      await tester.pump();
      expect(rowTop(tester, 50), 30);

      await growTopInset(tester);

      expect(rowTop(tester, 50), 30);
    });

    testWidgets('a scrollbar drag releases the hold, including the jumps it '
        'makes', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      const scrollbarStrip = Offset(_viewportWidth - 10, 80);
      final origin = tester.getTopLeft(find.byType(ChatScrollView));
      final gesture = await tester.startGesture(
        origin + scrollbarStrip,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final anchorId = controller.anchorMessageId;
      expect(anchorId, isNot(50));
      final top = rowTop(tester, anchorId);

      await growTopInset(tester);

      expect(rowTop(tester, anchorId), top);
    });

    testWidgets('another jumpTo moves the hold to its target', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      controller.jumpTo(30, alignment: 0.5);
      await tester.pump();

      await growTopInset(tester);

      expect(
        rowTop(tester, 30),
        _expectedAlignedTop(
          viewportHeight: _viewportHeight,
          topPadding: grownTopInset,
          bottomPadding: 0,
          messageHeight: _messageHeight,
          alignment: 0.5,
        ),
      );
      expect(find.text('msg-50'), findsNothing);
    });

    testWidgets('animateTo replaces the hold with its own settled alignment', (
      tester,
    ) async {
      controller.jumpTo(50);
      await mount(tester);
      final future = controller.animateTo(48, alignment: 0.5, highlight: false);
      await tester.pumpAndSettle();
      await future;

      await growTopInset(tester);

      expect(
        rowTop(tester, 48),
        _expectedAlignedTop(
          viewportHeight: _viewportHeight,
          topPadding: grownTopInset,
          bottomPadding: 0,
          messageHeight: _messageHeight,
          alignment: 0.5,
        ),
      );
    });

    testWidgets('a far-path animateTo holds its alignment after the stitch', (
      tester,
    ) async {
      controller.jumpTo(10);
      await mount(tester);
      expect(find.text('msg-80'), findsNothing);
      final future = controller.animateTo(80, alignment: 0.5, highlight: false);
      await tester.pumpAndSettle();
      await future;
      expect(
        controller.navigationPlacement,
        const AlignmentPlacement(messageId: 80, alignment: 0.5, isHeld: true),
      );

      await growTopInset(tester);

      expect(
        rowTop(tester, 80),
        _expectedAlignedTop(
          viewportHeight: _viewportHeight,
          topPadding: grownTopInset,
          bottomPadding: 0,
          messageHeight: _messageHeight,
          alignment: 0.5,
        ),
      );
    });

    testWidgets('a held Center Band placement is re-placed on a top inset '
        'change', (tester) async {
      const offsetFromMessageTop = 20.0;
      double rayOffsetTop(double topInset) =>
          topInset + (_viewportHeight - topInset) / 2 - offsetFromMessageTop;
      controller.jumpToCenterBand(50, offsetFromMessageTop);
      await mount(tester);
      expect(rowTop(tester, 50), rayOffsetTop(0));

      await growTopInset(tester);

      expect(rowTop(tester, 50), rayOffsetTop(grownTopInset));
    });

    testWidgets('jumpToCenterBand replaces the hold with its own placement', (
      tester,
    ) async {
      controller.jumpTo(50);
      await mount(tester);
      controller.jumpToCenterBand(30, 20);
      await tester.pump();

      await growTopInset(tester);

      expect(
        controller.centerBand.value,
        const ChatCenterBand(messageId: 30, offsetFromMessageTop: 20),
      );
    });

    testWidgets('the target becoming absent releases the hold', (tester) async {
      controller.jumpTo(50);
      await mount(tester);
      ds.removeMessages(<int>[50]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final top = rowTop(tester, 51);

      await growTopInset(tester);

      expect(find.text('msg-50'), findsNothing);
      expect(rowTop(tester, 51), top);
    });

    testWidgets('a bottom inset change is compensated, not re-aligned', (
      tester,
    ) async {
      controller.jumpTo(50);
      await mount(tester);

      bottomInset.value = 100;
      await tester.pump();
      await tester.pump();

      expect(rowTop(tester, 50), -100);
    });

    testWidgets('jump to the newest keeps the tail pin under a top inset '
        'change', (tester) async {
      controller.jumpTo(count - 1);
      await mount(tester);

      await growTopInset(tester);

      expect(rowBottom(tester, count - 1), _viewportHeight);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('following the tail releases the hold', (tester) async {
      // Rows 90–99 fill the band exactly: the target sits at the band top
      // and the newest at the band bottom.
      controller.jumpTo(90);
      await mount(tester);
      expect(rowTop(tester, 90), 0);
      expect(controller.isAtTail.value, isTrue);

      ds.insertMessage(_msg(count));
      await tester.pump();
      expect(rowBottom(tester, count), _viewportHeight);

      await growTopInset(tester);

      expect(rowBottom(tester, count), _viewportHeight);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('pixelOffset seats the target below the band top and the '
        'hold re-applies it after a top inset change', (tester) async {
      const offset = 39.0;
      controller.jumpTo(50, pixelOffset: offset);
      await mount(tester);
      expect(rowTop(tester, 50), offset);
      expect(
        controller.navigationPlacement,
        const AlignmentPlacement(
          messageId: 50,
          alignment: 0,
          pixelOffset: offset,
          isHeld: true,
        ),
      );

      await growTopInset(tester);

      expect(rowTop(tester, 50), grownTopInset + offset);
    });
  });
}
