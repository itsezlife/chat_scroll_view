import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

/// A [ChatDataSource] that fetches only [presentIds] in [fetchRange]; all
/// other IDs within [oldest]..[newest] are permanently absent.
///
/// Used to simulate a conversation where a contiguous batch of messages has
/// been deleted from the backend.
class GapDataSource extends ChatDataSource {
  GapDataSource({
    required Set<int> presentIds,
    required int oldest,
    required int newest,
  }) : _presentIds = presentIds {
    seedBoundaries(
      oldestKnownId: oldest,
      newestKnownId: newest,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final Set<int> _presentIds;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => [
    for (var id = fromId; id <= toId; id++)
      if (_presentIds.contains(id)) _msg(id),
  ];
}

/// A [GapDataSource] whose set of present IDs can be replaced after creation,
/// simulating a restore or additional deletions on re-fetch.
class _MutableGapDataSource extends ChatDataSource {
  _MutableGapDataSource({
    required Set<int> presentIds,
    required int oldest,
    required int newest,
  }) : _presentIds = Set<int>.of(presentIds) {
    seedBoundaries(
      oldestKnownId: oldest,
      newestKnownId: newest,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  Set<int> _presentIds;

  set presentIds(Set<int> ids) => _presentIds = ids;

  /// Removes [id] from the in-memory slot and marks it absent (simulating a
  /// realtime delete event: server confirms deletion, client marks absent).
  void deleteMessage(int id) {
    final chunkIndex = ChatScrollChunk.chunkOf(id);
    final chunk = chunks[chunkIndex];
    if (chunk == null) return;
    final slot = id - chunk.firstId;
    chunk.messages[slot] = null;
    chunk.markAbsentSlot(slot);
    notifyDataChanged();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => [
    for (var id = fromId; id <= toId; id++)
      if (_presentIds.contains(id)) _msg(id),
  ];
}

/// Standard test harness: renders 'msg-$id' for loaded messages, 'shimmer-$id'
/// for unloaded (null + non-absent) slots, and [SizedBox.shrink] for absent
/// slots so they contribute zero height.
///
/// [cacheExtent] controls how many messages outside the visible area are
/// built. Use a large value in tests that need multiple chunks loaded.
Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double width = 400,
  double height = 600,
  double cacheExtent = 5000,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: cacheExtent,
          messageBuilder: (context, id, message, status) {
            if (status.isAbsent) return const SizedBox.shrink();
            if (message == null) {
              return SizedBox(height: 40, child: Text('shimmer-$id'));
            }
            return SizedBox(height: 40, child: Text('msg-$id'));
          },
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

/// Pumps the widget until all pending timers and microtasks are flushed
/// (up to [maxPumps] iterations at [stepMs] each).
Future<void> _settle(
  WidgetTester tester, {
  int maxPumps = 15,
  int stepMs = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

// ---------------------------------------------------------------------------
// Tests — absent-slot marking after fetchRange
// ---------------------------------------------------------------------------

void main() {
  group('absent-slot marking after fetchRange', () {
    // Design note: all IDs in these tests fit within chunk 0 (IDs 0–63) so
    // the viewport always fetches the chunk containing the absent IDs, making
    // the absent-marking pass fire reliably without manual scroll.

    testWidgets('deleted batch in middle: absent IDs are not rendered as '
        'shimmer rows', (tester) async {
      // IDs 1–20 and 40–63 present; IDs 21–39 absent — all in chunk 0.
      final presentIds = <int>{
        for (var i = 1; i <= 20; i++) i,
        for (var i = 40; i <= 63; i++) i,
      };
      final ds = GapDataSource(presentIds: presentIds, oldest: 1, newest: 63);
      final controller = ChatScrollController()..jumpTo(63);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await _settle(tester);

      // Absent IDs must not appear as loading shimmers.
      expect(find.text('shimmer-21'), findsNothing);
      expect(find.text('shimmer-30'), findsNothing);
      expect(find.text('shimmer-39'), findsNothing);

      // Real messages are present (anchor at 63).
      expect(find.text('msg-63'), findsOneWidget);

      // Data layer: statusOf confirms absent for the deleted range.
      for (var id = 21; id <= 39; id++) {
        expect(
          ds.statusOf(id).isAbsent,
          isTrue,
          reason: 'id $id should be absent',
        );
      }

      // Present IDs are not absent.
      expect(ds.statusOf(1).isAbsent, isFalse);
      expect(ds.statusOf(63).isAbsent, isFalse);
    });

    testWidgets(
      'invalidate clears absent mask — re-fetch re-marks absent slots',
      (tester) async {
        // IDs 1-29 and 41-63 present; IDs 30-40 absent from the start (never
        // returned by the backend).
        final ds = _MutableGapDataSource(
          presentIds: {
            for (var i = 1; i <= 29; i++) i,
            for (var i = 41; i <= 63; i++) i,
          },
          oldest: 1,
          newest: 63,
        );
        final controller = ChatScrollController()..jumpTo(63);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await _settle(tester);

        // After first fetch: IDs 30-40 are absent.
        for (var id = 30; id <= 40; id++) {
          expect(
            ds.statusOf(id).isAbsent,
            isTrue,
            reason: 'id $id should be absent after first fetch',
          );
        }

        // Invalidate: absent masks are cleared; chunks become dirty.
        ds.invalidate();
        // Before re-fetch: statusOf returns dirty (mask cleared, chunk dirty).
        expect(ds.statusOf(30).isDirty, isTrue);
        expect(ds.statusOf(30).isAbsent, isFalse);

        // After re-fetch: absent-marking re-confirms IDs 30-40 as absent.
        await _settle(tester);
        for (var id = 30; id <= 40; id++) {
          expect(
            ds.statusOf(id).isAbsent,
            isTrue,
            reason: 'id $id should be absent again after re-fetch',
          );
        }

        // Adjacent present IDs are not absent.
        expect(ds.statusOf(29).isAbsent, isFalse);
        expect(ds.statusOf(41).isAbsent, isFalse);
      },
    );

    testWidgets('realtime delete: deleting a message marks its slot absent', (
      tester,
    ) async {
      final ds = _MutableGapDataSource(
        presentIds: {for (var i = 1; i <= 20; i++) i},
        oldest: 1,
        newest: 20,
      );
      final controller = ChatScrollController()..jumpTo(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await _settle(tester);

      // Message 10 is present before deletion.
      expect(ds.statusOf(10).isAbsent, isFalse);
      expect(ds.getMessage(10), isNotNull);

      // Apply realtime delete.
      ds.deleteMessage(10);
      await tester.pump();

      // Slot is now absent.
      expect(ds.statusOf(10).isAbsent, isTrue);
      expect(ds.getMessage(10), isNull);

      // No shimmer is rendered for the deleted id.
      expect(find.text('shimmer-10'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — fan-out skipping across absent chunks and ranges
  // ---------------------------------------------------------------------------

  group('fan-out skipping across absent chunks and ranges', () {
    testWidgets('all-absent chunk: absent IDs render at zero height, '
        'real messages on either side are built', (tester) async {
      // Chunk 1 = IDs 64–127 are fully absent.
      // Real messages in chunk 0 (IDs 0–63) and chunk 2 (IDs 128–191).
      final presentIds = <int>{
        for (var i = 0; i <= 63; i++) i,
        for (var i = 128; i <= 191; i++) i,
      };
      final ds = GapDataSource(presentIds: presentIds, oldest: 0, newest: 191);
      // Anchor at start of chunk 2; large cacheExtent ensures chunks 0–2 load.
      final controller = ChatScrollController()..jumpTo(128);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, cacheExtent: 10000),
      );
      await _settle(tester, maxPumps: 20);

      // No shimmer for the absent chunk.
      expect(find.text('shimmer-64'), findsNothing);
      expect(find.text('shimmer-127'), findsNothing);

      // The fully-absent chunk must be correctly identified.
      final chunkIndex = ChatScrollChunk.chunkOf(64);
      expect(
        ds.chunks[chunkIndex]?.isFullyAbsent,
        isTrue,
        reason: 'chunk $chunkIndex should be fully absent',
      );

      // Data for absent IDs.
      expect(ds.statusOf(64).isAbsent, isTrue);
      expect(ds.statusOf(127).isAbsent, isTrue);

      // Real messages at anchor are present.
      expect(ds.statusOf(128).isAbsent, isFalse);
      expect(find.text('msg-128'), findsOneWidget);
    });

    testWidgets('multi-chunk gap: 5 contiguous absent chunks, absent IDs '
        'confirmed absent in data layer', (tester) async {
      // Chunks 1–5 (IDs 64–383) are absent.
      // Real messages at chunk 0 (0–63) and chunk 6 (384–447).
      final presentIds = <int>{
        for (var i = 0; i <= 63; i++) i,
        for (var i = 384; i <= 447; i++) i,
      };
      final ds = GapDataSource(presentIds: presentIds, oldest: 0, newest: 447);
      final controller = ChatScrollController()..jumpTo(384);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, cacheExtent: 20000),
      );
      await _settle(tester, maxPumps: 30);

      // Absent range is silent.
      expect(find.text('shimmer-100'), findsNothing);
      expect(find.text('shimmer-200'), findsNothing);
      expect(find.text('shimmer-300'), findsNothing);

      // Data layer confirms absent for IDs in each of the 5 absent chunks.
      expect(ds.statusOf(64).isAbsent, isTrue);
      expect(ds.statusOf(150).isAbsent, isTrue);
      expect(ds.statusOf(300).isAbsent, isTrue);
      expect(ds.statusOf(383).isAbsent, isTrue);

      // Present IDs not absent.
      expect(ds.statusOf(0).isAbsent, isFalse);
      expect(ds.statusOf(384).isAbsent, isFalse);
    });

    testWidgets('two-message conversation with large ID gap: absent range '
        'confirmed in data layer, no shimmer rows, bounded child count', (
      tester,
    ) async {
      // Only IDs 1 and 127 exist; IDs 2–126 are all absent (in chunk 0).
      final ds = GapDataSource(presentIds: {1, 127}, oldest: 1, newest: 127);
      final controller = ChatScrollController()..jumpTo(127);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await _settle(tester);

      final ro = _render(tester);

      // Two real messages are not absent.
      expect(ds.statusOf(1).isAbsent, isFalse);
      expect(ds.statusOf(127).isAbsent, isFalse);

      // Absent IDs confirmed.
      expect(ds.statusOf(50).isAbsent, isTrue);
      expect(ds.statusOf(100).isAbsent, isTrue);

      // No shimmers in the absent range.
      expect(find.text('shimmer-50'), findsNothing);
      expect(find.text('shimmer-100'), findsNothing);

      // With fan-out skipping the render object builds only the two real
      // messages — absent IDs are skipped without building any child widget.
      // Allow a small margin for day-separator tiles that may be injected.
      expect(ro.debugChildCount, lessThan(10));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — navigation to deleted or absent message IDs
  // ---------------------------------------------------------------------------

  group('graceful navigation to deleted messages', () {
    testWidgets('navigating near absent IDs: no persistent skeleton, '
        'anchor stays at a valid message', (tester) async {
      // IDs 60–80 are absent (in chunk 0, IDs 0–63 partially; chunk 1).
      // Real: IDs 50–59 and 81–127 present.
      final presentIds = <int>{
        for (var i = 50; i <= 59; i++) i,
        for (var i = 81; i <= 127; i++) i,
      };
      final ds = GapDataSource(presentIds: presentIds, oldest: 50, newest: 127);
      final controller = ChatScrollController()..jumpTo(127);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, cacheExtent: 10000),
      );
      await _settle(tester, maxPumps: 20);

      // Navigate to the nearest real message above the absent range.
      controller.jumpTo(81);
      await _settle(tester);

      // Absent IDs in the gap do not appear as shimmers.
      expect(find.text('shimmer-70'), findsNothing);
      expect(find.text('shimmer-60'), findsNothing);

      // Data-layer confirms absent for the targeted range.
      expect(ds.statusOf(65).isAbsent, isTrue);
      expect(ds.statusOf(79).isAbsent, isTrue);

      // Anchor is a valid present message.
      expect(controller.anchorMessageId, 81);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — fan-out termination at all-absent boundaries
  // ---------------------------------------------------------------------------

  group('fan-out termination at all-absent boundaries', () {
    testWidgets(
      'all-absent upward run up to newestKnownId: layout completes without '
      'hang and anchor message remains visible',
      (tester) async {
        // Only message 1 exists; messages 2–63 are absent (all in chunk 0).
        // Fan-out downward from id=2 to bound=63 — every slot is absent.
        // Old code returned `bound` (63) which is also absent → infinite loop.
        // Fixed code returns `bound + 1` (64) so the loop guard `id <= 63`
        // exits cleanly on the very next check.
        final ds = GapDataSource(presentIds: {1}, oldest: 1, newest: 63);
        final controller = ChatScrollController()..jumpTo(1);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        // If infinite-loop regression exists, this pumpWidget call will time
        // out and the test will fail. With the fix it must return promptly.
        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await _settle(tester);

        // Message 1 is the only real message — it must be rendered.
        expect(find.text('msg-1'), findsOneWidget);

        // Absent IDs must not appear as shimmers.
        expect(find.text('shimmer-2'), findsNothing);
        expect(find.text('shimmer-63'), findsNothing);

        // Data layer: all IDs 2–63 are absent.
        for (var id = 2; id <= 63; id++) {
          expect(ds.statusOf(id).isAbsent, isTrue, reason: 'id $id absent');
        }
      },
    );

    testWidgets(
      'all-absent downward run from newestKnownId: anchor below absent zone '
      'still visible after settle',
      (tester) async {
        // Only message 63 exists; messages 0–62 are absent.
        // Anchor starts at 63; fan upward from id=62 to bound=0 — all absent.
        // Fixed: _nextNonAbsentIdUp returns bound-1 = -1 so outer loop
        // `id >= 0` exits cleanly.
        final ds = GapDataSource(presentIds: {63}, oldest: 0, newest: 63);
        final controller = ChatScrollController()..jumpTo(63);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await _settle(tester);

        expect(find.text('msg-63'), findsOneWidget);
        expect(find.text('shimmer-0'), findsNothing);
        expect(find.text('shimmer-62'), findsNothing);
      },
    );
  });
}
