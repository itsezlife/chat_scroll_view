// ignore_for_file: unused_element_parameter

import 'dart:async' show unawaited;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

/// Messages per calendar day for day-chrome stitch fixtures.
const int _perDay = 8;

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

/// Same as [_msg] but spaced across calendar days for separator / floating-date
/// assertions (`i ~/ _perDay` maps to day-of-month starting at 1).
IChatMessage _dayMsg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
  updatedAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
  content: 'content $i',
);

int _calendarDayOf(int messageId) => 1 + messageId ~/ _perDay;

/// Separator finder label matching [dateSeparatorBuilder] (handles month rollover).
String _sepLabel(int messageId) {
  final date = _dayMsg(messageId).createdAt;
  return 'sep-${date.month}-${date.day}';
}

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(int count) {
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

  /// Test-only: mark [id] confirmed-absent without [removeMessages] (no
  /// [RemoveBatchMutation]) so presence-pin false-Absent paths can be probed.
  void markAbsentWithoutRemoveMutation(int id) {
    final chunk = chunks[ChatScrollChunk.chunkOf(id)];
    if (chunk == null) return;
    final slot = id - chunk.firstId;
    chunk.messages[slot] = null;
    if (!chunk.isAbsentSlot(slot)) {
      chunk.markAbsentSlot(slot);
    }
    notifyDataChanged();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

class _GrowingDataSource extends ChatDataSource {
  _GrowingDataSource(int initialCount) {
    for (var i = 0; i < initialCount; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: initialCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    _newestId = initialCount - 1;
  }

  int _newestId = -1;

  void appendOne() {
    final next = _newestId + 1;
    upsertMessage(_msg(next));
    seedBoundaries(newestKnownId: next, reachedNewest: true);
    _newestId = next;
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const double _viewportHeight = 600;
const double _composerInset = 96;
const double _keyboardInset = 346;

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double cacheExtent = 400,
  bool dateSeparators = false,
  double Function(int id)? messageHeight,
  ValueListenable<double>? bottomPadding,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: _viewportHeight,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: cacheExtent,
          bottomPadding: bottomPadding,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: messageHeight?.call(id) ?? 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
          dateSeparatorBuilder: dateSeparators
              ? (context, bucket, date) => SizedBox(
                  height: 24,
                  child: Text('sep-${date.month}-${date.day}'),
                )
              : null,
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject(find.byType(ChatScrollView)) as RenderChatScrollView;

/// Drive [animateFuture] with a hard pump budget — never bare-await, never
/// pumpAndSettle (stitch/ticker can keep scheduling frames).
Future<void> _driveAnimate(
  WidgetTester tester,
  Future<void> animateFuture, {
  int maxPumps = 200,
}) async {
  await tester.pump();
  var done = false;
  unawaited(animateFuture.whenComplete(() => done = true));
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'animateTo did not finish in $maxPumps pumps');
  await animateFuture;
}

/// Pump stitch frames until [predicate] matches in-flight progress, or fail.
Future<void> _pumpWhileStitching(
  WidgetTester tester,
  Future<void> animateFuture, {
  required bool Function(RenderChatScrollView render) predicate,
  int maxPumps = 200,
}) async {
  await tester.pump();
  var done = false;
  unawaited(animateFuture.whenComplete(() => done = true));
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final render = _render(tester);
    if (render.debugFarAnimateActive && predicate(render)) {
      return;
    }
  }
  fail('stitch predicate not met before settle ($maxPumps pumps)');
}

/// Ramp [inset] while pumping stitch frames; assert a message stays visible.
Future<void> _rampInsetDuringStitch(
  WidgetTester tester,
  Future<void> animateFuture,
  ValueNotifier<double> inset, {
  required double from,
  required double to,
  int steps = 8,
  int maxPumps = 200,
}) async {
  final stepDelta = (to - from) / steps;
  await tester.pump();
  var done = false;
  unawaited(animateFuture.whenComplete(() => done = true));
  for (var step = 0; step <= steps && !done; step++) {
    inset.value = from + stepDelta * step;
    await tester.pump(const Duration(milliseconds: 16));
    final render = _render(tester);
    expect(
      find.textContaining('msg-'),
      findsWidgets,
      reason:
          'bottomPadding=${inset.value.toStringAsFixed(1)} must not blank band',
    );
    if (render.debugFarAnimateActive && render.debugStitchMeasured) {
      expect(
        render.debugBuiltMessagesIntersectScrollBand(),
        isTrue,
        reason:
            'bottomPadding=${inset.value.toStringAsFixed(1)} scroll band must '
            'intersect built rows in paint space during measured stitch',
      );
    }
  }
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'preferBuilt after near-tail insert uses close path (no stitch)',
    (tester) async {
      const initial = 20;
      final ds = _GrowingDataSource(initial);
      final controller = ChatScrollController()..jumpTo(initial - 1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();

      ds.appendOne();
      await tester.pump();

      final future = controller.animateTo(
        ds.newestKnownId!,
        highlight: false,
        duration: const Duration(milliseconds: 120),
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
      );
      await tester.pump();
      expect(
        _render(tester).debugFarAnimateActive,
        isFalse,
        reason: 'newest is built nearby — close path, not stitch',
      );
      expect(_render(tester).debugPreferBuiltWaiting, isFalse);

      await _driveAnimate(tester, future);
    },
  );

  testWidgets('stitch mid-flight keeps outgoing ids pinned', (tester) async {
    const count = 256;
    final controller = ChatScrollController()..jumpTo(count ~/ 2);
    final ds = _PreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
    );
    await tester.pump();

    final beforeIds = _render(tester).debugBuiltMessageIds.toSet();
    expect(beforeIds, isNotEmpty);
    expect(
      beforeIds.contains(0),
      isFalse,
      reason: 'fixture must leave target unbuilt so stitch (not close) runs',
    );

    final future = controller.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final render = _render(tester);
    expect(render.debugFarAnimateActive, isTrue);
    expect(render.debugStitchOutgoingIds, isNotEmpty);
    expect(render.debugStitchOutgoingIds.intersection(beforeIds), isNotEmpty);
    // Outgoing strip must still be mounted for dual-translate paint.
    expect(
      render.debugStitchOutgoingIds.intersection(
        render.debugBuiltMessageIds.toSet(),
      ),
      equals(render.debugStitchOutgoingIds),
    );
    expect(render.debugStitchProgress, lessThan(1.0));
    expect(render.debugStitchScrollLength, greaterThan(100));

    await _driveAnimate(tester, future);
    expect(_render(tester).debugFarAnimateActive, isFalse);
    expect(_render(tester).debugStitchOutgoingIds, isEmpty);
  });

  testWidgets(
    'explicit delete of stitch target cancels animate and clears stitch',
    (tester) async {
      const count = 256;
      const target = 0;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
      );
      await tester.pump();

      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final mid = _render(tester);
      expect(mid.debugFarAnimateActive, isTrue);
      expect(mid.debugIsAnimating, isTrue);
      expect(mid.debugStitchOutgoingIds, isNotEmpty);
      final originBeforeDelete = controller.anchorMessageId;

      ds.removeMessages([target]);
      await tester.pump();

      final after = _render(tester);
      expect(after.debugIsAnimating, isFalse);
      expect(after.debugFarAnimateActive, isFalse);
      expect(after.debugStitchOutgoingIds, isEmpty);
      // No soft-retarget into a blank stitch band — animate settled cancelled.
      expect(controller.anchorMessageId, isNot(target));
      // Origin should remain a present row (delete-collapse of neighbors is OK
      // after cancel; the forbidden case is mid-flight soft retarget of target).
      expect(ds.getMessage(controller.anchorMessageId), isNotNull);
      expect(originBeforeDelete, isNotNull);

      await future;
    },
  );

  testWidgets('explicit delete of outgoing strip id cancels stitch', (
    tester,
  ) async {
    const count = 256;
    final controller = ChatScrollController()..jumpTo(count ~/ 2);
    final ds = _PreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
    );
    await tester.pump();

    final future = controller.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final mid = _render(tester);
    expect(mid.debugFarAnimateActive, isTrue);
    final outgoing = mid.debugStitchOutgoingIds;
    expect(outgoing, isNotEmpty);
    final doomed = outgoing.first;

    ds.removeMessages([doomed]);
    await tester.pump();

    final after = _render(tester);
    expect(after.debugIsAnimating, isFalse);
    expect(after.debugFarAnimateActive, isFalse);
    expect(after.debugStitchOutgoingIds, isEmpty);

    await future;
  });

  testWidgets(
    'stitch target stays built mid-flight (not treated absent / GC-dropped)',
    (tester) async {
      const count = 256;
      const target = 0;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          // Tight cache so GC pressure is real without dropping stitch pins.
          cacheExtent: 200,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));

      final mid = _render(tester);
      expect(mid.debugFarAnimateActive, isTrue);
      expect(mid.debugStitchOutgoingIds, isNotEmpty);
      // Presence pin: target + full outgoing strip remain built.
      expect(mid.debugBuiltMessageIds.contains(target), isTrue);
      expect(
        mid.debugStitchOutgoingIds.difference(mid.debugBuiltMessageIds),
        isEmpty,
      );
      // Soft-retarget forbidden while target is still present.
      expect(controller.anchorMessageId, target);
      expect(ds.getMessage(target), isNotNull);

      await _driveAnimate(tester, future);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets('false Absent on stitch target does not blank the flight', (
    tester,
  ) async {
    const count = 256;
    const target = 0;
    final controller = ChatScrollController()..jumpTo(count ~/ 2);
    final ds = _PreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
    );
    await tester.pump();

    final future = controller.animateTo(
      target,
      duration: const Duration(milliseconds: 800),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_render(tester).debugFarAnimateActive, isTrue);
    expect(controller.anchorMessageId, target);

    // Mark absent without RemoveBatchMutation (false Absent / non-cancel path).
    ds.markAbsentWithoutRemoveMutation(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final mid = _render(tester);
    expect(
      mid.debugIsAnimating,
      isTrue,
      reason: 'false Absent must not cancel — only explicit remove does',
    );
    expect(mid.debugFarAnimateActive, isTrue);
    expect(
      mid.debugBuiltMessageIds.contains(target),
      isTrue,
      reason: 'presence pin keeps target built despite false Absent',
    );
    // Fan-out must still build destination neighbors — not abort on Absent
    // anchor and leave only GC ghosts (blank incoming band).
    expect(
      mid.debugBuiltMessageIds.length,
      greaterThan(mid.debugStitchOutgoingIds.length + 1),
      reason: 'incoming/destination rows must keep building mid-flight',
    );
    expect(controller.anchorMessageId, target);
    expect(find.text('msg-$target'), findsOneWidget);

    await _driveAnimate(tester, future, maxPumps: 400);
  });

  testWidgets('immediate into unloaded range still completes', (tester) async {
    const count = 64;
    final controller = ChatScrollController()..jumpTo(count - 1);
    final ds = _PreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
    );
    await tester.pump();

    final future = controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await _driveAnimate(tester, future);
    expect(controller.anchorMessageId, 0);
    expect(_render(tester).debugFarAnimateActive, isFalse);
  });

  testWidgets(
    'unready destination waits then stitches after load (no shimmer-stitch)',
    (tester) async {
      const total = 200;
      const loadedFrom = 192;
      const target = 10;
      final controller = ChatScrollController()..jumpTo(total - 1);
      final ds = _GatedColdTargetDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final originId = controller.anchorMessageId;
      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final waiting = _render(tester);
      expect(
        waiting.debugLoadGateWaiting,
        isTrue,
        reason: 'unready target must stay in load-gate',
      );
      expect(waiting.debugFarAnimateActive, isFalse);
      expect(controller.anchorMessageId, originId);
      expect(find.text('shimmer-$target'), findsNothing);

      ds.releaseTargetWindow(aroundId: target);
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        _render(tester).debugLoadGateWaiting,
        isFalse,
        reason: 'path selection after readiness',
      );
      await _driveAnimate(tester, future, maxPumps: 400);

      expect(controller.anchorMessageId, target);
      expect(find.text('msg-$target'), findsOneWidget);
      expect(find.text('shimmer-$target'), findsNothing);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'explicit delete of target during load-gate wait cancels animate',
    (tester) async {
      const total = 200;
      const loadedFrom = 192;
      const target = 10;
      final controller = ChatScrollController()..jumpTo(total - 1);
      final ds = _GatedColdTargetDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(_render(tester).debugLoadGateWaiting, isTrue);
      expect(_render(tester).debugIsAnimating, isTrue);

      // Target may still be unloaded; stage removal after releasing a stub row
      // so removeMessages has a known id in span.
      ds.releaseTargetWindow(aroundId: target);
      await tester.pump();
      expect(ds.getMessage(target), isNotNull);
      ds.removeMessages([target]);
      await tester.pump();

      expect(_render(tester).debugIsAnimating, isFalse);
      expect(_render(tester).debugLoadGateWaiting, isFalse);
      expect(_render(tester).debugFarAnimateActive, isFalse);

      await future;
    },
  );

  testWidgets('load-gate destination-window fetch unblocks cold animateTo', (
    tester,
  ) async {
    const total = 200;
    const loadedFrom = 192;
    const target = 10;
    final controller = ChatScrollController()..jumpTo(total - 1);
    final ds = _FetchRecordingTailDataSource(
      totalCount: total,
      loadedFromId: loadedFrom,
    );
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final future = controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await tester.pump();
    // Post-frame destination fetch + settle.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      ds.fetchRequests,
      isNotEmpty,
      reason: 'load-gate must request a destination window',
    );
    final covering = ds.fetchRequests.any(
      (r) => r.fromId <= target && r.toId >= target,
    );
    expect(covering, isTrue);
    // Destination window is target ±1 chunk (3 chunks); gap fill would span
    // many more chunks between origin (~chunk 3) and target (~chunk 0).
    const radius = ChatChunkFetchScheduler.destinationWindowRadiusChunks;
    const windowWidth = 2 * radius;
    expect(
      ds.fetchRequests.any((r) {
        final span =
            ChatScrollChunk.chunkOf(r.toId) - ChatScrollChunk.chunkOf(r.fromId);
        return span > windowWidth;
      }),
      isFalse,
      reason: 'must not gap-fill origin…target',
    );

    await _driveAnimate(tester, future, maxPumps: 400);
    expect(controller.anchorMessageId, target);
    expect(find.text('msg-$target'), findsOneWidget);
  });

  testWidgets(
    'cold unloaded newest after multi-chunk history lands on real messages',
    (tester) async {
      // Multi-chunk history; jump away then drop newest window to force cold tail.
      const total = 1280; // 20 chunks × 64
      const newest = total - 1;
      final controller = ChatScrollController()..jumpTo(newest);
      final ds = _FetchRecordingFullDataSource(totalCount: total);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Scroll deep into history so LRU drops the cold newest.
      controller.jumpTo(0);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Drop newest window so destination is unloaded for load-gate animateTo.
      final newestChunk = ChatScrollChunk.chunkOf(newest);
      for (var ci = newestChunk - 1; ci <= newestChunk + 1; ci++) {
        ds.chunks.remove(ci);
      }
      expect(
        ds.getMessage(newest),
        isNull,
        reason: 'newest must be cold after multi-chunk LRU unload',
      );

      ds.fetchRequests.clear();
      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 200),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(ds.fetchRequests, isNotEmpty);
      const radius = ChatChunkFetchScheduler.destinationWindowRadiusChunks;
      const windowWidth = 2 * radius;
      expect(
        ds.fetchRequests.any((r) {
          final span =
              ChatScrollChunk.chunkOf(r.toId) -
              ChatScrollChunk.chunkOf(r.fromId);
          return span > windowWidth;
        }),
        isFalse,
        reason: 'load-gate must not contiguous-fill origin…target',
      );
      expect(
        ds.fetchRequests.any((r) => r.fromId <= newest && r.toId >= newest),
        isTrue,
      );

      await _driveAnimate(tester, future, maxPumps: 500);

      expect(
        controller.anchorMessageId,
        newest,
        reason: 'must not soft-retarget the navigation target away from newest',
      );
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(find.text('shimmer-$newest'), findsNothing);
      expect(
        find.textContaining('msg-'),
        findsWidgets,
        reason: 'landing band must be real messages, not a blank hole',
      );
    },
  );

  testWidgets(
    'preferBuilt cold newest after inserts+scroll-away lands without blank band',
    (tester) async {
      const initial = 64;
      final ds = _FetchRecordingGrowingDataSource(initial);
      final controller = ChatScrollController()..jumpTo(initial - 1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
      );
      await tester.pump();

      // Many inserts grow the newest across several chunks.
      for (var i = 0; i < 900; i++) {
        ds.appendOne();
      }
      await tester.pump();
      final newest = ds.newestKnownId!;
      expect(newest, greaterThan(800));

      controller.jumpTo(0);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final newestChunk = ChatScrollChunk.chunkOf(newest);
      for (var ci = newestChunk - 1; ci <= newestChunk + 1; ci++) {
        ds.chunks.remove(ci);
      }
      expect(ds.getMessage(newest), isNull);

      ds.fetchRequests.clear();
      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 200),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
      );
      await _driveAnimate(tester, future, maxPumps: 500);

      expect(controller.anchorMessageId, newest);
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(find.text('shimmer-$newest'), findsNothing);
      const radius = ChatChunkFetchScheduler.destinationWindowRadiusChunks;
      const windowWidth = 2 * radius;
      expect(
        ds.fetchRequests.any((r) {
          final span =
              ChatScrollChunk.chunkOf(r.toId) -
              ChatScrollChunk.chunkOf(r.fromId);
          return span > windowWidth;
        }),
        isFalse,
        reason: 'must not gap-storm during cold-newest navigation',
      );
    },
  );

  testWidgets('scroll-to-newest recovers sent-past-seed messages after LRU', (
    tester,
  ) async {
    // Mirrors CommentsDataSource: seeded history + sendMessage past the seed;
    // fetchRange must re-serve overrides after engine LRU drops the tail.
    const seedCount = 64;
    final ds = _SeedPlusSentTailDataSource(seedCount: seedCount);
    final controller = ChatScrollController()..jumpTo(seedCount - 1);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 400),
    );
    await tester.pump();

    for (var i = 0; i < 10; i++) {
      ds.sendPastSeed();
    }
    await tester.pump();
    final newest = ds.newestKnownId!;
    expect(newest, seedCount + 9);

    controller.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final newestChunk = ChatScrollChunk.chunkOf(newest);
    for (var ci = newestChunk - 1; ci <= newestChunk + 1; ci++) {
      ds.chunks.remove(ci);
    }
    expect(ds.getMessage(newest), isNull);

    final future = controller.animateTo(
      newest,
      duration: const Duration(milliseconds: 200),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.preferBuilt,
    );
    await _driveAnimate(tester, future, maxPumps: 500);

    expect(controller.anchorMessageId, newest);
    expect(find.text('msg-$newest'), findsOneWidget);
    expect(find.text('shimmer-$newest'), findsNothing);
  });

  testWidgets('floating date tracks destination-visible content mid-stitch', (
    tester,
  ) async {
    const count = 256;
    const originId = 8; // day 2 — room for a startsDay strip at origin
    const targetId = 200; // day 26
    final originDay = _calendarDayOf(originId);
    final targetDay = _calendarDayOf(targetId);

    final controller = ChatScrollController()..jumpTo(originId);
    final ds = _DayPreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(
        dataSource: ds,
        controller: controller,
        cacheExtent: 8000,
        dateSeparators: true,
      ),
    );
    await tester.pump();

    final before = _render(tester);
    expect(before.debugHasFloatingHeader, isTrue);
    expect(before.debugHeaderDate?.day, originDay);

    final future = controller.animateTo(
      targetId,
      duration: const Duration(milliseconds: 800),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );

    // Toward-newer: early flight still paint-shows the outgoing strip at the
    // top — header stays on the origin day (not a fake mid-gap day).
    await _pumpWhileStitching(
      tester,
      future,
      predicate: (r) =>
          r.debugStitchProgress < 0.2 && r.debugStitchScrollLength > 0,
    );
    final early = _render(tester);
    expect(early.debugFarAnimateActive, isTrue);
    expect(early.debugHeaderDate?.day, originDay);

    // Later, destination-band rows are paint-visible at the top — chrome
    // updates before settle from built visible content only.
    await _pumpWhileStitching(
      tester,
      future,
      predicate: (r) =>
          r.debugStitchProgress > 0.55 && r.debugStitchProgress < 1.0,
    );
    final mid = _render(tester);
    expect(mid.debugFarAnimateActive, isTrue);
    expect(
      mid.debugHeaderDate,
      isNotNull,
      reason: 'floating date must update during stitch, not only at settle',
    );
    expect(
      mid.debugHeaderDate!.day,
      isNot(originDay),
      reason: 'floating date must leave the origin day before settle',
    );
    expect(
      mid.debugHeaderDate!.day,
      greaterThan(originDay),
      reason: 'toward-newer stitch should reveal destination-side days',
    );
    final builtDays = {
      for (final id in mid.debugBuiltMessageIds) _dayMsg(id).createdAt.day,
    };
    expect(
      builtDays.contains(mid.debugHeaderDate!.day),
      isTrue,
      reason: 'no invented mid-gap day during stitch',
    );

    await _driveAnimate(tester, future);
    expect(_render(tester).debugHeaderDate?.day, targetDay);
  });

  testWidgets('startsDay separators ride outgoing and incoming stitch strips', (
    tester,
  ) async {
    const count = 256;
    const originId = 8;
    const targetId = 200;

    final controller = ChatScrollController()..jumpTo(originId);
    final ds = _DayPreloadedDataSource(count);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);

    await tester.pumpWidget(
      _scaffold(
        dataSource: ds,
        controller: controller,
        cacheExtent: 8000,
        dateSeparators: true,
      ),
    );
    await tester.pump();

    final future = controller.animateTo(
      targetId,
      duration: const Duration(milliseconds: 800),
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.immediate,
    );
    await _pumpWhileStitching(
      tester,
      future,
      predicate: (r) =>
          r.debugStitchProgress > 0.1 &&
          r.debugStitchProgress < 0.9 &&
          r.debugStitchOutgoingIds.isNotEmpty,
    );

    final mid = _render(tester);
    expect(mid.debugFarAnimateActive, isTrue);
    final outgoingStartsDay = mid.debugStitchOutgoingIds
        .where(mid.debugStartsDay)
        .toList();
    expect(
      outgoingStartsDay,
      isNotEmpty,
      reason: 'origin strip should include at least one startsDay row',
    );
    for (final id in outgoingStartsDay) {
      expect(
        find.text(_sepLabel(id)),
        findsWidgets,
        reason: 'outgoing startsDay separator must stay built mid-stitch',
      );
    }

    final incomingStartsDay = mid.debugBuiltMessageIds
        .difference(mid.debugStitchOutgoingIds)
        .where(mid.debugStartsDay)
        .toList();
    expect(
      incomingStartsDay,
      isNotEmpty,
      reason: 'destination band should include startsDay after teleport',
    );
    for (final id in incomingStartsDay) {
      expect(
        find.text(_sepLabel(id)),
        findsWidgets,
        reason: 'incoming startsDay separator must ride stitch paint',
      );
    }
    final participating = [...outgoingStartsDay, ...incomingStartsDay];
    expect(
      participating.any((id) => (mid.debugDividerOpacity(id) ?? 0) > 0),
      isTrue,
      reason: 'at least one stitch startsDay separator must keep paint opacity',
    );

    await _driveAnimate(tester, future);
  });

  testWidgets(
    'tall on-screen neighbor uses close path not stitch',
    (tester) async {
      // Scroll mid-tall-body so the previous tall row still intersects the
      // paint band (Telegram found → smoothScrollBy), even when |offset| > 2400.
      const count = 30;
      const originId = 20;
      const targetId = 19;
      const tallHeight = 3000.0;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 8000,
          messageHeight: (id) =>
              id == originId || id == targetId ? tallHeight : 60.0,
        ),
      );
      await tester.pump();

      // Pull older content into view so targetId peeks into the band.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _render(tester).debugBuiltMessageIds.contains(targetId),
        isTrue,
        reason: 'fixture must keep target built after drag',
      );

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 300),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        _render(tester).debugFarAnimateActive,
        isFalse,
        reason: 'band-intersecting tall neighbor must not stitch',
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
    },
  );

  testWidgets(
    'tall outgoing toward newer uses full-strip travel (not viewport*4 cap)',
    (tester) async {
      const count = 256;
      const originId = 40;
      const targetId = 240;
      // Larger than viewport*4 so a product band-cap would truncate travel.
      const tallHeight = _viewportHeight * 4 + 400;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 8000,
          messageHeight: (id) => id == originId ? tallHeight : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.05 &&
            r.debugStitchProgress < 0.95 &&
            r.debugStitchScrollLength > 0,
      );

      final mid = _render(tester);
      expect(mid.debugFarAnimateActive, isTrue);
      expect(
        mid.debugStitchScrollLength,
        greaterThan(_viewportHeight * 4),
        reason:
            'Telegram full-strip travel must include tall outgoing extent; '
            'must not clamp to viewport*4 for product reasons',
      );
      expect(
        mid.debugBuiltMessageIds.contains(targetId),
        isTrue,
        reason: 'destination must stay built mid-flight (no blank band)',
      );
      expect(find.text('msg-$targetId'), findsOneWidget);

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
      expect(find.text('shimmer-$targetId'), findsNothing);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'gap-span origin placeholder handoffs to close path (not multi-vh stitch)',
    (tester) async {
      const count = 200;
      const targetId = count - 1;
      const gapSpanHeight = _viewportHeight * 10;

      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 400,
          messageHeight: (id) => id == 0 ? gapSpanHeight : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 400),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
      );
      await _driveAnimate(tester, future, maxPumps: 400);

      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'gap-span origin defers stitch measure until destination row is built',
    (tester) async {
      const total = 1280;
      const newest = total - 1;
      const gapSpanHeight = _viewportHeight * 10;

      final controller = ChatScrollController()..jumpTo(0);
      final ds = _FetchRecordingFullDataSource(totalCount: total);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 400,
          messageHeight: (id) => id == 0 ? gapSpanHeight : 60.0,
        ),
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final newestChunk = ChatScrollChunk.chunkOf(newest);
      for (var ci = newestChunk - 1; ci <= newestChunk + 1; ci++) {
        ds.chunks.remove(ci);
      }
      expect(ds.getMessage(newest), isNull);

      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 400),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
      );

      double? firstMeasureScrollLen;
      var done = false;
      unawaited(future.whenComplete(() => done = true));
      var sawJumped = false;
      for (var i = 0; i < 500 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final render = _render(tester);
        if (render.debugFarAnimateJumped) sawJumped = true;
        if (render.debugFarAnimateJumped && !render.debugStitchMeasured) {
          expect(
            find.textContaining('msg-'),
            findsWidgets,
            reason: 'pre-measure stitch must keep outgoing rows in band',
          );
        }
        if (firstMeasureScrollLen == null && render.debugStitchMeasured) {
          firstMeasureScrollLen = render.debugStitchScrollLength;
        }
      }

      expect(
        sawJumped,
        isTrue,
        reason: 'cold newest from gap-span origin must use stitch path',
      );

      expect(
        firstMeasureScrollLen,
        isNotNull,
        reason: 'stitch must eventually measure after destination builds',
      );
      expect(
        firstMeasureScrollLen!,
        greaterThan(100),
        reason:
            'first measure must use full-strip travel, not scrollLen≈1 stub',
      );
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(find.text('shimmer-$newest'), findsNothing);
      await future;
    },
  );

  testWidgets(
    'tail stitch keeps messages visible when keyboard opens mid-flight',
    (tester) async {
      const count = 256;
      const newest = count - 1;
      final inset = ValueNotifier<double>(_composerInset);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.1 &&
            r.debugStitchProgress < 0.9 &&
            r.debugStitchMeasured,
      );

      await _rampInsetDuringStitch(
        tester,
        future,
        inset,
        from: _composerInset,
        to: _keyboardInset,
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, newest);
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'tail stitch commit pins newest after keyboard opens mid-flight',
    (tester) async {
      const count = 256;
      const newest = count - 1;
      const messageHeight = 60.0;
      final inset = ValueNotifier<double>(_composerInset);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.1 &&
            r.debugStitchProgress < 0.9 &&
            r.debugStitchMeasured,
      );

      await _rampInsetDuringStitch(
        tester,
        future,
        inset,
        from: _composerInset,
        to: _keyboardInset,
      );

      await _driveAnimate(tester, future, maxPumps: 300);

      final render = _render(tester);
      final newestTop = render.debugLayoutTop(newest);
      final bottomEdge = _viewportHeight - render.debugBottomPad;
      expect(newestTop, isNotNull);
      expect(
        newestTop! + messageHeight,
        closeTo(bottomEdge, 1.0),
        reason:
            'stitch commit must bake inset compensation — newest bottom on '
            'bottomEdge without waiting for a follow-up pinNewest layout',
      );
      expect(controller.anchorPixelOffset, closeTo(newestTop, 0.5));
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(render.debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'tail stitch keeps messages visible when keyboard opens post-jump pre-measure',
    (tester) async {
      const count = 256;
      const newest = count - 1;
      final inset = ValueNotifier<double>(_composerInset);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      // Jump runs synchronously in animateTo; layout (and measure) has not.
      expect(_render(tester).debugFarAnimateJumped, isTrue);
      expect(_render(tester).debugStitchMeasured, isFalse);
      inset.value = _keyboardInset;
      await tester.pump();
      expect(
        find.textContaining('msg-'),
        findsWidgets,
        reason: 'post-jump pre-measure inset must not blank the band',
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, newest);
      expect(find.text('msg-$newest'), findsOneWidget);
    },
  );

  testWidgets(
    'tail stitch keeps messages visible when keyboard closes mid-flight',
    (tester) async {
      const count = 256;
      const newest = count - 1;
      final inset = ValueNotifier<double>(_keyboardInset);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        newest,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.1 &&
            r.debugStitchProgress < 0.9 &&
            r.debugStitchMeasured,
      );

      await _rampInsetDuringStitch(
        tester,
        future,
        inset,
        from: _keyboardInset,
        to: _composerInset,
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, newest);
      expect(find.text('msg-$newest'), findsOneWidget);
    },
  );

  testWidgets(
    'mid-history stitch keeps messages visible when keyboard opens mid-flight',
    (tester) async {
      const count = 256;
      const originId = 232;
      const targetId = 157;
      final inset = ValueNotifier<double>(_composerInset);
      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
          messageHeight: (id) => id == originId ? 400.0 : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        alignment: 0.5,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.1 &&
            r.debugStitchProgress < 0.9 &&
            r.debugStitchMeasured,
      );

      final mid = _render(tester);
      expect(mid.debugFarAnimateActive, isTrue);
      expect(
        mid.debugBuiltMessageIds.length,
        greaterThanOrEqualTo(3),
        reason: 'toward-older stitch must capture multiple outgoing rows',
      );

      await _rampInsetDuringStitch(
        tester,
        future,
        inset,
        from: _composerInset,
        to: _keyboardInset,
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'mid-history stitch keeps messages visible when keyboard closes mid-flight',
    (tester) async {
      const count = 256;
      const originId = 232;
      const targetId = 157;
      final inset = ValueNotifier<double>(_keyboardInset);
      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          bottomPadding: inset,
          messageHeight: (id) => id == originId ? 400.0 : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        alignment: 0.5,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.1 &&
            r.debugStitchProgress < 0.9 &&
            r.debugStitchMeasured,
      );

      await _rampInsetDuringStitch(
        tester,
        future,
        inset,
        from: _keyboardInset,
        to: _composerInset,
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
      expect(_render(tester).debugFarAnimateActive, isFalse);
    },
  );

  testWidgets(
    'tall incoming toward older uses full-strip travel (not viewport*4 cap)',
    (tester) async {
      const count = 256;
      const originId = 220;
      const targetId = 10;
      const tallHeight = _viewportHeight * 4 + 400;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 8000,
          messageHeight: (id) => id == targetId ? tallHeight : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) =>
            r.debugStitchProgress > 0.05 &&
            r.debugStitchProgress < 0.95 &&
            r.debugStitchScrollLength > 0,
      );

      final mid = _render(tester);
      expect(mid.debugFarAnimateActive, isTrue);
      expect(
        mid.debugStitchScrollLength,
        greaterThan(_viewportHeight * 4),
        reason:
            'Telegram full-strip travel must include tall incoming extent; '
            'must not clamp to viewport*4 for product reasons',
      );
      expect(mid.debugBuiltMessageIds.contains(targetId), isTrue);
      expect(find.text('msg-$targetId'), findsOneWidget);

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
      expect(find.text('shimmer-$targetId'), findsNothing);
    },
  );

  testWidgets(
    'tall close land keeps newer neighbor built for reverse close hop',
    (tester) async {
      // Repro docs/broken-logs First: after landing on a tall older row,
      // the newer neighbor must stay built so reverse animateTo uses close
      // (not stitch notBuilt).
      const count = 40;
      const newerId = 20;
      const tallerOlderId = 19;
      const tallHeight = 3000.0;

      final controller = ChatScrollController()..jumpTo(newerId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          // Small cache so tall older alone overshoots lowerBound (like prod).
          cacheExtent: 200,
          messageHeight: (id) => id == tallerOlderId ? tallHeight : 60.0,
        ),
      );
      await tester.pump();

      // Bring taller older into the paint band (Telegram found → close).
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _render(tester).debugBuiltMessageIds.contains(tallerOlderId),
        isTrue,
        reason: 'fixture must keep tall older built after drag',
      );

      final toOlder = controller.animateTo(
        tallerOlderId,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
        highlight: false,
      );
      expect(
        _render(tester).debugFarAnimateActive,
        isFalse,
        reason: 'older tall neighbor from newer seat uses close path',
      );
      await _driveAnimate(tester, toOlder, maxPumps: 300);

      expect(controller.anchorMessageId, tallerOlderId);
      expect(
        _render(tester).debugBuiltMessageIds.contains(newerId),
        isTrue,
        reason: 'newer neighbor must survive tall-anchor fan-out',
      );

      final toNewer = controller.animateTo(
        newerId,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
        highlight: false,
      );
      await tester.pump();
      expect(
        _render(tester).debugFarAnimateActive,
        isFalse,
        reason: 'reverse hop must close-path, not stitch notBuilt',
      );
      await _driveAnimate(tester, toNewer, maxPumps: 300);
      expect(controller.anchorMessageId, newerId);
    },
  );

  testWidgets(
    'stitch flight does not layout-thrash via range coverage',
    (tester) async {
      // Far strip is intentionally short; coverage checks must not
      // markNeedsLayout every ticker frame (broken-logs layout.jump spam).
      const count = 80;
      const originId = 5;
      const targetId = 70;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
        highlight: false,
      );
      await tester.pump();
      expect(_render(tester).debugFarAnimateActive, isTrue);

      // Wait until measured dual-translate is moving.
      await _pumpWhileStitching(
        tester,
        future,
        predicate: (r) => r.debugStitchProgress > 0.05,
      );

      final layoutsAtMid = _render(tester).debugLayoutFrameId;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!_render(tester).debugFarAnimateActive) break;
      }
      final layoutsAfter = _render(tester).debugLayoutFrameId;
      final layoutDelta = layoutsAfter - layoutsAtMid;

      expect(
        layoutDelta,
        lessThan(8),
        reason:
            'mid-stitch ticker must paint, not re-layout every frame '
            '(got $layoutDelta layouts over ~20 frames)',
      );

      await _driveAnimate(tester, future, maxPumps: 300);
    },
  );

  testWidgets(
    'measured stitch progress never regresses when destination fetch completes mid-flight',
    (tester) async {
      const total = 256;
      const originId = 220;
      const targetId = 40;
      const loadedFromId = 200;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _FetchRecordingTailDataSource(
        totalCount: total,
        loadedFromId: loadedFromId,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_render(tester).debugStitchMeasured) break;
      }

      expect(
        _render(tester).debugStitchMeasured,
        isTrue,
        reason: 'fixture must reach measured dual-translate',
      );

      var lastProgress = -1.0;
      var done = false;
      unawaited(future.whenComplete(() => done = true));
      final layoutsAtMid = _render(tester).debugLayoutFrameId;
      for (var i = 0; i < 300 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final render = _render(tester);
        if (!render.debugFarAnimateActive || !render.debugStitchMeasured) {
          continue;
        }
        final progress = render.debugStitchProgress;
        expect(
          progress + 0.001,
          greaterThanOrEqualTo(lastProgress),
          reason:
              'stitch progress must not regress mid-flight '
              '(was ${lastProgress.toStringAsFixed(3)}, '
              'now ${progress.toStringAsFixed(3)})',
        );
        lastProgress = progress;
        expect(
          find.textContaining('msg-'),
          findsWidgets,
          reason:
              'destination fetch must not blank the band at '
              'progress=${progress.toStringAsFixed(3)}',
        );
      }

      final layoutDelta = _render(tester).debugLayoutFrameId - layoutsAtMid;
      expect(
        layoutDelta,
        lessThan(24),
        reason:
            'jumpFetch during measured flight must stay on stitch slim '
            '(got $layoutDelta layouts)',
      );

      await _driveAnimate(tester, future, maxPumps: 300);
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
    },
  );

  testWidgets(
    'mid-history align 0.5 tall target keeps band populated jump through settle',
    (tester) async {
      const count = 256;
      const originId = 220;
      const targetId = 10;
      const tallHeight = _viewportHeight * 3 + 200;

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          messageHeight: (id) => id == targetId ? tallHeight : 60.0,
        ),
      );
      await tester.pump();

      final future = controller.animateTo(
        targetId,
        alignment: 0.5,
        duration: const Duration(milliseconds: 800),
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );

      var done = false;
      unawaited(future.whenComplete(() => done = true));
      var sawMeasured = false;
      for (var i = 0; i < 400 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final render = _render(tester);
        if (render.debugFarAnimateJumped) {
          expect(
            find.textContaining('msg-'),
            findsWidgets,
            reason: 'post-jump band must stay populated before measure',
          );
        }
        if (render.debugStitchMeasured) {
          sawMeasured = true;
          expect(
            find.textContaining('msg-'),
            findsWidgets,
            reason:
                'mid-history measured flight must not leave blank viewport '
                'at progress=${render.debugStitchProgress.toStringAsFixed(3)}',
          );
        }
      }

      expect(sawMeasured, isTrue, reason: 'tall mid-history target must measure');
      await future;
      expect(controller.anchorMessageId, targetId);
      expect(find.text('msg-$targetId'), findsOneWidget);
    },
  );

  testWidgets(
    'repeated mid-history animateTo keeps band populated',
    (tester) async {
      const count = 256;
      const originId = 232;
      const targets = <int>[157, 90, 200, 120];

      final controller = ChatScrollController()..jumpTo(originId);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          messageHeight: (id) => id == originId ? 400.0 : 60.0,
        ),
      );
      await tester.pump();

      for (final targetId in targets) {
        final future = controller.animateTo(
          targetId,
          alignment: 0.5,
          duration: const Duration(milliseconds: 400),
          highlight: false,
          loadPolicy: AnimateToLoadPolicy.immediate,
        );
        await tester.pump();
        var done = false;
        unawaited(future.whenComplete(() => done = true));
        for (var i = 0; i < 200 && !done; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (_render(tester).debugFarAnimateActive) {
            expect(
              find.textContaining('msg-'),
              findsWidgets,
              reason:
                  'mid-history re-entry to $targetId must not blank viewport',
            );
          }
        }
        await future;
        expect(controller.anchorMessageId, targetId);
        expect(find.text('msg-$targetId'), findsOneWidget);
        expect(_render(tester).debugFarAnimateActive, isFalse);
      }
    },
  );
}

class _DayPreloadedDataSource extends ChatDataSource {
  _DayPreloadedDataSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_dayMsg(i));
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

/// Tail loaded; older ids stay cold until [releaseTargetWindow] upserts them.
class _GatedColdTargetDataSource extends ChatDataSource {
  _GatedColdTargetDataSource({
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

  void releaseTargetWindow({required int aroundId, int radius = 32}) {
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

/// Tail loaded; [fetchRange] serves cold ids and records requests.
class _FetchRecordingTailDataSource extends ChatDataSource {
  _FetchRecordingTailDataSource({
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
  final List<({int fromId, int toId})> fetchRequests = [];

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    fetchRequests.add((fromId: fromId, toId: toId));
    final lo = fromId.clamp(0, totalCount - 1);
    final hi = toId.clamp(0, totalCount - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

/// Fully preloaded history; [fetchRange] re-serves after LRU eviction.
class _FetchRecordingFullDataSource extends ChatDataSource {
  _FetchRecordingFullDataSource({
    required this.totalCount,
    this.chunkBudget = 3,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: totalCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = 0; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int totalCount;
  final int chunkBudget;
  final List<({int fromId, int toId})> fetchRequests = [];

  @override
  int get maxChunks => chunkBudget;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    fetchRequests.add((fromId: fromId, toId: toId));
    final lo = fromId.clamp(0, totalCount - 1);
    final hi = toId.clamp(0, totalCount - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

/// Grows via [appendOne]; [fetchRange] re-serves after LRU eviction.
class _FetchRecordingGrowingDataSource extends ChatDataSource {
  _FetchRecordingGrowingDataSource(int initialCount, {this.chunkBudget = 3}) {
    for (var i = 0; i < initialCount; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: initialCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    _newestId = initialCount - 1;
  }

  int _newestId = -1;
  final int chunkBudget;
  final List<({int fromId, int toId})> fetchRequests = [];

  @override
  int get maxChunks => chunkBudget;

  void appendOne() {
    final next = _newestId + 1;
    insertMessage(_msg(next));
    _newestId = next;
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    fetchRequests.add((fromId: fromId, toId: toId));
    final lo = fromId.clamp(0, _newestId);
    final hi = toId.clamp(0, _newestId);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

/// Seeded history plus [sendPastSeed]; [fetchRange] re-serves sent ids from
/// an override map (CommentsDataSource / GeneratedChatDataSource contract).
class _SeedPlusSentTailDataSource extends ChatDataSource {
  _SeedPlusSentTailDataSource({required this.seedCount, this.chunkBudget = 3}) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: seedCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = 0; i < seedCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int seedCount;
  final int chunkBudget;
  final Map<int, IChatMessage> _tailOverrides = <int, IChatMessage>{};

  @override
  int get maxChunks => chunkBudget;

  void sendPastSeed() {
    final id = nextInsertId;
    final message = _msg(id);
    _tailOverrides[id] = message;
    insertMessage(message);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    final upper = newestKnownId ?? seedCount - 1;
    if (upper < 0) return const [];
    final lo = fromId.clamp(0, upper);
    final hi = toId.clamp(0, upper);
    final result = <IChatMessage>[];
    for (var id = lo; id <= hi; id++) {
      if (id < seedCount) {
        result.add(_msg(id));
        continue;
      }
      final override = _tailOverrides[id];
      if (override != null) result.add(override);
    }
    return result;
  }
}
