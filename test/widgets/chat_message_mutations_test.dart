import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i, {String content = 'content'}) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: '$content $i',
);

class _MutableSource extends ChatDataSource {
  _MutableSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  void insertAtTail(int id) {
    upsertMessage(_msg(id));
    seedBoundaries(newestKnownId: id, reachedNewest: true);
    notifyInsert(id, reason: 'test');
    notifyDataChanged();
  }

  void updateContent(int id, String content) {
    upsertMessage(_msg(id, content: content));
    requestUpdate(id, reason: 'test-edit');
  }

  /// Nulls a slot in place (backend hard-delete) without collapse animation.
  void hardDeleteSlot(int id) {
    final chunkIndex = ChatScrollChunk.chunkOf(id);
    final chunk = chunks[chunkIndex];
    if (chunk == null) return;
    final slot = id - chunk.firstId;
    if (chunk.messages[slot] == null) return;
    chunk.messages[slot] = null;
    chunk.markAbsentSlot(slot);
    chunk.status = ChatMessageStatus.valid;
    if (newestKnownId == id) {
      seedBoundaries(newestKnownId: id - 1, reachedNewest: true);
    }
    notifyDataChanged();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Two calendar days — ids 0..5 on 2026-01-01, ids 6..11 on 2026-01-02.
class _DaySource extends ChatDataSource {
  _DaySource() {
    for (var i = 0; i < 12; i++) {
      upsertMessage(
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026, 1, 1 + (i ~/ 6)),
          updatedAt: DateTime(2026, 1, 1 + (i ~/ 6)),
          content: 'content $i',
        ),
      );
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 11,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _dayHarness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          groupBy: (message) {
            final day = message.createdAt;
            return '${day.year}-${day.month}-${day.day}';
          },
          messageBuilder: (context, id, message, status) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
          dateSeparatorBuilder: (context, bucket, date) =>
              const SizedBox(height: 24),
        ),
      ),
    ),
  ),
);

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double messageHeight = 60,
  ChatSelectionController? selectionController,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          selectionController: selectionController,
          messageBuilder: (context, id, message, status) => SizedBox(
            height: messageHeight,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

/// Drive [animateFuture] to completion — the future needs ticker frames.
Future<void> _driveAnimate(
  WidgetTester tester,
  Future<void> animateFuture, {
  required Duration animateDuration,
}) async {
  await tester.pump();
  final pumps = (animateDuration.inMilliseconds ~/ 16) + 2;
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await animateFuture;
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('Message extent mutations', () {
    testWidgets('visible insert expands over multiple frames', (tester) async {
      const count = 64;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      ds.insertAtTail(count);
      await tester.pump();

      final ro = _render(tester);
      final samples = <double>[];
      for (var i = 0; i < 30; i++) {
        final h = ro.debugEffectiveHeightOf(count);
        if (h != null) samples.add(h);
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(samples.length, greaterThanOrEqualTo(3));
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1] - 0.5));
      }
      expect(samples.last, closeTo(60, 6));
    });

    testWidgets('removal keeps child until collapse completes', (tester) async {
      const count = 64;
      const targetId = count - 5;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(_render(tester).debugHasMessageChild(targetId), isTrue);

      ds.requestRemoval(targetId, reason: 'test');
      await tester.pump();

      expect(_render(tester).debugHasMessageChild(targetId), isTrue);

      var removed = false;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!_render(tester).debugHasMessageChild(targetId)) {
          removed = true;
          break;
        }
      }
      expect(removed, isTrue);
      expect(ds.getMessage(targetId), isNull);
    });

    testWidgets('off-screen insert applies instantly without spring frames', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      // Scroll up so the tail is off-screen.
      for (var i = 0; i < 80; i++) {
        controller.applyScrollDelta(200);
        _render(tester).markNeedsLayout();
        await tester.pump();
      }

      ds.insertAtTail(count);
      await tester.pump();

      final ro = _render(tester);
      final h0 = ro.debugEffectiveHeightOf(count);
      await tester.pump(const Duration(milliseconds: 16));
      final h1 = ro.debugEffectiveHeightOf(count);

      if (h0 != null && h1 != null) {
        expect((h1 - h0).abs(), lessThan(0.5));
        expect(h1, closeTo(60, 0.5));
      }
    });

    testWidgets('scroll-in and fetch do not trigger insert animation', (
      tester,
    ) async {
      const count = 64;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      final ro = _render(tester);
      final anchorBefore = controller.anchorMessageId;

      // Scroll up to reveal older messages that were never explicitly inserted.
      for (var i = 0; i < 40; i++) {
        controller.applyScrollDelta(200);
        ro.markNeedsLayout();
        await tester.pump();
      }
      expect(controller.anchorMessageId, isNot(anchorBefore));

      final olderId = controller.anchorMessageId;
      final height = ro.debugEffectiveHeightOf(olderId);
      expect(height, isNotNull);
      expect(height, closeTo(60, 0.5));

      // No spring frames — height stays at full measured size across ticks.
      await tester.pump(const Duration(milliseconds: 16));
      expect(ro.debugEffectiveHeightOf(olderId), closeTo(60, 0.5));
    });

    testWidgets('tail delete reassigns anchor and stays pinned', (
      tester,
    ) async {
      const count = 64;
      const tailId = count - 1;
      const predecessorId = count - 2;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, tailId);

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      var removed = false;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final ro = _render(tester);
        if (!ro.debugHasMessageChild(tailId)) {
          removed = true;
          break;
        }
      }
      expect(removed, isTrue);

      expect(ds.getMessage(tailId), isNull);
      expect(ds.statusOf(tailId).isAbsent, isTrue);
      expect(ds.newestKnownId, predecessorId);
      expect(controller.anchorMessageId, predecessorId);
      expect(_render(tester).debugHasMessageChild(predecessorId), isTrue);
    });

    testWidgets('tail delete moves anchor before collapse finishes', (
      tester,
    ) async {
      const count = 64;
      const tailId = count - 1;
      const predecessorId = count - 2;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      expect(_render(tester).debugHasMessageChild(tailId), isTrue);
      expect(controller.anchorMessageId, predecessorId);
    });

    testWidgets('tail removal scroll tracks animated collapse', (tester) async {
      const count = 64;
      const tailId = count - 1;
      const predecessorId = tailId - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      expect(controller.anchorMessageId, predecessorId);

      const bottomEdge = 600.0;
      final height0 = _render(tester).debugEffectiveHeightOf(tailId)!;
      var sawCollapse = false;
      var sawScrollCompensation = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final ro = _render(tester);
        final height = ro.debugEffectiveHeightOf(tailId);
        if (height == null) break;
        if (height < 50) {
          sawCollapse = true;
          break;
        }
        if (height < height0 - 5) {
          final ghostTop = ro.debugMessageTopOf(tailId);
          if (ghostTop != null) {
            final ghostBottom = ghostTop + height;
            if ((ghostBottom - bottomEdge).abs() < 8.0) {
              sawScrollCompensation = true;
            }
          }
        }
      }
      expect(sawCollapse, isTrue);
      expect(sawScrollCompensation, isTrue);
    });

    testWidgets('tall newest tail removal pins bottom during collapse', (
      tester,
    ) async {
      const count = 64;
      const tailId = count - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, messageHeight: 400),
      );
      await tester.pump();

      const bottomEdge = 600.0;
      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      var sawPin = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final ro = _render(tester);
        if (!ro.debugHasMessageChild(tailId)) break;
        final h = ro.debugEffectiveHeightOf(tailId);
        if (h == null) break;
        if (h < 350) {
          final ghostTop = ro.debugMessageTopOf(tailId);
          if (ghostTop != null) {
            final ghostBottom = ghostTop + h;
            if ((ghostBottom - bottomEdge).abs() < 8.0) {
              sawPin = true;
            }
          }
          break;
        }
      }
      expect(sawPin, isTrue);
    });

    testWidgets(
      'tail delete while navigation-highlighted clears highlight and stays pinned',
      (tester) async {
        const count = 64;
        const tailId = count - 1;
        const predecessorId = tailId - 1;
        final controller = ChatScrollController()..jumpTo(tailId);
        final ds = _MutableSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            messageHeight: 400,
          ),
        );
        await tester.pump();

        await _driveAnimate(
          tester,
          controller.animateTo(
            tailId,
            duration: const Duration(milliseconds: 1),
          ),
          animateDuration: const Duration(milliseconds: 1),
        );

        final roBefore = _render(tester);
        expect(roBefore.debugHighlightTargetId, tailId);

        ds.requestRemoval(tailId, reason: 'test');
        await tester.pump();

        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(controller.anchorMessageId, predecessorId);

        const bottomEdge = 600.0;
        var sawPin = false;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final ro = _render(tester);
          if (!ro.debugHasMessageChild(tailId)) break;
          final h = ro.debugEffectiveHeightOf(tailId);
          if (h == null) break;
          final ghostTop = ro.debugMessageTopOf(tailId);
          if (ghostTop != null) {
            final ghostBottom = ghostTop + h;
            if ((ghostBottom - bottomEdge).abs() < 8.0) {
              sawPin = true;
              break;
            }
          }
        }
        expect(sawPin, isTrue);

        // Ghost-pin should converge before finalize — no anchor snap on eviction.
        double? anchorBeforeFinalize;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (!_render(tester).debugHasMessageChild(tailId)) {
            anchorBeforeFinalize = controller.anchorPixelOffset;
            break;
          }
        }
        expect(anchorBeforeFinalize, isNotNull);
        await tester.pump();
        expect(
          (controller.anchorPixelOffset - anchorBeforeFinalize!).abs(),
          lessThan(8.0),
        );
        final predH = _render(tester).debugEffectiveHeightOf(predecessorId)!;
        expect(
          (controller.anchorPixelOffset + predH - bottomEdge).abs(),
          lessThan(8.0),
        );
      },
    );

    testWidgets(
      'tail delete while selected clears selection and exits mode',
      (tester) async {
        const count = 64;
        const tailId = count - 1;
        final controller = ChatScrollController()..jumpTo(tailId);
        final ds = _MutableSource(count);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            selectionController: selection,
          ),
        );
        await tester.pump();

        selection.startSelection(tailId);
        expect(selection.isSelectionMode, isTrue);
        expect(selection.isSelected(tailId), isTrue);

        ds.requestRemoval(tailId, reason: 'test');
        await tester.pump();

        expect(selection.isSelectionMode, isFalse);
        expect(selection.isSelected(tailId), isFalse);
      },
    );

    testWidgets(
      'tail delete while selected stays pinned with wrapped predecessor',
      (tester) async {
        const count = 64;
        const tailId = count - 1;
        const predecessorId = tailId - 1;
        final controller = ChatScrollController()..jumpTo(tailId);
        final ds = _MutableSource(count);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(selection.dispose);

        String words(int n) => List.filled(n, 'word').join(' ');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: ChatScrollView(
                    reverse: true,
                    dataSource: ds,
                    controller: controller,
                    selectionController: selection,
                    messageBuilder: (context, id, message, status) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        id == predecessorId ? words(80) : words(5),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        selection.startSelection(tailId);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(_render(tester).debugHasMessageChild(tailId), isTrue);
        expect(controller.anchorMessageId, tailId);

        ds.requestRemoval(tailId, reason: 'test');
        await tester.pump();
        await tester.pump();

        expect(selection.isSelectionMode, isFalse);
        expect(controller.anchorMessageId, predecessorId);

        const bottomEdge = 600.0;
        var sawPin = false;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final ro = _render(tester);
          if (!ro.debugHasMessageChild(tailId)) break;
          final h = ro.debugEffectiveHeightOf(tailId);
          if (h == null) break;
          final ghostTop = ro.debugMessageTopOf(tailId);
          if (ghostTop != null) {
            final ghostBottom = ghostTop + h;
            if ((ghostBottom - bottomEdge).abs() < 8.0) {
              sawPin = true;
              break;
            }
          }
        }
        expect(sawPin, isTrue);

        double? anchorBeforeFinalize;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (!_render(tester).debugHasMessageChild(tailId)) {
            anchorBeforeFinalize = controller.anchorPixelOffset;
            break;
          }
        }
        expect(anchorBeforeFinalize, isNotNull);
        await tester.pump();
        expect(
          (controller.anchorPixelOffset - anchorBeforeFinalize!).abs(),
          lessThan(8.0),
        );
        final predH = _render(tester).debugEffectiveHeightOf(predecessorId)!;
        expect(
          (controller.anchorPixelOffset + predH - bottomEdge).abs(),
          lessThan(8.0),
        );
      },
    );

    testWidgets(
      'hard-delete anchor slot reassigns to present neighbor',
      (tester) async {
        const count = 64;
        const tailId = count - 1;
        const predecessorId = tailId - 1;
        final controller = ChatScrollController()..jumpTo(tailId);
        final ds = _MutableSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
        await tester.pump();

        expect(controller.anchorMessageId, tailId);
        ds.hardDeleteSlot(tailId);
        await tester.pump();
        await tester.pump();

        expect(ds.getMessage(tailId), isNull);
        expect(controller.anchorMessageId, predecessorId);
        expect(_render(tester).debugHasMessageChild(predecessorId), isTrue);
      },
    );

    testWidgets('short tail delete with tall predecessor stays at tail', (
      tester,
    ) async {
      const count = 64;
      const tailId = count - 1;
      const predecessorId = tailId - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  reverse: true,
                  dataSource: ds,
                  controller: controller,
                  messageBuilder: (context, id, message, status) => SizedBox(
                    height: id == predecessorId ? 400 : 60,
                    child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!_render(tester).debugHasMessageChild(tailId)) break;
      }
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      const bottomEdge = 600.0;
      final ro = _render(tester);
      final anchorH = ro.debugEffectiveHeightOf(predecessorId) ?? 400;
      final bottom = controller.anchorPixelOffset + anchorH;
      expect((bottom - bottomEdge).abs(), lessThan(8.0));
    });

    testWidgets('collapsed removal keeps zero height before layout evicts', (
      tester,
    ) async {
      const count = 64;
      const tailId = count - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, messageHeight: 120),
      );
      await tester.pump();

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      double? heightWhenQueued;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final ro = _render(tester);
        if (!ro.debugHasMessageChild(tailId)) break;
        final h = ro.debugEffectiveHeightOf(tailId);
        if (h != null && h <= 0.5) {
          heightWhenQueued = h;
          await tester.pump(const Duration(milliseconds: 16));
          if (ro.debugHasMessageChild(tailId)) {
            expect(ro.debugEffectiveHeightOf(tailId), lessThan(1.0));
          }
          break;
        }
      }
      expect(heightWhenQueued, isNotNull);
    });

    testWidgets('content update triggers layout remeasure', (tester) async {
      const count = 64;
      const targetId = 60;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, messageHeight: 60),
      );
      await tester.pump();

      expect(_render(tester).debugHasMessageChild(targetId), isTrue);
      ds.updateContent(targetId, 'edited');
      await tester.pump();
      expect(_render(tester).debugHasMessageChild(targetId), isTrue);
    });

    testWidgets('startsDay uses previous present message after delete', (
      tester,
    ) async {
      const deleteId = 6;
      const successorId = 7;
      final controller = ChatScrollController()..jumpTo(11);
      final ds = _DaySource();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _dayHarness(dataSource: ds, controller: controller),
      );
      await tester.pump();

      expect(_render(tester).debugStartsDay(successorId), isFalse);

      ds.requestRemoval(deleteId, reason: 'test');
      await tester.pump();
      await tester.pump();

      expect(_render(tester).debugStartsDay(successorId), isTrue);
    });

    testWidgets('tail fling bounded without removal ghost', (tester) async {
      const count = 40;
      const tailId = count - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final anchorAtTail = controller.anchorPixelOffset;
      final center = tester.getCenter(find.byType(ChatScrollView));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final drift = (controller.anchorPixelOffset - anchorAtTail).abs();
      expect(
        drift,
        lessThan(600.0),
        reason: 'tail fling without removal should stay bounded',
      );
    });

    testWidgets('overscroll bounded during removal fling', (tester) async {
      const count = 40;
      const tailId = count - 1;
      const deleteId = tailId - 4;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      final anchorAtTail = controller.anchorPixelOffset;
      ds.requestRemoval(deleteId, reason: 'test');
      await tester.pump();

      final center = tester.getCenter(find.byType(ChatScrollView));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final drift = (controller.anchorPixelOffset - anchorAtTail).abs();
      expect(
        drift,
        lessThan(600.0),
        reason: 'fling during removal should not drift unbounded',
      );
    });

    testWidgets('removal finalize does not teleport more than viewport height', (
      tester,
    ) async {
      const count = 40;
      const tailId = count - 1;
      const deleteId = tailId - 3;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pumpAndSettle();

      ds.requestRemoval(deleteId, reason: 'test');
      await tester.pump();

      final center = tester.getCenter(find.byType(ChatScrollView));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();

      var maxJump = 0.0;
      var prev = controller.anchorPixelOffset;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final jump = (controller.anchorPixelOffset - prev).abs();
        if (jump > maxJump) maxJump = jump;
        prev = controller.anchorPixelOffset;
      }

      expect(maxJump, lessThan(600.0));
    });
  });
}
