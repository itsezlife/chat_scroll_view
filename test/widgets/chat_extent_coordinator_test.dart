import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_extent_coordinator.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_parent_data.dart';
import 'package:chatscrollview/src/chat_scroll/chat_mutations.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSource extends ChatDataSource {
  _TestSource() {
    upsertMessage(
      UserChatMessage(
        id: 0,
        sender: 'u',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: 'a',
      ),
    );
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 0,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const [];
}

class _FakeChild extends RenderBox {
  _FakeChild(this.pd, {this.height = 60});

  final ChatMessageParentData pd;
  final double height;

  @override
  void performLayout() {
    size = Size(100, height);
  }

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! ChatMessageParentData) {
      child.parentData = ChatMessageParentData();
    }
  }
}

class _FakeBridge implements ChatChildManagerBridge {
  final List<int> removed = <int>[];
  final List<int> invalidated = <int>[];

  @override
  void invalidateBuiltChild(int id) => invalidated.add(id);

  @override
  void removeChildren(List<int> ids) => removed.addAll(ids);
}

class _TwoMessageSource extends ChatDataSource {
  _TwoMessageSource() {
    for (var i = 0; i < 2; i++) {
      upsertMessage(
        UserChatMessage(
          id: i,
          sender: 'u',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'm$i',
        ),
      );
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const [];
}

void main() {
  group('ChatExtentCoordinator', () {
    late _TestSource source;
    late ChatScrollController controller;
    late _FakeBridge bridge;
    late ChatMessageParentData pd;
    late _FakeChild child;
    late ChatExtentCoordinator coordinator;
    var layoutCount = 0;

    setUp(() {
      source = _TestSource();
      controller = ChatScrollController()..jumpTo(0);
      bridge = _FakeBridge();
      pd = ChatMessageParentData()..id = 0;
      child = _FakeChild(pd);
      child.layout(const BoxConstraints.tightFor(width: 100, height: 60));
      pd.offset = 100;
      layoutCount = 0;
      coordinator = ChatExtentCoordinator(
        dataSource: source,
        controller: controller,
        childForId: (_) => child,
        parentDataOf: (_) => pd,
        hasSize: () => true,
        viewportHeight: () => 600,
        bottomPad: () => 0,
        applyScrollDelta: controller.applyScrollDelta,
        markNeedsLayout: () => layoutCount++,
        markNeedsPaint: () {},
        ensureTicker: () {},
        invokeChildManager: (fn) => fn(),
        childManager: bridge,
        repositionFromAnchor: () {},
        wasAtTailLastLayout: () => true,
        findPresentNeighbor: (_, _) => null,
        applyAnchorMoveAwayFromRemoved: (_, {required pinTail}) {},
        planAnchorMoveAwayFromRemoved: (_) => null,
        rebuildGroupedNeighbors: (_) {},
        seedTailInsertPin: (_) {},
      );
    });

    tearDown(() {
      source.dispose();
      controller.dispose();
    });

    test('insert mutation queues deferred animation', () {
      coordinator.onMutation(
        const ChatMutation(ChatMutationKind.insert, 0, reason: 'test'),
      );
      expect(layoutCount, 1);
      coordinator.applyDeferredExtentAnimations({0});
      expect(pd.heightSpring, isNotNull);
      expect(pd.animatedHeight, 0);
    });

    test('remove mutation starts collapse on built child', () {
      coordinator.onMutation(
        const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
      );
      expect(pd.pendingRemoval, isTrue);
      expect(pd.heightSpring, isNotNull);
    });

    test('update mutation queues resize', () {
      pd.animatedHeight = 30;
      pd.targetHeight = 30;
      coordinator.onMutation(
        const ChatMutation(ChatMutationKind.update, 0, reason: 'test'),
      );
      coordinator.applyDeferredExtentAnimations({0});
      expect(pd.heightSpring, isNotNull);
    });

    test('remove mutation eagerly reassigns anchor off deleted id', () {
      var anchorMoves = 0;
      int? movedTarget;
      controller.reassignAnchor(0, 100);
      coordinator = ChatExtentCoordinator(
        dataSource: source,
        controller: controller,
        childForId: (_) => child,
        parentDataOf: (_) => pd,
        hasSize: () => true,
        viewportHeight: () => 600,
        bottomPad: () => 0,
        applyScrollDelta: controller.applyScrollDelta,
        markNeedsLayout: () => layoutCount++,
        markNeedsPaint: () {},
        ensureTicker: () {},
        invokeChildManager: (fn) => fn(),
        childManager: bridge,
        repositionFromAnchor: () {},
        wasAtTailLastLayout: () => true,
        findPresentNeighbor: (_, _) => 99,
        applyAnchorMoveAwayFromRemoved: (targetId, {required pinTail}) {
          anchorMoves++;
          movedTarget = targetId;
          controller.reassignAnchor(targetId, pinTail ? 540 : 50);
        },
        planAnchorMoveAwayFromRemoved: (_) => (targetId: 99, pinTail: true),
        rebuildGroupedNeighbors: (_) {},
        seedTailInsertPin: (_) {},
      );
      coordinator.onMutation(
        const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
      );
      expect(anchorMoves, 1);
      expect(movedTarget, 99);
      expect(controller.anchorMessageId, 99);
      expect(controller.anchorPixelOffset, 50);
      expect(pd.pendingRemoval, isTrue);
    });

    test('viewport-spanning removal does not scroll during collapse', () {
      // Mirrors deleting a very tall row (e.g. id=5980, h=3722, top<0) while
      // the anchor sits on a different built message — collapse in place, no
      // mid-animation scroll; structural layout at finalize owns the jump.
      final twoSource = _TwoMessageSource();
      final twoController = ChatScrollController()..reassignAnchor(1, 400);
      final pdRemoved = ChatMessageParentData()..id = 0..offset = -50;
      final pdAnchor = ChatMessageParentData()..id = 1..offset = 400;
      final childRemoved = _FakeChild(pdRemoved, height: 800);
      final childAnchor = _FakeChild(pdAnchor);
      childRemoved.layout(
        const BoxConstraints.tightFor(width: 100, height: 800),
      );
      childAnchor.layout(const BoxConstraints.tightFor(width: 100, height: 60));
      var scrollTotal = 0.0;
      final twoCoordinator = ChatExtentCoordinator(
        dataSource: twoSource,
        controller: twoController,
        childForId: (id) => id == 0 ? childRemoved : childAnchor,
        parentDataOf: (child) =>
            child == childRemoved ? pdRemoved : pdAnchor,
        hasSize: () => true,
        viewportHeight: () => 600,
        bottomPad: () => 0,
        applyScrollDelta: (delta) {
          scrollTotal += delta;
          twoController.applyScrollDelta(delta);
        },
        markNeedsLayout: () {},
        markNeedsPaint: () {},
        ensureTicker: () {},
        invokeChildManager: (fn) => fn(),
        childManager: bridge,
        repositionFromAnchor: () {},
        wasAtTailLastLayout: () => false,
        findPresentNeighbor: (_, _) => null,
        applyAnchorMoveAwayFromRemoved: (_, {required pinTail}) {},
        planAnchorMoveAwayFromRemoved: (_) => null,
        rebuildGroupedNeighbors: (_) {},
        seedTailInsertPin: (_) {},
      );
      addTearDown(twoSource.dispose);
      addTearDown(twoController.dispose);

      twoCoordinator.onMutation(
        const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
      );
      expect(pdRemoved.pendingRemoval, isTrue);

      var prev = Duration.zero;
      for (var i = 1; i <= 40; i++) {
        final elapsed = Duration(milliseconds: 16 * i);
        twoCoordinator.advanceAnimations(elapsed, prev);
        prev = elapsed;
      }

      expect(scrollTotal, 0.0);
      expect(twoController.anchorPixelOffset, 400);
    });

    test('partial-height removal does not scroll during collapse', () {
      final twoSource = _TwoMessageSource();
      final twoController = ChatScrollController()..reassignAnchor(1, 400);
      final pdRemoved = ChatMessageParentData()..id = 0..offset = 50;
      final pdAnchor = ChatMessageParentData()..id = 1..offset = 400;
      final childRemoved = _FakeChild(pdRemoved, height: 400);
      final childAnchor = _FakeChild(pdAnchor);
      childRemoved.layout(
        const BoxConstraints.tightFor(width: 100, height: 400),
      );
      childAnchor.layout(const BoxConstraints.tightFor(width: 100, height: 60));
      var scrollTotal = 0.0;
      final twoCoordinator = ChatExtentCoordinator(
        dataSource: twoSource,
        controller: twoController,
        childForId: (id) => id == 0 ? childRemoved : childAnchor,
        parentDataOf: (child) =>
            child == childRemoved ? pdRemoved : pdAnchor,
        hasSize: () => true,
        viewportHeight: () => 600,
        bottomPad: () => 0,
        applyScrollDelta: (delta) {
          scrollTotal += delta;
          twoController.applyScrollDelta(delta);
        },
        markNeedsLayout: () {},
        markNeedsPaint: () {},
        ensureTicker: () {},
        invokeChildManager: (fn) => fn(),
        childManager: bridge,
        repositionFromAnchor: () {},
        wasAtTailLastLayout: () => false,
        findPresentNeighbor: (_, _) => null,
        applyAnchorMoveAwayFromRemoved: (_, {required pinTail}) {},
        planAnchorMoveAwayFromRemoved: (_) => null,
        rebuildGroupedNeighbors: (_) {},
        seedTailInsertPin: (_) {},
      );
      addTearDown(twoSource.dispose);
      addTearDown(twoController.dispose);

      twoCoordinator.onMutation(
        const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
      );

      var prev = Duration.zero;
      for (var i = 1; i <= 40; i++) {
        final elapsed = Duration(milliseconds: 16 * i);
        twoCoordinator.advanceAnimations(elapsed, prev);
        prev = elapsed;
      }

      expect(scrollTotal, 0.0);
      expect(twoController.anchorPixelOffset, 400);
    });

    test('bottom-overlap removal does not scroll during collapse', () {
      // Mirrors mid-history delete where bottom crosses the inset but the
      // message top is still in view (e.g. id=6006: offset=157, h=599).
      final twoSource = _TwoMessageSource();
      final twoController = ChatScrollController()..reassignAnchor(1, 400);
      final pdRemoved = ChatMessageParentData()..id = 0..offset = 157;
      final pdAnchor = ChatMessageParentData()..id = 1..offset = 400;
      final childRemoved = _FakeChild(pdRemoved, height: 599);
      final childAnchor = _FakeChild(pdAnchor);
      childRemoved.layout(
        const BoxConstraints.tightFor(width: 100, height: 599),
      );
      childAnchor.layout(const BoxConstraints.tightFor(width: 100, height: 60));
      var scrollTotal = 0.0;
      final twoCoordinator = ChatExtentCoordinator(
        dataSource: twoSource,
        controller: twoController,
        childForId: (id) => id == 0 ? childRemoved : childAnchor,
        parentDataOf: (child) =>
            child == childRemoved ? pdRemoved : pdAnchor,
        hasSize: () => true,
        viewportHeight: () => 644,
        bottomPad: () => 0,
        applyScrollDelta: (delta) {
          scrollTotal += delta;
          twoController.applyScrollDelta(delta);
        },
        markNeedsLayout: () {},
        markNeedsPaint: () {},
        ensureTicker: () {},
        invokeChildManager: (fn) => fn(),
        childManager: bridge,
        repositionFromAnchor: () {},
        wasAtTailLastLayout: () => false,
        findPresentNeighbor: (_, _) => null,
        applyAnchorMoveAwayFromRemoved: (_, {required pinTail}) {},
        planAnchorMoveAwayFromRemoved: (_) => null,
        rebuildGroupedNeighbors: (_) {},
        seedTailInsertPin: (_) {},
      );
      addTearDown(twoSource.dispose);
      addTearDown(twoController.dispose);

      twoCoordinator.onMutation(
        const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
      );

      var prev = Duration.zero;
      for (var i = 1; i <= 40; i++) {
        final elapsed = Duration(milliseconds: 16 * i);
        twoCoordinator.advanceAnimations(elapsed, prev);
        prev = elapsed;
      }

      expect(scrollTotal, 0.0);
      expect(twoController.anchorPixelOffset, 400);
    });

    test(
      'viewport-spanning predecessor scrolls once at finalize not during collapse',
      () {
        // Mirrors deleting id=5997 (h=3619, top<0) while anchor sits on a
        // younger built row below the removed bottom (anchor=6002 at y=1291).
        final twoSource = _TwoMessageSource();
        final twoController = ChatScrollController()..reassignAnchor(1, 1291.2);
        final pdRemoved = ChatMessageParentData()
          ..id = 0
          ..offset = -2883.8;
        final pdAnchor = ChatMessageParentData()..id = 1..offset = 1291.2;
        final childRemoved = _FakeChild(pdRemoved, height: 3619);
        final childAnchor = _FakeChild(pdAnchor, height: 679);
        childRemoved.layout(
          const BoxConstraints.tightFor(width: 100, height: 3619),
        );
        childAnchor.layout(
          const BoxConstraints.tightFor(width: 100, height: 679),
        );
        var scrollTotal = 0.0;
        var scrollWhileCollapsing = 0.0;
        final twoCoordinator = ChatExtentCoordinator(
          dataSource: twoSource,
          controller: twoController,
          childForId: (id) => id == 0 ? childRemoved : childAnchor,
          parentDataOf: (child) =>
              child == childRemoved ? pdRemoved : pdAnchor,
          hasSize: () => true,
          viewportHeight: () => 644,
          bottomPad: () => 0,
          applyScrollDelta: (delta) {
            scrollTotal += delta;
            twoController.applyScrollDelta(delta);
          },
          markNeedsLayout: () {},
          markNeedsPaint: () {},
          ensureTicker: () {},
          invokeChildManager: (fn) => fn(),
          childManager: bridge,
          repositionFromAnchor: () {},
          wasAtTailLastLayout: () => false,
          findPresentNeighbor: (_, _) => null,
          applyAnchorMoveAwayFromRemoved: (_, {required pinTail}) {},
          planAnchorMoveAwayFromRemoved: (_) => null,
          rebuildGroupedNeighbors: (_) {},
          seedTailInsertPin: (_) {},
        );
        addTearDown(twoSource.dispose);
        addTearDown(twoController.dispose);

        twoCoordinator.onMutation(
          const ChatMutation(ChatMutationKind.remove, 0, reason: 'test'),
        );

        var prev = Duration.zero;
        for (var i = 1; i <= 150; i++) {
          final before = scrollTotal;
          final elapsed = Duration(milliseconds: 16 * i);
          twoCoordinator.advanceAnimations(elapsed, prev);
          prev = elapsed;
          if (pdRemoved.animatedHeight > 100) {
            scrollWhileCollapsing += scrollTotal - before;
          }
        }

        expect(scrollWhileCollapsing, 0.0);
        expect(scrollTotal, closeTo(-3619, 0.5));
        expect(twoController.anchorPixelOffset, closeTo(1291.2 - 3619, 0.5));
      },
    );
  });
}
