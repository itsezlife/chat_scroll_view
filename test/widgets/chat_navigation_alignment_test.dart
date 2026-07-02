import 'dart:async';

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Newest chunk loaded; older pages fetch on demand. [releasePendingFetches]
/// unblocks in-flight [fetchRange] calls so tests can observe the skeleton
/// window before messages land.
class _GatedLazyTailDataSource extends ChatDataSource {
  _GatedLazyTailDataSource({
    required this.totalCount,
    required this.loadedFromId,
  }) {
    seedBoundaries(newestKnownId: totalCount - 1, reachedNewest: true);
    for (var i = loadedFromId; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(oldestKnownId: loadedFromId);
  }

  final int totalCount;
  final int loadedFromId;
  final List<Completer<void>> _pendingGates = [];
  bool _releaseFetches = false;

  void releasePendingFetches() {
    _releaseFetches = true;
    for (final gate in _pendingGates) {
      if (!gate.isCompleted) gate.complete();
    }
    _pendingGates.clear();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    if (!_releaseFetches) {
      final gate = Completer<void>();
      _pendingGates.add(gate);
      await gate.future;
    }
    final lo = fromId.clamp(0, totalCount - 1);
    final hi = toId.clamp(0, totalCount - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;
const _messageHeight = 60.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double bottomPadding = 0,
  double topPadding = 0,
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
          bottomPadding: ValueNotifier<double>(bottomPadding),
          topPadding: ValueNotifier<double>(topPadding),
          messageBuilder: (context, id, message, status) => SizedBox(
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
          bottomPadding: bottomPadding,
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
          topPadding: topPadding,
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
          topPadding: topPadding,
          bottomPadding: bottomPadding,
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
          topPadding: topPadding,
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
        _harness(dataSource: ds, controller: controller, bottomPadding: 96),
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
      expect(controller.navigationAlignment, 0.0);
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

    testWidgets('animateTo alignment 0.5 applies after unloaded target loads', (
      tester,
    ) async {
      const total = 200;
      const loadedFrom = 192;
      const target = 50;
      const shimmerHeight = 40.0;
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
                  messageBuilder: (context, id, message, status) => SizedBox(
                    height: message == null ? shimmerHeight : loadedHeight,
                    child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await future;
      await tester.pump();

      expect(find.text('shimmer-$target'), findsOneWidget);
      expect(controller.navigationAlignment, 0.5);
      expect(
        controller.anchorPixelOffset,
        isNot(
          closeTo(
            _expectedAlignedTop(
              viewportHeight: _viewportHeight,
              bottomPadding: 0,
              messageHeight: loadedHeight,
              alignment: 0.5,
            ),
            1,
          ),
        ),
        reason: 'shimmer height must not satisfy final centered alignment',
      );

      ds.releasePendingFetches();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final expectedEnd = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: loadedHeight,
        alignment: 0.5,
      );
      expect(find.text('msg-$target'), findsOneWidget);
      expect(controller.anchorMessageId, target);
      expect(controller.anchorPixelOffset, closeTo(expectedEnd, 1));
    });
  });
}
