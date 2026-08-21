import 'dart:async' show unawaited;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
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

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double cacheExtent = 400,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: cacheExtent,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
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

void main() {
  testWidgets(
    'preferBuilt after near-tail insert uses close path (no stitch)',
    (tester) async {
      const initial = 20;
      final ds = _GrowingDataSource(initial);
      final controller = ChatScrollController()..jumpTo(initial - 1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_scaffold(dataSource: ds, controller: controller));
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
      _scaffold(dataSource: ds, controller: controller, cacheExtent: 8000),
    );
    await tester.pump();

    final beforeIds = _render(tester).debugBuiltMessageIds.toSet();
    expect(beforeIds, isNotEmpty);

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
    expect(
      render.debugStitchOutgoingIds.intersection(beforeIds),
      isNotEmpty,
    );
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
}
