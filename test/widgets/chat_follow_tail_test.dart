import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

// ---------------------------------------------------------------------------
// Test data source: messages preloaded + counts grow via `appendOne`.
// ---------------------------------------------------------------------------

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _GrowingDataSource extends ChatDataSource {
  _GrowingDataSource(int initialCount) {
    if (initialCount > 0) {
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
  }

  int _newestId = -1;

  /// Append a single new message and bump the newest boundary.
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
  ValueListenable<double>? bottomPadding,
  double Function(int id)? heightForId,
  bool Function(IChatMessage)? isSelfMessage,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          bottomPadding: bottomPadding,
          isSelfMessage: isSelfMessage,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: heightForId?.call(id) ?? 60,
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
  group('follow tail: isAtTail listenable', () {
    testWidgets('starts false, flips true once viewport pins newest', (
      tester,
    ) async {
      final ds = _GrowingDataSource(20);
      final controller = ChatScrollController()..jumpTo(19);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      // Before mount.
      expect(controller.isAtTail.value, isFalse);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(find.text('msg-19'), findsOneWidget);
    });

    testWidgets('flips false after scrolling away from the bottom', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      // Drag down (= reveal older history).
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAtTail.value, isFalse);
    });

    testWidgets('flips back true after scrolling to the bottom again', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();

      // Scroll up.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAtTail.value, isFalse);

      // jumpTo newest brings us back to tail after the next layout.
      controller.jumpTo(39);
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets(
      'small scroll past band edge stays at-tail without snapping back',
      (tester) async {
        // Slop keeps follow-tail; must not yank the user back on a small
        // intentional scroll-away from the exact pin.
        final ds = _GrowingDataSource(40);
        final controller = ChatScrollController()..jumpTo(39);
        final inset = ValueNotifier<double>(100);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(inset.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            bottomPadding: inset,
          ),
        );
        await tester.pump();
        expect(controller.isAtTail.value, isTrue);

        controller.scrollBy(8);
        await tester.pump();

        final bandBottom =
            tester.getBottomLeft(find.byType(ChatScrollView)).dy - inset.value;
        expect(
          tester.getBottomLeft(find.text('msg-39')).dy,
          closeTo(bandBottom + 8, 0.5),
          reason: 'must not pin-snap small scroll-away',
        );
        expect(controller.isAtTail.value, isTrue);
      },
    );

    testWidgets(
      'append while slightly past band edge still follow-pins',
      (tester) async {
        final ds = _GrowingDataSource(40);
        final controller = ChatScrollController()..jumpTo(39);
        final inset = ValueNotifier<double>(100);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(inset.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            bottomPadding: inset,
          ),
        );
        await tester.pump();

        controller.scrollBy(8);
        await tester.pump();
        expect(controller.isAtTail.value, isTrue);

        ds.appendOne();
        await tester.pump();
        await tester.pump();

        final bandBottom =
            tester.getBottomLeft(find.byType(ChatScrollView)).dy - inset.value;
        expect(
          tester.getBottomLeft(find.text('msg-40')).dy,
          closeTo(bandBottom, 0.5),
        );
        expect(controller.isAtTail.value, isTrue);
      },
    );

    testWidgets(
      'scroll far past band edge does not count as at-tail',
      (tester) async {
        final ds = _GrowingDataSource(40);
        final controller = ChatScrollController()..jumpTo(39);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pump();
        expect(controller.isAtTail.value, isTrue);

        controller.scrollBy(200);
        await tester.pump();
        expect(controller.isAtTail.value, isFalse);
      },
    );
  });

  group('follow tail: auto-scroll on new message', () {
    testWidgets('new message at the tail keeps the viewport pinned to it', (
      tester,
    ) async {
      final ds = _GrowingDataSource(20);
      final controller = ChatScrollController()..jumpTo(19);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      expect(find.text('msg-19'), findsOneWidget);
      expect(controller.isAtTail.value, isTrue);

      // A new message arrives. Because we were at tail, the viewport must
      // auto-scroll so the new newest (id 20) is visible.
      ds.appendOne();
      await tester.pump();
      await tester.pump();

      // Strong assertion: msg-20 sits exactly at the bottom edge — proving
      // the pin moved, not just that the widget is in the cache extent.
      final viewportBottom = tester.getBottomLeft(find.byType(ChatScrollView));
      final msg20Bottom = tester.getBottomLeft(find.text('msg-20'));
      expect(
        msg20Bottom.dy,
        closeTo(viewportBottom.dy, 0.5),
        reason: 'newest must be pinned to the bottom edge after auto-scroll',
      );
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('new message while scrolled away does not move the anchor', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();

      // Move off the tail.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAtTail.value, isFalse);
      final anchorBefore = controller.anchorMessageId;
      final offsetBefore = controller.anchorPixelOffset;

      // A new message arrives. We must NOT auto-scroll — user is reading
      // history.
      ds.appendOne();
      await tester.pump();
      await tester.pump();

      expect(controller.anchorMessageId, anchorBefore);
      expect(controller.anchorPixelOffset, offsetBefore);
      expect(controller.isAtTail.value, isFalse);
      // The newest is not built into the visible band.
      expect(find.text('msg-40'), findsNothing);
    });

    testWidgets('multiple appended messages keep pinning when at tail', (
      tester,
    ) async {
      final ds = _GrowingDataSource(10);
      final controller = ChatScrollController()..jumpTo(9);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      for (var i = 10; i < 15; i++) {
        ds.appendOne();
        await tester.pump();
        await tester.pump();
        expect(
          find.text('msg-$i'),
          findsOneWidget,
          reason: 'msg-$i should auto-scroll into view at tail',
        );
        expect(controller.isAtTail.value, isTrue);
      }
    });

    testWidgets(
      'same-id newest height growth at tail keeps bottom on band edge',
      (tester) async {
        // Edit / content change: newest id unchanged, child height grows.
        // Without repinBottom on height drift, growth expands under bottomPad.
        final ds = _GrowingDataSource(20);
        final controller = ChatScrollController()..jumpTo(19);
        final inset = ValueNotifier<double>(120);
        final heights = ValueNotifier<Map<int, double>>({19: 60});
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(inset.dispose);
        addTearDown(heights.dispose);

        Widget build() => AnimatedBuilder(
          animation: heights,
          builder: (context, _) => _scaffold(
            dataSource: ds,
            controller: controller,
            bottomPadding: inset,
            heightForId: (id) => heights.value[id] ?? 60,
          ),
        );

        await tester.pumpWidget(build());
        await tester.pump();
        expect(controller.isAtTail.value, isTrue);

        final bandBottomBefore =
            tester.getBottomLeft(find.byType(ChatScrollView)).dy - inset.value;
        expect(
          tester.getBottomLeft(find.text('msg-19')).dy,
          closeTo(bandBottomBefore, 0.5),
        );

        heights.value = {19: 180};
        await tester.pumpWidget(build());
        await tester.pump();

        final bandBottomAfter =
            tester.getBottomLeft(find.byType(ChatScrollView)).dy - inset.value;
        expect(
          tester.getBottomLeft(find.text('msg-19')).dy,
          closeTo(bandBottomAfter, 0.5),
          reason: 'newest bottom must stay on scroll-band bottom while height '
              'grows (expand upward, not under composer)',
        );
        expect(controller.isAtTail.value, isTrue);
      },
    );
  });

  group('follow tail: self insert', () {
    testWidgets('self insert while scrolled away jumps to newest', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          isSelfMessage: (m) => m.sender == 'me',
        ),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAtTail.value, isFalse);

      // Multi-device self send while reading history.
      ds.insertMessage(
        UserChatMessage(
          id: 40,
          sender: 'me',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'from desktop',
        ),
      );
      await tester.pump();
      // animateTo default 300ms — settle past the close-path animation.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(find.text('msg-40'), findsOneWidget);
    });

    testWidgets('at-tail self insert skips animateTo (layout pin only)', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          isSelfMessage: (m) => m.sender == 'me',
          heightForId: (id) => id == 40 ? 120 : 60,
        ),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      ds.insertMessage(
        UserChatMessage(
          id: 40,
          sender: 'me',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'local send',
        ),
      );
      await tester.pump();
      expect(
        _render(tester).debugIsAnimating,
        isFalse,
        reason: 'at-tail self insert must not animateTo',
      );
      expect(_render(tester).debugFarAnimateActive, isFalse);

      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      expect(find.text('msg-40'), findsOneWidget);
    });

    testWidgets('incoming insert while scrolled away does not jump', (
      tester,
    ) async {
      final ds = _GrowingDataSource(40);
      final controller = ChatScrollController()..jumpTo(39);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          isSelfMessage: (m) => m.sender == 'me',
        ),
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isAtTail.value, isFalse);
      final anchorBefore = controller.anchorMessageId;

      ds.appendOne(); // sender is 'User', not 'me'
      await tester.pump();
      await tester.pump();

      expect(controller.isAtTail.value, isFalse);
      expect(controller.anchorMessageId, anchorBefore);
      expect(find.text('msg-40'), findsNothing);
    });
  });

  group('follow tail: render-side counters', () {
    testWidgets('debugChildCount stays bounded after many appends', (
      tester,
    ) async {
      final ds = _GrowingDataSource(20);
      final controller = ChatScrollController()..jumpTo(19);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      final initialChildren = _render(tester).debugChildCount;

      for (var i = 0; i < 30; i++) {
        ds.appendOne();
      }
      await tester.pump();
      await tester.pump();

      // Builds are tied to viewport + cache extent — appending shouldn't
      // inflate everything ever produced. Allow a small slack for the
      // directional-lead build-ahead.
      expect(
        _render(tester).debugChildCount,
        lessThanOrEqualTo(initialChildren + 8),
      );
      // And much less than the conversation's total size.
      expect(_render(tester).debugChildCount, lessThan(50));
    });
  });
}
