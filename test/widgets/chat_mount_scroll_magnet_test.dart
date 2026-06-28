import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data — mirrors demo geometry: reverse + bottomPadding 96.
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
const _bottomInset = 96.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ValueListenable<double>? bottomPadding,
}) {
  return MaterialApp(
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
            messageBuilder: (context, id, message, status) => SizedBox(
              height: 60,
              child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pump through post-release settle — catches layout-driven tail re-pin.
Future<void> _pumpSettle(WidgetTester tester, {Duration total = const Duration(milliseconds: 1000)}) async {
  final steps = total.inMilliseconds ~/ 16;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<({ChatScrollController controller, _PreloadedDataSource ds, ValueNotifier<double> inset})> _mountAtTail(
  WidgetTester tester, {
  int count = 40,
}) async {
  final newest = count - 1;
  final ds = _PreloadedDataSource(count);
  final inset = ValueNotifier<double>(_bottomInset);
  final controller = ChatScrollController()..jumpTo(newest);
  addTearDown(controller.dispose);
  addTearDown(ds.dispose);
  addTearDown(inset.dispose);

  await tester.pumpWidget(
    _harness(dataSource: ds, controller: controller, bottomPadding: inset),
  );
  await tester.pump();
  expect(controller.isAtTail.value, isTrue, reason: 'precondition: mounted at tail');
  return (controller: controller, ds: ds, inset: inset);
}

void main() {
  group('mount scroll magnet: drag', () {
    testWidgets('post-mount moderate drag up stays off-tail', (tester) async {
      const count = 40;
      final mounted = await _mountAtTail(tester, count: count);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 300));
      await tester.pump();
      await _pumpSettle(tester);

      expect(mounted.controller.isAtTail.value, isFalse);
    });

    testWidgets('post-mount drag position stable for 1s', (tester) async {
      const count = 40;
      final mounted = await _mountAtTail(tester, count: count);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();

      // Capture a mid-history message that should stay visible.
      final anchorBefore = mounted.controller.anchorMessageId;
      expect(mounted.controller.isAtTail.value, isFalse);

      await _pumpSettle(tester);

      expect(mounted.controller.isAtTail.value, isFalse);
      expect(find.text('msg-$anchorBefore'), findsWidgets);
    });
  });

  group('mount scroll magnet: fling', () {
    testWidgets('post-mount moderate fling completes off-tail', (tester) async {
      const count = 40;
      final mounted = await _mountAtTail(tester, count: count);

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 800),
        800,
      );
      await _pumpSettle(tester);

      expect(mounted.controller.isAtTail.value, isFalse);
    });

    testWidgets('fling does not reverse mid-flight', (tester) async {
      const count = 40;
      final mounted = await _mountAtTail(tester, count: count);

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 800),
        800,
      );

      // Mid-deceleration: should already be off-tail, not snap back.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!mounted.controller.isAtTail.value) break;
      }
      expect(mounted.controller.isAtTail.value, isFalse);

      await _pumpSettle(tester);
      expect(mounted.controller.isAtTail.value, isFalse);
    });
  });

  group('mount scroll magnet: re-attach', () {
    testWidgets('re-attach then drag up matches continuous mount', (tester) async {
      const count = 40;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final inset = ValueNotifier<double>(_bottomInset);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      final widget = _harness(
        dataSource: ds,
        controller: controller,
        bottomPadding: inset,
      );

      await tester.pumpWidget(widget);
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      // Simulate route pop / rebuild — detach and re-attach render object.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(widget);
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 300));
      await tester.pump();
      await _pumpSettle(tester);

      expect(controller.isAtTail.value, isFalse);
    });
  });

  group('mount scroll magnet: lazy tail', () {
    testWidgets('lazy tail load after user drag does not yank to newest', (tester) async {
      const count = 40;
      final newest = count - 1;
      final ds = _LazyTailDataSource(count);
      final inset = ValueNotifier<double>(_bottomInset);
      final controller = ChatScrollController()..jumpTo(newest);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, bottomPadding: inset),
      );
      await tester.pump();

      // User scrolls before messages load — preempts attach tail settle.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 400));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      await _pumpSettle(tester);

      expect(ds.loaded, isTrue);
      expect(controller.isAtTail.value, isFalse);
    });
  });
}
