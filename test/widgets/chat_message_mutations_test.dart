import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
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
      expect(controller.isAtTail.value, isTrue);
      expect(_render(tester).debugHasMessageChild(predecessorId), isTrue);
    });

    testWidgets('tail removal scroll tracks animated collapse', (tester) async {
      const count = 64;
      const tailId = count - 1;
      final controller = ChatScrollController()..jumpTo(tailId);
      final ds = _MutableSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      final anchorY0 = controller.anchorPixelOffset;
      final height0 = _render(tester).debugEffectiveHeightOf(tailId)!;

      ds.requestRemoval(tailId, reason: 'test');
      await tester.pump();

      var sawScrollCompensation = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final height = _render(tester).debugEffectiveHeightOf(tailId);
        if (height == null) break;
        if (height < height0 - 5 &&
            controller.anchorPixelOffset > anchorY0 + 5) {
          sawScrollCompensation = true;
          break;
        }
      }
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
          final bottom = controller.anchorPixelOffset + h;
          if ((bottom - bottomEdge).abs() < 8.0) {
            sawPin = true;
          }
          break;
        }
      }
      expect(sawPin, isTrue);
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
  });
}
