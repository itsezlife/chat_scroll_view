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
  _FakeChild(this.pd);

  final ChatMessageParentData pd;

  @override
  void performLayout() {
    size = const Size(100, 60);
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
  });
}
