import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

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

/// Metadata-only at construction (like [BackendChatDataSource.connect]);
/// messages arrive on the first [fetchRange] — exercises tail repin after
/// lazy load.
class _LazyTailDataSource extends ChatDataSource {
  _LazyTailDataSource(this.count) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final int count;
  bool loaded = false;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final lo = fromId.clamp(0, count - 1);
    final hi = toId.clamp(0, count - 1);
    final messages = <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
    upsertMessages(messages);
    loaded = true;
    return messages;
  }
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  bool reverse = false,
  ValueListenable<double>? bottomPadding,
  double Function(int id)? messageHeight,
}) {
  final heightFor = messageHeight ?? (_) => 60.0;
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: ChatScrollView(
            reverse: reverse,
            dataSource: dataSource,
            controller: controller,
            bottomPadding: bottomPadding,
            messageBuilder: (context, id, message, status) => SizedBox(
              height: heightFor(id),
              child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drive [animateFuture] to completion — the future only resolves once the
/// viewport ticker fires, which requires explicit pumps in widget tests.
Future<void> _driveAnimate(
  WidgetTester tester,
  Future<void> animateFuture, {
  Duration animateDuration = const Duration(milliseconds: 300),
}) async {
  await tester.pump();
  final pumps = (animateDuration.inMilliseconds ~/ 16) + 2;
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await animateFuture;
  await tester.pump();
}

Future<void> _slowDrag(
  WidgetTester tester,
  Offset totalDelta, {
  int steps = 10,
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
}

void main() {
  group('jump to tail', () {
    testWidgets('post-frame jumpTo newest pins tail on first layout', (
      tester,
    ) async {
      const count = 20;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(96);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          reverse: true,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);
      expect(
        tester.getTopLeft(find.text('msg-$newest')).dy,
        closeTo(_viewportHeight - 96 - 60, 1),
      );
    });

    testWidgets('jumpTo newest from scrolled-up position restores tail', (
      tester,
    ) async {
      const count = 40;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAtTail.value, isFalse);

      controller.jumpTo(newest);
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);
    });

    testWidgets('animateTo newest sets tail pin', (tester) async {
      const count = 40;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAtTail.value, isFalse);

      final future = controller.animateTo(newest);
      await _driveAnimate(tester, future);
      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);
    });

    testWidgets('jumpTo past newest clamps without phantom shimmer', (
      tester,
    ) async {
      const count = 20;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, reverse: true),
      );
      await tester.pump();

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
      expect(find.text('shimmer-$count'), findsNothing);
      expect(find.text('msg-$newest'), findsOneWidget);
    });

    testWidgets('overscroll at tail leaves no phantom row after bounce-back', (
      tester,
    ) async {
      const count = 20;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, reverse: true),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      // Pull past the bottom boundary (negative Y = toward newer / past tail).
      await _slowDrag(tester, const Offset(0, -180));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('shimmer-$newest'), findsNothing);
      expect(find.text('msg-$newest'), findsOneWidget);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('lazy fetch repins tail after messages load', (tester) async {
      const count = 5;
      const newest = count - 1;
      final ds = _LazyTailDataSource(count);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          reverse: true,
          messageHeight: (id) => id == newest ? 120.0 : 400.0,
        ),
      );
      await tester.pump();
      expect(ds.loaded, isFalse);

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();

      expect(ds.loaded, isTrue);
      expect(controller.isAtTail.value, isTrue);
      expect(
        tester.getTopLeft(find.text('msg-$newest')).dy,
        closeTo(_viewportHeight - 120, 1),
      );
    });

    testWidgets('scroll away from tail is not yanked back by pending pin', (
      tester,
    ) async {
      const count = 40;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final bottomPad = ValueNotifier<double>(96);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(bottomPad.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          reverse: true,
          bottomPadding: bottomPad,
        ),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);

      // Small drag: leave the tail while anchor id can still be `newest`.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAtTail.value, isFalse);

      // Pending tail pin must not snap the user back on the next frames.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(controller.isAtTail.value, isFalse);
    });

    testWidgets('tall newest message pins bottom above bottomPadding', (
      tester,
    ) async {
      const count = 10;
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(96);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          reverse: true,
          bottomPadding: inset,
          messageHeight: (id) => id == newest ? 200.0 : 60.0,
        ),
      );
      await tester.pump();

      final top = tester.getTopLeft(find.text('msg-$newest')).dy;
      expect(top, closeTo(_viewportHeight - 96 - 200, 1));
      expect(controller.isAtTail.value, isTrue);
    });
  });
}
